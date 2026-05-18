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

    public static func serializeFlat(
        row: DatabaseRow,
        schema: DatabaseSchema,
        extraScalars: [(key: String, value: String)] = []
    ) -> String {
        let estimatedSize = 40 + row.properties.count * 40 + row.body.count
        var fm = String()
        fm.reserveCapacity(estimatedSize)

        fm += "---\nid: "
        fm += row.id
        fm += "\n"

        for prop in schema.properties {
            if let value = row.properties[prop.id] {
                let s = serializeValue(value)
                if !s.isEmpty {
                    fm += prop.id
                    fm += ": "
                    fm += s
                    fm += "\n"
                }
            }
        }
        for scalar in extraScalars where !scalar.value.isEmpty {
            fm += scalar.key
            fm += ": "
            fm += scalar.value
            fm += "\n"
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

    // Parse returning both the row and the raw (unparsed) property strings.
    // swiftlint:disable:next cyclomatic_complexity
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
        let flatPropLookup = flatPropertyLookup(for: schema.properties)

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
                        // Property keys in YAML are not padded, so skip trim.
                        let key = String(propLine[propLine.startIndex..<colonIdx])
                        // Value has exactly one leading space after colon in our format.
                        let afterColon = propLine.index(after: colonIdx)
                        let valStart: Substring.Index
                        if afterColon < propLine.endIndex && propLine[afterColon] == " " {
                            valStart = propLine.index(after: afterColon)
                        } else {
                            valStart = afterColon
                        }
                        let rawValue = String(propLine[valStart...])
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
                    let sub = trimmed.dropFirst(3)
                    let start = sub.firstIndex(where: { $0 != " " }) ?? sub.endIndex
                    id = String(sub[start...])
                } else if trimmed.hasPrefix("created_at:") {
                    let sub = trimmed.dropFirst(11)
                    let start = sub.firstIndex(where: { $0 != " " }) ?? sub.endIndex
                    createdAt = parseISO8601Date(String(sub[start...]))
                } else if trimmed.hasPrefix("updated_at:") {
                    let sub = trimmed.dropFirst(11)
                    let start = sub.firstIndex(where: { $0 != " " }) ?? sub.endIndex
                    updatedAt = parseISO8601Date(String(sub[start...]))
                } else if let (key, rawValue) = parseFrontmatterScalar(trimmed),
                          let property = flatPropLookup[canonicalFrontmatterKey(key)] {
                    if properties[property.id] == nil {
                        rawProperties[property.id] = rawValue
                        properties[property.id] = parseValue(rawValue, type: property.type)
                    }
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

    private static func flatPropertyLookup(
        for properties: [PropertyDefinition]
    ) -> [String: (id: String, type: PropertyType)] {
        var lookup: [String: (id: String, type: PropertyType)] = [:]
        for property in properties {
            lookup[canonicalFrontmatterKey(property.id)] = (property.id, property.type)
            let nameKey = canonicalFrontmatterKey(property.name)
            if lookup[nameKey] == nil {
                lookup[nameKey] = (property.id, property.type)
            }
        }
        return lookup
    }

    private static func canonicalFrontmatterKey(_ key: String) -> String {
        var result = ""
        var previousWasSeparator = false
        for scalar in key.unicodeScalars {
            let value = scalar.value
            let isAlphaNumeric = (48...57).contains(value) || (65...90).contains(value) || (97...122).contains(value)
            if isAlphaNumeric {
                let lowercased = value >= 65 && value <= 90 ? value + 32 : value
                if let scalar = UnicodeScalar(lowercased) {
                    result.unicodeScalars.append(scalar)
                }
                previousWasSeparator = false
            } else if !previousWasSeparator {
                result.append("_")
                previousWasSeparator = true
            }
        }
        return result.trimmingCharacters(in: CharacterSet(charactersIn: "_"))
    }

    private static func parseFrontmatterScalar(_ trimmed: Substring) -> (key: String, rawValue: String)? {
        guard let colonIdx = trimmed.firstIndex(of: ":") else { return nil }
        let key = String(trimmed[..<colonIdx]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty,
              !["id", "created_at", "updated_at"].contains(key.lowercased()) else {
            return nil
        }

        let afterColon = trimmed.index(after: colonIdx)
        let value = String(trimmed[afterColon...]).trimmingCharacters(in: .whitespacesAndNewlines)
        return (key, value)
    }

    // swiftlint:disable:next cyclomatic_complexity
    private static func parseValue(_ raw: String, type: PropertyType) -> PropertyValue {
        var value: String
        // Strip one pair of surrounding quotes
        if raw.count >= 2 && raw.first == "\"" && raw.last == "\"" {
            value = String(raw.dropFirst().dropLast())
        } else {
            value = raw
        }
        // Single-pass unescape: handle \\" and \\" in one scan
        if value.contains("\\") {
            value = yamlUnescape(value)
        }
        if value.isEmpty { return .empty }

        switch type {
        case .title, .text:
            return .text(value)
        case .number:
            return .number(Double(value) ?? 0)
        case .select:
            return .select(value)
        case .multiSelect:
            return .multiSelect(parseArray(value))
        case .date:
            return .date(value)
        case .checkbox:
            return .checkbox(value == "true")
        case .url:
            return .url(value)
        case .email:
            return .email(value)
        case .relation:
            if value.first == "[" {
                return .relationMany(parseArray(value))
            }
            return .relation(value)
        case .formula:
            // Computed at display time, never persisted
            return .empty
        case .lookup:
            // Computed at render time; stored value is treated as text
            return .text(value)
        case .rollup:
            // Computed at render time; stored value is treated as text
            return .text(value)
        }
    }

    /// Single-pass YAML unescape: \" → " and \\\\ → \\
    @inline(__always)
    private static func yamlUnescape(_ s: String) -> String {
        var result = String()
        result.reserveCapacity(s.count)
        var iter = s.makeIterator()
        while let c = iter.next() {
            if c == "\\" {
                if let next = iter.next() {
                    switch next {
                    case "\"": result.append("\"")
                    case "\\": result.append("\\")
                    default:
                        result.append("\\")
                        result.append(next)
                    }
                } else {
                    result.append("\\")
                }
            } else {
                result.append(c)
            }
        }
        return result
    }

    /// Parse "[a, b, c]" or "a, b" into array of trimmed, non-empty strings.
    /// Avoids intermediate array/string allocations from split+trim+filter chains.
    @inline(__always)
    private static func parseArray(_ value: String) -> [String] {
        let s: Substring
        if value.first == "[" && value.last == "]" {
            s = value.dropFirst().dropLast()
        } else {
            s = value[...]
        }
        var items: [String] = []
        var start = s.startIndex
        while start < s.endIndex {
            // Skip leading whitespace
            while start < s.endIndex && (s[start] == " " || s[start] == "\t") { start = s.index(after: start) }
            guard start < s.endIndex else { break }
            // Find comma or end
            let commaIdx = s[start...].firstIndex(of: ",") ?? s.endIndex
            // Trim trailing whitespace and quotes
            var end = commaIdx
            while end > start && (s[s.index(before: end)] == " " || s[s.index(before: end)] == "\t") { end = s.index(before: end) }
            // Strip surrounding quotes
            var itemStart = start
            var itemEnd = end
            if itemStart < itemEnd && s[itemStart] == "\"" { itemStart = s.index(after: itemStart) }
            if itemEnd > itemStart && s[s.index(before: itemEnd)] == "\"" { itemEnd = s.index(before: itemEnd) }
            if itemStart < itemEnd {
                items.append(String(s[itemStart..<itemEnd]))
            }
            start = commaIdx < s.endIndex ? s.index(after: commaIdx) : s.endIndex
        }
        return items
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
