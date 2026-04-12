import Foundation

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

public enum FilterConjunction: String, Codable, Sendable {
    case and
    case or
}

public struct FilterGroup: Codable, Identifiable, Sendable {
    public let id: String
    public var conjunction: FilterConjunction
    public var conditions: [FilterCondition]

    public init(id: String = UUID().uuidString, conjunction: FilterConjunction = .and, conditions: [FilterCondition] = []) {
        self.id = id
        self.conjunction = conjunction
        self.conditions = conditions
    }
}

public enum FilterCondition: Codable, Identifiable, Sendable {
    case filter(FilterConfig)
    case group(FilterGroup)

    public var id: String {
        switch self {
        case .filter(let f): return f.id
        case .group(let g): return g.id
        }
    }

    private enum CodingKeys: String, CodingKey {
        case type, filter, group
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "filter":
            let f = try container.decode(FilterConfig.self, forKey: .filter)
            self = .filter(f)
        case "group":
            let g = try container.decode(FilterGroup.self, forKey: .group)
            self = .group(g)
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unknown FilterCondition type: \(type)")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .filter(let f):
            try container.encode("filter", forKey: .type)
            try container.encode(f, forKey: .filter)
        case .group(let g):
            try container.encode("group", forKey: .type)
            try container.encode(g, forKey: .group)
        }
    }
}

public struct ViewConfig: Identifiable, Codable, Sendable {
    public let id: String
    public var name: String
    public var type: ViewType
    public var sorts: [SortConfig]
    public var filters: [FilterConfig]
    public var filterGroup: FilterGroup?
    public var columnWidths: [String: Double]?
    public var hiddenColumns: [String]?
    public var wrapCellText: Bool?
    public var groupBy: String?
    public var dateProperty: String?
    public var manualRowOrder: [String]?
    public var subGroupBy: String?
    public var hideTitle: Bool?
    public var calculations: [String: String]?

    public init(id: String, name: String, type: ViewType, sorts: [SortConfig] = [],
                filters: [FilterConfig] = [], filterGroup: FilterGroup? = nil,
                columnWidths: [String: Double]? = nil,
                hiddenColumns: [String]? = nil, wrapCellText: Bool? = nil,
                groupBy: String? = nil, dateProperty: String? = nil,
                manualRowOrder: [String]? = nil, subGroupBy: String? = nil,
                hideTitle: Bool? = nil, calculations: [String: String]? = nil) {
        self.id = id
        self.name = name
        self.type = type
        self.sorts = sorts
        self.filters = filters
        self.filterGroup = filterGroup
        self.columnWidths = columnWidths
        self.hiddenColumns = hiddenColumns
        self.wrapCellText = wrapCellText
        self.groupBy = groupBy
        self.dateProperty = dateProperty
        self.manualRowOrder = manualRowOrder
        self.subGroupBy = subGroupBy
        self.hideTitle = hideTitle
        self.calculations = calculations
    }

    enum CodingKeys: String, CodingKey {
        case id, name, type, sorts, filters, calculations
        case filterGroup = "filter_group"
        case columnWidths = "column_widths"
        case hiddenColumns = "hidden_columns"
        case wrapCellText = "wrap_cell_text"
        case groupBy = "group_by"
        case dateProperty = "date_property"
        case manualRowOrder = "manual_row_order"
        case subGroupBy = "sub_group_by"
        case hideTitle = "hide_title"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        type = try container.decode(ViewType.self, forKey: .type)
        sorts = try container.decodeIfPresent([SortConfig].self, forKey: .sorts) ?? []
        filters = try container.decodeIfPresent([FilterConfig].self, forKey: .filters) ?? []
        filterGroup = try container.decodeIfPresent(FilterGroup.self, forKey: .filterGroup)
        columnWidths = try container.decodeIfPresent([String: Double].self, forKey: .columnWidths)
        hiddenColumns = try container.decodeIfPresent([String].self, forKey: .hiddenColumns)
        wrapCellText = try container.decodeIfPresent(Bool.self, forKey: .wrapCellText)
        groupBy = try container.decodeIfPresent(String.self, forKey: .groupBy)
        dateProperty = try container.decodeIfPresent(String.self, forKey: .dateProperty)
        manualRowOrder = try container.decodeIfPresent([String].self, forKey: .manualRowOrder)
        subGroupBy = try container.decodeIfPresent(String.self, forKey: .subGroupBy)
        hideTitle = try container.decodeIfPresent(Bool.self, forKey: .hideTitle)
        calculations = try container.decodeIfPresent([String: String].self, forKey: .calculations)

        // Migration: wrap legacy flat filters into an AND group
        if filterGroup == nil && !filters.isEmpty {
            filterGroup = FilterGroup(conjunction: .and, conditions: filters.map { .filter($0) })
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(type, forKey: .type)
        try container.encode(sorts, forKey: .sorts)
        try container.encode(filters, forKey: .filters)
        try container.encodeIfPresent(filterGroup, forKey: .filterGroup)
        try container.encodeIfPresent(columnWidths, forKey: .columnWidths)
        try container.encodeIfPresent(hiddenColumns, forKey: .hiddenColumns)
        try container.encodeIfPresent(wrapCellText, forKey: .wrapCellText)
        try container.encodeIfPresent(groupBy, forKey: .groupBy)
        try container.encodeIfPresent(dateProperty, forKey: .dateProperty)
        try container.encodeIfPresent(manualRowOrder, forKey: .manualRowOrder)
        try container.encodeIfPresent(subGroupBy, forKey: .subGroupBy)
        try container.encodeIfPresent(hideTitle, forKey: .hideTitle)
        try container.encodeIfPresent(calculations, forKey: .calculations)
    }
}
