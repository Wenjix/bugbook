import Foundation

public struct RowSerializer {

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

    // MARK: - Serialize

    public static func serialize(row: DatabaseRow, schema: DatabaseSchema) -> String {
        // Estimate capacity: ~80 bytes header + ~40 bytes per property + body
        let estimatedSize = 80 + row.properties.count * 40 + row.body.count
        var fm = String()
        fm.reserveCapacity(estimatedSize)

        fm += "---\nid: "
        fm += row.id
        fm += "\ncreated_at: "
        fm += sharedISOFormatter.string(from: row.createdAt)
        fm += "\nupdated_at: "
        fm += sharedISOFormatter.string(from: row.updatedAt)
        fm += "\n"

        if !row.properties.isEmpty {
            fm += "properties:\n"
            for prop in schema.properties {
                if let value = row.properties[prop.id] {
                    let s = serializeValue(value)
                    if !s.isEmpty {
                        fm += "  "
                        fm += prop.id
                        fm += ": "
                        fm += s
                        fm += "\n"
                    }
                }
            }
        }

        fm += "---\n"

        if row.body.isEmpty {
            fm += "\n"
        } else {
            fm += "\n"
            fm += row.body
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

    /// Parse returning both the row and the raw (unparsed) property strings.
    public static func parseDetailed(content: String, schema: DatabaseSchema, skipBody: Bool = false) -> ParseResult? {
        guard content.hasPrefix("---") else { return nil }
        let afterMarker = content.index(content.startIndex, offsetBy: 3)
        guard let endRange = content.range(of: "\n---", range: afterMarker..<content.endIndex) else { return nil }

        let yamlBlock = content[afterMarker..<endRange.lowerBound]
        let body = skipBody ? "" : String(content[endRange.upperBound...]).trimmingCharacters(in: .newlines)

        var id = ""
        var createdAt = Date()
        var updatedAt = Date()
        var properties: [String: PropertyValue] = [:]
        var rawProperties: [String: String] = [:]
        var inProperties = false

        // Build property lookup dictionary once instead of O(n) scan per property
        let propLookup = Dictionary(uniqueKeysWithValues: schema.properties.map { ($0.id, $0.type) })

        // Manual line iteration over the Substring to avoid allocating an array of strings
        var lineStart = yamlBlock.startIndex
        while lineStart < yamlBlock.endIndex {
            let lineEnd = yamlBlock[lineStart...].firstIndex(of: "\n") ?? yamlBlock.endIndex
            let line = yamlBlock[lineStart..<lineEnd]

            // Advance past the newline for next iteration
            lineStart = lineEnd < yamlBlock.endIndex ? yamlBlock.index(after: lineEnd) : yamlBlock.endIndex

            // Skip empty/whitespace-only lines
            let trimmedStart = line.firstIndex(where: { $0 != " " && $0 != "\t" }) ?? line.endIndex
            if trimmedStart == line.endIndex { continue }
            let trimmed = line[trimmedStart..<line.endIndex]

            if inProperties {
                if line.hasPrefix("  ") {
                    let propLine = line[line.index(line.startIndex, offsetBy: 2)...]
                    if let colonIdx = propLine.firstIndex(of: ":") {
                        let key = String(propLine[propLine.startIndex..<colonIdx]).trimmingCharacters(in: .whitespaces)
                        let rawValue = String(propLine[propLine.index(after: colonIdx)...]).trimmingCharacters(in: .whitespaces)
                        rawProperties[key] = rawValue
                        if let propType = propLookup[key] {
                            properties[key] = parseValue(rawValue, type: propType)
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
                    createdAt = parseISO8601Date(val)
                } else if trimmed.hasPrefix("updated_at:") {
                    let val = String(trimmed.dropFirst(11)).trimmingCharacters(in: .whitespaces)
                    updatedAt = parseISO8601Date(val)
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
        case .formula:
            // Formula values are computed at display time, never persisted.
            return .empty
        case .lookup:
            // Lookup is computed at render time; stored value is treated as text.
            return .text(value)
        case .rollup:
            // Rollup is computed at render time; stored value is treated as text.
            return .text(value)
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

    /// Fast manual ISO 8601 date parser. Falls back to cached formatters.
    /// Expected format: "2024-01-15T09:30:00Z" (20 chars minimum)
    private static func parseISO8601Date(_ s: String) -> Date {
        // Fast path: try manual parsing for standard ISO 8601 format
        if s.count >= 20, s.hasSuffix("Z") {
            let chars = Array(s.utf8)
            // yyyy-MM-ddTHH:mm:ssZ
            if chars.count >= 20,
               chars[4] == UInt8(ascii: "-"), chars[7] == UInt8(ascii: "-"),
               chars[10] == UInt8(ascii: "T"), chars[13] == UInt8(ascii: ":"),
               chars[16] == UInt8(ascii: ":") {
                let year = asciiDigits4(chars, at: 0)
                let month = asciiDigits2(chars, at: 5)
                let day = asciiDigits2(chars, at: 8)
                let hour = asciiDigits2(chars, at: 11)
                let minute = asciiDigits2(chars, at: 14)
                let second = asciiDigits2(chars, at: 17)

                if let year, let month, let day, let hour, let minute, let second,
                   month >= 1, month <= 12, day >= 1, day <= 31,
                   hour >= 0, hour <= 23, minute >= 0, minute <= 59, second >= 0, second <= 59 {
                    var comps = DateComponents()
                    comps.year = year
                    comps.month = month
                    comps.day = day
                    comps.hour = hour
                    comps.minute = minute
                    comps.second = second
                    comps.timeZone = TimeZone(identifier: "UTC")
                    if let date = utcCalendar.date(from: comps) {
                        return date
                    }
                }
            }
        }
        // Slow fallback: use cached formatters
        return sharedISOFormatter.date(from: s) ?? sharedDateOnlyFormatter.date(from: s) ?? Date()
    }

    private static let utcCalendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }()

    @inline(__always)
    private static func asciiDigits2(_ bytes: [UInt8], at offset: Int) -> Int? {
        let d0 = Int(bytes[offset]) - 48
        let d1 = Int(bytes[offset + 1]) - 48
        guard d0 >= 0, d0 <= 9, d1 >= 0, d1 <= 9 else { return nil }
        return d0 * 10 + d1
    }

    @inline(__always)
    private static func asciiDigits4(_ bytes: [UInt8], at offset: Int) -> Int? {
        let d0 = Int(bytes[offset]) - 48
        let d1 = Int(bytes[offset + 1]) - 48
        let d2 = Int(bytes[offset + 2]) - 48
        let d3 = Int(bytes[offset + 3]) - 48
        guard d0 >= 0, d0 <= 9, d1 >= 0, d1 <= 9,
              d2 >= 0, d2 <= 9, d3 >= 0, d3 <= 9 else { return nil }
        return d0 * 1000 + d1 * 100 + d2 * 10 + d3
    }
}
