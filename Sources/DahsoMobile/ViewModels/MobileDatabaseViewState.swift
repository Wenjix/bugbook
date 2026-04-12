import Foundation
import Observation
import DahsoCore

@MainActor
@Observable
final class MobileDatabaseViewState {
    let dbPath: String

    var schema: DatabaseSchema?
    var rows: [DatabaseRow] = []
    var activeViewId: String = ""
    var error: String?

    private let dbStore = DatabaseStore()
    private let rowStore = RowStore()
    private let indexManager = IndexManager()

    var activeView: ViewConfig? {
        schema?.views.first(where: { $0.id == activeViewId })
    }

    var visibleProperties: [PropertyDefinition] {
        guard let schema, let view = activeView else { return schema?.properties ?? [] }
        let hidden = Set(view.hiddenColumns ?? [])
        return schema.properties.filter { !hidden.contains($0.id) }
    }

    init(dbPath: String) {
        self.dbPath = dbPath
    }

    // MARK: - Loading

    func loadData() {
        do {
            let loadedSchema = try dbStore.loadSchema(at: dbPath)
            schema = loadedSchema
            rows = rowStore.loadAllRows(in: dbPath, schema: loadedSchema)

            if activeViewId.isEmpty || !loadedSchema.views.contains(where: { $0.id == activeViewId }) {
                activeViewId = loadedSchema.defaultView
            }
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: - Filtered & Sorted Rows

    func filteredAndSortedRows() -> [DatabaseRow] {
        guard let view = activeView, let schema else { return rows }

        var result = rows

        // Apply filters
        if let group = view.filterGroup {
            result = result.filter { row in
                matchesFilterGroup(row, group: group, schema: schema)
            }
        } else {
            for filter in view.filters {
                result = result.filter { row in
                    let val = row.properties[filter.property] ?? .empty
                    return matchesFilter(val, filter: filter)
                }
            }
        }

        // Apply sorts
        for sort in view.sorts.reversed() {
            result.sort { a, b in
                let va = a.properties[sort.property] ?? .empty
                let vb = b.properties[sort.property] ?? .empty
                let cmp = compareValues(va, vb)
                return sort.ascending ? cmp == .orderedAscending : cmp == .orderedDescending
            }
        }

        // Default sort by updatedAt if no sorts defined
        if view.sorts.isEmpty {
            result.sort { $0.updatedAt > $1.updatedAt }
        }

        return result
    }

    // MARK: - Grouped Rows (for Kanban)

    func groupedRows(by propertyId: String) -> [(option: SelectOption?, rows: [DatabaseRow])] {
        guard let schema, let prop = schema.properties.first(where: { $0.id == propertyId }) else { return [] }
        let filtered = filteredAndSortedRows()
        let options = prop.options ?? []

        var groups: [(option: SelectOption?, rows: [DatabaseRow])] = []
        var noValueRows: [DatabaseRow] = []

        for option in options {
            let matching = filtered.filter { row in
                if case .select(let id) = row.properties[propertyId] { return id == option.id }
                if case .multiSelect(let ids) = row.properties[propertyId] { return ids.contains(option.id) }
                return false
            }
            groups.append((option: option, rows: matching))
        }

        noValueRows = filtered.filter { row in
            let val = row.properties[propertyId] ?? .empty
            if case .empty = val { return true }
            if case .select(let s) = val { return s.isEmpty }
            return false
        }

        if !noValueRows.isEmpty {
            groups.insert((option: nil, rows: noValueRows), at: 0)
        }

        return groups
    }

    // MARK: - Row CRUD

    @discardableResult
    func createRow(properties: [String: PropertyValue]? = nil) -> DatabaseRow? {
        guard let schema else { return nil }
        let rowId = RowStore.generateRowId()
        let now = Date()

        var props: [String: PropertyValue] = [:]
        if let titleProp = schema.titleProperty {
            props[titleProp.id] = .text("Untitled")
        }
        if let extra = properties {
            props.merge(extra) { _, new in new }
        }

        let row = DatabaseRow(id: rowId, properties: props, body: "", createdAt: now, updatedAt: now)
        do {
            try rowStore.saveRow(row, schema: schema, dbPath: dbPath)
            rows.append(row)
            rebuildIndex()
            return row
        } catch {
            self.error = error.localizedDescription
            return nil
        }
    }

    func saveRow(_ row: DatabaseRow) {
        guard let schema else { return }
        if let idx = rows.firstIndex(where: { $0.id == row.id }) {
            rows[idx] = row
        }
        do {
            try rowStore.saveRow(row, schema: schema, dbPath: dbPath)
            rebuildIndex()
        } catch {
            self.error = error.localizedDescription
        }
    }

    func deleteRow(_ row: DatabaseRow) {
        rows.removeAll { $0.id == row.id }
        try? rowStore.deleteRow(rowId: row.id, dbPath: dbPath)
        rebuildIndex()
    }

    // MARK: - Schema Operations

    func addProperty(name: String, type: PropertyType) {
        guard var s = schema else { return }
        let id = "prop_\(String(UUID().uuidString.prefix(5).lowercased()))"
        var config: PropertyConfig?
        if type == .select || type == .multiSelect {
            config = PropertyConfig(options: [])
        }
        let prop = PropertyDefinition(id: id, name: name, type: type, config: config)
        s.properties.append(prop)
        schema = s
        saveSchema()
    }

    func renameProperty(_ propertyId: String, to newName: String) {
        guard var s = schema, let idx = s.properties.firstIndex(where: { $0.id == propertyId }) else { return }
        s.properties[idx].name = newName
        schema = s
        saveSchema()
    }

    func deleteProperty(_ propertyId: String) {
        guard var s = schema else { return }
        s.properties.removeAll { $0.id == propertyId }
        schema = s
        saveSchema()

        // Remove property from all rows
        for i in rows.indices {
            rows[i].properties.removeValue(forKey: propertyId)
        }
    }

    func addSelectOption(_ propertyId: String, name: String, color: String) {
        guard var s = schema, let idx = s.properties.firstIndex(where: { $0.id == propertyId }) else { return }
        let optionId = "opt_\(String(UUID().uuidString.prefix(5).lowercased()))"
        let option = SelectOption(id: optionId, name: name, color: color)
        var existing = s.properties[idx].config?.options ?? []
        existing.append(option)
        if s.properties[idx].config == nil {
            s.properties[idx].config = PropertyConfig(options: existing)
        } else {
            s.properties[idx].config?.options = existing
        }
        schema = s
        saveSchema()
    }

    func deleteSelectOption(_ propertyId: String, optionId: String) {
        guard var s = schema, let idx = s.properties.firstIndex(where: { $0.id == propertyId }) else { return }
        s.properties[idx].config?.options?.removeAll { $0.id == optionId }
        schema = s
        saveSchema()
    }

    // MARK: - View Operations

    func addView(name: String, type: ViewType) {
        guard var s = schema else { return }
        let viewId = "view_\(String(UUID().uuidString.prefix(5).lowercased()))"
        let view = ViewConfig(id: viewId, name: name, type: type)
        s.views.append(view)
        schema = s
        activeViewId = viewId
        saveSchema()
    }

    func deleteView(_ viewId: String) {
        guard var s = schema else { return }
        s.views.removeAll { $0.id == viewId }
        if activeViewId == viewId {
            activeViewId = s.views.first?.id ?? ""
        }
        schema = s
        saveSchema()
    }

    func updateViewSort(propertyId: String, ascending: Bool) {
        guard var s = schema, let viewIdx = s.views.firstIndex(where: { $0.id == activeViewId }) else { return }
        s.views[viewIdx].sorts = [SortConfig(property: propertyId, direction: ascending ? "asc" : "desc")]
        schema = s
        saveSchema()
    }

    func clearViewSorts() {
        guard var s = schema, let viewIdx = s.views.firstIndex(where: { $0.id == activeViewId }) else { return }
        s.views[viewIdx].sorts = []
        schema = s
        saveSchema()
    }

    func addViewFilter(propertyId: String, op: String, value: String) {
        guard var s = schema, let viewIdx = s.views.firstIndex(where: { $0.id == activeViewId }) else { return }
        let filter = FilterConfig(property: propertyId, op: op, value: value)
        s.views[viewIdx].filters.append(filter)
        schema = s
        saveSchema()
    }

    func clearViewFilters() {
        guard var s = schema, let viewIdx = s.views.firstIndex(where: { $0.id == activeViewId }) else { return }
        s.views[viewIdx].filters = []
        s.views[viewIdx].filterGroup = nil
        schema = s
        saveSchema()
    }

    func setViewGroupBy(_ propertyId: String?) {
        guard var s = schema, let viewIdx = s.views.firstIndex(where: { $0.id == activeViewId }) else { return }
        s.views[viewIdx].groupBy = propertyId
        schema = s
        saveSchema()
    }

    func toggleColumnVisibility(_ propertyId: String) {
        guard var s = schema, let viewIdx = s.views.firstIndex(where: { $0.id == activeViewId }) else { return }
        var hidden = s.views[viewIdx].hiddenColumns ?? []
        if hidden.contains(propertyId) {
            hidden.removeAll { $0 == propertyId }
        } else {
            hidden.append(propertyId)
        }
        s.views[viewIdx].hiddenColumns = hidden
        schema = s
        saveSchema()
    }

    // MARK: - Private

    private func saveSchema() {
        guard let schema else { return }
        try? dbStore.saveSchema(schema, at: dbPath)
    }

    private func rebuildIndex() {
        guard let schema else { return }
        let index = indexManager.rebuild(dbPath: dbPath, schema: schema, rows: rows)
        try? indexManager.saveIndex(index, at: dbPath)
    }

    // MARK: - Filter Matching

    private func matchesFilterGroup(_ row: DatabaseRow, group: FilterGroup, schema: DatabaseSchema) -> Bool {
        let results = group.conditions.map { condition -> Bool in
            switch condition {
            case .filter(let config):
                return matchesFilter(row.properties[config.property] ?? .empty, filter: config)
            case .group(let subGroup):
                return matchesFilterGroup(row, group: subGroup, schema: schema)
            }
        }
        switch group.conjunction {
        case .and: return results.allSatisfy { $0 }
        case .or: return results.contains(true)
        }
    }

    private func matchesFilter(_ value: PropertyValue, filter: FilterConfig) -> Bool {
        let str = value.stringValue
        switch filter.op {
        case "equals": return str == filter.value
        case "not_equals": return str != filter.value
        case "contains": return str.localizedCaseInsensitiveContains(filter.value)
        case "not_contains": return !str.localizedCaseInsensitiveContains(filter.value)
        case "is_empty": return str.isEmpty
        case "is_not_empty": return !str.isEmpty
        default: return true
        }
    }

    private func compareValues(_ a: PropertyValue, _ b: PropertyValue) -> ComparisonResult {
        switch (a, b) {
        case (.number(let na), .number(let nb)):
            if na < nb { return .orderedAscending }
            if na > nb { return .orderedDescending }
            return .orderedSame
        case (.empty, .empty): return .orderedSame
        case (.empty, _): return .orderedDescending
        case (_, .empty): return .orderedAscending
        default:
            return a.stringValue.localizedCaseInsensitiveCompare(b.stringValue)
        }
    }
}
