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

    @Option(help: "Comma-separated list of property IDs or names to include")
    var fields: String?

    @Flag(name: .long, help: "Include raw schema property IDs and stored values alongside friendly properties")
    var rawProperties: Bool = false

    func run() throws {
        let (dbPath, schema) = try resolveDatabase(db, workspace: options.resolvedWorkspace)

        let filters: [Filter] = try filter.map { try parseFilter($0, schema: schema) }
        let sorts: [Sort] = try sort.map { try parseSort($0, schema: schema) }
        let fieldList = try parseFieldList(schema: schema)

        let indexData = try loadOrRebuildIndex(dbPath: dbPath, schema: schema)

        guard let rowsMap = indexData["rows"] as? [String: [String: Any]] else {
            try outputJSON(["rows": [] as [Any], "total_count": 0, "has_more": false])
            return
        }

        let matchingIds = applyFiltersAndSorts(filters: filters, sorts: sorts, rowsMap: rowsMap, schema: schema)
        let paginatedResult = paginate(matchingIds)

        let outputRows = buildOutputRows(
            ids: paginatedResult.ids, rowsMap: rowsMap, dbPath: dbPath, schema: schema, fieldList: fieldList
        )

        try outputJSON([
            "rows": outputRows,
            "total_count": paginatedResult.totalCount,
            "has_more": paginatedResult.hasMore,
        ])
    }

    // MARK: - Helpers

    private func parseFieldList(schema: DatabaseSchema) throws -> [String]? {
        try fields?
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .map { try resolveSchemaPropertyID($0, schema: schema) }
    }

    private func loadOrRebuildIndex(dbPath: String, schema: DatabaseSchema) throws -> [String: Any] {
        let indexManager = IndexManager()
        let rowStore = RowStore()

        if let existing = indexManager.loadIndex(at: dbPath),
           !indexManager.isStale(indexData: existing, dbPath: dbPath) {
            return existing
        }

        let allRows = rowStore.loadAllRows(in: dbPath, schema: schema)
        let rebuilt = indexManager.rebuild(dbPath: dbPath, schema: schema, rows: allRows)
        try indexManager.saveIndex(rebuilt, at: dbPath)
        return rebuilt
    }

    private func applyFiltersAndSorts(
        filters: [Filter], sorts: [Sort], rowsMap: [String: [String: Any]], schema: DatabaseSchema
    ) -> [String] {
        var ids = Array(rowsMap.keys)

        for activeFilter in filters {
            ids = ids.filter { rowId in
                guard let rowData = rowsMap[rowId],
                      let props = rowData["properties"] as? [String: Any] else { return false }
                return matchesFilter(activeFilter, properties: props, schema: schema)
            }
        }

        for sortExpr in sorts.reversed() {
            ids.sort { id1, id2 in
                let props1 = (rowsMap[id1]?["properties"] as? [String: Any]) ?? [:]
                let props2 = (rowsMap[id2]?["properties"] as? [String: Any]) ?? [:]
                let lhs = props1[sortExpr.property]
                let rhs = props2[sortExpr.property]
                let result = compareValues(lhs, rhs)
                return sortExpr.ascending ? result < 0 : result > 0
            }
        }

        return ids
    }

    private func paginate(_ ids: [String]) -> (ids: [String], totalCount: Int, hasMore: Bool) {
        var result = ids
        let totalCount = result.count

        if let offset = offset, offset > 0 {
            result = Array(result.dropFirst(offset))
        }
        if let limit = limit, limit > 0 {
            result = Array(result.prefix(limit))
        }

        let hasMore = totalCount > (offset ?? 0) + result.count
        return (result, totalCount, hasMore)
    }

    private func buildOutputRows(
        ids: [String], rowsMap: [String: [String: Any]], dbPath: String,
        schema: DatabaseSchema, fieldList: [String]?
    ) -> [[String: Any]] {
        let rowStore = RowStore()
        var outputRows: [[String: Any]] = []

        for rowId in ids {
            guard let rowData = rowsMap[rowId],
                  let props = rowData["properties"] as? [String: Any] else { continue }

            var row: [String: Any] = [
                "id": rowId,
                "created_at": rowData["created_at"] ?? "",
                "updated_at": rowData["updated_at"] ?? "",
            ]

            let propertyOutput = presentedQueryProperties(
                props, schema: schema, fields: fieldList, includeRawProperties: rawProperties
            )
            for (key, value) in propertyOutput {
                row[key] = value
            }

            if body, let filename = rowData["filename"] as? String {
                let filePath = (dbPath as NSString).appendingPathComponent("\(filename).md")
                if let dbRow = rowStore.loadRow(at: filePath, schema: schema) {
                    row["body"] = dbRow.body
                }
            }

            outputRows.append(row)
        }

        return outputRows
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

// MARK: - Property Value Comparison

private func comparePropertyValue(_ raw: Any?, to value: PropertyValue) -> Int {
    guard let raw = raw else { return value == .empty ? 0 : -1 }

    switch value {
    case .text(let text):
        return compareRawToString(raw, expected: text)
    case .number(let num):
        return compareRawToNumber(raw, expected: num)
    case .select(let sel):
        return compareRawToString(raw, expected: sel)
    case .date(let dateStr):
        return compareRawToDate(raw, expected: dateStr)
    case .checkbox(let flag):
        if let rawBool = raw as? Bool { return rawBool == flag ? 0 : -1 }
    case .relation(let rel):
        if let rawStr = raw as? String { return rawStr == rel ? 0 : -1 }
    case .empty:
        return isPropertyEmpty(raw) ? 0 : 1
    default:
        break
    }
    return -1
}

private func compareRawToString(_ raw: Any, expected: String) -> Int {
    guard let rawStr = raw as? String else { return -1 }
    return rawStr.compare(expected).rawValue
}

private func compareRawToNumber(_ raw: Any, expected: Double) -> Int {
    if let rawNum = raw as? Double {
        if rawNum < expected { return -1 }
        if rawNum > expected { return 1 }
        return 0
    }
    if let rawInt = raw as? Int {
        let asDouble = Double(rawInt)
        if asDouble < expected { return -1 }
        if asDouble > expected { return 1 }
        return 0
    }
    return -1
}

private func compareRawToDate(_ raw: Any, expected: String) -> Int {
    guard let rawStr = raw as? String else { return -1 }
    let rawKey = DatabaseDateValue.decode(from: rawStr)?.sortKey ?? rawStr
    let compareKey = DatabaseDateValue.decode(from: expected)?.sortKey ?? expected
    return rawKey.compare(compareKey).rawValue
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

// MARK: - Generic Value Comparison

private func compareValues(_ lhs: Any?, _ rhs: Any?) -> Int {
    if lhs == nil && rhs == nil { return 0 }
    if lhs == nil { return -1 }
    if rhs == nil { return 1 }

    if let lhsStr = lhs as? String, let rhsStr = rhs as? String {
        return lhsStr.compare(rhsStr).rawValue
    }
    if let lhsDbl = lhs as? Double, let rhsDbl = rhs as? Double {
        return compareDoubles(lhsDbl, rhsDbl)
    }
    if let lhsInt = lhs as? Int, let rhsInt = rhs as? Int {
        return compareInts(lhsInt, rhsInt)
    }
    if let lhsBool = lhs as? Bool, let rhsBool = rhs as? Bool {
        if lhsBool == rhsBool { return 0 }
        return lhsBool ? 1 : -1
    }
    return 0
}

private func compareDoubles(_ lhs: Double, _ rhs: Double) -> Int {
    if lhs < rhs { return -1 }
    if lhs > rhs { return 1 }
    return 0
}

private func compareInts(_ lhs: Int, _ rhs: Int) -> Int {
    if lhs < rhs { return -1 }
    if lhs > rhs { return 1 }
    return 0
}
