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

    public func loadRow(at path: String, schema: DatabaseSchema, skipBody: Bool = false) -> DatabaseRow? {
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
        return RowSerializer.parse(content: content, schema: schema, skipBody: skipBody)
    }

    public func loadAllRows(in dbPath: String, schema: DatabaseSchema, skipBody: Bool = false) -> [DatabaseRow] {
        let start = CFAbsoluteTimeGetCurrent()
        guard let contents = try? fm.contentsOfDirectory(atPath: dbPath) else { return [] }

        // Track best row per ID to detect and clean up duplicates.
        var bestByID: [String: (row: DatabaseRow, filename: String)] = [:]
        var duplicateFiles: [String] = []

        for name in contents {
            guard name.hasSuffix(".md"), !name.hasPrefix("_") else { continue }
            let filePath = (dbPath as NSString).appendingPathComponent(name)
            guard let row = loadRow(at: filePath, schema: schema, skipBody: skipBody) else { continue }

            let rowId = row.id
            if let existing = bestByID[rowId] {
                let suffix = Self.extractIdSuffix(from: rowId)
                let existingIsCanonical = existing.filename.contains("(\(suffix))")
                let newIsCanonical = name.contains("(\(suffix))")

                if newIsCanonical && !existingIsCanonical {
                    duplicateFiles.append(existing.filename)
                    bestByID[rowId] = (row, name)
                } else if !newIsCanonical && existingIsCanonical {
                    duplicateFiles.append(name)
                } else {
                    // Both canonical or both non-canonical — keep newer
                    if row.updatedAt > existing.row.updatedAt {
                        duplicateFiles.append(existing.filename)
                        bestByID[rowId] = (row, name)
                    } else {
                        duplicateFiles.append(name)
                    }
                }
            } else {
                bestByID[rowId] = (row, name)
            }
        }

        // Clean up orphan duplicate files.
        for filename in duplicateFiles {
            let filePath = (dbPath as NSString).appendingPathComponent(filename)
            try? fm.removeItem(atPath: filePath)
        }

        let rows = bestByID.values.map(\.row).sorted { $0.createdAt < $1.createdAt }
        let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000
        if elapsed > 100 {
            print("[RowStore] loadAllRows: \(rows.count) rows in \(Int(elapsed))ms")
        }
        return rows
    }

    /// Load just the body content for a row by ID.
    public func loadRowBody(rowId: String, dbPath: String) -> String {
        let suffix = Self.extractIdSuffix(from: rowId)
        guard let contents = try? fm.contentsOfDirectory(atPath: dbPath) else { return "" }
        for name in contents where name.hasSuffix(".md") && name.contains("(\(suffix))") {
            let filePath = (dbPath as NSString).appendingPathComponent(name)
            if let content = try? String(contentsOfFile: filePath, encoding: .utf8) {
                return Self.extractBody(from: content)
            }
        }
        return ""
    }

    /// Extract the body portion from a frontmatter file's content.
    public static func extractBody(from content: String) -> String {
        guard content.hasPrefix("---") else { return content }
        let afterFirst = content.index(content.startIndex, offsetBy: 3)
        guard let endRange = content.range(of: "\n---", range: afterFirst..<content.endIndex) else { return "" }
        return String(content[endRange.upperBound...]).trimmingCharacters(in: .newlines)
    }

    // MARK: - Save

    public func saveRow(_ row: DatabaseRow, schema: DatabaseSchema, dbPath: String) throws {
        let title = row.title(schema: schema)
        let suffix = Self.extractIdSuffix(from: row.id)
        let filename = Self.rowFilename(title: title, suffix: suffix)
        let filePath = (dbPath as NSString).appendingPathComponent(filename)

        // Single directory listing for both body preservation and stale file cleanup.
        let dirContents = try? fm.contentsOfDirectory(atPath: dbPath)

        // If the row has no in-memory body, preserve the existing body on disk
        // (rows loaded without body for table/kanban performance).
        var effectiveRow = row
        if effectiveRow.body.isEmpty, let dirContents {
            for name in dirContents where name.hasSuffix(".md") && name.contains("(\(suffix))") {
                let existingPath = (dbPath as NSString).appendingPathComponent(name)
                if let existing = try? String(contentsOfFile: existingPath, encoding: .utf8) {
                    effectiveRow.body = Self.extractBody(from: existing)
                    break
                }
            }
        }

        // Remove old file if title changed (different filename)
        if let dirContents {
            for name in dirContents where name.contains("(\(suffix))") && name != filename {
                let oldPath = (dbPath as NSString).appendingPathComponent(name)
                try? fm.removeItem(atPath: oldPath)
            }
        }

        let fileContent = RowSerializer.serialize(row: effectiveRow, schema: schema)
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
