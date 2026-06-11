import Foundation
import os

private let log = Logger(subsystem: "com.bugbook.app", category: "WorkspaceManager")

/// Manages the top tab strip: an ordered list of workspaces (one document per
/// tab), the active tab, and layout persistence.
@MainActor
@Observable
class WorkspaceManager {
    struct ClosedTabItem: Equatable {
        let index: Int
        let content: PaneContent
        let closedAt: Date
    }

    var workspaces: [Workspace] = []
    var activeWorkspaceIndex: Int = 0
    private(set) var recentlyClosedItems: [ClosedTabItem] = []
    /// Set after each successful layout save; UI can observe this for a brief indicator.
    var lastSavedAt: Date?
    var layoutPersistenceEnabled = true

    /// Where the layout persists. Injectable so tests can round-trip against
    /// a temp file instead of the real profile.
    @ObservationIgnored private let layoutFileURL: URL
    @ObservationIgnored private var persistTask: Task<Void, Never>?

    init(layoutFileURL: URL? = nil) {
        self.layoutFileURL = layoutFileURL ?? Self.defaultLayoutFileURL
    }

    // MARK: - Active Tab

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

    /// The active tab's content.
    var activeContent: PaneContent? {
        activeWorkspace?.content
    }

    /// The active tab's document (nil if no workspace).
    var focusedOpenFile: OpenFile? {
        activeWorkspace?.openFile
    }

    /// The active tab's content identity (== the document/tab id).
    var activeTabID: UUID? {
        activeWorkspace?.content.id
    }

    /// True when the active tab holds a real restored document (not an empty
    /// placeholder) — used by launch navigation to avoid clobbering it.
    var hasRestoredDocument: Bool {
        guard let file = focusedOpenFile else { return false }
        return !file.isEmptyTab
    }

    // MARK: - Tab Lifecycle

    func addWorkspace(name: String? = nil) {
        let ws = Workspace.makeDefault(name: name ?? "Home")
        workspaces.append(ws)
        activeWorkspaceIndex = workspaces.count - 1
        schedulePersist()
    }

    func addWorkspaceWith(content: PaneContent) {
        let adjustedContent = BugbookFeatureGate.sanitizedContent(content)
        let ws = Workspace(
            id: UUID(),
            name: adjustedContent.paneItemTitle,
            icon: nil,
            content: adjustedContent,
            createdAt: Date()
        )
        workspaces.append(ws)
        activeWorkspaceIndex = workspaces.count - 1
        schedulePersist()
    }

    func closeWorkspace(at index: Int) {
        guard index >= 0, index < workspaces.count else { return }
        let removed = workspaces.remove(at: index)
        recordClosedItem(removed.content, at: index)

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
        guard index >= 0, index < workspaces.count, index != activeWorkspaceIndex else { return }
        activeWorkspaceIndex = index
        // The active tab is part of the persisted layout — without this a
        // relaunch restores a stale focused tab.
        schedulePersist()
    }

    /// Cycle the active tab forward/backward (wraps).
    func cycleWorkspace(step: Int) {
        guard workspaces.count > 1, step != 0 else { return }
        let count = workspaces.count
        activeWorkspaceIndex = ((activeWorkspaceIndex + step) % count + count) % count
        schedulePersist()
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

    // MARK: - Content Operations

    /// Replace the active tab's content.
    func updateActiveContent(_ content: PaneContent) {
        guard var ws = activeWorkspace else { return }
        ws.content = BugbookFeatureGate.sanitizedContent(content)
        activeWorkspace = ws
        schedulePersist()
    }

    /// Update the OpenFile of the tab holding `tabId` (e.g. after navigation
    /// or a dirty-flag change).
    func updateOpenFile(tabId: UUID, persist: Bool = true, transform: (inout OpenFile) -> Void) {
        guard let index = workspaceIndex(containingTabId: tabId),
              case .document(var file) = workspaces[index].content else { return }
        transform(&file)
        workspaces[index].content = .document(openFile: file)
        if persist {
            schedulePersist()
        }
    }

    func openFile(tabId: UUID) -> OpenFile? {
        guard let index = workspaceIndex(containingTabId: tabId) else { return nil }
        return workspaces[index].openFile
    }

    func workspaceIndex(containingTabId tabId: UUID) -> Int? {
        workspaces.firstIndex { $0.content.id == tabId }
    }

    /// All document tabs across the strip, in order.
    func allDocuments() -> [(workspaceIndex: Int, file: OpenFile)] {
        workspaces.enumerated().compactMap { index, workspace in
            workspace.openFile.map { (index, $0) }
        }
    }

    /// Close the tab holding `tabId`. Returns the removed content.
    @discardableResult
    func closeTab(tabId: UUID) -> PaneContent? {
        guard let index = workspaceIndex(containingTabId: tabId) else { return nil }
        let removed = workspaces[index].content
        closeWorkspace(at: index)
        return removed
    }

    /// Reopen the most recently closed tab (skipping content the current mode
    /// disallows). Returns the reopened tab's content id.
    @discardableResult
    func reopenLastClosedItem() -> UUID? {
        while !recentlyClosedItems.isEmpty {
            let item = recentlyClosedItems.removeFirst()
            guard BugbookFeatureGate.allowsPaneContent(item.content) else { continue }
            let content = contentWithUniqueID(from: item.content)
            let ws = Workspace(
                id: UUID(),
                name: content.paneItemTitle,
                icon: nil,
                content: content,
                createdAt: Date()
            )
            let index = min(max(item.index, 0), workspaces.count)
            workspaces.insert(ws, at: index)
            activeWorkspaceIndex = index
            schedulePersist()
            return content.id
        }
        return nil
    }

    private func recordClosedItem(_ content: PaneContent, at index: Int) {
        guard content.openFile?.isEmptyTab != true else { return }
        recentlyClosedItems.removeAll { $0.content.id == content.id }
        recentlyClosedItems.insert(
            ClosedTabItem(index: index, content: content, closedAt: Date()),
            at: 0
        )
        if recentlyClosedItems.count > 30 {
            recentlyClosedItems = Array(recentlyClosedItems.prefix(30))
        }
    }

    private func contentWithUniqueID(from content: PaneContent) -> PaneContent {
        let existingIDs = Set(workspaces.map { $0.content.id })
        guard existingIDs.contains(content.id) else { return content }
        return content.reidentified(as: UUID())
    }

    // MARK: - Persistence

    private static var defaultLayoutFileURL: URL {
        BugbookPaths.profileDirectory()
            .appendingPathComponent("WorkspaceLayouts", isDirectory: true)
            .appendingPathComponent("layouts.json")
    }

    private func ensureLayoutDirectory() {
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

    /// Drop external-file tabs: they are session-only and never written to the
    /// saved layout.
    private static func withoutExternalFiles(_ input: [Workspace]) -> [Workspace] {
        input.filter { !$0.isExternalFile }
    }

    private func persist() {
        ensureLayoutDirectory()
        let persistable = Self.withoutExternalFiles(workspaces)
        let layout = PersistedLayout(
            version: 2,
            activeWorkspaceIndex: min(activeWorkspaceIndex, max(persistable.count - 1, 0)),
            workspaces: persistable
        )
        do {
            let data = try JSONEncoder().encode(layout)
            try data.write(to: layoutFileURL, options: .atomic)
            lastSavedAt = Date()
        } catch {
            log.error("Failed to persist workspace layout: \(error)")
        }
    }

    /// Flush any scheduled persist immediately (tests, shutdown).
    func persistNow() {
        guard layoutPersistenceEnabled else { return }
        persistTask?.cancel()
        persist()
    }

    /// Restore from disk or create a default workspace.
    func restoreOrCreateDefault() {
        let url = layoutFileURL
        guard FileManager.default.fileExists(atPath: url.path) else {
            addWorkspace(name: "Workspace")
            return
        }
        do {
            let data = try Data(contentsOf: url)
            let layout = try Self.decodeLayout(from: data)
            // Discard external-file tabs a prior session left behind, and
            // page tabs whose file no longer exists (deleted or renamed away
            // outside the rename propagation) — those would restore as
            // silently blank tabs.
            let restored = Self.prunedMissingDocuments(
                Self.withoutExternalFiles(layout.workspaces)
            )
            guard !restored.isEmpty else {
                addWorkspace(name: "Workspace")
                return
            }
            let sanitized = sanitize(workspaces: restored)
            workspaces = sanitized.workspaces
            activeWorkspaceIndex = min(max(layout.activeWorkspaceIndex, 0), workspaces.count - 1)
            if sanitized.changed || layout.migrated || restored.count != layout.workspaces.count {
                schedulePersist()
            }
        } catch {
            log.error("Failed to restore workspace layout: \(error)")
            addWorkspace(name: "Workspace")
        }
    }

    /// Drop page tabs whose backing file is gone — a restored tab pointing at
    /// a nonexistent path renders blank with no error. Non-page content
    /// (databases, rows, built-ins, empty tabs) resolves its own state and is
    /// kept. Internal + injectable for tests.
    static func prunedMissingDocuments(
        _ input: [Workspace],
        fileManager: FileManager = .default
    ) -> [Workspace] {
        input.filter { workspace in
            guard let file = workspace.openFile,
                  file.kind == .page,
                  !file.isEmptyTab,
                  !file.path.isEmpty,
                  !file.path.hasPrefix("bugbook://") else { return true }
            return fileManager.fileExists(atPath: file.path)
        }
    }

    @discardableResult
    func sanitizeForCurrentMode() -> Bool {
        let sanitized = sanitize(workspaces: workspaces)
        guard sanitized.changed else { return false }
        workspaces = sanitized.workspaces
        activeWorkspaceIndex = min(activeWorkspaceIndex, max(workspaces.count - 1, 0))
        schedulePersist()
        return true
    }

    private func sanitize(workspaces input: [Workspace]) -> (workspaces: [Workspace], changed: Bool) {
        var changed = false
        let next = input.compactMap { workspace -> Workspace? in
            guard let sanitized = workspace.sanitizedForCurrentMode() else {
                changed = true
                return nil
            }
            return sanitized
        }
        return (next.isEmpty ? [Workspace.makeDefault(name: "Workspace")] : next, changed || next.isEmpty)
    }

    // MARK: - Layout Decoding & v1 Migration

    /// Decoded layout plus whether it came from a pre-tabs (v1) file and was
    /// migrated. Internal so raw-JSON fixture tests can exercise the seam.
    struct DecodedLayout {
        let activeWorkspaceIndex: Int
        let workspaces: [Workspace]
        let migrated: Bool
    }

    /// Decode a persisted layout. Version 2 is the current one-document-per-tab
    /// shape. Version 1 files (the old pane-tree layout: workspaces holding a
    /// recursive split tree of leaves, each leaf holding its own tab strip)
    /// flatten IN TREE ORDER into one top-level tab per document — no open
    /// document is dropped. The old active workspace's focused document becomes
    /// the active tab.
    static func decodeLayout(from data: Data) throws -> DecodedLayout {
        let decoder = JSONDecoder()
        let probe = try decoder.decode(LayoutVersionProbe.self, from: data)
        if probe.version >= 2 {
            let layout = try decoder.decode(PersistedLayout.self, from: data)
            return DecodedLayout(
                activeWorkspaceIndex: layout.activeWorkspaceIndex,
                workspaces: layout.workspaces,
                migrated: false
            )
        }
        let legacy = try decoder.decode(LegacyLayoutV1.self, from: data)
        return migrate(legacy: legacy)
    }

    private struct LayoutVersionProbe: Codable {
        let version: Int
    }

    /// Minimal decode-only model of the v1 pane-tree layout. This is the only
    /// surviving trace of the pane system — it exists solely at the persistence
    /// seam so existing layouts.json files migrate cleanly on first launch.
    private struct LegacyLayoutV1: Decodable {
        let version: Int
        var activeWorkspaceIndex: Int
        var workspaces: [LegacyWorkspaceV1]
    }

    private struct LegacyWorkspaceV1: Decodable {
        let id: UUID
        var name: String
        var icon: String?
        var root: LegacyPaneNodeV1
        var focusedPaneId: UUID
        var createdAt: Date
    }

    private indirect enum LegacyPaneNodeV1: Decodable {
        case leaf(LegacyLeafV1)
        case split(first: LegacyPaneNodeV1, second: LegacyPaneNodeV1)

        struct LegacyLeafV1: Decodable {
            let id: UUID
            var tabs: [PaneContent]
            var selectedTabIndex: Int

            private enum CodingKeys: String, CodingKey {
                case id, tabs, selectedTabIndex, content
            }

            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                id = try container.decode(UUID.self, forKey: .id)
                if let decoded = try container.decodeIfPresent([PaneContent].self, forKey: .tabs), !decoded.isEmpty {
                    tabs = decoded
                    selectedTabIndex = try container.decodeIfPresent(Int.self, forKey: .selectedTabIndex) ?? 0
                } else {
                    tabs = [try container.decode(PaneContent.self, forKey: .content)]
                    selectedTabIndex = 0
                }
                selectedTabIndex = min(max(selectedTabIndex, 0), max(tabs.count - 1, 0))
            }
        }

        private enum CodingKeys: String, CodingKey {
            case type, leaf, split
        }

        private enum SplitKeys: String, CodingKey {
            case first, second
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let type = try container.decode(String.self, forKey: .type)
            switch type {
            case "split":
                let split = try container.nestedContainer(keyedBy: SplitKeys.self, forKey: .split)
                self = .split(
                    first: try split.decode(LegacyPaneNodeV1.self, forKey: .first),
                    second: try split.decode(LegacyPaneNodeV1.self, forKey: .second)
                )
            default:
                self = .leaf(try container.decode(LegacyLeafV1.self, forKey: .leaf))
            }
        }

        /// (leaf id, tabs, selected tab id) for every leaf, depth-first.
        var leavesInTreeOrder: [(id: UUID, tabs: [PaneContent], selectedTabID: UUID?)] {
            switch self {
            case .leaf(let leaf):
                let selected = leaf.tabs.indices.contains(leaf.selectedTabIndex)
                    ? leaf.tabs[leaf.selectedTabIndex].id
                    : leaf.tabs.first?.id
                return [(leaf.id, leaf.tabs, selected)]
            case .split(let first, let second):
                return first.leavesInTreeOrder + second.leavesInTreeOrder
            }
        }
    }

    private static func migrate(legacy: LegacyLayoutV1) -> DecodedLayout {
        var flattened: [Workspace] = []
        var activeIndex = 0

        for (workspaceIndex, legacyWorkspace) in legacy.workspaces.enumerated() {
            let isActiveWorkspace = workspaceIndex == legacy.activeWorkspaceIndex
            let leaves = legacyWorkspace.root.leavesInTreeOrder
            let focusedLeaf = leaves.first { $0.id == legacyWorkspace.focusedPaneId }

            for leaf in leaves {
                for content in leaf.tabs {
                    let tab = Workspace(
                        id: UUID(),
                        name: content.paneItemTitle,
                        icon: nil,
                        content: content,
                        createdAt: legacyWorkspace.createdAt
                    )
                    if isActiveWorkspace,
                       leaf.id == focusedLeaf?.id ?? leaves.first?.id,
                       content.id == (focusedLeaf ?? leaves.first)?.selectedTabID {
                        activeIndex = flattened.count
                    }
                    flattened.append(tab)
                }
            }
        }

        return DecodedLayout(
            activeWorkspaceIndex: min(max(activeIndex, 0), max(flattened.count - 1, 0)),
            workspaces: flattened,
            migrated: true
        )
    }
}
