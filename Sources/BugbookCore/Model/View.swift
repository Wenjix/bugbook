import Foundation

// MARK: - View Type

public enum ViewType: String, Codable, CaseIterable, Sendable {
    case table
    case kanban
    case list
    case calendar

    public var systemImageName: String {
        switch self {
        case .table: return "tablecells"
        case .kanban: return "rectangle.split.3x1"
        case .list: return "list.bullet"
        case .calendar: return "calendar"
        }
    }
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
    public var wrapCellText: Bool?
    public var groupBy: String?
    public var dateProperty: String?
    public var manualRowOrder: [String]?
    public var subGroupBy: String?
    public var calculations: [String: String]?

    public init(id: String, name: String, type: ViewType, sorts: [SortConfig] = [],
                filters: [FilterConfig] = [], columnWidths: [String: Double]? = nil,
                hiddenColumns: [String]? = nil, wrapCellText: Bool? = nil,
                groupBy: String? = nil, dateProperty: String? = nil,
                manualRowOrder: [String]? = nil, subGroupBy: String? = nil,
                calculations: [String: String]? = nil) {
        self.id = id
        self.name = name
        self.type = type
        self.sorts = sorts
        self.filters = filters
        self.columnWidths = columnWidths
        self.hiddenColumns = hiddenColumns
        self.wrapCellText = wrapCellText
        self.groupBy = groupBy
        self.dateProperty = dateProperty
        self.manualRowOrder = manualRowOrder
        self.subGroupBy = subGroupBy
        self.calculations = calculations
    }

    enum CodingKeys: String, CodingKey {
        case id, name, type, sorts, filters, calculations
        case columnWidths = "column_widths"
        case hiddenColumns = "hidden_columns"
        case wrapCellText = "wrap_cell_text"
        case groupBy = "group_by"
        case dateProperty = "date_property"
        case manualRowOrder = "manual_row_order"
        case subGroupBy = "sub_group_by"
    }
}
