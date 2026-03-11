import Foundation
import BugbookCore

class DatabaseService {
    private let fileManager = FileManager.default

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static let dateOnlyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()

    // MARK: - ID Generation

    private static let alphanumericChars = Array("abcdefghijklmnopqrstuvwxyz0123456789")

    private func randomAlphanumeric(_ length: Int) -> String {
        String((0..<length).map { _ in Self.alphanumericChars.randomElement()! })
    }

    // MARK: - Load Database

    func loadDatabase(at path: String) throws -> (DatabaseSchema, [DatabaseRow]) {
        let schemaPath = (path as NSString).appendingPathComponent("_schema.json")
        let data = try Data(contentsOf: URL(fileURLWithPath: schemaPath))
        let schema = try JSONDecoder().decode(DatabaseSchema.self, from: data)
        let rows = try loadRows(in: path, schema: schema)
        return (schema, rows)
    }

    // MARK: - Save Schema

    func saveSchema(_ schema: DatabaseSchema, at path: String) throws {
        let schemaPath = (path as NSString).appendingPathComponent("_schema.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(schema)
        try data.write(to: URL(fileURLWithPath: schemaPath), options: .atomic)
    }

    // MARK: - Save Row

    func saveRow(_ row: DatabaseRow, schema: DatabaseSchema, at dbPath: String) throws {
        let title = row.title(schema: schema)
        let suffix = extractIdSuffix(from: row.id)
        let filename = rowFilename(title: title, suffix: suffix)
        let filePath = (dbPath as NSString).appendingPathComponent(filename)

        // Single directory listing for both body preservation and stale file cleanup.
        let dirContents = try? fileManager.contentsOfDirectory(atPath: dbPath)

        // If the row has no in-memory body, preserve the existing body on disk
        // (rows loaded without body for table/kanban performance).
        var effectiveBody = row.body
        if effectiveBody.isEmpty, let dirContents {
            for name in dirContents where name.hasSuffix(".md") && name.contains("(\(suffix))") {
                let existingPath = (dbPath as NSString).appendingPathComponent(name)
                if let existing = try? String(contentsOfFile: existingPath, encoding: .utf8) {
                    effectiveBody = extractBody(from: existing)
                    break
                }
            }
        }

        // Remove old file if title changed (different filename)
        if let dirContents {
            for name in dirContents where name.contains("(\(suffix))") && name != filename {
                let oldPath = (dbPath as NSString).appendingPathComponent(name)
                try? fileManager.removeItem(atPath: oldPath)
            }
        }

        var frontmatter = "---\n"
        frontmatter += "id: \(row.id)\n"
        frontmatter += "created_at: \(iso8601String(from: row.createdAt))\n"
        frontmatter += "updated_at: \(iso8601String(from: row.updatedAt))\n"

        if !row.properties.isEmpty {
            frontmatter += "properties:\n"
            for prop in schema.properties {
                if let value = row.properties[prop.id] {
                    let serialized = serializePropertyValue(value)
                    if !serialized.isEmpty {
                        frontmatter += "  \(prop.id): \(serialized)\n"
                    }
                }
            }
        }

        frontmatter += "---\n"

        let bodyContent: String
        if effectiveBody.isEmpty {
            bodyContent = "\n"
        } else {
            bodyContent = "\n\(effectiveBody)"
        }

        let fileContent = frontmatter + bodyContent
        try fileContent.write(toFile: filePath, atomically: true, encoding: .utf8)
    }

    // MARK: - Load Row Body (on demand)

    func loadRowBody(rowId: String, at dbPath: String) -> String {
        let suffix = extractIdSuffix(from: rowId)
        guard let contents = try? fileManager.contentsOfDirectory(atPath: dbPath) else { return "" }
        for name in contents where name.hasSuffix(".md") && name.contains("(\(suffix))") {
            let filePath = (dbPath as NSString).appendingPathComponent(name)
            if let content = try? String(contentsOfFile: filePath, encoding: .utf8) {
                return extractBody(from: content)
            }
        }
        return ""
    }

    private func extractBody(from content: String) -> String {
        guard content.hasPrefix("---") else { return content }
        let afterFirst = content.index(content.startIndex, offsetBy: 3)
        guard let endRange = content.range(of: "\n---", range: afterFirst..<content.endIndex) else { return "" }
        return String(content[endRange.upperBound...]).trimmingCharacters(in: .newlines)
    }

    // MARK: - Create Row

    func createRow(in dbPath: String, schema: DatabaseSchema) throws -> DatabaseRow {
        let now = Date()
        let suffix = randomAlphanumeric(6)
        let rowId = "row_\(suffix)"

        var properties: [String: PropertyValue] = [:]
        // Set default title
        if let titleProp = schema.titleProperty {
            properties[titleProp.id] = .text("")
        }

        let row = DatabaseRow(
            id: rowId,
            properties: properties,
            body: "",
            createdAt: now,
            updatedAt: now
        )
        try saveRow(row, schema: schema, at: dbPath)
        try updateIndex(rows: try loadRows(in: dbPath, schema: schema), schema: schema, at: dbPath)
        return row
    }

    // MARK: - Delete Row

    func deleteRow(_ rowId: String, in dbPath: String) throws {
        let suffix = extractIdSuffix(from: rowId)
        guard let contents = try? fileManager.contentsOfDirectory(atPath: dbPath) else { return }
        for name in contents {
            if name.contains("(\(suffix))") && name.hasSuffix(".md") {
                let filePath = (dbPath as NSString).appendingPathComponent(name)
                try fileManager.removeItem(atPath: filePath)
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
        schema.properties[idx].name = newName
        try saveSchema(schema, at: dbPath)
        // Row properties are keyed by ID, not name — no row migration needed.
        // But re-save rows so filenames update if the title property was renamed.
        for i in rows.indices {
            try saveRow(rows[i], schema: schema, at: dbPath)
        }
    }

    func changePropertyType(_ propertyId: String, to newType: PropertyType, in schema: inout DatabaseSchema, rows: inout [DatabaseRow], at dbPath: String) throws {
        guard let idx = schema.properties.firstIndex(where: { $0.id == propertyId }) else { return }
        let oldType = schema.properties[idx].type
        schema.properties[idx].type = newType
        // Add empty options for select/multiSelect types
        if newType == .select || newType == .multiSelect {
            if schema.properties[idx].config == nil {
                schema.properties[idx].config = PropertyConfig(options: [])
            } else if schema.properties[idx].config?.options == nil {
                schema.properties[idx].config?.options = []
            }
        }
        // Set up relation config with empty target
        if newType == .relation {
            if schema.properties[idx].config == nil {
                schema.properties[idx].config = PropertyConfig(target: nil)
            }
        }
        try saveSchema(schema, at: dbPath)
        // Convert existing values where possible
        for i in rows.indices {
            if let val = rows[i].properties[propertyId] {
                rows[i].properties[propertyId] = convertValue(val, from: oldType, to: newType)
                try saveRow(rows[i], schema: schema, at: dbPath)
            }
        }
    }

    func addSelectOption(_ option: SelectOption, toProperty propertyId: String, in schema: inout DatabaseSchema, at dbPath: String) throws {
        guard let idx = schema.properties.firstIndex(where: { $0.id == propertyId }) else { return }
        if schema.properties[idx].config == nil {
            schema.properties[idx].config = PropertyConfig(options: [])
        }
        if schema.properties[idx].config?.options == nil {
            schema.properties[idx].config?.options = []
        }
        schema.properties[idx].config?.options?.append(option)
        try saveSchema(schema, at: dbPath)
    }

    func updateSelectOption(_ optionId: String, name: String?, color: String?, inProperty propertyId: String, in schema: inout DatabaseSchema, at dbPath: String) throws {
        guard let propIdx = schema.properties.firstIndex(where: { $0.id == propertyId }),
              let optIdx = schema.properties[propIdx].config?.options?.firstIndex(where: { $0.id == optionId }) else { return }
        if let name = name {
            schema.properties[propIdx].config?.options?[optIdx].name = name
        }
        if let color = color {
            schema.properties[propIdx].config?.options?[optIdx].color = color
        }
        try saveSchema(schema, at: dbPath)
    }

    func deleteSelectOption(_ optionId: String, fromProperty propertyId: String, in schema: inout DatabaseSchema, rows: inout [DatabaseRow], at dbPath: String) throws {
        guard let propIdx = schema.properties.firstIndex(where: { $0.id == propertyId }) else { return }
        schema.properties[propIdx].config?.options?.removeAll { $0.id == optionId }
        try saveSchema(schema, at: dbPath)
        // Clear this option from any rows that reference it
        for i in rows.indices {
            guard let val = rows[i].properties[propertyId] else { continue }
            switch val {
            case .select(let id) where id == optionId:
                rows[i].properties[propertyId] = .empty
                try saveRow(rows[i], schema: schema, at: dbPath)
            case .multiSelect(var ids):
                let before = ids.count
                ids.removeAll { $0 == optionId }
                if ids.count != before {
                    rows[i].properties[propertyId] = ids.isEmpty ? .empty : .multiSelect(ids)
                    try saveRow(rows[i], schema: schema, at: dbPath)
                }
            default:
                break
            }
        }
    }

    // MARK: - Private: Value Conversion

    private func convertValue(_ value: PropertyValue, from oldType: PropertyType, to newType: PropertyType) -> PropertyValue {
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
        case .relation(let s): str = s
        case .relationMany(let arr): str = arr.joined(separator: ", ")
        case .empty: return .empty
        }

        switch newType {
        case .title, .text: return .text(str)
        case .number: return .number(Double(str) ?? 0)
        case .checkbox: return .checkbox(str == "true" || str == "1")
        case .date: return .date(str)
        case .url: return .url(str)
        case .email: return .email(str)
        case .select: return .text(str)
        case .multiSelect: return .text(str)
        case .relation: return .relation(str)
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
        if schema.defaultView == viewId, let first = schema.views.first {
            schema.defaultView = first.id
        }
        try saveSchema(schema, at: dbPath)
    }

    func setDefaultView(_ viewId: String, in schema: inout DatabaseSchema, at dbPath: String) throws {
        schema.defaultView = viewId
        try saveSchema(schema, at: dbPath)
    }

    // MARK: - Update Index

    func updateIndex(rows: [DatabaseRow], schema: DatabaseSchema, at dbPath: String) throws {
        let indexPath = (dbPath as NSString).appendingPathComponent("_index.json")

        // Build rows map
        var rowsMap: [String: Any] = [:]
        for row in rows {
            let title = row.title(schema: schema)
            let suffix = extractIdSuffix(from: row.id)

            // Build serializable properties
            var props: [String: Any] = [:]
            for prop in schema.properties {
                if let val = row.properties[prop.id] {
                    props[prop.id] = serializePropertyValueForIndex(val)
                }
            }

            let filename = rowFilename(title: title, suffix: suffix).replacingOccurrences(of: ".md", with: "")
            let filePath = (dbPath as NSString).appendingPathComponent("\(filename).md")
            let mtime: Int
            if let attrs = try? fileManager.attributesOfItem(atPath: filePath),
               let modDate = attrs[.modificationDate] as? Date {
                mtime = Int(modDate.timeIntervalSince1970 * 1000)
            } else {
                mtime = Int(row.updatedAt.timeIntervalSince1970 * 1000)
            }

            rowsMap[row.id] = [
                "properties": props,
                "created_at": iso8601String(from: row.createdAt),
                "updated_at": iso8601String(from: row.updatedAt),
                "filename": filename,
                "mtime": mtime
            ] as [String: Any]
        }

        // Build reverse indexes for indexed property types
        let indexedTypes: Set<PropertyType> = [.select, .multiSelect, .relation, .checkbox]
        var indexes: [String: [String: [String]]] = [:]
        for prop in schema.properties where indexedTypes.contains(prop.type) {
            var propIndex: [String: [String]] = [:]
            for row in rows {
                guard let val = row.properties[prop.id] else { continue }
                switch val {
                case .select(let optId):
                    propIndex[optId, default: []].append(row.id)
                case .multiSelect(let optIds):
                    for optId in optIds {
                        propIndex[optId, default: []].append(row.id)
                    }
                case .relation(let rowId):
                    propIndex[rowId, default: []].append(row.id)
                case .relationMany(let rowIds):
                    for rid in rowIds {
                        propIndex[rid, default: []].append(row.id)
                    }
                case .checkbox(let b):
                    let key = b ? "true" : "false"
                    propIndex[key, default: []].append(row.id)
                default:
                    break
                }
            }
            if !propIndex.isEmpty {
                indexes[prop.id] = propIndex
            }
        }

        let indexObj: [String: Any] = [
            "version": 1,
            "updated_at": iso8601String(from: Date()),
            "rows": rowsMap,
            "indexes": indexes
        ]

        let data = try JSONSerialization.data(withJSONObject: indexObj, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: URL(fileURLWithPath: indexPath), options: .atomic)
    }

    // MARK: - Private: Load Rows

    private func loadRows(in dbPath: String, schema: DatabaseSchema) throws -> [DatabaseRow] {
        guard let contents = try? fileManager.contentsOfDirectory(atPath: dbPath) else { return [] }

        // Track best row per ID and filenames to detect duplicates.
        var bestByID: [String: (row: DatabaseRow, filename: String, repaired: Bool)] = [:]
        var duplicateFiles: [String] = []

        for name in contents {
            guard name.hasSuffix(".md"), !name.hasPrefix("_") else { continue }
            let filePath = (dbPath as NSString).appendingPathComponent(name)
            guard let content = try? String(contentsOfFile: filePath, encoding: .utf8) else { continue }
            guard let parsed = parseRow(from: content, schema: schema, skipBody: true) else { continue }

            let rowId = parsed.row.id
            if let existing = bestByID[rowId] {
                // Keep the one whose filename matches the canonical suffix pattern.
                let suffix = extractIdSuffix(from: rowId)
                let existingIsCanonical = existing.filename.contains("(\(suffix))")
                let newIsCanonical = name.contains("(\(suffix))")

                if newIsCanonical && !existingIsCanonical {
                    duplicateFiles.append(existing.filename)
                    bestByID[rowId] = (parsed.row, name, parsed.repaired)
                } else if !newIsCanonical && existingIsCanonical {
                    duplicateFiles.append(name)
                } else {
                    // Both canonical or both non-canonical — keep newer
                    if parsed.row.updatedAt > existing.row.updatedAt {
                        duplicateFiles.append(existing.filename)
                        bestByID[rowId] = (parsed.row, name, parsed.repaired)
                    } else {
                        duplicateFiles.append(name)
                    }
                }
            } else {
                bestByID[rowId] = (parsed.row, name, parsed.repaired)
            }
        }

        // Clean up orphan duplicate files.
        for filename in duplicateFiles {
            let filePath = (dbPath as NSString).appendingPathComponent(filename)
            try? fileManager.removeItem(atPath: filePath)
        }

        let rows = bestByID.values.map(\.row)
        let repairedRows = bestByID.values.filter(\.repaired).map(\.row)
        let sortedRows = rows.sorted { $0.createdAt < $1.createdAt }

        // If we repaired legacy properties during load, persist the mapped values.
        if !repairedRows.isEmpty {
            for row in repairedRows {
                try? saveRow(row, schema: schema, at: dbPath)
            }
            try? updateIndex(rows: sortedRows, schema: schema, at: dbPath)
        }

        return sortedRows
    }

    // MARK: - Private: Parse Row

    private struct ParsedRow {
        let row: DatabaseRow
        let repaired: Bool
    }

    private func parseRow(from content: String, schema: DatabaseSchema, skipBody: Bool = false) -> ParsedRow? {
        guard content.hasPrefix("---") else { return nil }
        let afterFirstMarker = content.index(content.startIndex, offsetBy: 3)
        guard let endRange = content.range(of: "\n---", range: afterFirstMarker..<content.endIndex) else { return nil }

        let yamlBlock = String(content[afterFirstMarker..<endRange.lowerBound])
        let body = skipBody ? "" : String(content[endRange.upperBound...]).trimmingCharacters(in: .newlines)

        var id = ""
        var createdAt = Date()
        var updatedAt = Date()
        var properties: [String: PropertyValue] = [:]
        var rawProperties: [String: String] = [:]
        var inProperties = false

        let isoFormatter = Self.isoFormatter
        let dateOnlyFormatter = Self.dateOnlyFormatter

        for line in yamlBlock.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }

            if inProperties {
                if line.hasPrefix("  ") {
                    let propLine = String(line.dropFirst(2))
                    if let colonIdx = propLine.firstIndex(of: ":") {
                        let key = String(propLine[propLine.startIndex..<colonIdx]).trimmingCharacters(in: .whitespaces)
                        let rawValue = String(propLine[propLine.index(after: colonIdx)...]).trimmingCharacters(in: .whitespaces)
                        rawProperties[key] = rawValue
                        // Look up by property ID
                        if let propDef = schema.properties.first(where: { $0.id == key }) {
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
                } else if trimmed.hasPrefix("created_at:") {
                    let val = String(trimmed.dropFirst(11)).trimmingCharacters(in: .whitespaces)
                    createdAt = isoFormatter.date(from: val) ?? dateOnlyFormatter.date(from: val) ?? Date()
                } else if trimmed.hasPrefix("updated_at:") {
                    let val = String(trimmed.dropFirst(11)).trimmingCharacters(in: .whitespaces)
                    updatedAt = isoFormatter.date(from: val) ?? dateOnlyFormatter.date(from: val) ?? Date()
                }
            }
        }

        guard !id.isEmpty else { return nil }
        let repairedProperties = repairLegacyProperties(in: properties, rawProperties: rawProperties, schema: schema)

        return ParsedRow(
            row: DatabaseRow(
                id: id,
                properties: repairedProperties.properties,
                body: body,
                createdAt: createdAt,
                updatedAt: updatedAt
            ),
            repaired: repairedProperties.repaired
        )
    }

    // MARK: - Private Helpers

    private func repairLegacyProperties(
        in properties: [String: PropertyValue],
        rawProperties: [String: String],
        schema: DatabaseSchema
    ) -> (properties: [String: PropertyValue], repaired: Bool) {
        var repairedProps = properties
        var didRepair = false

        if let titleProp = schema.titleProperty,
           !hasMeaningfulValue(repairedProps[titleProp.id]),
           let inferredTitle = inferLegacyTitle(from: rawProperties) {
            repairedProps[titleProp.id] = .text(inferredTitle)
            didRepair = true
        }

        if let statusProp = schema.properties.first(where: { $0.type == .select }),
           !hasMeaningfulValue(repairedProps[statusProp.id]),
           let optionId = inferLegacySelectOption(for: statusProp, from: rawProperties) {
            repairedProps[statusProp.id] = .select(optionId)
            didRepair = true
        }

        if let tagsProp = schema.properties.first(where: { $0.type == .multiSelect }),
           !hasMeaningfulValue(repairedProps[tagsProp.id]),
           let rawMultiSelect = inferLegacyMultiSelect(from: rawProperties) {
            let parsed = parsePropertyValue(rawMultiSelect, type: .multiSelect)
            if hasMeaningfulValue(parsed) {
                repairedProps[tagsProp.id] = parsed
                didRepair = true
            }
        }

        return (repairedProps, didRepair)
    }

    private func hasMeaningfulValue(_ value: PropertyValue?) -> Bool {
        guard let value else { return false }
        switch value {
        case .empty:
            return false
        case .text(let text):
            return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .multiSelect(let values):
            return !values.isEmpty
        case .relationMany(let values):
            return !values.isEmpty
        case .select(let value), .url(let value), .email(let value), .relation(let value):
            return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .date(let value):
            if let parsed = DatabaseDateValue.decode(from: value) {
                return !parsed.start.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .number:
            return true
        case .checkbox:
            return true
        }
    }

    private func inferLegacyTitle(from rawProperties: [String: String]) -> String? {
        var bestMatch: (score: Int, value: String)?
        for (key, rawValue) in rawProperties {
            guard let candidate = scalarText(from: rawValue), !candidate.isEmpty else { continue }
            if looksLikeIdentifier(candidate) { continue }
            let normalizedCandidate = candidate.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if normalizedCandidate == "null" || normalizedCandidate == "nil" || normalizedCandidate == "none" {
                continue
            }

            let keyLower = key.lowercased()
            var score = 0
            if keyLower.contains("title") || keyLower.contains("name") { score += 100 }
            if rawValue.trimmingCharacters(in: .whitespaces).hasPrefix("\"") { score += 30 }
            if candidate.contains(" ") { score += 10 }
            if keyLower.contains("status") || keyLower.contains("tag") || keyLower.contains("label") {
                score -= 40
            }

            if let best = bestMatch {
                if score > best.score {
                    bestMatch = (score, candidate)
                }
            } else {
                bestMatch = (score, candidate)
            }
        }
        return bestMatch?.value
    }

    private func inferLegacySelectOption(for property: PropertyDefinition, from rawProperties: [String: String]) -> String? {
        guard let options = property.options, !options.isEmpty else { return nil }

        var candidateValues: [String] = []
        if let exact = rawProperties[property.id] {
            candidateValues.append(exact)
        }
        for (key, value) in rawProperties where key.lowercased().contains("status") {
            candidateValues.append(value)
        }
        for value in rawProperties.values where scalarToken(from: value).hasPrefix("opt_") {
            candidateValues.append(value)
        }

        var seen: Set<String> = []
        let uniqueCandidates = candidateValues.filter { seen.insert($0).inserted }
        for candidate in uniqueCandidates {
            let token = scalarToken(from: candidate)
            guard !token.isEmpty else { continue }

            if let exactMatch = options.first(where: { $0.id == token }) {
                return exactMatch.id
            }
            if let mapped = mapLegacySelectToken(token, options: options) {
                return mapped.id
            }
        }

        return nil
    }

    private func inferLegacyMultiSelect(from rawProperties: [String: String]) -> String? {
        for (key, value) in rawProperties {
            if key.lowercased().contains("status") { continue }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("["), trimmed.hasSuffix("]"), trimmed.count > 2 {
                return trimmed
            }
        }
        return nil
    }

    private func mapLegacySelectToken(_ token: String, options: [SelectOption]) -> SelectOption? {
        let normalizedToken = normalizeStatusToken(token)
        let compactToken = normalizedToken.replacingOccurrences(of: " ", with: "")

        for option in options {
            let normalizedOption = normalizeStatusToken(option.name)
            let compactOption = normalizedOption.replacingOccurrences(of: " ", with: "")
            if normalizedOption == normalizedToken ||
                compactOption == compactToken ||
                compactToken.contains(compactOption) ||
                compactOption.contains(compactToken) {
                return option
            }
        }

        guard let tokenBucket = statusBucket(for: normalizedToken) else { return nil }
        return options.first { option in
            let optionBucket = statusBucket(for: normalizeStatusToken(option.name))
            return optionBucket == tokenBucket
        }
    }

    private func statusBucket(for normalizedValue: String) -> String? {
        let compact = normalizedValue.replacingOccurrences(of: " ", with: "")
        if compact.contains("done") || compact.contains("complete") || compact.contains("closed") {
            return "done"
        }
        if compact.contains("progress") || compact.contains("doing") || compact.contains("active") || compact.contains("review") {
            return "in_progress"
        }
        if compact.contains("todo") || compact.contains("backlog") || compact.contains("notstarted") || compact.contains("queued") {
            return "todo"
        }
        if compact.contains("block") || compact.contains("stuck") {
            return "blocked"
        }
        if compact.contains("cancel") || compact.contains("wontdo") {
            return "cancelled"
        }
        return nil
    }

    private func normalizeStatusToken(_ value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func scalarText(from rawValue: String) -> String? {
        let token = scalarToken(from: rawValue)
        if token.isEmpty { return nil }
        return token
    }

    private func scalarToken(from rawValue: String) -> String {
        var value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("["), value.hasSuffix("]") {
            return ""
        }
        if value.hasPrefix("\""), value.hasSuffix("\""), value.count >= 2 {
            value = String(value.dropFirst().dropLast())
        }
        return value
            .replacingOccurrences(of: "\\\"", with: "\"")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func looksLikeIdentifier(_ value: String) -> Bool {
        let lower = value.lowercased()
        if lower.hasPrefix("opt_") || lower.hasPrefix("prop_") || lower.hasPrefix("row_") || lower.hasPrefix("db_") {
            return true
        }
        return lower.range(of: "^[a-z0-9_-]{12,}$", options: .regularExpression) != nil
    }

    private func parsePropertyValue(_ raw: String, type: PropertyType) -> PropertyValue {
        let value = raw.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        if value.isEmpty { return .empty }

        switch type {
        case .title, .text:
            return .text(value)
        case .number:
            return .number(Double(value) ?? 0)
        case .select:
            return .select(value)
        case .multiSelect:
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
        case .relation:
            if value.hasPrefix("[") {
                let items = value.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
                    .components(separatedBy: ",")
                    .map { $0.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\"")) }
                    .filter { !$0.isEmpty }
                return .relationMany(items)
            }
            return .relation(value)
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
        case .multiSelect(let arr): return "[\(arr.joined(separator: ", "))]"
        case .date(let s): return s
        case .checkbox(let b): return b ? "true" : "false"
        case .url(let s): return "\"\(s)\""
        case .email(let s): return "\"\(s)\""
        case .relation(let s): return s
        case .relationMany(let arr): return "[\(arr.joined(separator: ", "))]"
        case .empty: return ""
        }
    }

    private func serializePropertyValueForIndex(_ value: PropertyValue) -> Any {
        switch value {
        case .text(let s): return s
        case .number(let n): return n
        case .select(let s): return s
        case .multiSelect(let arr): return arr
        case .date(let s): return DatabaseDateValue.decode(from: s)?.sortKey ?? s
        case .checkbox(let b): return b
        case .url(let s): return s
        case .email(let s): return s
        case .relation(let s): return s
        case .relationMany(let arr): return arr
        case .empty: return NSNull()
        }
    }

    private func rowFilename(title: String, suffix: String) -> String {
        let sanitized = title
            .replacingOccurrences(of: "[/\\\\?%*:|\"<>]", with: "-", options: .regularExpression)
            .prefix(80)
        return "\(sanitized) (\(suffix)).md"
    }

    private func extractIdSuffix(from rowId: String) -> String {
        // row_a1b2c3 -> a1b2c3
        if rowId.hasPrefix("row_") {
            return String(rowId.dropFirst(4))
        }
        return rowId
    }

    private func iso8601String(from date: Date) -> String {
        Self.isoFormatter.string(from: date)
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
