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
        focusedLeaf?.activeOpenFile
    }

    /// All leaves in the tree, flattened.
    var allLeaves: [PaneNode.Leaf] {
        root.allLeaves
    }

    /// True when every tab in every pane is an external-file tab.
    var isEntirelyExternalFiles: Bool {
        let leaves = allLeaves
        guard !leaves.isEmpty else { return false }
        return leaves.allSatisfy { leaf in
            !leaf.tabs.isEmpty && leaf.tabs.allSatisfy { $0.openFile?.isExternal == true }
        }
    }

    /// A copy with external-file tabs removed from every pane (used when persisting —
    /// external tabs are session-only and must not be written to the saved layout).
    func strippingExternalFileTabs() -> Workspace {
        var copy = self
        copy.root = root.strippingExternalFileTabs()
        return copy
    }

    /// Create a default workspace with a single empty-tab document pane.
    static func makeDefault(name: String = "Workspace") -> Workspace {
        let paneId = UUID()
        return Workspace(
            id: UUID(),
            name: name,
            icon: nil,
            root: .leaf(.init(id: paneId, content: .emptyDocument(id: paneId))),
            focusedPaneId: paneId,
            createdAt: Date()
        )
    }

}
