import Foundation

public struct RowSerializer {

    // MARK: - Cached Formatters

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

    // MARK: - Serialize

    public static func serialize(row: DatabaseRow, schema: DatabaseSchema) -> String {
        var parts: [String] = []
        parts.reserveCapacity(6 + schema.properties.count)

        parts.append("---")
        parts.append("id: \(row.id)")
        parts.append("created_at: \(iso8601String(from: row.createdAt))")
        parts.append("updated_at: \(iso8601String(from: row.updatedAt))")

        if !row.properties.isEmpty {
            parts.append("properties:")
            for prop in schema.properties {
                if let value = row.properties[prop.id] {
                    let s = serializeValue(value)
                    if !s.isEmpty {
                        parts.append("  \(prop.id): \(s)")
                    }
                }
            }
        }

        parts.append("---")
        parts.append("")

        var result = parts.joined(separator: "\n")
        if !row.body.isEmpty {
            result.append(row.body)
        }

        return result
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

        var id: Substring = ""
        var createdAt = Date()
        var updatedAt = Date()
        var properties: [String: PropertyValue] = [:]
        properties.reserveCapacity(schema.properties.count)
        var rawProperties: [String: String] = [:]
        rawProperties.reserveCapacity(schema.properties.count)
        var inProperties = false

        let propById = Dictionary(uniqueKeysWithValues: schema.properties.map { ($0.id, $0) })

        // Manual line scanning to avoid allocating an array of substrings
        var lineStart = yamlBlock.startIndex
        while lineStart < yamlBlock.endIndex {
            let lineEnd = yamlBlock[lineStart...].firstIndex(of: "\n") ?? yamlBlock.endIndex
            let line = yamlBlock[lineStart..<lineEnd]

            if !line.isEmpty {
                if inProperties {
                    if line.hasPrefix("  ") {
                        let propLine = line.dropFirst(2)
                        if let colonIdx = propLine.firstIndex(of: ":") {
                            let key = String(propLine[propLine.startIndex..<colonIdx])
                            let afterColon = propLine.index(after: colonIdx)
                            let rawSub = propLine[afterColon...].drop(while: { $0 == " " })
                            let rawValue = String(rawSub)
                            rawProperties[key] = rawValue
                            if let propDef = propById[key] {
                                properties[key] = parseValue(rawValue, type: propDef.type)
                            }
                        }
                    } else {
                        inProperties = false
                    }
                }

                if !inProperties {
                    if line.hasSuffix("properties:") && line.drop(while: { $0 == " " }) == "properties:" {
                        inProperties = true
                    } else if line.contains("id:") && !line.hasPrefix(" ") {
                        let trimmed = line.drop(while: { $0 == " " })
                        if trimmed.hasPrefix("id:") {
                            id = trimmed.dropFirst(3).drop(while: { $0 == " " })
                        }
                    } else if line.contains("created_at:") {
                        let trimmed = line.drop(while: { $0 == " " })
                        if trimmed.hasPrefix("created_at:") {
                            let val = String(trimmed.dropFirst(11).drop(while: { $0 == " " }))
                            createdAt = fastParseISO8601(val) ?? Date()
                        }
                    } else if line.contains("updated_at:") {
                        let trimmed = line.drop(while: { $0 == " " })
                        if trimmed.hasPrefix("updated_at:") {
                            let val = String(trimmed.dropFirst(11).drop(while: { $0 == " " }))
                            updatedAt = fastParseISO8601(val) ?? Date()
                        }
                    }
                }
            }

            lineStart = lineEnd < yamlBlock.endIndex ? yamlBlock.index(after: lineEnd) : yamlBlock.endIndex
        }

        guard !id.isEmpty else { return nil }

        return ParseResult(
            row: DatabaseRow(id: String(id), properties: properties, body: body, createdAt: createdAt, updatedAt: updatedAt),
            rawProperties: rawProperties
        )
    }

    // MARK: - Private

    private static func parseValue(_ raw: String, type: PropertyType) -> PropertyValue {
        var value = raw
        // Strip one pair of surrounding quotes
        if value.first == "\"" && value.last == "\"" && value.count >= 2 {
            value = String(value.dropFirst().dropLast())
        }
        // Unescape backslash sequences only if backslashes are present
        if value.contains("\\") {
            value = value.replacingOccurrences(of: "\\\"", with: "\"")
                         .replacingOccurrences(of: "\\\\", with: "\\")
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
        guard s.contains("\\") || s.contains("\"") else { return s }
        return s.replacingOccurrences(of: "\\", with: "\\\\")
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

    // MARK: - Fast Date Parsing

    /// Cumulative days before each month (non-leap year)
    private static let monthDays: [Int] = [0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334]

    /// Parse "yyyy-MM-ddTHH:mm:ssZ" via direct integer math. ~5x faster than ISO8601DateFormatter.
    private static func fastParseISO8601(_ s: String) -> Date? {
        let u = Array(s.utf8)
        guard u.count >= 10 else { return nil }

        func d2(_ i: Int) -> Int { (Int(u[i]) - 48) * 10 + Int(u[i+1]) - 48 }
        func d4(_ i: Int) -> Int { (Int(u[i]) - 48) * 1000 + (Int(u[i+1]) - 48) * 100 + d2(i+2) }

        let year = d4(0)
        guard u[4] == 0x2D else { return nil } // '-'
        let month = d2(5)
        guard u[7] == 0x2D, month >= 1, month <= 12 else { return nil }
        let day = d2(8)

        // Days from epoch (1970-01-01)
        let y = year - 1970
        var days = y * 365 + (y + 1) / 4  // approximate leap days
        // Correct for century/400-year rules
        if year > 2000 { days -= (year - 2001) / 100 - (year - 2001) / 400 }
        days += monthDays[month - 1] + day - 1
        // Leap day correction for current year
        if month > 2 && (year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)) {
            days += 1
        }

        var seconds = Double(days) * 86400.0

        // Parse time if present
        if u.count >= 19 && u[10] == 0x54 { // 'T'
            let hour = d2(11)
            let minute = d2(14) // skip ':'
            let second = d2(17)
            seconds += Double(hour * 3600 + minute * 60 + second)
        }

        return Date(timeIntervalSince1970: seconds)
    }

    private static func iso8601String(from date: Date) -> String {
        let ti = Int(date.timeIntervalSince1970)
        let seconds = ti % 60
        let minutes = (ti / 60) % 60
        let hours = (ti / 3600) % 24

        var days = ti / 86400
        var year = 1970
        while true {
            let daysInYear = (year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)) ? 366 : 365
            if days < daysInYear { break }
            days -= daysInYear
            year += 1
        }
        let isLeap = (year % 4 == 0 && (year % 100 != 0 || year % 400 == 0))
        let mdays = [31, isLeap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
        var month = 0
        while month < 12 && days >= mdays[month] {
            days -= mdays[month]
            month += 1
        }
        let day = days + 1
        month += 1

        return String(format: "%04d-%02d-%02dT%02d:%02d:%02dZ", year, month, day, hours, minutes, seconds)
    }
}
