import Foundation

public struct RowSerializer {

    // MARK: - Serialize

    public static func serialize(row: DatabaseRow, schema: DatabaseSchema) -> String {
        var fm = "---\n"
        fm += "id: \(row.id)\n"
        fm += "created_at: \(iso8601String(from: row.createdAt))\n"
        fm += "updated_at: \(iso8601String(from: row.updatedAt))\n"

        if !row.properties.isEmpty {
            fm += "properties:\n"
            for prop in schema.properties {
                if let value = row.properties[prop.id] {
                    let s = serializeValue(value)
                    if !s.isEmpty {
                        fm += "  \(prop.id): \(s)\n"
                    }
                }
            }
        }

        fm += "---\n"

        if row.body.isEmpty {
            fm += "\n"
        } else {
            fm += "\n\(row.body)"
        }

        return fm
    }

    // MARK: - Parse

    /// Result of a detailed parse that includes raw property strings for legacy repair.
    public struct ParseResult {
        public let row: DatabaseRow
        public let rawProperties: [String: String]
    }

    public static func parse(content: String, schema: DatabaseSchema, skipBody: Bool = false) -> DatabaseRow? {
        parseDetailed(content: content, schema: schema, skipBody: skipBody)?.row
    }

    // MARK: - Cached Formatters

    private static let sharedISOFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static let sharedDateOnlyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()

    /// Parse returning both the row and the raw (unparsed) property strings.
    public static func parseDetailed(content: String, schema: DatabaseSchema, skipBody: Bool = false) -> ParseResult? {
        guard content.hasPrefix("---") else { return nil }
        let afterMarker = content.index(content.startIndex, offsetBy: 3)
        guard let endRange = content.range(of: "\n---", range: afterMarker..<content.endIndex) else { return nil }

        let yamlBlock = String(content[afterMarker..<endRange.lowerBound])
        let body = skipBody ? "" : String(content[endRange.upperBound...]).trimmingCharacters(in: .newlines)

        var id = ""
        var createdAt = Date()
        var updatedAt = Date()
        var properties: [String: PropertyValue] = [:]
        var rawProperties: [String: String] = [:]
        var inProperties = false

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
                        if let propDef = schema.properties.first(where: { $0.id == key }) {
                            properties[key] = parseValue(rawValue, type: propDef.type)
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
                    createdAt = fastParseISO8601(val) ?? sharedISOFormatter.date(from: val) ?? sharedDateOnlyFormatter.date(from: val) ?? Date()
                } else if trimmed.hasPrefix("updated_at:") {
                    let val = String(trimmed.dropFirst(11)).trimmingCharacters(in: .whitespaces)
                    updatedAt = fastParseISO8601(val) ?? sharedISOFormatter.date(from: val) ?? sharedDateOnlyFormatter.date(from: val) ?? Date()
                }
            }
        }

        guard !id.isEmpty else { return nil }

        return ParseResult(
            row: DatabaseRow(id: id, properties: properties, body: body, createdAt: createdAt, updatedAt: updatedAt),
            rawProperties: rawProperties
        )
    }

    // MARK: - Private

    private static func parseValue(_ raw: String, type: PropertyType) -> PropertyValue {
        var value = raw
        // Strip one pair of surrounding quotes
        if value.hasPrefix("\"") && value.hasSuffix("\"") && value.count >= 2 {
            value = String(value.dropFirst().dropLast())
        }
        // Unescape backslash sequences
        value = value.replacingOccurrences(of: "\\\"", with: "\"")
                     .replacingOccurrences(of: "\\\\", with: "\\")
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

    private static func yamlEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
         .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private static func serializeValue(_ value: PropertyValue) -> String {
        switch value {
        case .text(let s): return "\"\(yamlEscape(s))\""
        case .number(let n):
            if n == n.rounded() && n < 1e15 { return String(Int(n)) }
            return String(n)
        case .select(let s): return s
        case .multiSelect(let arr): return "[\(arr.joined(separator: ", "))]"
        case .date(let s): return s
        case .checkbox(let b): return b ? "true" : "false"
        case .url(let s): return "\"\(yamlEscape(s))\""
        case .email(let s): return "\"\(yamlEscape(s))\""
        case .relation(let s): return s
        case .relationMany(let arr): return "[\(arr.joined(separator: ", "))]"
        case .empty: return ""
        }
    }

    public static func serializeValueForIndex(_ value: PropertyValue) -> Any {
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

    private static func iso8601String(from date: Date) -> String {
        sharedISOFormatter.string(from: date)
    }

    private static let utcGregorianCalendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }()

    /// Fast manual ISO 8601 parser for the common format "2024-01-15T10:30:00Z".
    /// Falls back to nil for uncommon formats so the caller can use DateFormatter.
    private static func fastParseISO8601(_ string: String) -> Date? {
        // Expected: "2024-01-15T10:30:00Z" (20 chars)
        guard string.count == 20, string.hasSuffix("Z") else { return nil }
        let chars = Array(string)
        guard chars[4] == "-", chars[7] == "-", chars[10] == "T",
              chars[13] == ":", chars[16] == ":" else { return nil }

        guard let year = Int(string[string.startIndex..<string.index(string.startIndex, offsetBy: 4)]),
              let month = Int(string[string.index(string.startIndex, offsetBy: 5)..<string.index(string.startIndex, offsetBy: 7)]),
              let day = Int(string[string.index(string.startIndex, offsetBy: 8)..<string.index(string.startIndex, offsetBy: 10)]),
              let hour = Int(string[string.index(string.startIndex, offsetBy: 11)..<string.index(string.startIndex, offsetBy: 13)]),
              let minute = Int(string[string.index(string.startIndex, offsetBy: 14)..<string.index(string.startIndex, offsetBy: 16)]),
              let second = Int(string[string.index(string.startIndex, offsetBy: 17)..<string.index(string.startIndex, offsetBy: 19)])
        else { return nil }

        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.second = second

        return utcGregorianCalendar.date(from: components)
    }
}
