import Foundation

public class RowStore {
    private let fm = FileManager.default

    public init() {}

    // MARK: - ID & Filename Helpers

    private static let alphanumericChars = Array("abcdefghijklmnopqrstuvwxyz0123456789")

    public static func generateRowId() -> String {
        let suffix = String((0..<6).map { _ in alphanumericChars.randomElement()! })
        return "row_\(suffix)"
    }

    public static func rowFilename(title: String, suffix: String) -> String {
        let sanitized = title
            .replacingOccurrences(of: "[/\\\\?%*:|\"<>]", with: "-", options: .regularExpression)
            .prefix(80)
        return "\(sanitized) (\(suffix)).md"
    }

    public static func extractIdSuffix(from rowId: String) -> String {
        if rowId.hasPrefix("row_") {
            return String(rowId.dropFirst(4))
        }
        return rowId
    }

    // MARK: - Load

    public func loadRow(at path: String, schema: DatabaseSchema) -> DatabaseRow? {
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
        return RowSerializer.parse(content: content, schema: schema)
    }

    public func loadAllRows(in dbPath: String, schema: DatabaseSchema) -> [DatabaseRow] {
        guard let contents = try? fm.contentsOfDirectory(atPath: dbPath) else { return [] }
        var rows: [DatabaseRow] = []
        for name in contents {
            guard name.hasSuffix(".md"), !name.hasPrefix("_") else { continue }
            let filePath = (dbPath as NSString).appendingPathComponent(name)
            if let row = loadRow(at: filePath, schema: schema) {
                rows.append(row)
            }
        }
        return rows.sorted { $0.createdAt < $1.createdAt }
    }

    // MARK: - Save

    public func saveRow(_ row: DatabaseRow, schema: DatabaseSchema, dbPath: String) throws {
        let title = row.title(schema: schema)
        let suffix = Self.extractIdSuffix(from: row.id)
        let filename = Self.rowFilename(title: title, suffix: suffix)
        let filePath = (dbPath as NSString).appendingPathComponent(filename)

        // Remove old file if title changed (different filename)
        if let contents = try? fm.contentsOfDirectory(atPath: dbPath) {
            for name in contents {
                if name.contains("(\(suffix))") && name != filename {
                    let oldPath = (dbPath as NSString).appendingPathComponent(name)
                    try? fm.removeItem(atPath: oldPath)
                }
            }
        }

        let fileContent = RowSerializer.serialize(row: row, schema: schema)
        try fileContent.write(toFile: filePath, atomically: true, encoding: .utf8)
    }

    // MARK: - Delete

    public func deleteRow(rowId: String, dbPath: String) throws {
        let suffix = Self.extractIdSuffix(from: rowId)
        guard let contents = try? fm.contentsOfDirectory(atPath: dbPath) else { return }
        for name in contents {
            if name.contains("(\(suffix))") && name.hasSuffix(".md") {
                let filePath = (dbPath as NSString).appendingPathComponent(name)
                try fm.removeItem(atPath: filePath)
                break
            }
        }
    }
}
