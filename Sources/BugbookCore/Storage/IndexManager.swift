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
        var rowsMap: [String: Any] = [:]
        for row in rows {
            let title = row.title(schema: schema)
            let suffix = RowStore.extractIdSuffix(from: row.id)

            var props: [String: Any] = [:]
            for prop in schema.properties {
                if let val = row.properties[prop.id] {
                    props[prop.id] = RowSerializer.serializeValueForIndex(val)
                }
            }

            let filename = RowStore.rowFilename(title: title, suffix: suffix).replacingOccurrences(of: ".md", with: "")
            let filePath = (dbPath as NSString).appendingPathComponent("\(filename).md")
            let mtime: Int
            if let attrs = try? fm.attributesOfItem(atPath: filePath),
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

        // Build reverse indexes
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
                    propIndex[b ? "true" : "false", default: []].append(row.id)
                default:
                    break
                }
            }
            if !propIndex.isEmpty {
                indexes[prop.id] = propIndex
            }
        }

        return [
            "version": 1,
            "updated_at": Self.isoFormatter.string(from: Date()),
            "rows": rowsMap,
            "indexes": indexes
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
}
