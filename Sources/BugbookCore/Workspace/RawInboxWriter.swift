import Foundation

/// Writes captured notes into the workspace `raw/` inbox.
///
/// Shared helper used by the iOS share extension and any in-app quick-capture
/// surface. Produces `<workspace>/raw/YYYY-MM-DD-<slug>.md` files with an H1 title
/// and body, matching Bugbook's page format (title derived from first H1).
public enum RawInboxWriter {
    public enum WriteError: LocalizedError {
        case writeFailed(path: String, underlying: Error)

        public var errorDescription: String? {
            switch self {
            case .writeFailed(let path, let underlying):
                return "Failed to write raw note at \(path): \(underlying.localizedDescription)"
            }
        }
    }

    /// Generates a unique file path under `<workspace>/raw/`.
    /// Ensures the `raw/` directory exists. Returns the full absolute path.
    public static func newRawFilePath(
        workspace: String,
        title: String,
        date: Date = Date()
    ) -> String {
        let fm = FileManager.default
        let rawDir = (workspace as NSString).appendingPathComponent("raw")
        if !fm.fileExists(atPath: rawDir) {
            try? fm.createDirectory(atPath: rawDir, withIntermediateDirectories: true)
        }

        let dateString = Self.dateFormatter.string(from: date)
        let slug = slugify(title)
        let base = "\(dateString)-\(slug)"

        var candidate = (rawDir as NSString).appendingPathComponent("\(base).md")
        var counter = 2
        while fm.fileExists(atPath: candidate) {
            candidate = (rawDir as NSString).appendingPathComponent("\(base)-\(counter).md")
            counter += 1
        }
        return candidate
    }

    /// Writes a raw note to `<workspace>/raw/YYYY-MM-DD-slug.md`.
    /// File contents are `# <title>\n\n<body>\n`.
    /// Returns the absolute path written.
    @discardableResult
    public static func writeRawNote(
        workspace: String,
        title: String,
        body: String,
        date: Date = Date()
    ) throws -> String {
        let path = newRawFilePath(workspace: workspace, title: title, date: date)
        let displayTitle = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Note" : title
        let contents = "# \(displayTitle)\n\n\(body)\n"
        do {
            try contents.write(toFile: path, atomically: true, encoding: .utf8)
        } catch {
            throw WriteError.writeFailed(path: path, underlying: error)
        }
        return path
    }

    // MARK: - Internal helpers

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        return formatter
    }()
    // Note: RowSerializer.sharedDateOnlyFormatter uses UTC timezone which would
    // produce wrong dates for local-time filenames. Keeping a separate formatter
    // with .current timezone is intentional.

    /// Converts a title to a filesystem-safe lowercase slug. Non-alphanumeric runs
    /// collapse to a single `-`; leading/trailing dashes are stripped; output is
    /// capped at 60 characters. Returns `note` for empty input.
    static func slugify(_ title: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "note" }

        var result = ""
        var lastWasDash = false
        for scalar in trimmed.lowercased().unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                result.unicodeScalars.append(scalar)
                lastWasDash = false
            } else if !lastWasDash {
                result.append("-")
                lastWasDash = true
            }
        }
        result = result.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        if result.isEmpty { return "note" }
        if result.count > 60 {
            result = String(result.prefix(60))
                .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
            if result.isEmpty { return "note" }
        }
        return result
    }
}
