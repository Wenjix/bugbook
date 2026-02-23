import Foundation

struct DatabaseRow: Identifiable, Equatable {
    let id: String
    var title: String
    var properties: [String: PropertyValue]
    var body: String
    var createdAt: Date
    var updatedAt: Date
    var fullWidth: Bool
}

enum PropertyValue: Equatable, Codable {
    case text(String)
    case number(Double)
    case select(String)
    case multiSelect([String])
    case date(String)
    case checkbox(Bool)
    case url(String)
    case email(String)
    case empty

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case type
        case value
    }

    private enum ValueType: String, Codable {
        case text, number, select, multiSelect, date, checkbox, url, email, empty
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(ValueType.self, forKey: .type)
        switch type {
        case .text:
            self = .text(try container.decode(String.self, forKey: .value))
        case .number:
            self = .number(try container.decode(Double.self, forKey: .value))
        case .select:
            self = .select(try container.decode(String.self, forKey: .value))
        case .multiSelect:
            self = .multiSelect(try container.decode([String].self, forKey: .value))
        case .date:
            self = .date(try container.decode(String.self, forKey: .value))
        case .checkbox:
            self = .checkbox(try container.decode(Bool.self, forKey: .value))
        case .url:
            self = .url(try container.decode(String.self, forKey: .value))
        case .email:
            self = .email(try container.decode(String.self, forKey: .value))
        case .empty:
            self = .empty
        }
    }

    func encode(to encoder: Encoder) throws {
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
        case .empty:
            try container.encode(ValueType.empty, forKey: .type)
        }
    }
}
