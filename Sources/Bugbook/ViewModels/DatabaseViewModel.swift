import SwiftUI
import BugbookCore

@Observable
class DatabaseViewModel {
    let dbPath: String
    private let rowStore = RowStore()
    private let indexManager = IndexManager()
    private let dbStore = DatabaseStore()

    var schema: DatabaseSchema?
    var rows: [DatabaseRow] = []
    var activeView: ViewConfig?
    var totalCount: Int = 0

    init(dbPath: String) { self.dbPath = dbPath }

    func load() throws {
        schema = try dbStore.loadSchema(at: dbPath)
        guard let schema else { return }
        rows = rowStore.loadAllRows(in: dbPath, schema: schema)
        activeView = schema.views.first(where: { $0.id == schema.defaultView }) ?? schema.views.first
        totalCount = rows.count
    }

    func refresh() {
        guard let schema else { return }
        let filters = (activeView?.filters ?? []).map { parseFilter($0) }
        let sorts = (activeView?.sorts ?? []).map { Sort(property: $0.property, ascending: $0.ascending) }
        let query = Query(databaseId: schema.id, filters: filters, sorts: sorts)
        let result = QueryEngine.execute(query: query, schema: schema, rows: rows)
        totalCount = result.totalCount
    }

    private func parseFilter(_ config: FilterConfig) -> Filter {
        let value = PropertyValue.text(config.value)
        switch config.op {
        case "equals": return .equals(property: config.property, value: value)
        case "not_equals": return .notEquals(property: config.property, value: value)
        case "contains": return .contains(property: config.property, value: value)
        case "not_contains": return .notContains(property: config.property, value: value)
        case "is_empty": return .isEmpty(property: config.property)
        case "is_not_empty": return .isNotEmpty(property: config.property)
        case "greater_than": return .greaterThan(property: config.property, value: value)
        case "less_than": return .lessThan(property: config.property, value: value)
        default: return .isNotEmpty(property: config.property)
        }
    }
}
