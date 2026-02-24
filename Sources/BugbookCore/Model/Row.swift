import Foundation

// MARK: - Property Value

public enum PropertyValue: Equatable, Codable, Sendable {
    case text(String)
    case number(Double)
    case select(String)
    case multiSelect([String])
    case date(String)
    case checkbox(Bool)
    case url(String)
    case email(String)
    case relation(String)
    case relationMany([String])
    case empty

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case type, value
    }

    private enum ValueType: String, Codable {
        case text, number, select, multiSelect, date, checkbox, url, email, relation, relationMany, empty
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(ValueType.self, forKey: .type)
        switch type {
        case .text: self = .text(try container.decode(String.self, forKey: .value))
        case .number: self = .number(try container.decode(Double.self, forKey: .value))
        case .select: self = .select(try container.decode(String.self, forKey: .value))
        case .multiSelect: self = .multiSelect(try container.decode([String].self, forKey: .value))
        case .date: self = .date(try container.decode(String.self, forKey: .value))
        case .checkbox: self = .checkbox(try container.decode(Bool.self, forKey: .value))
        case .url: self = .url(try container.decode(String.self, forKey: .value))
        case .email: self = .email(try container.decode(String.self, forKey: .value))
        case .relation: self = .relation(try container.decode(String.self, forKey: .value))
        case .relationMany: self = .relationMany(try container.decode([String].self, forKey: .value))
        case .empty: self = .empty
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let val):
            try container.encode(ValueType.text, forKey: .type)
            try container.encode(val, forKey: .value)
        case .number(let val):
            try container.encode(ValueType.number, forKey: .type)
            try container.encode(val, forKey: .value)
        case .select(let val):
            try container.encode(ValueType.select, forKey: .type)
            try container.encode(val, forKey: .value)
        case .multiSelect(let val):
            try container.encode(ValueType.multiSelect, forKey: .type)
            try container.encode(val, forKey: .value)
        case .date(let val):
            try container.encode(ValueType.date, forKey: .type)
            try container.encode(val, forKey: .value)
        case .checkbox(let val):
            try container.encode(ValueType.checkbox, forKey: .type)
            try container.encode(val, forKey: .value)
        case .url(let val):
            try container.encode(ValueType.url, forKey: .type)
            try container.encode(val, forKey: .value)
        case .email(let val):
            try container.encode(ValueType.email, forKey: .type)
            try container.encode(val, forKey: .value)
        case .relation(let val):
            try container.encode(ValueType.relation, forKey: .type)
            try container.encode(val, forKey: .value)
        case .relationMany(let val):
            try container.encode(ValueType.relationMany, forKey: .type)
            try container.encode(val, forKey: .value)
        case .empty:
            try container.encode(ValueType.empty, forKey: .type)
        }
    }

    /// String representation for display/comparison
    public var stringValue: String {
        switch self {
        case .text(let s): return s
        case .number(let n): return n == n.rounded() && n < 1e15 ? String(Int(n)) : String(n)
        case .select(let s): return s
        case .multiSelect(let arr): return arr.joined(separator: ",")
        case .date(let s): return s
        case .checkbox(let b): return b ? "true" : "false"
        case .url(let s): return s
        case .email(let s): return s
        case .relation(let s): return s
        case .relationMany(let arr): return arr.joined(separator: ",")
        case .empty: return ""
        }
    }
}

// MARK: - Database Row

public struct DatabaseRow: Identifiable, Equatable, Sendable {
    public let id: String
    public var properties: [String: PropertyValue]
    public var body: String
    public var createdAt: Date
    public var updatedAt: Date

    public init(id: String, properties: [String: PropertyValue] = [:], body: String = "",
                createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id
        self.properties = properties
        self.body = body
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// Derive title from whichever property has type "title" in the schema
    public func title(schema: DatabaseSchema) -> String {
        guard let titleProp = schema.titleProperty,
              let val = properties[titleProp.id],
              case .text(let s) = val, !s.isEmpty else {
            return "New Page"
        }
        return s
    }
}

