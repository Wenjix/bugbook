import Foundation

/// A referenced item (block or page) attached as context to an AI sidebar prompt.
enum AiContextItem: Identifiable, Equatable {
    case block(id: UUID, preview: String, markdown: String)
    case page(path: String, name: String)

    var id: String {
        switch self {
        case .block(let id, _, _): return "block-\(id.uuidString)"
        case .page(let path, _): return "page-\(path)"
        }
    }

    var displayLabel: String {
        switch self {
        case .block(_, let preview, _):
            let trimmed = preview.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.count > 30 {
                return String(trimmed.prefix(30)) + "..."
            }
            return trimmed.isEmpty ? "Block" : trimmed
        case .page(_, let name):
            return cleanPageName(name)
        }
    }

    var iconName: String {
        switch self {
        case .block: return "text.quote"
        case .page: return "doc.text"
        }
    }

    /// Heading label used when building AI prompt context (not truncated).
    var contextHeading: String {
        switch self {
        case .block(_, let preview, _):
            let trimmed = preview.trimmingCharacters(in: .whitespacesAndNewlines)
            return "Referenced block (\(trimmed.isEmpty ? "untitled" : trimmed))"
        case .page(_, let name):
            return "Referenced page \"\(cleanPageName(name))\""
        }
    }

    private func cleanPageName(_ name: String) -> String {
        name.hasSuffix(".md") ? String(name.dropLast(3)) : name
    }

    var contextMarkdown: String {
        switch self {
        case .block(_, _, let markdown): return markdown
        case .page(let path, _):
            guard let content = try? String(contentsOfFile: path, encoding: .utf8) else {
                return "[Could not read page content]"
            }
            let maxChars = 8_000
            let snippet = String(content.prefix(maxChars))
            let truncated = content.count > maxChars ? "\n...[truncated]" : ""
            return snippet + truncated
        }
    }
}
