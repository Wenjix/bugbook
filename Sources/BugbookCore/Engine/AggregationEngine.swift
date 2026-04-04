import Foundation

public struct AggregationEngine {

    /// All supported aggregation function names.
    public static let allFunctions = [
        "count", "count_values", "count_unique",
        "sum", "avg", "min", "max",
        "percent_checked", "percent_unchecked"
    ]

    /// Returns the subset of functions applicable to a given property type.
    public static func availableFunctions(for type: PropertyType) -> [String] {
        switch type {
        case .number:
            return ["count", "count_values", "count_unique", "sum", "avg", "min", "max"]
        case .text, .title:
            return ["count", "count_values", "count_unique"]
        case .select:
            return ["count", "count_values", "count_unique"]
        case .multiSelect:
            return ["count", "count_values", "count_unique"]
        case .date:
            return ["count", "count_values", "count_unique", "min", "max"]
        case .checkbox:
            return ["count", "count_values", "percent_checked", "percent_unchecked"]
        case .url, .email:
            return ["count", "count_values", "count_unique"]
        case .relation:
            return ["count", "count_values", "count_unique"]
        case .formula:
            return ["count", "count_values", "count_unique", "sum", "avg", "min", "max"]
        case .lookup:
            return ["count", "count_values", "count_unique"]
        case .rollup:
            return ["count", "count_values", "count_unique"]
        }
    }

    /// Human-readable label for a function name.
    public static func displayName(for function: String) -> String {
        switch function {
        case "count": return "Count"
        case "count_values": return "Count values"
        case "count_unique": return "Count unique"
        case "sum": return "Sum"
        case "avg": return "Average"
        case "min": return "Min"
        case "max": return "Max"
        case "percent_checked": return "Percent checked"
        case "percent_unchecked": return "Percent unchecked"
        default: return function
        }
    }

    /// Compute an aggregation over rows for a given property.
    public static func compute(
        function: String,
        propertyId: String,
        rows: [DatabaseRow],
        schema: DatabaseSchema
    ) -> String {
        let values = rows.map { $0.properties[propertyId] ?? .empty }
        let prop = schema.properties.first(where: { $0.id == propertyId })
        let format = prop?.config?.format

        switch function {
        case "count":
            return "\(rows.count)"

        case "count_values":
            let count = values.filter { !isEmptyValue($0) }.count
            return "\(count)"

        case "count_unique":
            let unique = Set(values.compactMap { nonEmptyString($0) })
            return "\(unique.count)"

        case "sum":
            let total = values.reduce(0.0) { acc, val in
                if case .number(let n) = val { return acc + n }
                return acc
            }
            return formatNumber(total, format: format)

        case "avg":
            let numbers = values.compactMap { val -> Double? in
                if case .number(let n) = val { return n }
                return nil
            }
            guard !numbers.isEmpty else { return "-" }
            let avg = numbers.reduce(0, +) / Double(numbers.count)
            return formatNumber(avg, format: format)

        case "min":
            return computeMin(values: values, format: format)

        case "max":
            return computeMax(values: values, format: format)

        case "percent_checked":
            guard !rows.isEmpty else { return "-" }
            let checked = values.filter {
                if case .checkbox(true) = $0 { return true }
                return false
            }.count
            let pct = Double(checked) / Double(rows.count) * 100
            return "\(Int(pct.rounded()))%"

        case "percent_unchecked":
            guard !rows.isEmpty else { return "-" }
            let unchecked = values.filter { val in
                switch val {
                case .checkbox(false): return true
                case .checkbox(true): return false
                default: return false
                }
            }.count
            let pct = Double(unchecked) / Double(rows.count) * 100
            return "\(Int(pct.rounded()))%"

        default:
            return "-"
        }
    }

    // MARK: - Private

    private static func isEmptyValue(_ val: PropertyValue) -> Bool {
        switch val {
        case .empty: return true
        case .text(let s): return s.isEmpty
        case .select(let s): return s.isEmpty
        case .multiSelect(let arr): return arr.isEmpty
        case .date(let s): return s.isEmpty
        case .url(let s): return s.isEmpty
        case .email(let s): return s.isEmpty
        case .relation(let s): return s.isEmpty
        case .relationMany(let arr): return arr.isEmpty
        case .number: return false
        case .checkbox: return false
        }
    }

    private static func nonEmptyString(_ val: PropertyValue) -> String? {
        switch val {
        case .empty: return nil
        case .text(let s): return s.isEmpty ? nil : s
        case .number(let n): return String(n)
        case .select(let s): return s.isEmpty ? nil : s
        case .multiSelect(let arr): return arr.isEmpty ? nil : arr.joined(separator: ",")
        case .date(let s): return s.isEmpty ? nil : s
        case .checkbox(let b): return b ? "true" : "false"
        case .url(let s): return s.isEmpty ? nil : s
        case .email(let s): return s.isEmpty ? nil : s
        case .relation(let s): return s.isEmpty ? nil : s
        case .relationMany(let arr): return arr.isEmpty ? nil : arr.joined(separator: ",")
        }
    }

    private static func computeMin(values: [PropertyValue], format: String?) -> String {
        var minNum: Double?
        var minDate: String?

        for val in values {
            switch val {
            case .number(let n):
                if let current = minNum { minNum = Swift.min(current, n) } else { minNum = n }
            case .date(let raw):
                let key = DatabaseDateValue.decode(from: raw)?.sortKey ?? raw
                guard !key.isEmpty else { continue }
                if let current = minDate { if key < current { minDate = key } } else { minDate = key }
            default:
                break
            }
        }

        if let n = minNum { return formatNumber(n, format: format) }
        if let d = minDate {
            return DatabaseDateValue.decode(from: d)?.displayText(compact: true) ?? d
        }
        return "-"
    }

    private static func computeMax(values: [PropertyValue], format: String?) -> String {
        var maxNum: Double?
        var maxDate: String?

        for val in values {
            switch val {
            case .number(let n):
                if let current = maxNum { maxNum = Swift.max(current, n) } else { maxNum = n }
            case .date(let raw):
                let key = DatabaseDateValue.decode(from: raw)?.sortKey ?? raw
                guard !key.isEmpty else { continue }
                if let current = maxDate { if key > current { maxDate = key } } else { maxDate = key }
            default:
                break
            }
        }

        if let n = maxNum { return formatNumber(n, format: format) }
        if let d = maxDate {
            return DatabaseDateValue.decode(from: d)?.displayText(compact: true) ?? d
        }
        return "-"
    }

    private static let currencyFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.maximumFractionDigits = 2
        return f
    }()

    private static let decimalFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 2
        return f
    }()

    private static func formatNumber(_ value: Double, format: String?) -> String {
        switch format {
        case "dollar":
            return currencyFormatter.string(from: NSNumber(value: value)) ?? String(value)
        case "percent":
            return "\(Int((value * 100).rounded()))%"
        default:
            if value == value.rounded() && abs(value) < 1e15 {
                return String(Int(value))
            }
            return decimalFormatter.string(from: NSNumber(value: value)) ?? String(value)
        }
    }
}
