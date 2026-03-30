import Foundation
import SwiftUI
import BugbookCore

func applyManualRowOrder(_ orderedIds: [String]?, to inputRows: [DatabaseRow]) -> [DatabaseRow] {
    guard let orderedIds, !orderedIds.isEmpty else { return inputRows }
    let rowsById = Dictionary(uniqueKeysWithValues: inputRows.map { ($0.id, $0) })
    var orderedRows = orderedIds.compactMap { rowsById[$0] }
    let knownIds = Set(orderedRows.map(\.id))
    orderedRows.append(contentsOf: inputRows.filter { !knownIds.contains($0.id) })
    return orderedRows
}

func reorderedManualRowOrder(
    currentOrder: [String]?,
    allRows: [DatabaseRow],
    visibleRowIds: [String],
    draggedId: String,
    targetId: String?
) -> [String] {
    var baseOrder = applyManualRowOrder(currentOrder, to: allRows).map(\.id)
    var visibleOrder = baseOrder.filter { visibleRowIds.contains($0) }

    guard let sourceIndex = visibleOrder.firstIndex(of: draggedId) else { return baseOrder }
    let movedId = visibleOrder.remove(at: sourceIndex)

    if let targetId, let targetIndex = visibleOrder.firstIndex(of: targetId) {
        visibleOrder.insert(movedId, at: targetIndex)
    } else {
        visibleOrder.append(movedId)
    }

    var replacementIterator = visibleOrder.makeIterator()
    for index in baseOrder.indices where visibleRowIds.contains(baseOrder[index]) {
        baseOrder[index] = replacementIterator.next() ?? baseOrder[index]
    }
    return baseOrder
}

func matchesFilter(_ value: PropertyValue, filter: FilterConfig) -> Bool {
    // Checkbox-specific operators
    if case .checkbox(let checked) = value {
        switch filter.op {
        case "is_checked": return checked
        case "is_not_checked": return !checked
        default: break
        }
    }

    // Date comparisons use sortable keys for correct ordering
    if case .date(let raw) = value {
        let sortKey = DatabaseDateValue.decode(from: raw)?.sortKey ?? raw
        switch filter.op {
        case "equals": return sortKey == filter.value
        case "not_equals": return sortKey != filter.value
        case "greater_than": return sortKey > filter.value
        case "less_than": return sortKey < filter.value
        case "greater_than_or_equal": return sortKey >= filter.value
        case "less_than_or_equal": return sortKey <= filter.value
        default: break
        }
    }

    let stringVal = stringFromValue(value)
    switch filter.op {
    case "equals": return stringVal == filter.value
    case "not_equals": return stringVal != filter.value
    case "contains": return stringVal.localizedCaseInsensitiveContains(filter.value)
    case "not_contains": return !stringVal.localizedCaseInsensitiveContains(filter.value)
    case "is_empty": return stringVal.isEmpty
    case "is_not_empty": return !stringVal.isEmpty
    case "greater_than":
        if let lhs = Double(stringVal), let rhs = Double(filter.value) { return lhs > rhs }
        return stringVal > filter.value
    case "less_than":
        if let lhs = Double(stringVal), let rhs = Double(filter.value) { return lhs < rhs }
        return stringVal < filter.value
    case "less_than_or_equal":
        if let lhs = Double(stringVal), let rhs = Double(filter.value) { return lhs <= rhs }
        return stringVal <= filter.value
    default: return true
    }
}

func compareValues(_ a: PropertyValue, _ b: PropertyValue) -> ComparisonResult {
    if case .number(let aNum) = a, case .number(let bNum) = b {
        if aNum < bNum { return .orderedAscending }
        if aNum > bNum { return .orderedDescending }
        return .orderedSame
    }
    if case .date(let aRaw) = a, case .date(let bRaw) = b {
        let aKey = DatabaseDateValue.decode(from: aRaw)?.sortKey ?? aRaw
        let bKey = DatabaseDateValue.decode(from: bRaw)?.sortKey ?? bRaw
        return aKey.compare(bKey)
    }
    return stringFromValue(a).compare(stringFromValue(b))
}

func stringFromValue(_ value: PropertyValue) -> String {
    switch value {
    case .text(let s): return s
    case .number(let n): return String(n)
    case .select(let s): return s
    case .multiSelect(let arr): return arr.joined(separator: ",")
    case .date(let s): return DatabaseDateValue.decode(from: s)?.displayText(compact: true) ?? s
    case .checkbox(let b): return b ? "1" : "0"
    case .url(let s): return s
    case .email(let s): return s
    case .relation(let s): return s
    case .relationMany(let arr): return arr.joined(separator: ",")
    case .empty: return ""
    }
}

func ensureCalendarDateProperty(
    schema: inout DatabaseSchema,
    activeViewId: String,
    preferredPropertyId: String?,
    dbService: DatabaseService,
    dbPath: String
) throws -> String {
    let resolvedProperty = schema.properties.first(where: { $0.id == preferredPropertyId && $0.type == .date })
        ?? schema.properties.first(where: { $0.type == .date })
        ?? {
            let newProperty = PropertyDefinition(
                id: "prop_date_\(UUID().uuidString.prefix(6).lowercased())",
                name: uniqueDatePropertyName(in: schema),
                type: .date
            )
            try? dbService.addProperty(newProperty, to: &schema, at: dbPath)
            return schema.properties.first(where: { $0.id == newProperty.id })
        }()

    guard let dateProperty = resolvedProperty else {
        throw NSError(domain: "Bugbook.Database", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to create a calendar date property"])
    }

    if let viewIndex = schema.views.firstIndex(where: { $0.id == activeViewId && $0.type == .calendar }),
       schema.views[viewIndex].dateProperty != dateProperty.id {
        schema.views[viewIndex].dateProperty = dateProperty.id
        try dbService.updateView(schema.views[viewIndex], in: &schema, at: dbPath)
    }

    return dateProperty.id
}

func postDatabaseChangeNotification(dbPath: String, origin: String) {
    NotificationCenter.default.post(
        name: .databaseDidChange,
        object: nil,
        userInfo: [DatabaseNotificationKey.dbPath: dbPath, DatabaseNotificationKey.origin: origin]
    )
}

func requestDatabaseRowModal(dbPath: String, rowId: String, autoFocusTitle: Bool = false) {
    let post = {
        NotificationCenter.default.post(
            name: .databaseRowModalRequested,
            object: nil,
            userInfo: [
                DatabaseNotificationKey.dbPath: dbPath,
                DatabaseNotificationKey.rowId: rowId,
                DatabaseNotificationKey.autoFocusTitle: autoFocusTitle
            ]
        )
    }
    if Thread.isMainThread {
        post()
    } else {
        DispatchQueue.main.async(execute: post)
    }
}

struct RowLoadErrorView: View {
    let message: String
    var buttonLabel: String = "Retry"
    let onAction: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text("Failed to load row")
                .font(.headline)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button(buttonLabel, action: onAction)
                .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }
}

func defaultDatabaseViewConfig() -> ViewConfig {
    ViewConfig(id: "default", name: "Table", type: .table, sorts: [], filters: [])
}

// MARK: - View Tab Drop Delegate

struct ViewTabDropDelegate: DropDelegate {
    let targetId: String
    let state: DatabaseViewState
    @Binding var draggedId: String?
    @Binding var dropTargetId: String?

    func dropEntered(info: DropInfo) {
        guard let draggedId, draggedId != targetId else { return }
        dropTargetId = targetId
    }

    func dropExited(info: DropInfo) {
        if dropTargetId == targetId {
            dropTargetId = nil
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        guard let draggedId, draggedId != targetId else { return false }
        state.reorderViews(sourceId: draggedId, beforeId: targetId)
        self.draggedId = nil
        dropTargetId = nil
        return true
    }

    func validateDrop(info: DropInfo) -> Bool {
        draggedId != nil && draggedId != targetId
    }
}

func uniqueDatePropertyName(in schema: DatabaseSchema) -> String {
    let existingNames = Set(schema.properties.map(\.name))
    if !existingNames.contains("Date") {
        return "Date"
    }
    var suffix = 2
    while existingNames.contains("Date \(suffix)") {
        suffix += 1
    }
    return "Date \(suffix)"
}

// MARK: - Aggregation Engine

enum AggregationFunction: String, CaseIterable {
    case count
    case countValues = "count_values"
    case countUnique = "count_unique"
    case sum
    case avg
    case min
    case max
    case percentChecked = "percent_checked"
    case percentUnchecked = "percent_unchecked"

    var displayName: String {
        switch self {
        case .count: return "Count"
        case .countValues: return "Count values"
        case .countUnique: return "Count unique"
        case .sum: return "Sum"
        case .avg: return "Average"
        case .min: return "Min"
        case .max: return "Max"
        case .percentChecked: return "Percent checked"
        case .percentUnchecked: return "Percent unchecked"
        }
    }

    static func available(for type: PropertyType) -> [AggregationFunction] {
        var funcs: [AggregationFunction] = [.count, .countValues]
        if type != .checkbox {
            funcs.append(.countUnique)
        }
        if type == .number {
            funcs.append(contentsOf: [.sum, .avg, .min, .max])
        }
        if type == .date {
            funcs.append(contentsOf: [.min, .max])
        }
        if type == .checkbox {
            funcs.append(contentsOf: [.percentChecked, .percentUnchecked])
        }
        return funcs
    }
}

enum AggregationEngine {
    static func compute(
        function: AggregationFunction,
        propertyId: String,
        propertyType: PropertyType,
        rows: [DatabaseRow],
        config: PropertyConfig?
    ) -> String {
        let values = rows.map { $0.properties[propertyId] ?? .empty }

        switch function {
        case .count:
            return "\(rows.count)"

        case .countValues:
            let nonEmpty = values.filter { !isEmptyValue($0) }
            return "\(nonEmpty.count)"

        case .countUnique:
            let strings = values.compactMap { isEmptyValue($0) ? nil : stringFromValue($0) }
            return "\(Set(strings).count)"

        case .sum:
            let total = values.reduce(0.0) { acc, val in
                if case .number(let n) = val { return acc + n }
                return acc
            }
            return formatNumber(total, config: config)

        case .avg:
            let numbers = values.compactMap { val -> Double? in
                if case .number(let n) = val { return n }
                return nil
            }
            guard !numbers.isEmpty else { return "0" }
            let avg = numbers.reduce(0.0, +) / Double(numbers.count)
            return formatNumber(avg, config: config)

        case .min:
            if propertyType == .number {
                let numbers = values.compactMap { val -> Double? in
                    if case .number(let n) = val { return n }
                    return nil
                }
                guard let m = numbers.min() else { return "" }
                return formatNumber(m, config: config)
            } else if propertyType == .date {
                let dates = values.compactMap { val -> String? in
                    if case .date(let raw) = val {
                        return DatabaseDateValue.decode(from: raw)?.sortKey ?? raw
                    }
                    return nil
                }.filter { !$0.isEmpty }
                guard let m = dates.min() else { return "" }
                return formatDateSortKey(m)
            }
            return ""

        case .max:
            if propertyType == .number {
                let numbers = values.compactMap { val -> Double? in
                    if case .number(let n) = val { return n }
                    return nil
                }
                guard let m = numbers.max() else { return "" }
                return formatNumber(m, config: config)
            } else if propertyType == .date {
                let dates = values.compactMap { val -> String? in
                    if case .date(let raw) = val {
                        return DatabaseDateValue.decode(from: raw)?.sortKey ?? raw
                    }
                    return nil
                }.filter { !$0.isEmpty }
                guard let m = dates.max() else { return "" }
                return formatDateSortKey(m)
            }
            return ""

        case .percentChecked:
            guard !rows.isEmpty else { return "0%" }
            let checked = values.filter { if case .checkbox(true) = $0 { return true }; return false }.count
            let pct = Int(round(Double(checked) / Double(rows.count) * 100))
            return "\(pct)%"

        case .percentUnchecked:
            guard !rows.isEmpty else { return "0%" }
            let unchecked = values.filter { val in
                switch val {
                case .checkbox(false): return true
                case .checkbox(true): return false
                default: return true // empty counts as unchecked
                }
            }.count
            let pct = Int(round(Double(unchecked) / Double(rows.count) * 100))
            return "\(pct)%"
        }
    }

    static func computeAll(
        calculations: [String: String],
        properties: [PropertyDefinition],
        rows: [DatabaseRow]
    ) -> [String: String] {
        var results: [String: String] = [:]
        for (propId, funcName) in calculations {
            guard let fn = AggregationFunction(rawValue: funcName) else { continue }
            let prop = properties.first(where: { $0.id == propId })
            let type = prop?.type ?? .text
            results[propId] = compute(
                function: fn,
                propertyId: propId,
                propertyType: type,
                rows: rows,
                config: prop?.config
            )
        }
        return results
    }

    private static func isEmptyValue(_ value: PropertyValue) -> Bool {
        switch value {
        case .empty: return true
        case .text(let s): return s.isEmpty
        case .select(let s): return s.isEmpty
        case .multiSelect(let arr): return arr.isEmpty
        case .date(let s): return s.isEmpty
        case .url(let s): return s.isEmpty
        case .email(let s): return s.isEmpty
        case .relation(let s): return s.isEmpty
        case .relationMany(let arr): return arr.isEmpty
        case .number, .checkbox: return false
        }
    }

    private static func formatNumber(_ n: Double, config: PropertyConfig?) -> String {
        let format = config?.format ?? "number"
        switch format {
        case "percent":
            return "\(formatPlainNumber(n))%"
        case "currency":
            return "$\(formatPlainNumber(n))"
        default:
            return formatPlainNumber(n)
        }
    }

    private static func formatPlainNumber(_ n: Double) -> String {
        if n == n.rounded() && abs(n) < 1e15 {
            return String(Int(n))
        }
        // Two decimal places for non-integer
        return String(format: "%.2f", n)
    }

    private static func formatDateSortKey(_ sortKey: String) -> String {
        // sortKey is ISO-style "YYYY-MM-DD"; present as-is for readability
        sortKey
    }
}
