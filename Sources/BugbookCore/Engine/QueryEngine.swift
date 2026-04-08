import Foundation

public struct QueryEngine {

    /// Execute a query against a set of rows: filter, sort, paginate.
    public static func execute(query: Query, schema: DatabaseSchema, rows: [DatabaseRow]) -> QueryResult {
        // 1. Apply all filters in a single pass (ANDed)
        var sorted: [DatabaseRow]
        if query.filters.isEmpty {
            sorted = rows
        } else {
            let filters = query.filters
            sorted = rows.filter { row in
                filters.allSatisfy { matches(row: row, filter: $0) }
            }
        }

        // 2. Sort
        if !query.sorts.isEmpty {
            sorted.sort { a, b in
                for sort in query.sorts {
                    let aVal = a.properties[sort.property]
                    let bVal = b.properties[sort.property]
                    let cmp = compareValues(aVal, bVal)
                    if cmp != 0 {
                        return sort.ascending ? cmp < 0 : cmp > 0
                    }
                }
                return false
            }
        }

        // 3. Paginate using slice indices to avoid extra Array allocations
        let totalCount = sorted.count
        let offset = query.offset ?? 0
        let startIdx = min(offset, totalCount)
        let endIdx: Int
        if let limit = query.limit {
            endIdx = min(startIdx + limit, totalCount)
        } else {
            endIdx = totalCount
        }

        let hasMore: Bool
        if let limit = query.limit {
            hasMore = (offset + limit) < totalCount
        } else {
            hasMore = false
        }

        let page = startIdx < endIdx ? Array(sorted[startIdx..<endIdx]) : []
        return QueryResult(rows: page, totalCount: totalCount, hasMore: hasMore)
    }

    // MARK: - Filter Matching

    private static func matches(row: DatabaseRow, filter: Filter) -> Bool {
        switch filter {
        case .equals(let prop, let value):
            let rowVal = row.properties[prop]
            return valuesEqual(rowVal, value)

        case .notEquals(let prop, let value):
            let rowVal = row.properties[prop]
            return !valuesEqual(rowVal, value)

        case .greaterThan(let prop, let value):
            let rowVal = row.properties[prop]
            return compareValues(rowVal, value) > 0

        case .lessThan(let prop, let value):
            let rowVal = row.properties[prop]
            return compareValues(rowVal, value) < 0

        case .contains(let prop, let value):
            guard let rowVal = row.properties[prop] else { return false }
            return containsValue(rowVal, value)

        case .notContains(let prop, let value):
            guard let rowVal = row.properties[prop] else { return true }
            return !containsValue(rowVal, value)

        case .isEmpty(let prop):
            guard let rowVal = row.properties[prop] else { return true }
            if case .empty = rowVal { return true }
            return false

        case .isNotEmpty(let prop):
            guard let rowVal = row.properties[prop] else { return false }
            if case .empty = rowVal { return false }
            return true

        case .inList(let prop, let values):
            guard let rowVal = row.properties[prop] else { return false }
            return values.contains(where: { valuesEqual(rowVal, $0) })
        }
    }

    private static func valuesEqual(_ a: PropertyValue?, _ b: PropertyValue?) -> Bool {
        guard let a = a else { return b == nil || b == .empty }
        guard let b = b else { return a == .empty }
        if case .date(let aRaw) = a, case .date(let bRaw) = b {
            let aKey = DatabaseDateValue.decode(from: aRaw)?.sortKey ?? aRaw
            let bKey = DatabaseDateValue.decode(from: bRaw)?.sortKey ?? bRaw
            return aKey == bKey
        }
        return a == b
    }

    private static func containsValue(_ rowVal: PropertyValue, _ searchVal: PropertyValue) -> Bool {
        let searchStr = searchVal.stringValue

        switch rowVal {
        case .multiSelect(let arr):
            return arr.contains(searchStr)
        case .relationMany(let arr):
            return arr.contains(searchStr)
        default:
            return rowVal.stringValue.localizedCaseInsensitiveContains(searchStr)
        }
    }

    // MARK: - Sorting

    /// Returns <0 if a<b, 0 if equal, >0 if a>b
    private static func compareValues(_ a: PropertyValue?, _ b: PropertyValue?) -> Int {
        // Fast path: check type-specific comparisons before computing stringValue
        if case .number(let an) = a, case .number(let bn) = b {
            if an < bn { return -1 }
            if an > bn { return 1 }
            return 0
        }

        if case .date(let aRaw) = a, case .date(let bRaw) = b {
            let aKey = DatabaseDateValue.decode(from: aRaw)?.sortKey ?? aRaw
            let bKey = DatabaseDateValue.decode(from: bRaw)?.sortKey ?? bRaw
            return aKey.compare(bKey).rawValue
        }

        let aStr = a?.stringValue ?? ""
        let bStr = b?.stringValue ?? ""

        // Both empty
        if aStr.isEmpty && bStr.isEmpty { return 0 }
        // Empties sort last
        if aStr.isEmpty { return 1 }
        if bStr.isEmpty { return -1 }

        return aStr.compare(bStr).rawValue
    }
}
