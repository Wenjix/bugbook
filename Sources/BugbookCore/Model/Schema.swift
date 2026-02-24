import Foundation

// MARK: - Property Types

public enum PropertyType: String, Codable, CaseIterable, Sendable {
    case title
    case text
    case number
    case select
    case multiSelect = "multi_select"
    case date
    case checkbox
    case url
    case email
    case relation
}

// MARK: - Select Option

public struct SelectOption: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public var name: String
    public var color: String

    public init(id: String, name: String, color: String) {
        self.id = id
        self.name = name
        self.color = color
    }
}

// MARK: - Property Config

public struct PropertyConfig: Codable, Sendable {
    public var options: [SelectOption]?
    public var format: String?
    public var target: String?
    public var cardinality: String?

    public init(options: [SelectOption]? = nil, format: String? = nil, target: String? = nil, cardinality: String? = nil) {
        self.options = options
        self.format = format
        self.target = target
        self.cardinality = cardinality
    }
}

// MARK: - Property Definition

public struct PropertyDefinition: Identifiable, Codable, Sendable {
    public let id: String
    public var name: String
    public var type: PropertyType
    public var config: PropertyConfig?

    public init(id: String, name: String, type: PropertyType, config: PropertyConfig? = nil) {
        self.id = id
        self.name = name
        self.type = type
        self.config = config
    }

    /// Convenience accessor for select/multi_select options
    public var options: [SelectOption]? {
        get { config?.options }
        set {
            if config == nil { config = PropertyConfig() }
            config?.options = newValue
        }
    }
}

// MARK: - Database Schema

public struct DatabaseSchema: Codable, Identifiable, Sendable {
    public let id: String
    public var name: String
    public var version: Int
    public var properties: [PropertyDefinition]
    public var views: [ViewConfig]
    public var defaultView: String
    public var createdAt: String

    public init(id: String, name: String, version: Int = 1, properties: [PropertyDefinition],
                views: [ViewConfig], defaultView: String, createdAt: String) {
        self.id = id
        self.name = name
        self.version = version
        self.properties = properties
        self.views = views
        self.defaultView = defaultView
        self.createdAt = createdAt
    }

    enum CodingKeys: String, CodingKey {
        case id, name, version, properties, views
        case defaultView = "default_view"
        case createdAt = "created_at"
    }

    /// Find the property definition with type .title
    public var titleProperty: PropertyDefinition? {
        properties.first(where: { $0.type == .title })
    }
}
