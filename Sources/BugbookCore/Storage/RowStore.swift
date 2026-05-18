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
        var sanitized = String()
        sanitized.reserveCapacity(min(title.count, 80) + suffix.count + 6)
        var count = 0
        for c in title {
            guard count < 80 else { break }
            switch c {
            case "/", "\\", "?", "%", "*", ":", "|", "\"", "<", ">":
                sanitized.append("-")
            default:
                sanitized.append(c)
            }
            count += 1
        }
        sanitized.append(" (")
        sanitized.append(suffix)
        sanitized.append(").md")
        return sanitized
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

        let mdFiles = contents.filter { $0.hasSuffix(".md") && !$0.hasPrefix("_") }

        // Track best row per ID to detect and clean up duplicates.
        var bestByID: [String: (row: DatabaseRow, filename: String)] = [:]
        bestByID.reserveCapacity(mdFiles.count)
        var duplicateFiles: [String] = []

        for name in mdFiles {
            let filePath = (dbPath as NSString).appendingPathComponent(name)
            guard let row = loadRow(at: filePath, schema: schema, skipBody: skipBody) else { continue }

            let rowId = row.id
            if let existing = bestByID[rowId] {
                // Build the suffix pattern once per conflict, not per row
                let suffixPattern = "(\(Self.extractIdSuffix(from: rowId)))"
                let existingIsCanonical = existing.filename.contains(suffixPattern)
                let newIsCanonical = name.contains(suffixPattern)

                if newIsCanonical && !existingIsCanonical {
                    duplicateFiles.append(existing.filename)
                    bestByID[rowId] = (row, name)
                } else if !newIsCanonical && existingIsCanonical {
                    duplicateFiles.append(name)
                } else {
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

    /// Result of a detailed row load that includes raw property strings for legacy repair.
    public struct DetailedLoadResult {
        public let row: DatabaseRow
        public let filename: String
        public let rawProperties: [String: String]
    }

    /// Load all rows with detailed parse results (raw properties for legacy repair).
    /// Handles duplicate detection and cleanup just like loadAllRows.
    public func loadAllRowsDetailed(in dbPath: String, schema: DatabaseSchema) -> [DetailedLoadResult] {
        guard let contents = try? fm.contentsOfDirectory(atPath: dbPath) else { return [] }

        var bestByID: [String: DetailedLoadResult] = [:]
        var duplicateFiles: [String] = []

        for name in contents {
            guard name.hasSuffix(".md"), !name.hasPrefix("_") else { continue }
            let filePath = (dbPath as NSString).appendingPathComponent(name)
            guard let content = try? String(contentsOfFile: filePath, encoding: .utf8) else { continue }
            guard let parsed = RowSerializer.parseDetailed(content: content, schema: schema, skipBody: true) else { continue }

            let detail = DetailedLoadResult(row: parsed.row, filename: name, rawProperties: parsed.rawProperties)
            let rowId = parsed.row.id

            if let existing = bestByID[rowId] {
                let suffix = Self.extractIdSuffix(from: rowId)
                let existingIsCanonical = existing.filename.contains("(\(suffix))")
                let newIsCanonical = name.contains("(\(suffix))")

                if newIsCanonical && !existingIsCanonical {
                    duplicateFiles.append(existing.filename)
                    bestByID[rowId] = detail
                } else if !newIsCanonical && existingIsCanonical {
                    duplicateFiles.append(name)
                } else {
                    if parsed.row.updatedAt > existing.row.updatedAt {
                        duplicateFiles.append(existing.filename)
                        bestByID[rowId] = detail
                    } else {
                        duplicateFiles.append(name)
                    }
                }
            } else {
                bestByID[rowId] = detail
            }
        }

        for filename in duplicateFiles {
            let filePath = (dbPath as NSString).appendingPathComponent(filename)
            try? fm.removeItem(atPath: filePath)
        }

        return bestByID.values.sorted { $0.row.createdAt < $1.row.createdAt }
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
        for name in contents where name.hasSuffix(".md") && !name.hasPrefix("_") {
            let filePath = (dbPath as NSString).appendingPathComponent(name)
            guard let content = try? String(contentsOfFile: filePath, encoding: .utf8),
                  Self.extractFrontmatterID(from: content) == rowId else {
                continue
            }
            return Self.extractBody(from: content)
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

        // Single directory listing for both body preservation and stale file cleanup.
        let dirContents = try? fm.contentsOfDirectory(atPath: dbPath)
        let existingFilePath = existingRowFilePath(rowId: row.id, suffix: suffix, dbPath: dbPath, contents: dirContents)
        let filename = existingFilePath.map { ($0 as NSString).lastPathComponent }
            ?? Self.rowFilename(title: title, suffix: suffix)
        let filePath = (dbPath as NSString).appendingPathComponent(filename)

        // If the row has no in-memory body, preserve the existing body on disk
        // (rows loaded without body for table/kanban performance).
        var effectiveRow = row
        let existingContent = existingFilePath.flatMap { try? String(contentsOfFile: $0, encoding: .utf8) }
        if effectiveRow.body.isEmpty {
            if let existingContent {
                effectiveRow.body = Self.extractBody(from: existingContent)
            } else if let dirContents {
                for name in dirContents where name.hasSuffix(".md") && name.contains("(\(suffix))") {
                    let existingPath = (dbPath as NSString).appendingPathComponent(name)
                    if let existing = try? String(contentsOfFile: existingPath, encoding: .utf8) {
                        effectiveRow.body = Self.extractBody(from: existing)
                        break
                    }
                }
            }
        }

        // Remove old file if title changed (different filename)
        if row.id.hasPrefix("row_"), let dirContents {
            for name in dirContents where name.contains("(\(suffix))") && name != filename {
                let oldPath = (dbPath as NSString).appendingPathComponent(name)
                try? fm.removeItem(atPath: oldPath)
            }
        }

        let preservesFlatFrontmatter = existingContent.map(Self.usesFlatFrontmatter) ?? !row.id.hasPrefix("row_")
        let fileContent = preservesFlatFrontmatter
            ? RowSerializer.serializeFlat(row: effectiveRow, schema: schema)
            : RowSerializer.serialize(row: effectiveRow, schema: schema)
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
        for name in contents where name.hasSuffix(".md") && !name.hasPrefix("_") {
            let filePath = (dbPath as NSString).appendingPathComponent(name)
            guard let content = try? String(contentsOfFile: filePath, encoding: .utf8),
                  Self.extractFrontmatterID(from: content) == rowId else {
                continue
            }
            try fm.removeItem(atPath: filePath)
            break
        }
    }

    private func existingRowFilePath(
        rowId: String,
        suffix: String,
        dbPath: String,
        contents: [String]?
    ) -> String? {
        guard let contents else { return nil }
        for name in contents where name.hasSuffix(".md") && name.contains("(\(suffix))") {
            return (dbPath as NSString).appendingPathComponent(name)
        }
        for name in contents where name.hasSuffix(".md") && !name.hasPrefix("_") {
            let filePath = (dbPath as NSString).appendingPathComponent(name)
            guard let content = try? String(contentsOfFile: filePath, encoding: .utf8),
                  Self.extractFrontmatterID(from: content) == rowId else {
                continue
            }
            return filePath
        }
        return nil
    }

    private static func usesFlatFrontmatter(_ content: String) -> Bool {
        guard content.hasPrefix("---") else { return false }
        let afterFirst = content.index(content.startIndex, offsetBy: 3)
        guard let endRange = content.range(of: "\n---", range: afterFirst..<content.endIndex) else {
            return false
        }
        let frontmatter = content[afterFirst..<endRange.lowerBound]
        return !frontmatter.contains("\nproperties:")
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
