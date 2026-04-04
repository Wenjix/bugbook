import ArgumentParser
import Foundation
import BugbookCore

enum CLIError: Error, CustomStringConvertible {
    case databaseNotFound(String)
    case invalidFilter(String)
    case invalidSort(String)
    case fileNotFound(String)
    case invalidInput(String)
    case operationFailed(String)

    var description: String {
        switch self {
        case .databaseNotFound(let name): return "Database not found: \(name)"
        case .invalidFilter(let expr): return "Invalid filter expression: \(expr)"
        case .invalidSort(let expr): return "Invalid sort expression: \(expr)"
        case .fileNotFound(let path): return "File not found: \(path)"
        case .invalidInput(let msg): return "Invalid input: \(msg)"
        case .operationFailed(let msg): return "Operation failed: \(msg)"
        }
    }
}

enum MutationOutputMode: String, ExpressibleByArgument {
    case full
    case summary
}

enum PageMarkdownFormatStyle: String, ExpressibleByArgument {
    case bugbook
    case commonmark
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

    let idMatches = databases.filter { $0.id == name }
    if idMatches.count > 1 {
        let matches = idMatches
            .map { relativePath(from: $0.path, workspace: normalizedWorkspace) }
            .sorted()
            .joined(separator: ", ")
        throw CLIError.invalidInput("Database ID is ambiguous: \(name). Matches: \(matches)")
    }
    if let match = idMatches.first {
        let schema = try store.loadSchema(at: match.path)
        return (path: match.path, schema: schema)
    }

    let nameMatches = databases.filter { $0.name.lowercased() == name.lowercased() }
    if nameMatches.count > 1 {
        let matches = nameMatches
            .map { relativePath(from: $0.path, workspace: normalizedWorkspace) }
            .sorted()
            .joined(separator: ", ")
        throw CLIError.invalidInput("Database name is ambiguous: \(name). Matches: \(matches)")
    }

    guard let db = nameMatches.first else {
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
        ("!=", { prop, val, schema in .notEquals(property: prop, value: try parsePropertyValue(val, property: prop, schema: schema)) }),
        ("!~", { prop, val, schema in .notContains(property: prop, value: try parsePropertyValue(val, property: prop, schema: schema)) }),
        (">=", { prop, val, schema in throw CLIError.invalidFilter(expr) }),
        ("<=", { prop, val, schema in throw CLIError.invalidFilter(expr) }),
        ("~",  { prop, val, schema in .contains(property: prop, value: try parsePropertyValue(val, property: prop, schema: schema)) }),
        (">",  { prop, val, schema in .greaterThan(property: prop, value: try parsePropertyValue(val, property: prop, schema: schema)) }),
        ("<",  { prop, val, schema in .lessThan(property: prop, value: try parsePropertyValue(val, property: prop, schema: schema)) }),
        ("=",  { prop, val, schema in
            if val == "_empty" { return .isEmpty(property: prop) }
            if val == "_not_empty" { return .isNotEmpty(property: prop) }
            return .equals(property: prop, value: try parsePropertyValue(val, property: prop, schema: schema))
        }),
    ]

    for (op, build) in operators {
        if let range = expr.range(of: op) {
            let prop = String(expr[expr.startIndex..<range.lowerBound])
            let val = String(expr[range.upperBound...])
            guard !prop.isEmpty else { throw CLIError.invalidFilter(expr) }
            return try build(try resolveSchemaPropertyID(prop, schema: schema), val, schema)
        }
    }

    throw CLIError.invalidFilter(expr)
}

/// Parse a sort expression: "property:asc" or "property:desc"
func parseSort(_ expr: String, schema: DatabaseSchema) throws -> Sort {
    let parts = expr.split(separator: ":", maxSplits: 1)
    let property = try resolveSchemaPropertyID(String(parts[0]), schema: schema)
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
func parsePropertyValue(_ raw: String, property: String, schema: DatabaseSchema) throws -> PropertyValue {
    guard let propDef = try resolveSchemaPropertyDefinition(property, schema: schema) else {
        // Fall back to text if property not found
        return .text(raw)
    }

    switch propDef.type {
    case .title, .text:
        return .text(raw)
    case .number:
        return .number(Double(raw) ?? 0)
    case .select:
        return .select(try resolveSelectOptionID(raw, definition: propDef))
    case .multiSelect:
        let items = try raw
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .map { try resolveSelectOptionID($0, definition: propDef) }
        return .multiSelect(items)
    case .date:
        return .date(raw)
    case .checkbox:
        return .checkbox(parseBoolLiteral(raw))
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
    case .formula:
        // Formula values are computed, not set directly.
        return .empty
    case .lookup:
        // Lookup is computed; treat raw input as text.
        return .text(raw)
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
        let resolvedKey = try resolveSchemaPropertyID(key, schema: schema)
        properties[resolvedKey] = try parsePropertyValue(val, property: resolvedKey, schema: schema)
    }
    return properties
}

func resolveSchemaPropertyID(_ property: String, schema: DatabaseSchema) throws -> String {
    guard let definition = try resolveSchemaPropertyDefinition(property, schema: schema) else {
        throw CLIError.invalidInput("Property not found: \(property)")
    }
    return definition.id
}

private func resolveSchemaPropertyDefinition(_ property: String, schema: DatabaseSchema) throws -> PropertyDefinition? {
    if let exactID = schema.properties.first(where: { $0.id == property }) {
        return exactID
    }

    let lowered = property.lowercased()
    if let caseInsensitiveID = schema.properties.first(where: { $0.id.lowercased() == lowered }) {
        return caseInsensitiveID
    }
    if let exactName = schema.properties.first(where: { $0.name.lowercased() == lowered }) {
        return exactName
    }

    let normalized = normalizeSchemaLookup(property)
    let matches = schema.properties.filter {
        normalizeSchemaLookup($0.id) == normalized || normalizeSchemaLookup($0.name) == normalized
    }
    if matches.count > 1 {
        let names = matches.map(\.name).sorted().joined(separator: ", ")
        throw CLIError.invalidInput("Property reference is ambiguous: \(property). Matches: \(names)")
    }
    return matches.first
}

private func resolveSelectOptionID(_ raw: String, definition: PropertyDefinition) throws -> String {
    guard let options = definition.config?.options else {
        return raw
    }

    if options.contains(where: { $0.id == raw }) {
        return raw
    }

    let lowered = raw.lowercased()
    if let exactName = options.first(where: { $0.name.lowercased() == lowered }) {
        return exactName.id
    }

    let normalized = normalizeSchemaLookup(raw)
    let matches = options.filter {
        normalizeSchemaLookup($0.id) == normalized || normalizeSchemaLookup($0.name) == normalized
    }
    if matches.count > 1 {
        let names = matches.map(\.name).sorted().joined(separator: ", ")
        throw CLIError.invalidInput("Option reference is ambiguous for \(definition.name): \(raw). Matches: \(names)")
    }
    guard let match = matches.first else {
        throw CLIError.invalidInput("Option not found for \(definition.name): \(raw)")
    }
    return match.id
}

private func normalizeSchemaLookup(_ value: String) -> String {
    value
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .replacingOccurrences(of: "[\\s_-]+", with: "", options: .regularExpression)
        .lowercased()
}

private func parseBoolLiteral(_ raw: String) -> Bool {
    switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
    case "true", "1", "yes", "y":
        return true
    default:
        return false
    }
}

/// Output a JSON-serializable value to stdout.
func outputJSON(_ value: Any) throws {
    let data = try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys])
    if let str = String(data: data, encoding: .utf8) {
        print(str)
    }
}

func presentedQueryProperties(
    _ rawProperties: [String: Any],
    schema: DatabaseSchema,
    fields: [String]? = nil,
    includeRawProperties: Bool = false
) -> [String: Any] {
    let fieldSet = fields.map(Set.init)
    let outputKeys = schemaPropertyOutputKeys(schema: schema)
    let definitionsByID = Dictionary(uniqueKeysWithValues: schema.properties.map { ($0.id, $0) })

    var presented: [String: Any] = [:]
    var rawOutput: [String: Any] = [:]

    for definition in schema.properties {
        if let fieldSet, !fieldSet.contains(definition.id) {
            continue
        }
        guard let rawValue = rawProperties[definition.id] else {
            continue
        }

        let outputKey = outputKeys[definition.id] ?? definition.id
        presented[outputKey] = displayPropertyValue(rawValue, definition: definition)
        if includeRawProperties {
            rawOutput[definition.id] = rawValue
        }
    }

    for (key, value) in rawProperties {
        if definitionsByID[key] != nil {
            continue
        }
        if let fieldSet, !fieldSet.contains(key) {
            continue
        }
        presented[key] = value
        if includeRawProperties {
            rawOutput[key] = value
        }
    }

    var output: [String: Any] = [
        "properties": presented,
    ]
    if includeRawProperties {
        output["raw_properties"] = rawOutput
    }
    return output
}

/// Convert a DatabaseRow to a JSON-serializable dictionary.
func rowToJSON(
    _ row: DatabaseRow,
    schema: DatabaseSchema? = nil,
    includeBody: Bool = false,
    fields: [String]? = nil,
    includeRawProperties: Bool = false
) -> [String: Any] {
    var dict: [String: Any] = [
        "id": row.id,
        "created_at": iso8601String(from: row.createdAt),
        "updated_at": iso8601String(from: row.updatedAt),
    ]

    let rawProperties = row.properties.reduce(into: [String: Any]()) { partialResult, item in
        if let fields, !fields.contains(item.key) {
            return
        }
        partialResult[item.key] = propertyValueToJSON(item.value)
    }

    if let schema {
        let presented = presentedQueryProperties(
            rawProperties,
            schema: schema,
            fields: fields,
            includeRawProperties: includeRawProperties
        )
        for (key, value) in presented {
            dict[key] = value
        }
    } else {
        dict["properties"] = rawProperties
    }

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

private func schemaPropertyOutputKeys(schema: DatabaseSchema) -> [String: String] {
    var normalizedCounts: [String: Int] = [:]
    for property in schema.properties {
        let normalized = normalizeSchemaLookup(property.name)
        normalizedCounts[normalized, default: 0] += 1
    }

    var keys: [String: String] = [:]
    for property in schema.properties {
        let normalized = normalizeSchemaLookup(property.name)
        if normalizedCounts[normalized, default: 0] > 1 {
            keys[property.id] = "\(property.name) [\(property.id)]"
        } else {
            keys[property.id] = property.name
        }
    }
    return keys
}

private func displayPropertyValue(_ rawValue: Any, definition: PropertyDefinition) -> Any {
    switch definition.type {
    case .select:
        guard let storedID = rawValue as? String else { return rawValue }
        return definition.config?.options?.first(where: { $0.id == storedID })?.name ?? storedID

    case .multiSelect:
        guard let storedIDs = rawValue as? [String] else { return rawValue }
        return storedIDs.map { storedID in
            definition.config?.options?.first(where: { $0.id == storedID })?.name ?? storedID
        }

    case .date:
        guard let raw = rawValue as? String else { return rawValue }
        return DatabaseDateValue.decode(from: raw)?.displayText() ?? raw

    default:
        return rawValue
    }
}
