import Foundation

@MainActor
class DatabaseService: ObservableObject {
    private let fileManager = FileManager.default

    // MARK: - Load Database

    func loadDatabase(at path: String) async throws -> (DatabaseSchema, [DatabaseRow]) {
        let schemaPath = (path as NSString).appendingPathComponent("_schema.md")
        let schemaContent = try String(contentsOfFile: schemaPath, encoding: .utf8)
        let schema = try parseSchema(from: schemaContent)
        let rows = try loadRows(in: path, schema: schema)
        return (schema, rows)
    }

    // MARK: - Save Schema

    func saveSchema(_ schema: DatabaseSchema, at path: String) throws {
        let schemaPath = (path as NSString).appendingPathComponent("_schema.md")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let jsonData = try encoder.encode(schema)
        let jsonString = String(data: jsonData, encoding: .utf8) ?? "{}"
        let content = "---\nschema: \(jsonString)\n---\n"
        try content.write(toFile: schemaPath, atomically: true, encoding: .utf8)
    }

    // MARK: - Save Row

    func saveRow(_ row: DatabaseRow, schema: DatabaseSchema, at dbPath: String) throws {
        let filename = rowFilename(for: row)
        let filePath = (dbPath as NSString).appendingPathComponent(filename)

        // Remove old file if title changed (different filename)
        let contents = try? fileManager.contentsOfDirectory(atPath: dbPath)
        if let contents = contents {
            for name in contents {
                if name.contains("(\(row.id))") && name != filename {
                    let oldPath = (dbPath as NSString).appendingPathComponent(name)
                    try? fileManager.removeItem(atPath: oldPath)
                }
            }
        }

        var frontmatter = "---\n"
        frontmatter += "id: \(row.id)\n"
        frontmatter += "createdAt: \(dateString(from: row.createdAt))\n"
        frontmatter += "updatedAt: \(dateString(from: row.updatedAt))\n"
        frontmatter += "fullWidth: \(row.fullWidth)\n"

        if !row.properties.isEmpty {
            frontmatter += "properties:\n"
            for prop in schema.properties {
                if let value = row.properties[prop.name] {
                    let serialized = serializePropertyValue(value)
                    if !serialized.isEmpty {
                        frontmatter += "  \(prop.name): \(serialized)\n"
                    }
                }
            }
        }

        frontmatter += "---\n"

        let bodyContent: String
        if row.body.isEmpty {
            bodyContent = "\n# \(row.title)\n"
        } else {
            bodyContent = "\n\(row.body)"
        }

        let fileContent = frontmatter + bodyContent
        try fileContent.write(toFile: filePath, atomically: true, encoding: .utf8)
    }

    // MARK: - Create Row

    func createRow(in dbPath: String, schema: DatabaseSchema) throws -> DatabaseRow {
        let now = Date()
        let row = DatabaseRow(
            id: "row_\(UUID().uuidString)",
            title: "Untitled",
            properties: [:],
            body: "",
            createdAt: now,
            updatedAt: now,
            fullWidth: false
        )
        try saveRow(row, schema: schema, at: dbPath)
        try updateIndex(rows: try loadRows(in: dbPath, schema: schema), at: dbPath)
        return row
    }

    // MARK: - Delete Row

    func deleteRow(_ rowId: String, in dbPath: String) throws {
        guard let contents = try? fileManager.contentsOfDirectory(atPath: dbPath) else { return }
        for name in contents {
            if name.contains("(\(rowId))") && name.hasSuffix(".md") {
                let filePath = (dbPath as NSString).appendingPathComponent(name)
                try fileManager.removeItem(atPath: filePath)
                break
            }
        }
    }

    // MARK: - Schema Operations

    func addProperty(_ property: PropertyDefinition, to schema: inout DatabaseSchema, at dbPath: String) throws {
        schema.properties.append(property)
        try saveSchema(schema, at: dbPath)
    }

    func updateProperty(_ property: PropertyDefinition, in schema: inout DatabaseSchema, at dbPath: String) throws {
        guard let idx = schema.properties.firstIndex(where: { $0.id == property.id }) else { return }
        schema.properties[idx] = property
        try saveSchema(schema, at: dbPath)
    }

    func deleteProperty(_ propertyId: String, from schema: inout DatabaseSchema, at dbPath: String) throws {
        schema.properties.removeAll { $0.id == propertyId }
        try saveSchema(schema, at: dbPath)
    }

    func renameProperty(_ propertyId: String, to newName: String, in schema: inout DatabaseSchema, rows: inout [DatabaseRow], at dbPath: String) throws {
        guard let idx = schema.properties.firstIndex(where: { $0.id == propertyId }) else { return }
        let oldName = schema.properties[idx].name
        schema.properties[idx].name = newName
        try saveSchema(schema, at: dbPath)
        // Migrate row data from old key to new key
        for i in rows.indices {
            if let val = rows[i].properties.removeValue(forKey: oldName) {
                rows[i].properties[newName] = val
            }
            try saveRow(rows[i], schema: schema, at: dbPath)
        }
    }

    func changePropertyType(_ propertyId: String, to newType: PropertyType, in schema: inout DatabaseSchema, rows: inout [DatabaseRow], at dbPath: String) throws {
        guard let idx = schema.properties.firstIndex(where: { $0.id == propertyId }) else { return }
        let propName = schema.properties[idx].name
        let oldType = schema.properties[idx].type
        schema.properties[idx].type = newType
        // Add empty options array for select/multiSelect types
        if newType == .select || newType == .multiSelect {
            if schema.properties[idx].options == nil {
                schema.properties[idx].options = []
            }
        } else {
            schema.properties[idx].options = nil
        }
        try saveSchema(schema, at: dbPath)
        // Convert existing values where possible
        for i in rows.indices {
            if let val = rows[i].properties[propName] {
                rows[i].properties[propName] = convertValue(val, from: oldType, to: newType)
                try saveRow(rows[i], schema: schema, at: dbPath)
            }
        }
    }

    func addSelectOption(_ option: SelectOption, toProperty propertyId: String, in schema: inout DatabaseSchema, at dbPath: String) throws {
        guard let idx = schema.properties.firstIndex(where: { $0.id == propertyId }) else { return }
        if schema.properties[idx].options == nil {
            schema.properties[idx].options = []
        }
        schema.properties[idx].options?.append(option)
        try saveSchema(schema, at: dbPath)
    }

    // MARK: - Private: Value Conversion

    private func convertValue(_ value: PropertyValue, from oldType: PropertyType, to newType: PropertyType) -> PropertyValue {
        // Extract string representation
        let str: String
        switch value {
        case .text(let s): str = s
        case .number(let n): str = n == n.rounded() ? String(Int(n)) : String(n)
        case .select(let s): str = s
        case .multiSelect(let arr): str = arr.joined(separator: ", ")
        case .date(let s): str = s
        case .checkbox(let b): str = b ? "true" : "false"
        case .url(let s): str = s
        case .email(let s): str = s
        case .empty: return .empty
        }

        // Convert to new type
        switch newType {
        case .text: return .text(str)
        case .number: return .number(Double(str) ?? 0)
        case .checkbox: return .checkbox(str == "true" || str == "1")
        case .date: return .date(str)
        case .url: return .url(str)
        case .email: return .email(str)
        case .select: return .text(str) // Can't auto-create options, store as text
        case .multiSelect: return .text(str)
        }
    }

    func reorderProperties(_ orderedIds: [String], in schema: inout DatabaseSchema, at dbPath: String) throws {
        let byId = Dictionary(uniqueKeysWithValues: schema.properties.map { ($0.id, $0) })
        schema.properties = orderedIds.compactMap { byId[$0] }
        try saveSchema(schema, at: dbPath)
    }

    // MARK: - View Operations

    func addView(_ view: ViewConfig, to schema: inout DatabaseSchema, at dbPath: String) throws {
        schema.views.append(view)
        try saveSchema(schema, at: dbPath)
    }

    func updateView(_ view: ViewConfig, in schema: inout DatabaseSchema, at dbPath: String) throws {
        guard let idx = schema.views.firstIndex(where: { $0.id == view.id }) else { return }
        schema.views[idx] = view
        try saveSchema(schema, at: dbPath)
    }

    func deleteView(_ viewId: String, from schema: inout DatabaseSchema, at dbPath: String) throws {
        schema.views.removeAll { $0.id == viewId }
        if schema.defaultViewId == viewId, let first = schema.views.first {
            schema.defaultViewId = first.id
        }
        try saveSchema(schema, at: dbPath)
    }

    func setDefaultView(_ viewId: String, in schema: inout DatabaseSchema, at dbPath: String) throws {
        schema.defaultViewId = viewId
        try saveSchema(schema, at: dbPath)
    }

    // MARK: - Update Index

    func updateIndex(rows: [DatabaseRow], at dbPath: String) throws {
        let indexPath = (dbPath as NSString).appendingPathComponent("_index.json")
        let entries: [[String: String]] = rows.map { row in
            [
                "id": row.id,
                "title": row.title,
                "updatedAt": dateString(from: row.updatedAt)
            ]
        }
        let data = try JSONSerialization.data(withJSONObject: entries, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: URL(fileURLWithPath: indexPath))
    }

    // MARK: - Private: Parse Schema

    private func parseSchema(from content: String) throws -> DatabaseSchema {
        guard content.hasPrefix("---") else {
            throw DatabaseError.invalidSchema
        }
        let afterFirstMarker = content.index(content.startIndex, offsetBy: 3)
        guard let endRange = content.range(of: "\n---", range: afterFirstMarker..<content.endIndex) else {
            throw DatabaseError.invalidSchema
        }
        let yamlBlock = String(content[afterFirstMarker..<endRange.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Find the JSON value after "schema: "
        guard let schemaRange = yamlBlock.range(of: "schema: ") ?? yamlBlock.range(of: "schema:") else {
            throw DatabaseError.invalidSchema
        }
        var jsonString = String(yamlBlock[schemaRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        // If the value doesn't start with {, it might be on the next line
        if !jsonString.hasPrefix("{") {
            throw DatabaseError.invalidSchema
        }
        // Trim anything after the closing brace at the right depth
        jsonString = extractJSON(jsonString)

        guard let jsonData = jsonString.data(using: .utf8) else {
            throw DatabaseError.invalidSchema
        }
        return try JSONDecoder().decode(DatabaseSchema.self, from: jsonData)
    }

    // MARK: - Private: Load Rows

    private func loadRows(in dbPath: String, schema: DatabaseSchema) throws -> [DatabaseRow] {
        guard let contents = try? fileManager.contentsOfDirectory(atPath: dbPath) else { return [] }
        var rows: [DatabaseRow] = []

        for name in contents {
            guard name.hasSuffix(".md"), name != "_schema.md" else { continue }
            let filePath = (dbPath as NSString).appendingPathComponent(name)
            guard let content = try? String(contentsOfFile: filePath, encoding: .utf8) else { continue }
            if let row = parseRow(from: content, schema: schema) {
                rows.append(row)
            }
        }

        return rows.sorted { $0.createdAt < $1.createdAt }
    }

    // MARK: - Private: Parse Row

    private func parseRow(from content: String, schema: DatabaseSchema) -> DatabaseRow? {
        guard content.hasPrefix("---") else { return nil }
        let afterFirstMarker = content.index(content.startIndex, offsetBy: 3)
        guard let endRange = content.range(of: "\n---", range: afterFirstMarker..<content.endIndex) else { return nil }

        let yamlBlock = String(content[afterFirstMarker..<endRange.lowerBound])
        let body = String(content[endRange.upperBound...]).trimmingCharacters(in: .newlines)

        var id = ""
        var createdAt = Date()
        var updatedAt = Date()
        var fullWidth = false
        var properties: [String: PropertyValue] = [:]
        var inProperties = false

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.timeZone = TimeZone(identifier: "UTC")

        for line in yamlBlock.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }

            if inProperties {
                // Property lines are indented with 2 spaces
                if line.hasPrefix("  ") {
                    let propLine = String(line.dropFirst(2))
                    if let colonIdx = propLine.firstIndex(of: ":") {
                        let key = String(propLine[propLine.startIndex..<colonIdx]).trimmingCharacters(in: .whitespaces)
                        let rawValue = String(propLine[propLine.index(after: colonIdx)...]).trimmingCharacters(in: .whitespaces)
                        // Find matching property definition
                        if let propDef = schema.properties.first(where: { $0.name == key }) {
                            properties[key] = parsePropertyValue(rawValue, type: propDef.type)
                        }
                    }
                } else {
                    inProperties = false
                }
            }

            if !inProperties {
                if trimmed == "properties:" {
                    inProperties = true
                } else if trimmed.hasPrefix("id:") {
                    id = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                } else if trimmed.hasPrefix("createdAt:") {
                    let val = String(trimmed.dropFirst(10)).trimmingCharacters(in: .whitespaces)
                    createdAt = dateFormatter.date(from: val) ?? Date()
                } else if trimmed.hasPrefix("updatedAt:") {
                    let val = String(trimmed.dropFirst(10)).trimmingCharacters(in: .whitespaces)
                    updatedAt = dateFormatter.date(from: val) ?? Date()
                } else if trimmed.hasPrefix("fullWidth:") {
                    let val = String(trimmed.dropFirst(10)).trimmingCharacters(in: .whitespaces)
                    fullWidth = val == "true"
                }
            }
        }

        guard !id.isEmpty else { return nil }

        // Extract title from body (first # heading) or from filename
        let title = extractTitle(from: body) ?? "Untitled"

        return DatabaseRow(
            id: id,
            title: title,
            properties: properties,
            body: body,
            createdAt: createdAt,
            updatedAt: updatedAt,
            fullWidth: fullWidth
        )
    }

    // MARK: - Private Helpers

    private func parsePropertyValue(_ raw: String, type: PropertyType) -> PropertyValue {
        let value = raw.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        if value.isEmpty { return .empty }

        switch type {
        case .text:
            return .text(value)
        case .number:
            return .number(Double(value) ?? 0)
        case .select:
            return .select(value)
        case .multiSelect:
            // Stored as comma-separated or JSON array
            if value.hasPrefix("[") {
                let items = value.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
                    .components(separatedBy: ",")
                    .map { $0.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\"")) }
                    .filter { !$0.isEmpty }
                return .multiSelect(items)
            }
            return .multiSelect(value.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) })
        case .date:
            return .date(value)
        case .checkbox:
            return .checkbox(value == "true")
        case .url:
            return .url(value)
        case .email:
            return .email(value)
        }
    }

    private func serializePropertyValue(_ value: PropertyValue) -> String {
        switch value {
        case .text(let s): return "\"\(s)\""
        case .number(let n):
            if n == n.rounded() && n < 1e15 {
                return String(Int(n))
            }
            return String(n)
        case .select(let s): return s
        case .multiSelect(let arr): return "[\(arr.map { "\"\($0)\"" }.joined(separator: ", "))]"
        case .date(let s): return s
        case .checkbox(let b): return b ? "true" : "false"
        case .url(let s): return "\"\(s)\""
        case .email(let s): return "\"\(s)\""
        case .empty: return ""
        }
    }

    private func rowFilename(for row: DatabaseRow) -> String {
        let sanitized = row.title
            .replacingOccurrences(of: "[/\\\\?%*:|\"<>]", with: "-", options: .regularExpression)
            .prefix(80)
        return "\(sanitized) (\(row.id)).md"
    }

    private func dateString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: date)
    }

    private func extractTitle(from body: String) -> String? {
        for line in body.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("# ") {
                return String(trimmed.dropFirst(2))
            }
        }
        return nil
    }

    private func extractJSON(_ input: String) -> String {
        var depth = 0
        var endIdx = input.startIndex
        for (i, ch) in input.enumerated() {
            if ch == "{" { depth += 1 }
            else if ch == "}" { depth -= 1 }
            if depth == 0 {
                endIdx = input.index(input.startIndex, offsetBy: i + 1)
                break
            }
        }
        return String(input[input.startIndex..<endIdx])
    }
}

enum DatabaseError: Error, LocalizedError {
    case invalidSchema
    case rowNotFound

    var errorDescription: String? {
        switch self {
        case .invalidSchema: return "Invalid database schema"
        case .rowNotFound: return "Database row not found"
        }
    }
}
