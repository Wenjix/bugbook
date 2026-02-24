import Foundation

// MARK: - Query

public struct Query: Sendable {
    public let databaseId: String
    public var filters: [Filter]
    public var sorts: [Sort]
    public var limit: Int?
    public var offset: Int?
    public var includeBody: Bool
    public var fields: [String]?

    public init(databaseId: String, filters: [Filter] = [], sorts: [Sort] = [],
                limit: Int? = nil, offset: Int? = nil, includeBody: Bool = false,
                fields: [String]? = nil) {
        self.databaseId = databaseId
        self.filters = filters
        self.sorts = sorts
        self.limit = limit
        self.offset = offset
        self.includeBody = includeBody
        self.fields = fields
    }
}

// MARK: - Filter

public enum Filter: Sendable {
    case equals(property: String, value: PropertyValue)
    case notEquals(property: String, value: PropertyValue)
    case greaterThan(property: String, value: PropertyValue)
    case lessThan(property: String, value: PropertyValue)
    case contains(property: String, value: PropertyValue)
    case notContains(property: String, value: PropertyValue)
    case isEmpty(property: String)
    case isNotEmpty(property: String)
    case inList(property: String, values: [PropertyValue])

    /// The property ID this filter applies to
    public var propertyId: String {
        switch self {
        case .equals(let p, _), .notEquals(let p, _),
             .greaterThan(let p, _), .lessThan(let p, _),
             .contains(let p, _), .notContains(let p, _),
             .isEmpty(let p), .isNotEmpty(let p),
             .inList(let p, _):
            return p
        }
    }
}

// MARK: - Sort

public struct Sort: Sendable {
    public let property: String
    public let ascending: Bool

    public init(property: String, ascending: Bool = true) {
        self.property = property
        self.ascending = ascending
    }
}

// MARK: - Query Result

public struct QueryResult: Sendable {
    public let rows: [DatabaseRow]
    public let totalCount: Int
    public let hasMore: Bool

    public init(rows: [DatabaseRow], totalCount: Int, hasMore: Bool) {
        self.rows = rows
        self.totalCount = totalCount
        self.hasMore = hasMore
    }
}

// MARK: - Mutation

public struct Mutation: Sendable {
    public let databaseId: String
    public let operations: [Operation]

    public init(databaseId: String, operations: [Operation]) {
        self.databaseId = databaseId
        self.operations = operations
    }
}

public enum Operation: Sendable {
    case createRow(properties: [String: PropertyValue], body: String?)
    case updateRow(rowId: String, properties: [String: PropertyValue])
    case updateRowBody(rowId: String, body: String)
    case deleteRow(rowId: String)
}

// MARK: - Mutation Result

public struct MutationResult: Sendable {
    public let created: [String]
    public let updated: [String]
    public let deleted: [String]
    public let errors: [MutationError]

    public init(created: [String] = [], updated: [String] = [], deleted: [String] = [],
                errors: [MutationError] = []) {
        self.created = created
        self.updated = updated
        self.deleted = deleted
        self.errors = errors
    }

    public var hasErrors: Bool { !errors.isEmpty }
}

public struct MutationError: Sendable, CustomStringConvertible {
    public let operation: Int
    public let message: String

    public init(operation: Int, message: String) {
        self.operation = operation
        self.message = message
    }

    public var description: String { "Operation \(operation): \(message)" }
}

// MARK: - Validation Error

public struct ValidationError: Sendable, CustomStringConvertible {
    public let propertyId: String
    public let message: String

    public init(propertyId: String, message: String) {
        self.propertyId = propertyId
        self.message = message
    }

    public var description: String { "\(propertyId): \(message)" }
}

// MARK: - Database Info

public struct DatabaseInfo: Sendable {
    public let id: String
    public let name: String
    public let path: String
    public let rowCount: Int

    public init(id: String, name: String, path: String, rowCount: Int) {
        self.id = id
        self.name = name
        self.path = path
        self.rowCount = rowCount
    }
}
