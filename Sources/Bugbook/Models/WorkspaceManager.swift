import Foundation
import os

private let log = Logger(subsystem: "com.bugbook.app", category: "WorkspaceManager")

/// Manages all workspaces, the active workspace, pane operations, and layout persistence.
@MainActor
@Observable
class WorkspaceManager {
    var workspaces: [Workspace] = []
    var activeWorkspaceIndex: Int = 0

    @ObservationIgnored private var persistTask: Task<Void, Never>?

    // MARK: - Active Workspace

    var activeWorkspace: Workspace? {
        get {
            guard activeWorkspaceIndex >= 0, activeWorkspaceIndex < workspaces.count else { return nil }
            return workspaces[activeWorkspaceIndex]
        }
        set {
            guard activeWorkspaceIndex >= 0, activeWorkspaceIndex < workspaces.count, let newValue else { return }
            workspaces[activeWorkspaceIndex] = newValue
        }
    }

    /// The currently focused leaf in the active workspace.
    var focusedPane: PaneNode.Leaf? {
        activeWorkspace?.focusedLeaf
    }

    /// The OpenFile for the focused pane (nil if terminal or no workspace).
    var focusedOpenFile: OpenFile? {
        activeWorkspace?.focusedOpenFile
    }

    // MARK: - Workspace Lifecycle

    func addWorkspace(name: String? = nil) {
        let index = workspaces.count + 1
        let ws = Workspace.makeDefault(name: name ?? "Workspace \(index)")
        workspaces.append(ws)
        activeWorkspaceIndex = workspaces.count - 1
        schedulePersist()
    }

    func closeWorkspace(at index: Int) {
        guard index >= 0, index < workspaces.count else { return }
        workspaces.remove(at: index)

        if workspaces.isEmpty {
            addWorkspace()
            return
        }

        if activeWorkspaceIndex >= workspaces.count {
            activeWorkspaceIndex = workspaces.count - 1
        } else if activeWorkspaceIndex > index {
            activeWorkspaceIndex -= 1
        }
        schedulePersist()
    }

    func switchWorkspace(to index: Int) {
        guard index >= 0, index < workspaces.count else { return }
        activeWorkspaceIndex = index
    }

    func reorderWorkspace(from sourceIndex: Int, to destinationIndex: Int) {
        guard sourceIndex != destinationIndex,
              sourceIndex >= 0, sourceIndex < workspaces.count,
              destinationIndex >= 0, destinationIndex <= workspaces.count else { return }
        let activeId = activeWorkspace?.id
        let ws = workspaces.remove(at: sourceIndex)
        let adjusted = destinationIndex > sourceIndex ? destinationIndex - 1 : destinationIndex
        workspaces.insert(ws, at: adjusted)
        if let activeId, let newIndex = workspaces.firstIndex(where: { $0.id == activeId }) {
            activeWorkspaceIndex = newIndex
        }
        schedulePersist()
    }

    func renameWorkspace(at index: Int, name: String) {
        guard index >= 0, index < workspaces.count else { return }
        workspaces[index].name = name
        schedulePersist()
    }

    // MARK: - Pane Operations

    /// Split the focused pane, inserting a new sibling pane.
    func splitFocusedPane(
        axis: PaneNode.Split.Axis,
        newContent: PaneContent = .terminal
    ) -> UUID? {
        guard var ws = activeWorkspace else { return nil }
        let newLeafId = UUID()

        // If the new content is a document, ensure its OpenFile.id matches the leaf id
        var adjustedContent = newContent
        if case .document(var file) = newContent {
            file = OpenFile(
                id: newLeafId,
                path: file.path,
                content: file.content,
                isDirty: file.isDirty,
                isEmptyTab: file.isEmptyTab,
                kind: file.kind,
                displayName: file.displayName,
                openerPagePath: file.openerPagePath,
                icon: file.icon,
                navigationHistory: file.navigationHistory,
                navigationHistoryIndex: file.navigationHistoryIndex
            )
            adjustedContent = .document(openFile: file)
        }

        let newLeaf = PaneNode.leaf(.init(id: newLeafId, content: adjustedContent))
        ws.root = ws.root.insertingSplit(replacing: ws.focusedPaneId, axis: axis, newSibling: newLeaf)
        ws.focusedPaneId = newLeafId
        activeWorkspace = ws
        schedulePersist()
        return newLeafId
    }

    /// Close a pane by its ID.
    func closePane(id: UUID) {
        guard var ws = activeWorkspace else { return }

        // Single leaf: close the workspace
        if case .leaf(let leaf) = ws.root, leaf.id == id {
            closeWorkspace(at: activeWorkspaceIndex)
            return
        }

        let (newRoot, siblingId) = ws.root.removingLeaf(id: id)
        if let newRoot {
            ws.root = newRoot
            if ws.focusedPaneId == id {
                ws.focusedPaneId = siblingId ?? newRoot.firstLeaf?.id ?? ws.focusedPaneId
            }
            activeWorkspace = ws
        }
        schedulePersist()
    }

    func setFocusedPane(id: UUID) {
        guard var ws = activeWorkspace else { return }
        guard ws.focusedPaneId != id else { return }
        ws.focusedPaneId = id
        activeWorkspace = ws
    }

    func updateSplitRatio(splitId: UUID, ratio: Double) {
        guard var ws = activeWorkspace else { return }
        let clamped = min(max(ratio, 0.15), 0.85)
        ws.root = ws.root.updatingRatio(splitId: splitId, ratio: clamped)
        activeWorkspace = ws
        schedulePersist()
    }

    /// Replace the content of a specific pane leaf.
    func updatePaneContent(paneId: UUID, content: PaneContent) {
        guard var ws = activeWorkspace else { return }
        ws.root = ws.root.updatingLeafContent(leafId: paneId, content: content)
        activeWorkspace = ws
        schedulePersist()
    }

    /// Update the OpenFile inside a document pane (e.g. after navigation or dirty flag change).
    func updatePaneOpenFile(paneId: UUID, transform: (inout OpenFile) -> Void) {
        guard var ws = activeWorkspace else { return }
        guard let leaf = ws.root.findLeaf(id: paneId),
              case .document(var file) = leaf.content else { return }
        transform(&file)
        ws.root = ws.root.updatingLeafContent(leafId: paneId, content: .document(openFile: file))
        activeWorkspace = ws
    }

    // MARK: - Queries

    /// All document-type leaves across all workspaces.
    func allDocumentLeaves() -> [(workspaceIndex: Int, leaf: PaneNode.Leaf, file: OpenFile)] {
        var results: [(Int, PaneNode.Leaf, OpenFile)] = []
        for (i, ws) in workspaces.enumerated() {
            for leaf in ws.allLeaves {
                if case .document(let file) = leaf.content {
                    results.append((i, leaf, file))
                }
            }
        }
        return results
    }

    /// Find the first document leaf in the active workspace that isn't the given pane.
    func nearestDocumentLeaf(from paneId: UUID) -> PaneNode.Leaf? {
        guard let ws = activeWorkspace else { return nil }
        for leaf in ws.allLeaves {
            if leaf.id != paneId, case .document = leaf.content {
                return leaf
            }
        }
        return nil
    }

    // MARK: - Persistence

    private static var layoutFileURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport
            .appendingPathComponent("Bugbook/WorkspaceLayouts", isDirectory: true)
            .appendingPathComponent("layouts.json")
    }

    private static func ensureLayoutDirectory() {
        let dir = layoutFileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    private struct PersistedLayout: Codable {
        let version: Int
        var activeWorkspaceIndex: Int
        var workspaces: [Workspace]
    }

    func schedulePersist() {
        persistTask?.cancel()
        persistTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            self?.persist()
        }
    }

    private func persist() {
        Self.ensureLayoutDirectory()
        let layout = PersistedLayout(version: 1, activeWorkspaceIndex: activeWorkspaceIndex, workspaces: workspaces)
        do {
            let data = try JSONEncoder().encode(layout)
            try data.write(to: Self.layoutFileURL, options: .atomic)
        } catch {
            log.error("Failed to persist workspace layout: \(error)")
        }
    }

    /// Restore from disk or create a default workspace.
    func restoreOrCreateDefault() {
        let url = Self.layoutFileURL
        guard FileManager.default.fileExists(atPath: url.path) else {
            addWorkspace(name: "Workspace")
            return
        }
        do {
            let data = try Data(contentsOf: url)
            let layout = try JSONDecoder().decode(PersistedLayout.self, from: data)
            guard !layout.workspaces.isEmpty else {
                addWorkspace(name: "Workspace")
                return
            }
            workspaces = layout.workspaces
            activeWorkspaceIndex = min(layout.activeWorkspaceIndex, workspaces.count - 1)
        } catch {
            log.error("Failed to restore workspace layout: \(error)")
            addWorkspace(name: "Workspace")
        }
    }
}
