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

func matchesFilterGroup(_ row: DatabaseRow, group: FilterGroup, schema: DatabaseSchema) -> Bool {
    switch group.conjunction {
    case .and:
        return group.conditions.allSatisfy { condition in
            matchesFilterCondition(row, condition: condition, schema: schema)
        }
    case .or:
        return group.conditions.isEmpty || group.conditions.contains { condition in
            matchesFilterCondition(row, condition: condition, schema: schema)
        }
    }
}

private func matchesFilterCondition(_ row: DatabaseRow, condition: FilterCondition, schema: DatabaseSchema) -> Bool {
    switch condition {
    case .filter(let filterConfig):
        let val = row.properties[filterConfig.property] ?? .empty
        return matchesFilter(val, filter: filterConfig)
    case .group(let nestedGroup):
        return matchesFilterGroup(row, group: nestedGroup, schema: schema)
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
