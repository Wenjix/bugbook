import Foundation

/// One document tab in the top tab strip. A workspace owns exactly one
/// document's content; the tab bar renders one pill per workspace.
struct Workspace: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var icon: String?
    var content: PaneContent
    var createdAt: Date

    /// The OpenFile for this tab's document.
    var openFile: OpenFile? {
        content.openFile
    }

    /// True when this tab holds an external markdown file (session-only —
    /// never written to the saved layout).
    var isExternalFile: Bool {
        content.openFile?.isExternal == true
    }

    /// Create a default workspace tab with an empty document.
    static func makeDefault(name: String = "Workspace") -> Workspace {
        let tabId = UUID()
        return Workspace(
            id: UUID(),
            name: name,
            icon: nil,
            content: .emptyDocument(id: tabId),
            createdAt: Date()
        )
    }
}
