import Foundation

public class IndexManager {
    private let fm = FileManager.default
    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    public init() {}

    // MARK: - Load

    public func loadIndex(at dbPath: String) -> [String: Any]? {
        let indexPath = (dbPath as NSString).appendingPathComponent("_index.json")
        guard let data = fm.contents(atPath: indexPath),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return obj
    }

    // MARK: - Staleness

    public func isStale(indexData: [String: Any], dbPath: String) -> Bool {
        guard let indexRows = indexData["rows"] as? [String: [String: Any]] else { return true }

        // Get actual row files on disk
        guard let contents = try? fm.contentsOfDirectory(atPath: dbPath) else { return true }
        let mdFiles = contents.filter { $0.hasSuffix(".md") && !$0.hasPrefix("_") }

        // Row count mismatch
        if indexRows.count != mdFiles.count { return true }

        // Compare mtimes
        for (_, rowData) in indexRows {
            guard let filename = rowData["filename"] as? String,
                  let indexMtime = rowData["mtime"] as? Int else { return true }
            let filePath = (dbPath as NSString).appendingPathComponent("\(filename).md")
            guard let attrs = try? fm.attributesOfItem(atPath: filePath),
                  let modDate = attrs[.modificationDate] as? Date else { return true }
            let diskMtime = Int(modDate.timeIntervalSince1970 * 1000)
            if diskMtime != indexMtime { return true }
        }

        return false
    }

    // MARK: - Rebuild

    public func rebuild(dbPath: String, schema: DatabaseSchema, rows: [DatabaseRow]) -> [String: Any] {
        // Pre-filter indexed properties once
        let indexedTypes: Set<PropertyType> = [.select, .multiSelect, .relation, .checkbox]
        let indexedProps = schema.properties.filter { indexedTypes.contains($0.type) }

        // Single pass: build row entries and reverse indexes simultaneously
        var rowsMap: [String: Any] = Dictionary(minimumCapacity: rows.count)
        var indexes: [String: [String: [String]]] = Dictionary(minimumCapacity: indexedProps.count)
        for prop in indexedProps {
            indexes[prop.id] = [:]
        }

        // Build local index dicts to avoid repeated hash lookups on `indexes`
        var localIndexes: [String: [String: [String]]] = Dictionary(minimumCapacity: indexedProps.count)
        for prop in indexedProps { localIndexes[prop.id] = [:] }

        for row in rows {
            rowsMap[row.id] = buildRowEntry(row: row, schema: schema, dbPath: dbPath)

            // Build reverse indexes in the same pass
            for prop in indexedProps {
                guard let val = row.properties[prop.id] else { continue }
                switch val {
                case .select(let optId):
                    localIndexes[prop.id]![optId, default: []].append(row.id)
                case .multiSelect(let optIds):
                    for optId in optIds {
                        localIndexes[prop.id]![optId, default: []].append(row.id)
                    }
                case .relation(let rowId):
                    localIndexes[prop.id]![rowId, default: []].append(row.id)
                case .relationMany(let rowIds):
                    for rid in rowIds {
                        localIndexes[prop.id]![rid, default: []].append(row.id)
                    }
                case .checkbox(let b):
                    localIndexes[prop.id]![b ? "true" : "false", default: []].append(row.id)
                default:
                    break
                }
            }
        }

        indexes = localIndexes.filter { !$0.value.isEmpty }

        return [
            "version": 1,
            "updated_at": Self.isoFormatter.string(from: Date()),
            "rows": rowsMap,
            "indexes": indexes
        ]
    }

    // MARK: - Single Row Entry

    /// Build the index entry dictionary for a single row (used by incremental updates).
    public func buildRowEntry(row: DatabaseRow, schema: DatabaseSchema, dbPath: String) -> [String: Any] {
        var props: [String: Any] = [:]
        for prop in schema.properties {
            if let val = row.properties[prop.id] {
                props[prop.id] = RowSerializer.serializeValueForIndex(val)
            }
        }

        let filename = rowFilename(row: row, schema: schema, dbPath: dbPath)
        let filePath = (dbPath as NSString).appendingPathComponent("\(filename).md")
        let mtime: Int
        if let attrs = try? fm.attributesOfItem(atPath: filePath),
           let modDate = attrs[.modificationDate] as? Date {
            mtime = Int(modDate.timeIntervalSince1970 * 1000)
        } else {
            mtime = Int(row.updatedAt.timeIntervalSince1970 * 1000)
        }

        return [
            "properties": props,
            "created_at": iso8601String(from: row.createdAt),
            "updated_at": iso8601String(from: row.updatedAt),
            "filename": filename,
            "mtime": mtime
        ]
    }

    // MARK: - Save

    public func saveIndex(_ index: [String: Any], at dbPath: String) throws {
        let indexPath = (dbPath as NSString).appendingPathComponent("_index.json")
        let data = try JSONSerialization.data(withJSONObject: index, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: URL(fileURLWithPath: indexPath), options: .atomic)
    }

    // MARK: - Private

    private func iso8601String(from date: Date) -> String {
        Self.isoFormatter.string(from: date)
    }

    private func rowFilename(row: DatabaseRow, schema: DatabaseSchema, dbPath: String) -> String {
        let title = row.title(schema: schema)
        let suffix = RowStore.extractIdSuffix(from: row.id)
        let fallback = RowStore.rowFilename(title: title, suffix: suffix)
            .replacingOccurrences(of: ".md", with: "")

        guard let contents = try? fm.contentsOfDirectory(atPath: dbPath) else {
            return fallback
        }

        for name in contents where name.hasSuffix(".md") && name.contains("(\(suffix))") {
            return String(name.dropLast(3))
        }

        for name in contents where name.hasSuffix(".md") && !name.hasPrefix("_") {
            let filePath = (dbPath as NSString).appendingPathComponent(name)
            guard let content = try? String(contentsOfFile: filePath, encoding: .utf8),
                  Self.extractFrontmatterID(from: content) == row.id else {
                continue
            }
            return String(name.dropLast(3))
        }

        return fallback
    }

    private static func extractFrontmatterID(from content: String) -> String? {
        guard content.hasPrefix("---") else { return nil }
        let afterFirst = content.index(content.startIndex, offsetBy: 3)
        guard let endRange = content.range(of: "\n---", range: afterFirst..<content.endIndex) else {
            return nil
        }
        let frontmatter = content[afterFirst..<endRange.lowerBound]
        for rawLine in frontmatter.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("id:") else { continue }
            let rawValue = line.dropFirst(3).trimmingCharacters(in: .whitespaces)
            guard !rawValue.isEmpty else { return nil }
            if rawValue.hasPrefix("\""), rawValue.hasSuffix("\""), rawValue.count >= 2 {
                return String(rawValue.dropFirst().dropLast())
            }
            return rawValue
        }
        return nil
    }
}
