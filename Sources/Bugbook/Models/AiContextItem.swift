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

    private func cleanPageName(_ name: String) -> String {
        name.hasSuffix(".md") ? String(name.dropLast(3)) : name
    }
}
