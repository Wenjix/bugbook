import ArgumentParser
import Foundation
import BugbookCore

struct QueryCmd: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "query",
        abstract: "Query rows from a database"
    )

    @OptionGroup var options: Bugbook.Options

    @Argument(help: "Database name or ID")
    var db: String

    @Option(name: .long, parsing: .singleValue, help: "Filter expression (repeatable)")
    var filter: [String] = []

    @Option(name: .long, parsing: .singleValue, help: "Sort expression (repeatable)")
    var sort: [String] = []

    @Option(help: "Maximum number of rows to return")
    var limit: Int?

    @Option(help: "Number of rows to skip")
    var offset: Int?

    @Flag(help: "Include row body content")
    var body: Bool = false

    @Option(help: "Comma-separated list of property IDs to include")
    var fields: String?

    func run() throws {
        let (dbPath, schema) = try resolveDatabase(db, workspace: options.resolvedWorkspace)

        // Parse filters
        var filters: [Filter] = []
        for expr in filter {
            filters.append(try parseFilter(expr, schema: schema))
        }

        // Parse sorts
        var sorts: [Sort] = []
        for expr in sort {
            sorts.append(try parseSort(expr))
        }

        let fieldList = fields?.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }

        // Load index for querying
        let indexManager = IndexManager()
        let rowStore = RowStore()

        // Load or rebuild index
        let indexData: [String: Any]
        if let existing = indexManager.loadIndex(at: dbPath),
           !indexManager.isStale(indexData: existing, dbPath: dbPath) {
            indexData = existing
        } else {
            let allRows = rowStore.loadAllRows(in: dbPath, schema: schema)
            let rebuilt = indexManager.rebuild(dbPath: dbPath, schema: schema, rows: allRows)
            try indexManager.saveIndex(rebuilt, at: dbPath)
            indexData = rebuilt
        }

        guard let rowsMap = indexData["rows"] as? [String: [String: Any]] else {
            try outputJSON(["rows": [] as [Any], "total_count": 0, "has_more": false])
            return
        }

        // Apply filters in-memory against the index rows map
        var matchingIds = Array(rowsMap.keys)

        for f in filters {
            matchingIds = matchingIds.filter { rowId in
                guard let rowData = rowsMap[rowId],
                      let props = rowData["properties"] as? [String: Any] else { return false }
                return matchesFilter(f, properties: props, schema: schema)
            }
        }

        // Sort
        for s in sorts.reversed() {
            matchingIds.sort { id1, id2 in
                let props1 = (rowsMap[id1]?["properties"] as? [String: Any]) ?? [:]
                let props2 = (rowsMap[id2]?["properties"] as? [String: Any]) ?? [:]
                let v1 = props1[s.property]
                let v2 = props2[s.property]
                let result = compareValues(v1, v2)
                return s.ascending ? result < 0 : result > 0
            }
        }

        let totalCount = matchingIds.count

        // Apply offset/limit
        if let offset = offset, offset > 0 {
            matchingIds = Array(matchingIds.dropFirst(offset))
        }
        if let limit = limit, limit > 0 {
            matchingIds = Array(matchingIds.prefix(limit))
        }

        let hasMore = totalCount > (offset ?? 0) + matchingIds.count

        // Build output rows
        var outputRows: [[String: Any]] = []
        for rowId in matchingIds {
            guard let rowData = rowsMap[rowId],
                  let props = rowData["properties"] as? [String: Any] else { continue }

            var row: [String: Any] = [
                "id": rowId,
                "created_at": rowData["created_at"] ?? "",
                "updated_at": rowData["updated_at"] ?? "",
            ]

            var filteredProps: [String: Any] = [:]
            for (key, val) in props {
                if let fieldList = fieldList, !fieldList.contains(key) { continue }
                filteredProps[key] = val
            }
            row["properties"] = filteredProps

            if body {
                // Load the actual row file to get the body
                if let filename = rowData["filename"] as? String {
                    let filePath = (dbPath as NSString).appendingPathComponent("\(filename).md")
                    if let dbRow = rowStore.loadRow(at: filePath, schema: schema) {
                        row["body"] = dbRow.body
                    }
                }
            }

            outputRows.append(row)
        }

        try outputJSON([
            "rows": outputRows,
            "total_count": totalCount,
            "has_more": hasMore,
        ])
    }
}

// MARK: - Filter Matching

private func matchesFilter(_ filter: Filter, properties: [String: Any], schema: DatabaseSchema) -> Bool {
    switch filter {
    case .equals(let prop, let value):
        return comparePropertyValue(properties[prop], to: value) == 0

    case .notEquals(let prop, let value):
        return comparePropertyValue(properties[prop], to: value) != 0

    case .greaterThan(let prop, let value):
        return comparePropertyValue(properties[prop], to: value) > 0

    case .lessThan(let prop, let value):
        return comparePropertyValue(properties[prop], to: value) < 0

    case .contains(let prop, let value):
        return propertyContains(properties[prop], value: value)

    case .notContains(let prop, let value):
        return !propertyContains(properties[prop], value: value)

    case .isEmpty(let prop):
        return isPropertyEmpty(properties[prop])

    case .isNotEmpty(let prop):
        return !isPropertyEmpty(properties[prop])

    case .inList(let prop, let values):
        return values.contains { comparePropertyValue(properties[prop], to: $0) == 0 }
    }
}

private func comparePropertyValue(_ raw: Any?, to value: PropertyValue) -> Int {
    guard let raw = raw else { return value == .empty ? 0 : -1 }

    switch value {
    case .text(let s):
        if let rawStr = raw as? String { return rawStr.compare(s).rawValue }
    case .number(let n):
        if let rawNum = raw as? Double {
            if rawNum < n { return -1 }
            if rawNum > n { return 1 }
            return 0
        }
        if let rawInt = raw as? Int {
            let d = Double(rawInt)
            if d < n { return -1 }
            if d > n { return 1 }
            return 0
        }
    case .select(let s):
        if let rawStr = raw as? String { return rawStr == s ? 0 : (rawStr < s ? -1 : 1) }
    case .date(let s):
        if let rawStr = raw as? String { return rawStr.compare(s).rawValue }
    case .checkbox(let b):
        if let rawBool = raw as? Bool { return rawBool == b ? 0 : -1 }
    case .relation(let s):
        if let rawStr = raw as? String { return rawStr == s ? 0 : -1 }
    case .empty:
        return isPropertyEmpty(raw) ? 0 : 1
    default:
        break
    }
    return -1
}

private func propertyContains(_ raw: Any?, value: PropertyValue) -> Bool {
    guard let raw = raw else { return false }
    let searchStr = value.stringValue

    if let str = raw as? String {
        return str.localizedCaseInsensitiveContains(searchStr)
    }
    if let arr = raw as? [String] {
        return arr.contains(searchStr)
    }
    return false
}

private func isPropertyEmpty(_ raw: Any?) -> Bool {
    guard let raw = raw else { return true }
    if raw is NSNull { return true }
    if let str = raw as? String { return str.isEmpty }
    if let arr = raw as? [Any] { return arr.isEmpty }
    return false
}

private func compareValues(_ v1: Any?, _ v2: Any?) -> Int {
    if v1 == nil && v2 == nil { return 0 }
    if v1 == nil { return -1 }
    if v2 == nil { return 1 }

    if let s1 = v1 as? String, let s2 = v2 as? String {
        return s1.compare(s2).rawValue
    }
    if let n1 = v1 as? Double, let n2 = v2 as? Double {
        if n1 < n2 { return -1 }
        if n1 > n2 { return 1 }
        return 0
    }
    if let n1 = v1 as? Int, let n2 = v2 as? Int {
        if n1 < n2 { return -1 }
        if n1 > n2 { return 1 }
        return 0
    }
    if let b1 = v1 as? Bool, let b2 = v2 as? Bool {
        if b1 == b2 { return 0 }
        return b1 ? 1 : -1
    }
    return 0
}
