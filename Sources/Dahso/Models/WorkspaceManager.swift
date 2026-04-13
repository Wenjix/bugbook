import Foundation
import os

private let log = Logger(subsystem: "com.dahso.app", category: "WorkspaceManager")

/// Manages all workspaces, the active workspace, pane operations, and layout persistence.
@MainActor
@Observable
class WorkspaceManager {
    var workspaces: [Workspace] = []
    var activeWorkspaceIndex: Int = 0
    /// Set after each successful layout save; UI can observe this for a brief indicator.
    var lastSavedAt: Date?
    var layoutPersistenceEnabled = true

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

    var focusedPaneContent: PaneContent? {
        activeWorkspace?.focusedLeaf?.activeContent
    }

    var focusedPaneTabID: UUID? {
        activeWorkspace?.focusedLeaf?.activeTabID
    }

    // MARK: - Workspace Lifecycle

    func addWorkspace(name: String? = nil) {
        let ws = Workspace.makeDefault(name: name ?? "New Tab")
        workspaces.append(ws)
        activeWorkspaceIndex = workspaces.count - 1
        schedulePersist()
    }

    func addWorkspaceWith(content: PaneContent) {
        let paneId = UUID()
        let adjustedContent = content.reidentified(as: paneId)
        let ws = Workspace(
            id: UUID(),
            name: "New Tab",
            icon: nil,
            root: .leaf(.init(id: paneId, tabs: [adjustedContent])),
            focusedPaneId: paneId,
            createdAt: Date()
        )
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

    func detachWorkspace(at index: Int) -> Workspace? {
        guard index >= 0, index < workspaces.count else { return nil }

        let detachedWorkspace = workspaces.remove(at: index)

        if workspaces.isEmpty {
            workspaces = [Workspace.makeDefault(name: "Workspace")]
            activeWorkspaceIndex = 0
        } else if activeWorkspaceIndex >= workspaces.count {
            activeWorkspaceIndex = workspaces.count - 1
        } else if activeWorkspaceIndex > index {
            activeWorkspaceIndex -= 1
        }

        schedulePersist()
        return detachedWorkspace
    }

    // MARK: - Pane Operations

    /// Split the focused pane, inserting a new sibling pane.
    func splitFocusedPane(
        axis: PaneNode.Split.Axis,
        newContent: PaneContent = .terminal()
    ) -> UUID? {
        guard var ws = activeWorkspace else { return nil }
        let newLeafId = UUID()
        let newLeaf = PaneNode.leaf(.init(id: newLeafId, content: newContent.reidentified(as: newLeafId)))
        ws.root = ws.root.insertingSplit(replacing: ws.focusedPaneId, axis: axis, newSibling: newLeaf)
        ws.focusedPaneId = newLeafId
        activeWorkspace = ws
        schedulePersist()
        return newLeafId
    }

    /// Pop a pane out of its current split into a new tab.
    /// If it's already the only pane, this is a no-op.
    func popOutPane(id: UUID) {
        guard var ws = activeWorkspace else { return }
        guard let leaf = ws.root.findLeaf(id: id) else { return }
        // Already the only pane — nothing to pop out
        if case .leaf = ws.root { return }

        // Remove from current workspace
        let (newRoot, siblingId) = ws.root.removingLeaf(id: id)
        if let newRoot {
            ws.root = newRoot
            if ws.focusedPaneId == id {
                ws.focusedPaneId = siblingId ?? newRoot.firstLeaf?.id ?? ws.focusedPaneId
            }
            activeWorkspace = ws
        }

        // Create new workspace with the popped-out pane
        let newWs = Workspace(
            id: UUID(),
            name: "New Tab",
            icon: nil,
            root: .leaf(leaf),
            focusedPaneId: leaf.id,
            createdAt: Date()
        )
        workspaces.append(newWs)
        activeWorkspaceIndex = workspaces.count - 1
        schedulePersist()
    }

    /// Close a pane by its ID.
    func closePane(id: UUID) {
        closePane(id: id, inWorkspaceAt: activeWorkspaceIndex)
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
    func updatePaneOpenFile(paneId: UUID, tabId: UUID? = nil, transform: (inout OpenFile) -> Void) {
        guard var ws = activeWorkspace else { return }
        guard let leaf = ws.root.findLeaf(id: paneId) else { return }
        let targetTabId = tabId ?? leaf.activeTabID
        guard
              let content = leaf.tabs.first(where: { $0.id == targetTabId }),
              case .document(var file) = content else { return }
        transform(&file)
        ws.root = ws.root.updatingTabContent(tabId: targetTabId) { _ in
            .document(openFile: file)
        }
        activeWorkspace = ws
    }

    /// Swap the content of two panes by their IDs.
    func swapPaneContents(paneA: UUID, paneB: UUID) {
        guard var ws = activeWorkspace else { return }
        guard let leafA = ws.root.findLeaf(id: paneA),
              let leafB = ws.root.findLeaf(id: paneB) else { return }
        let contentA = leafA.activeContent
        let contentB = leafB.activeContent
        ws.root = ws.root.updatingLeafContent(leafId: paneA, content: contentB)
        ws.root = ws.root.updatingLeafContent(leafId: paneB, content: contentA)
        activeWorkspace = ws
        schedulePersist()
    }

    // MARK: - Queries

    /// All document-type leaves across all workspaces.
    func allDocumentLeaves() -> [(workspaceIndex: Int, leaf: PaneNode.Leaf, file: OpenFile)] {
        var results: [(Int, PaneNode.Leaf, OpenFile)] = []
        for (i, ws) in workspaces.enumerated() {
            for leaf in ws.allLeaves {
                for content in leaf.tabs {
                    guard case .document(let file) = content else { continue }
                    results.append((i, leaf, file))
                }
            }
        }
        return results
    }

    func leaf(containingTabId tabId: UUID) -> PaneNode.Leaf? {
        for workspace in workspaces {
            if let leaf = workspace.root.findLeaf(containingTabId: tabId) {
                return leaf
            }
        }
        return nil
    }

    func leaf(id paneId: UUID) -> PaneNode.Leaf? {
        for workspace in workspaces {
            if let leaf = workspace.root.findLeaf(id: paneId) {
                return leaf
            }
        }
        return nil
    }

    func openFile(tabId: UUID) -> OpenFile? {
        leaf(containingTabId: tabId)?.tabs.compactMap(\.openFile).first { $0.id == tabId }
    }

    func updateOpenFile(tabId: UUID, persist: Bool = true, transform: (inout OpenFile) -> Void) {
        guard let workspaceIndex = workspaces.firstIndex(where: { $0.root.findLeaf(containingTabId: tabId) != nil }) else { return }
        var workspace = workspaces[workspaceIndex]
        guard let leaf = workspace.root.findLeaf(containingTabId: tabId),
              let content = leaf.tabs.first(where: { $0.id == tabId }),
              case .document(var file) = content else { return }
        transform(&file)
        workspace.root = workspace.root.updatingTabContent(tabId: tabId) { _ in
            .document(openFile: file)
        }
        workspaces[workspaceIndex] = workspace
        if workspaceIndex == activeWorkspaceIndex {
            activeWorkspace = workspace
        }
        if persist {
            schedulePersist()
        }
    }

    @discardableResult
    func addPaneTab(to paneId: UUID, content: PaneContent, select: Bool = true) -> UUID? {
        guard var ws = activeWorkspace,
              let leaf = ws.root.findLeaf(id: paneId) else { return nil }

        let tabId = content.id
        var updatedLeaf = leaf
        guard updatedLeaf.appendTab(content, select: select) else { return nil }
        ws.root = ws.root.updatingLeaf(id: paneId) { _ in updatedLeaf }
        if select {
            ws.focusedPaneId = paneId
        }
        activeWorkspace = ws
        schedulePersist()
        return tabId
    }

    @discardableResult
    func closePaneTab(paneId: UUID, tabId: UUID) -> PaneContent? {
        closePaneTab(paneId: paneId, tabId: tabId, inWorkspaceAt: activeWorkspaceIndex)
    }

    @discardableResult
    func closeFocusedPaneTab() -> PaneContent? {
        guard let ws = activeWorkspace,
              let leaf = ws.focusedLeaf else { return nil }
        return closePaneTab(paneId: leaf.id, tabId: leaf.activeTabID)
    }

    func selectPaneTab(paneId: UUID, tabId: UUID) {
        guard var ws = activeWorkspace else { return }
        ws.root = ws.root.updatingLeaf(id: paneId) { leaf in
            var updatedLeaf = leaf
            updatedLeaf.selectTab(id: tabId)
            return updatedLeaf
        }
        ws.focusedPaneId = paneId
        activeWorkspace = ws
    }

    func cyclePaneTabs(in paneId: UUID, step: Int) {
        guard step != 0,
              var ws = activeWorkspace,
              let leaf = ws.root.findLeaf(id: paneId),
              leaf.tabs.count > 1 else { return }

        var updatedLeaf = leaf
        let nextIndex = (leaf.selectedTabIndex + step + leaf.tabs.count) % leaf.tabs.count
        updatedLeaf.selectTab(at: nextIndex)
        ws.root = ws.root.updatingLeaf(id: paneId) { _ in updatedLeaf }
        ws.focusedPaneId = paneId
        activeWorkspace = ws
    }

    func movePaneTab(paneId: UUID, from sourceIndex: Int, to destinationIndex: Int) {
        guard var ws = activeWorkspace,
              let leaf = ws.root.findLeaf(id: paneId) else { return }
        var updatedLeaf = leaf
        updatedLeaf.moveTab(from: sourceIndex, to: destinationIndex)
        ws.root = ws.root.updatingLeaf(id: paneId) { _ in updatedLeaf }
        activeWorkspace = ws
        schedulePersist()
    }

    func setPaneTabs(paneId: UUID, tabs: [PaneContent], selectedTabID: UUID? = nil) {
        let normalizedTabs = tabs.isEmpty ? [PaneContent.browserDocument(id: paneId)] : tabs
        let selectedIndex = selectedTabID.flatMap { tabID in
            normalizedTabs.firstIndex { $0.id == tabID }
        } ?? 0

        if let workspaceIndex = workspaces.firstIndex(where: { $0.root.findLeaf(id: paneId) != nil }) {
            var workspace = workspaces[workspaceIndex]
            let replacement = PaneNode.Leaf(id: paneId, tabs: normalizedTabs, selectedTabIndex: selectedIndex)
            workspace.root = workspace.root.updatingLeaf(id: paneId) { _ in replacement }
            workspaces[workspaceIndex] = workspace
            if workspaceIndex == activeWorkspaceIndex {
                activeWorkspace = workspace
            }
            schedulePersist()
            return
        }

        let workspace = Workspace(
            id: UUID(),
            name: "New Tab",
            icon: nil,
            root: .leaf(.init(id: paneId, tabs: normalizedTabs, selectedTabIndex: selectedIndex)),
            focusedPaneId: paneId,
            createdAt: Date()
        )
        workspaces.append(workspace)
        activeWorkspaceIndex = workspaces.count - 1
        schedulePersist()
    }

    @discardableResult
    func closeTab(tabId: UUID, closePaneWhenLastTab: Bool = false) -> PaneContent? {
        guard let workspaceIndex = workspaces.firstIndex(where: { $0.root.findLeaf(containingTabId: tabId) != nil }),
              let leaf = workspaces[workspaceIndex].root.findLeaf(containingTabId: tabId) else { return nil }

        if leaf.tabs.count > 1 {
            return closePaneTab(paneId: leaf.id, tabId: tabId, inWorkspaceAt: workspaceIndex)
        }

        guard closePaneWhenLastTab else { return nil }
        let removed = leaf.activeContent
        closePane(id: leaf.id, inWorkspaceAt: workspaceIndex)
        return removed
    }


    // MARK: - Persistence

    @discardableResult
    private func closePaneTab(paneId: UUID, tabId: UUID, inWorkspaceAt workspaceIndex: Int) -> PaneContent? {
        guard workspaceIndex >= 0, workspaceIndex < workspaces.count else { return nil }

        var workspace = workspaces[workspaceIndex]
        guard let leaf = workspace.root.findLeaf(id: paneId),
              leaf.tabs.count > 1 else { return nil }

        var updatedLeaf = leaf
        let removed = updatedLeaf.removeTab(id: tabId)
        guard removed != nil else { return nil }

        workspace.root = workspace.root.updatingLeaf(id: paneId) { _ in updatedLeaf }
        workspaces[workspaceIndex] = workspace
        if workspaceIndex == activeWorkspaceIndex {
            activeWorkspace = workspace
        }
        schedulePersist()
        return removed
    }

    private func closePane(id: UUID, inWorkspaceAt workspaceIndex: Int) {
        guard workspaceIndex >= 0, workspaceIndex < workspaces.count else { return }

        var workspace = workspaces[workspaceIndex]

        if case .leaf(let leaf) = workspace.root, leaf.id == id {
            closeWorkspace(at: workspaceIndex)
            return
        }

        let (newRoot, siblingId) = workspace.root.removingLeaf(id: id)
        guard let newRoot else { return }

        workspace.root = newRoot
        if workspace.focusedPaneId == id {
            workspace.focusedPaneId = siblingId ?? newRoot.firstLeaf?.id ?? workspace.focusedPaneId
        }
        workspaces[workspaceIndex] = workspace
        if workspaceIndex == activeWorkspaceIndex {
            activeWorkspace = workspace
        }
        schedulePersist()
    }

    private static var layoutFileURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport
            .appendingPathComponent("Dahso/WorkspaceLayouts", isDirectory: true)
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
        guard layoutPersistenceEnabled else { return }
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
            lastSavedAt = Date()
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
