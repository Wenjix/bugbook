import Foundation

/// A workspace owns a pane tree layout and metadata.
/// Displayed as a tab in the workspace tab bar.
struct Workspace: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var icon: String?
    var root: PaneNode
    var focusedPaneId: UUID
    var createdAt: Date

    /// Whether this workspace has more than one pane (used for focus indicator visibility).
    var hasMultiplePanes: Bool {
        if case .split = root { return true }
        return false
    }

    /// The focused leaf, if it exists in the tree.
    var focusedLeaf: PaneNode.Leaf? {
        root.findLeaf(id: focusedPaneId)
    }

    /// The OpenFile for the focused pane, if it is a document pane.
    var focusedOpenFile: OpenFile? {
        guard let leaf = focusedLeaf,
              case .document(let file) = leaf.content else { return nil }
        return file
    }

    /// All leaves in the tree, flattened.
    var allLeaves: [PaneNode.Leaf] {
        root.allLeaves
    }

    /// Create a default workspace with a single empty-tab document pane.
    static func makeDefault(name: String = "Workspace") -> Workspace {
        let paneId = UUID()
        let emptyFile = OpenFile(
            id: paneId,
            path: "",
            content: "",
            isDirty: false,
            isEmptyTab: true
        )
        return Workspace(
            id: UUID(),
            name: name,
            icon: nil,
            root: .leaf(.init(id: paneId, content: .document(openFile: emptyFile))),
            focusedPaneId: paneId,
            createdAt: Date()
        )
    }

    /// Create a workspace from an existing OpenFile (migration from tab system).
    static func fromOpenFile(_ file: OpenFile, name: String = "Workspace") -> Workspace {
        Workspace(
            id: UUID(),
            name: name,
            icon: nil,
            root: .leaf(.init(id: file.id, content: .document(openFile: file))),
            focusedPaneId: file.id,
            createdAt: Date()
        )
    }
}
