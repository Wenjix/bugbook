import Foundation

// MARK: - View Type

public enum ViewType: String, Codable, CaseIterable, Sendable {
    case table
    case kanban
    case list
    case calendar
}

// MARK: - Sort Config (persisted in schema)

public struct SortConfig: Codable, Identifiable, Sendable {
    public let id: String
    public var property: String
    public var direction: String

    public var ascending: Bool { direction == "asc" }

    public init(id: String = UUID().uuidString, property: String, direction: String = "asc") {
        self.id = id
        self.property = property
        self.direction = direction
    }
}

// MARK: - Filter Config (persisted in schema)

public struct FilterConfig: Codable, Identifiable, Sendable {
    public let id: String
    public var property: String
    public var op: String
    public var value: String

    public init(id: String = UUID().uuidString, property: String, op: String, value: String) {
        self.id = id
        self.property = property
        self.op = op
        self.value = value
    }
}

// MARK: - View Config

public struct ViewConfig: Identifiable, Codable, Sendable {
    public let id: String
    public var name: String
    public var type: ViewType
    public var sorts: [SortConfig]
    public var filters: [FilterConfig]
    public var columnWidths: [String: Double]?
    public var hiddenColumns: [String]?
    public var groupBy: String?
    public var dateProperty: String?

    public init(id: String, name: String, type: ViewType, sorts: [SortConfig] = [],
                filters: [FilterConfig] = [], columnWidths: [String: Double]? = nil,
                hiddenColumns: [String]? = nil, groupBy: String? = nil, dateProperty: String? = nil) {
        self.id = id
        self.name = name
        self.type = type
        self.sorts = sorts
        self.filters = filters
        self.columnWidths = columnWidths
        self.hiddenColumns = hiddenColumns
        self.groupBy = groupBy
        self.dateProperty = dateProperty
    }

    enum CodingKeys: String, CodingKey {
        case id, name, type, sorts, filters
        case columnWidths = "column_widths"
        case hiddenColumns = "hidden_columns"
        case groupBy = "group_by"
        case dateProperty = "date_property"
    }
}
