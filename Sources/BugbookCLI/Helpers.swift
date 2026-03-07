import Foundation
import BugbookCore

enum CLIError: Error, CustomStringConvertible {
    case databaseNotFound(String)
    case invalidFilter(String)
    case invalidSort(String)
    case fileNotFound(String)
    case invalidInput(String)

    var description: String {
        switch self {
        case .databaseNotFound(let name): return "Database not found: \(name)"
        case .invalidFilter(let expr): return "Invalid filter expression: \(expr)"
        case .invalidSort(let expr): return "Invalid sort expression: \(expr)"
        case .fileNotFound(let path): return "File not found: \(path)"
        case .invalidInput(let msg): return "Invalid input: \(msg)"
        }
    }
}

/// Resolve a database name or ID to its path and schema.
func resolveDatabase(_ name: String, workspace: String) throws -> (path: String, schema: DatabaseSchema) {
    let fm = FileManager.default
    let expanded = (name as NSString).expandingTildeInPath
    let normalizedWorkspace = normalizePath(workspace)

    let pathCandidates: [String] = expanded.hasPrefix("/")
        ? [normalizePath(expanded)]
        : [
            normalizePath((normalizedWorkspace as NSString).appendingPathComponent(name)),
            normalizePath((normalizedWorkspace as NSString).appendingPathComponent("databases/\(name)")),
        ]

    for candidate in pathCandidates {
        let dbPath = candidate.hasSuffix("/_schema.json")
            ? (candidate as NSString).deletingLastPathComponent
            : candidate
        let schemaPath = (dbPath as NSString).appendingPathComponent("_schema.json")
        if isPathInsideWorkspace(dbPath, workspace: normalizedWorkspace),
           fm.fileExists(atPath: schemaPath) {
            let store = DatabaseStore()
            let schema = try store.loadSchema(at: dbPath)
            return (path: dbPath, schema: schema)
        }
    }

    let store = DatabaseStore()
    let databases = store.listDatabases(in: workspace)

    // Match by ID first, then by name (case-insensitive)
    let match = databases.first(where: { $0.id == name })
        ?? databases.first(where: { $0.name.lowercased() == name.lowercased() })

    guard let db = match else {
        throw CLIError.databaseNotFound(name)
    }

    let schema = try store.loadSchema(at: db.path)
    return (path: db.path, schema: schema)
}

/// Parse a filter expression string into a Filter enum.
/// Syntax: property=value, property!=value, property>value, property<value,
///         property~value, property!~value, property=_empty, property=_not_empty
func parseFilter(_ expr: String, schema: DatabaseSchema) throws -> Filter {
    // Order matters: check two-char operators before single-char
    let operators: [(op: String, build: (String, String, DatabaseSchema) throws -> Filter)] = [
        ("!=", { prop, val, schema in .notEquals(property: prop, value: parsePropertyValue(val, property: prop, schema: schema)) }),
        ("!~", { prop, val, schema in .notContains(property: prop, value: parsePropertyValue(val, property: prop, schema: schema)) }),
        (">=", { prop, val, schema in throw CLIError.invalidFilter(expr) }),
        ("<=", { prop, val, schema in throw CLIError.invalidFilter(expr) }),
        ("~",  { prop, val, schema in .contains(property: prop, value: parsePropertyValue(val, property: prop, schema: schema)) }),
        (">",  { prop, val, schema in .greaterThan(property: prop, value: parsePropertyValue(val, property: prop, schema: schema)) }),
        ("<",  { prop, val, schema in .lessThan(property: prop, value: parsePropertyValue(val, property: prop, schema: schema)) }),
        ("=",  { prop, val, schema in
            if val == "_empty" { return .isEmpty(property: prop) }
            if val == "_not_empty" { return .isNotEmpty(property: prop) }
            return .equals(property: prop, value: parsePropertyValue(val, property: prop, schema: schema))
        }),
    ]

    for (op, build) in operators {
        if let range = expr.range(of: op) {
            let prop = String(expr[expr.startIndex..<range.lowerBound])
            let val = String(expr[range.upperBound...])
            guard !prop.isEmpty else { throw CLIError.invalidFilter(expr) }
            return try build(prop, val, schema)
        }
    }

    throw CLIError.invalidFilter(expr)
}

/// Parse a sort expression: "property:asc" or "property:desc"
func parseSort(_ expr: String) throws -> Sort {
    let parts = expr.split(separator: ":", maxSplits: 1)
    let property = String(parts[0])
    let ascending: Bool
    if parts.count > 1 {
        switch parts[1].lowercased() {
        case "asc": ascending = true
        case "desc": ascending = false
        default: throw CLIError.invalidSort(expr)
        }
    } else {
        ascending = true
    }
    return Sort(property: property, ascending: ascending)
}

/// Determine the PropertyValue type from the schema and raw string value.
func parsePropertyValue(_ raw: String, property: String, schema: DatabaseSchema) -> PropertyValue {
    guard let propDef = schema.properties.first(where: { $0.id == property }) else {
        // Fall back to text if property not found
        return .text(raw)
    }

    switch propDef.type {
    case .title, .text:
        return .text(raw)
    case .number:
        return .number(Double(raw) ?? 0)
    case .select:
        return .select(raw)
    case .multiSelect:
        let items = raw.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        return .multiSelect(items)
    case .date:
        return .date(raw)
    case .checkbox:
        return .checkbox(raw == "true" || raw == "1")
    case .url:
        return .url(raw)
    case .email:
        return .email(raw)
    case .relation:
        if raw.contains(",") {
            let items = raw.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            return .relationMany(items)
        }
        return .relation(raw)
    }
}

/// Parse --set "key=value" pairs into a properties dictionary using schema types.
func parseSetValues(_ pairs: [String], schema: DatabaseSchema) throws -> [String: PropertyValue] {
    var properties: [String: PropertyValue] = [:]
    for pair in pairs {
        guard let eqIdx = pair.firstIndex(of: "=") else {
            throw CLIError.invalidInput("Set value must be key=value: \(pair)")
        }
        let key = String(pair[pair.startIndex..<eqIdx])
        let val = String(pair[pair.index(after: eqIdx)...])
        properties[key] = parsePropertyValue(val, property: key, schema: schema)
    }
    return properties
}

/// Output a JSON-serializable value to stdout.
func outputJSON(_ value: Any) throws {
    let data = try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys])
    if let str = String(data: data, encoding: .utf8) {
        print(str)
    }
}

/// Convert a DatabaseRow to a JSON-serializable dictionary.
func rowToJSON(_ row: DatabaseRow, includeBody: Bool = false, fields: [String]? = nil) -> [String: Any] {
    var dict: [String: Any] = [
        "id": row.id,
        "created_at": iso8601String(from: row.createdAt),
        "updated_at": iso8601String(from: row.updatedAt),
    ]

    var props: [String: Any] = [:]
    for (key, value) in row.properties {
        if let fields = fields, !fields.contains(key) { continue }
        props[key] = propertyValueToJSON(value)
    }
    dict["properties"] = props

    if includeBody {
        dict["body"] = row.body
    }

    return dict
}

func propertyValueToJSON(_ value: PropertyValue) -> Any {
    switch value {
    case .text(let s): return s
    case .number(let n): return n
    case .select(let s): return s
    case .multiSelect(let arr): return arr
    case .date(let s): return s
    case .checkbox(let b): return b
    case .url(let s): return s
    case .email(let s): return s
    case .relation(let s): return s
    case .relationMany(let arr): return arr
    case .empty: return NSNull()
    }
}

private let _iso8601Formatter: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime]
    return f
}()

func iso8601String(from date: Date) -> String {
    _iso8601Formatter.string(from: date)
}

func loadRow(rowId: String, dbPath: String, schema: DatabaseSchema) throws -> DatabaseRow? {
    let rowStore = RowStore()
    let suffix = RowStore.extractIdSuffix(from: rowId)
    guard let contents = try? FileManager.default.contentsOfDirectory(atPath: dbPath) else {
        return nil
    }

    for name in contents {
        if name.hasSuffix(".md") && !name.hasPrefix("_") && name.contains("(\(suffix))") {
            let filePath = (dbPath as NSString).appendingPathComponent(name)
            if let row = rowStore.loadRow(at: filePath, schema: schema), row.id == rowId {
                return row
            }
        }
    }

    return nil
}

/// Print an error to stderr and exit.
func exitWithError(_ message: String) -> Never {
    FileHandle.standardError.write(Data("Error: \(message)\n".utf8))
    _Exit(1)
}
