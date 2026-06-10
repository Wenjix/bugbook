import Foundation
import AppKit
import SwiftUI
import Sentry

enum CommandPaletteMode {
    case search
    case commands
    case newTab
    case splitLauncher
}

enum ViewMode {
    case editor
    case chat
    case graphView
    case calendar
}

struct MCPServerInfo: Identifiable {
    let name: String
    let command: String
    var id: String { name }
}

/// What the sidebar's contextual zone should display, derived from the selected pane type.
enum SidebarContextType: Equatable {
    case mail
    case calendar
    case workspace   // editor pages — shows file tree
    case none        // contextual zone collapses

    static func from(_ content: PaneContent) -> SidebarContextType {
        switch content {
        case .document(let file):
            if file.isMail { return .mail }
            if file.isCalendar { return .calendar }
            return .workspace
        }
    }
}

extension AppState {
    func withGoogleSettings<T>(
        _ operation: (inout AppSettings) async throws -> T
    ) async rethrows -> T {
        var updatedSettings = settings
        // Only write back when something actually changed — `settings` is `@Observable`
        // and an unconditional reassignment invalidates every view that reads any AppSettings
        // property on every Google API call.
        defer { if updatedSettings != settings { settings = updatedSettings } }
        return try await operation(&updatedSettings)
    }

    func withValidGoogleToken<T>(
        for email: String,
        scopes: [String],
        _ body: (GoogleOAuthToken) async throws -> T
    ) async throws -> T {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        return try await withGoogleSettings { settings in
            let token = try await GoogleAuthService.validToken(
                using: &settings,
                forAccount: trimmedEmail.isEmpty ? nil : trimmedEmail,
                requiredScopes: scopes
            )
            return try await body(token)
        }
    }
}

@MainActor
// swiftlint:disable:next type_body_length
@Observable class AppState {
    private static let dismissedLegacyWorkspacesDefaultsKey = "dismissedLegacyWorkspaceKeys"

    var openTabs: [OpenFile] = []
    var activeTabIndex: Int = 0

    // Unified sidebar state
    var sidebarVisible: Bool = true
    var sidebarWidth: CGFloat = 200
    /// Contextual zone type — follows the focused pane, always.
    var sidebarContextType: SidebarContextType = .workspace
    var workspacePath: String?
    var fileTree: [FileEntry] = []
    var sidebarReferences: [FileEntry] = []
    var favorites: [FileEntry] = []
    var agentSkills: [FileEntry] = []
    var settings: AppSettings = .default
    var commandPaletteOpen: Bool = false
    var commandPaletteMode: CommandPaletteMode = .search
    var showSettings: Bool = false
    var selectedSettingsTab: String = "general"
    var aiSidePanelOpen: Bool = false
    var aiInitialPrompt: String?
    var aiSelectionContext: String?
    var aiReferencedItems: [AiContextItem] = []
    var currentView: ViewMode = .editor
    var movePagePath: String?  // non-nil triggers move page picker
    var mcpServers: [MCPServerInfo] = []

    var isRecording: Bool = false
    var recordingBlockId: UUID?
    /// Active meeting page recording session (independent of pane).
    var activeMeetingSession: ActiveMeetingSession?
    /// If set, the next meeting page loaded at this path should auto-start recording.
    var pendingAutoRecordPath: String?
    var flashcardReviewOpen: Bool = false
    var showShortcutOverlay: Bool = false
    var dismissedLegacyKeys: Set<String> = []
    var legacyWorkspaces: [FileSystemService.LegacyWorkspace] = []
    var migratingLegacyWorkspaceKeys: Set<String> = []
    var legacyWorkspaceErrorMessages: [String: String] = [:]
    @ObservationIgnored private var loadedAiThreadStore: AiThreadStore?
    var aiThreadStore: AiThreadStore {
        if let loadedAiThreadStore { return loadedAiThreadStore }
        // Process singleton — every window shares one in-memory thread list
        // and one write queue; still created only on first chat use.
        let store = AiThreadStore.shared
        loadedAiThreadStore = store
        return store
    }

    /// Flush write-behind AI thread persistence to disk without forcing the
    /// store into existence when it was never used this session.
    func flushPendingAiThreadWrites() {
        loadedAiThreadStore?.flushPendingWrites()
    }

    @ObservationIgnored private let userDefaults: UserDefaults

    var activeTab: OpenFile? {
        guard activeTabIndex >= 0, activeTabIndex < openTabs.count else { return nil }
        return openTabs[activeTabIndex]
    }

    var legacyWorkspacesNeedingAttention: [FileSystemService.LegacyWorkspace] {
        legacyWorkspaces.filter { !dismissedLegacyKeys.contains($0.defaultsKey) }
    }

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        self.dismissedLegacyKeys = Set(
            userDefaults.stringArray(forKey: Self.dismissedLegacyWorkspacesDefaultsKey) ?? []
        )
    }

    func refreshLegacyWorkspaces(using fileSystem: FileSystemService) {
        guard BugbookFeatureGate.shouldScanLegacyWorkspaces else {
            updateLegacyWorkspaces([])
            return
        }
        let detectedWorkspaces = fileSystem.refreshLegacyWorkspaces()
        updateLegacyWorkspaces(detectedWorkspaces)
    }

    func refreshLegacyWorkspacesInBackground(using fileSystem: FileSystemService) async {
        guard BugbookFeatureGate.shouldScanLegacyWorkspaces else {
            updateLegacyWorkspaces([])
            return
        }
        let detectedWorkspaces = await fileSystem.refreshLegacyWorkspacesInBackground()
        updateLegacyWorkspaces(detectedWorkspaces)
    }

    private func updateLegacyWorkspaces(_ detectedWorkspaces: [FileSystemService.LegacyWorkspace]) {
        legacyWorkspaces = detectedWorkspaces
        legacyWorkspaceErrorMessages = legacyWorkspaceErrorMessages.filter { key, _ in
            legacyWorkspaces.contains { $0.defaultsKey == key }
        }
    }

    func dismissLegacyWorkspace(_ legacyWorkspace: FileSystemService.LegacyWorkspace) {
        dismissedLegacyKeys.insert(legacyWorkspace.defaultsKey)
        legacyWorkspaceErrorMessages.removeValue(forKey: legacyWorkspace.defaultsKey)
        persistDismissedLegacyKeys()
    }

    func revealLegacyWorkspace(_ legacyWorkspace: FileSystemService.LegacyWorkspace) {
        NSWorkspace.shared.activateFileViewerSelecting([legacyWorkspace.path])
    }

    func isMigratingLegacyWorkspace(_ legacyWorkspace: FileSystemService.LegacyWorkspace) -> Bool {
        migratingLegacyWorkspaceKeys.contains(legacyWorkspace.defaultsKey)
    }

    func legacyWorkspaceErrorMessage(
        for legacyWorkspace: FileSystemService.LegacyWorkspace
    ) -> String? {
        legacyWorkspaceErrorMessages[legacyWorkspace.defaultsKey]
    }

    func migrateLegacyWorkspace(
        _ legacyWorkspace: FileSystemService.LegacyWorkspace,
        using fileSystem: FileSystemService
    ) async {
        guard let workspacePath, !workspacePath.isEmpty else {
            legacyWorkspaceErrorMessages[legacyWorkspace.defaultsKey] = "The active workspace is unavailable."
            return
        }

        legacyWorkspaceErrorMessages.removeValue(forKey: legacyWorkspace.defaultsKey)
        migratingLegacyWorkspaceKeys.insert(legacyWorkspace.defaultsKey)
        defer { migratingLegacyWorkspaceKeys.remove(legacyWorkspace.defaultsKey) }

        do {
            try await fileSystem.migrateLegacyWorkspace(
                legacyWorkspace,
                into: URL(fileURLWithPath: workspacePath, isDirectory: true)
            )
            dismissLegacyWorkspace(legacyWorkspace)
            refreshLegacyWorkspaces(using: fileSystem)
        } catch {
            legacyWorkspaceErrorMessages[legacyWorkspace.defaultsKey] = error.localizedDescription
        }
    }

    /// Migrate every detected legacy workspace, sequentially. Errors are surfaced via
    /// `aggregatedLegacyMigrationError`; sources that succeed get dismissed individually
    /// so the banner can shrink to only those that still need attention.
    func migrateAllLegacyWorkspaces(using fileSystem: FileSystemService) async {
        let workspaces = legacyWorkspacesNeedingAttention
        guard !workspaces.isEmpty else { return }
        for ws in workspaces {
            await migrateLegacyWorkspace(ws, using: fileSystem)
        }
    }

    func dismissAllLegacyWorkspaces() {
        for ws in legacyWorkspacesNeedingAttention {
            dismissLegacyWorkspace(ws)
        }
    }

    var isMigratingAnyLegacyWorkspace: Bool {
        !migratingLegacyWorkspaceKeys.isEmpty
    }

    var aggregatedLegacyMigrationError: String? {
        let errors = legacyWorkspacesNeedingAttention
            .compactMap { legacyWorkspaceErrorMessages[$0.defaultsKey] }
        guard !errors.isEmpty else { return nil }
        return errors.joined(separator: " · ")
    }

    private func persistDismissedLegacyKeys() {
        userDefaults.set(
            Array(dismissedLegacyKeys).sorted(),
            forKey: Self.dismissedLegacyWorkspacesDefaultsKey
        )
    }

    private func cleanDisplayName(_ name: String) -> String {
        name.hasSuffix(".md") ? String(name.dropLast(3)) : name
    }

    private func makeTab(for entry: FileEntry, id: UUID = UUID()) -> OpenFile {
        let history = entry.path.isEmpty ? [] : [entry.path]
        let historyIndex = history.isEmpty ? -1 : 0
        return OpenFile(
            id: id,
            path: entry.path,
            content: "",
            isDirty: false,
            isEmptyTab: entry.path.isEmpty,
            kind: entry.kind,
            displayName: cleanDisplayName(entry.name),
            openerPagePath: nil,
            icon: entry.icon,
            navigationHistory: history,
            navigationHistoryIndex: historyIndex
        )
    }

    private func reidentified(_ tab: OpenFile, as id: UUID) -> OpenFile {
        OpenFile(
            id: id,
            path: tab.path,
            content: tab.content,
            isDirty: tab.isDirty,
            isEmptyTab: tab.isEmptyTab,
            kind: tab.kind,
            displayName: tab.displayName,
            openerPagePath: tab.openerPagePath,
            icon: tab.icon,
            navigationHistory: tab.navigationHistory,
            navigationHistoryIndex: tab.navigationHistoryIndex
        )
    }

    private func applyingEntry(_ entry: FileEntry, to tab: OpenFile, pushHistory: Bool) -> OpenFile {
        var updatedTab = tab
        updatedTab.path = entry.path
        updatedTab.content = ""
        updatedTab.isDirty = false
        updatedTab.isEmptyTab = entry.path.isEmpty
        updatedTab.kind = entry.kind
        updatedTab.displayName = cleanDisplayName(entry.name)
        updatedTab.icon = entry.icon
        updatedTab.openerPagePath = nil

        if pushHistory {
            pushHistoryPath(entry.path, into: &updatedTab)
        } else {
            syncHistoryCurrentPath(entry.path, into: &updatedTab)
        }

        return updatedTab
    }

    func openFile(_ entry: FileEntry) {
        if let existingIndex = openTabs.firstIndex(where: { $0.path == entry.path }) {
            activeTabIndex = existingIndex
            return
        }
        let tab = makeTab(for: entry)
        openTabs.append(tab)
        activeTabIndex = openTabs.count - 1
        let crumb = Breadcrumb(level: .info, category: "navigation.open")
        crumb.message = entry.name
        SentryBreadcrumbs.add(crumb)
    }

    /// Pane-aware replacement path used by the unified pane/tab workspace model.
    /// Returns true when caller should not load content because an existing pane tab
    /// was focused, false when the active pane tab was replaced and needs loading.
    @discardableResult
    func openFileReplacingCurrentTab(
        _ entry: FileEntry,
        workspaceManager: WorkspaceManager,
        paneId: UUID,
        pushHistory: Bool = true,
        preferExistingTab: Bool = true
    ) -> Bool {
        if preferExistingTab,
           let workspace = workspaceManager.activeWorkspace {
            for leaf in workspace.allLeaves {
                if let existingFile = leaf.tabs.compactMap(\.openFile).first(where: { $0.path == entry.path }) {
                    workspaceManager.selectPaneTab(paneId: leaf.id, tabId: existingFile.id)
                    return true
                }
            }
        }

        guard let leaf = workspaceManager.leaf(id: paneId) else { return true }

        let tabId = leaf.activeTabID
        let baseTab = leaf.activeOpenFile.map { reidentified($0, as: tabId) } ?? makeTab(for: entry, id: tabId)
        let updatedTab = applyingEntry(entry, to: baseTab, pushHistory: pushHistory)

        workspaceManager.updatePaneContent(
            paneId: paneId,
            content: .document(openFile: updatedTab)
        )
        workspaceManager.setFocusedPane(id: paneId)
        return false
    }

    // MARK: - Per-Tab Navigation History

    var canGoBackInActiveTab: Bool {
        guard activeTabIndex >= 0, activeTabIndex < openTabs.count else { return false }
        return openTabs[activeTabIndex].navigationHistoryIndex > 0
    }

    var canGoForwardInActiveTab: Bool {
        guard activeTabIndex >= 0, activeTabIndex < openTabs.count else { return false }
        let tab = openTabs[activeTabIndex]
        return tab.navigationHistoryIndex >= 0 && tab.navigationHistoryIndex < tab.navigationHistory.count - 1
    }

    func goBackInActiveTab() -> FileEntry? {
        stepHistory(inTabAt: activeTabIndex, delta: -1)
    }

    func goForwardInActiveTab() -> FileEntry? {
        stepHistory(inTabAt: activeTabIndex, delta: 1)
    }

    func updateNavigationPath(for tabId: UUID, from oldPath: String, to newPath: String) {
        guard let idx = openTabs.firstIndex(where: { $0.id == tabId }) else { return }
        var tab = openTabs[idx]
        if tab.path == oldPath {
            tab.path = newPath
        }
        for i in tab.navigationHistory.indices where tab.navigationHistory[i] == oldPath {
            tab.navigationHistory[i] = newPath
        }
        openTabs[idx] = tab
    }

    private func applyEntry(_ entry: FileEntry, toTabAt tabIndex: Int, pushHistory: Bool) {
        guard tabIndex >= 0, tabIndex < openTabs.count else { return }
        openTabs[tabIndex] = applyingEntry(entry, to: openTabs[tabIndex], pushHistory: pushHistory)
    }

    private func pushHistoryPath(_ path: String, into tab: inout OpenFile) {
        guard !path.isEmpty else {
            tab.navigationHistory = []
            tab.navigationHistoryIndex = -1
            return
        }

        if tab.navigationHistoryIndex >= 0,
           tab.navigationHistoryIndex < tab.navigationHistory.count,
           tab.navigationHistory[tab.navigationHistoryIndex] == path {
            return
        }

        if tab.navigationHistoryIndex < tab.navigationHistory.count - 1,
           tab.navigationHistoryIndex >= 0 {
            tab.navigationHistory.removeSubrange((tab.navigationHistoryIndex + 1)..<tab.navigationHistory.count)
        }

        tab.navigationHistory.append(path)
        tab.navigationHistoryIndex = tab.navigationHistory.count - 1
    }

    private func syncHistoryCurrentPath(_ path: String, into tab: inout OpenFile) {
        guard !path.isEmpty else {
            tab.navigationHistory = []
            tab.navigationHistoryIndex = -1
            return
        }

        if tab.navigationHistory.isEmpty {
            tab.navigationHistory = [path]
            tab.navigationHistoryIndex = 0
            return
        }

        if tab.navigationHistoryIndex < 0 || tab.navigationHistoryIndex >= tab.navigationHistory.count {
            tab.navigationHistoryIndex = tab.navigationHistory.count - 1
        }
        tab.navigationHistory[tab.navigationHistoryIndex] = path
    }

    private func stepHistory(inTabAt tabIndex: Int, delta: Int) -> FileEntry? {
        guard tabIndex >= 0, tabIndex < openTabs.count else { return nil }
        var tab = openTabs[tabIndex]
        let nextIndex = tab.navigationHistoryIndex + delta
        guard nextIndex >= 0, nextIndex < tab.navigationHistory.count else { return nil }

        tab.navigationHistoryIndex = nextIndex
        let path = tab.navigationHistory[nextIndex]
        let entry = resolveEntry(for: path)

        tab.path = entry.path
        tab.content = ""
        tab.isDirty = false
        tab.isEmptyTab = false
        tab.kind = entry.kind
        tab.displayName = cleanDisplayName(entry.name)
        tab.icon = entry.icon
        openTabs[tabIndex] = tab
        return entry
    }

    private func resolveEntry(for path: String) -> FileEntry {
        switch path {
        case "bugbook://mail":
            return FileEntry(id: path, name: "Mail", path: path, isDirectory: false, kind: .mail, icon: "envelope")
        case "bugbook://calendar":
            return FileEntry(id: path, name: "Calendar", path: path, isDirectory: false, kind: .calendar, icon: "calendar.badge.clock")
        case "bugbook://meetings":
            return FileEntry(id: path, name: "Meetings", path: path, isDirectory: false, kind: .meetings, icon: "person.2")
        case "bugbook://graph":
            return FileEntry(
                id: path,
                name: "Graph View",
                path: path,
                isDirectory: false,
                kind: .graphView,
                icon: "sf:point.3.connected.trianglepath.dotted"
            )
        case "bugbook://gateway":
            return FileEntry(id: path, name: "Home", path: path, isDirectory: false, kind: .gateway, icon: "house")
        default:
            break
        }

        if let row = DatabaseRowNavigationPath.parse(path) {
            return FileEntry(
                id: path,
                name: "Row",
                path: path,
                isDirectory: false,
                kind: .databaseRow(dbPath: row.dbPath, rowId: row.rowId)
            )
        }

        if let known = findEntry(byPath: path, in: fileTree) {
            return known
        }
        let schemaPath = (path as NSString).appendingPathComponent("_schema.json")
        let isDatabase = FileManager.default.fileExists(atPath: schemaPath)
        let kind: TabKind = isDatabase ? .database : .page
        return FileEntry(
            id: path,
            name: (path as NSString).lastPathComponent,
            path: path,
            isDirectory: isDatabase,
            kind: kind
        )
    }

    private func findEntry(byPath path: String, in entries: [FileEntry]) -> FileEntry? {
        for entry in entries {
            if entry.path == path {
                return entry
            }
            if let children = entry.children,
               let found = findEntry(byPath: path, in: children) {
                return found
            }
        }
        return nil
    }

    /// Reorder a tab from one index to another. Keeps activeTabIndex pointing at the same tab.
    func reorderTab(from sourceIndex: Int, to destinationIndex: Int) {
        guard sourceIndex != destinationIndex,
              sourceIndex >= 0, sourceIndex < openTabs.count,
              destinationIndex >= 0, destinationIndex <= openTabs.count else { return }

        let activeTabId = activeTab?.id
        let tab = openTabs.remove(at: sourceIndex)
        let adjustedDestination = destinationIndex > sourceIndex ? destinationIndex - 1 : destinationIndex
        openTabs.insert(tab, at: adjustedDestination)

        // Restore activeTabIndex to follow the previously active tab
        if let id = activeTabId, let newIndex = openTabs.firstIndex(where: { $0.id == id }) {
            activeTabIndex = newIndex
        }
    }

    /// Close any tabs that point to the given path (used when a file is deleted).
    /// Opens an empty tab if this would close the last tab (instead of quitting).
    func closeTabsForPath(_ path: String) {
        let matchingCount = openTabs.count(where: { $0.path == path })
        if matchingCount >= openTabs.count {
            // All tabs point to this path — replace with empty tab instead of quitting
            openTabs = []
            newEmptyTab()
            return
        }
        // Iterate in reverse so removal indices stay valid
        for i in stride(from: openTabs.count - 1, through: 0, by: -1) where openTabs[i].path == path {
            closeTab(at: i)
        }
    }

    func closeTab(at index: Int) {
        guard index >= 0, index < openTabs.count else { return }

        // Closing the last tab quits the app
        if openTabs.count == 1 {
            NSApplication.shared.terminate(nil)
            return
        }

        let wasActive = index == activeTabIndex
        openTabs.remove(at: index)
        if wasActive {
            // Select same index position, or last tab
            activeTabIndex = min(index, openTabs.count - 1)
        } else if activeTabIndex > index {
            activeTabIndex -= 1
        }
    }

    func openNotesChat() {
        guard BugbookFeatureGate.shouldExposeAgentSurfaces else {
            hideAgentSurfacesForCurrentMode()
            return
        }
        showSettings = false
        if currentView == .chat {
            currentView = .editor
        }
        aiSidePanelOpen = true
    }

    func closeNotesChat() {
        aiSidePanelOpen = false
        if currentView == .chat {
            currentView = .editor
        }
    }

    func openGraphView() {
        guard BugbookFeatureGate.allowsViewMode(.graphView) else {
            aiSidePanelOpen = false
            if currentView == .graphView {
                currentView = .editor
            }
            return
        }
        showSettings = false
        aiSidePanelOpen = false
        currentView = .graphView
    }

    func openCalendar() {
        guard BugbookFeatureGate.allowsTabKind(.calendar) else { return }
        showSettings = false
        currentView = .editor

        // Open calendar as a tab (reuse existing if open)
        let calendarPath = "bugbook://calendar"
        if let existingIndex = openTabs.firstIndex(where: { $0.isCalendar }) {
            activeTabIndex = existingIndex
            return
        }
        let tab = OpenFile(
            id: UUID(),
            path: calendarPath,
            content: "",
            isDirty: false,
            isEmptyTab: false,
            kind: .calendar,
            displayName: "Calendar",
            icon: "calendar.badge.clock"
        )
        openTabs.append(tab)
        activeTabIndex = openTabs.count - 1
    }

    func openMeetings() {
        guard BugbookFeatureGate.allowsTabKind(.meetings) else { return }
        showSettings = false
        currentView = .editor

        // Open meetings as a tab (reuse existing if open)
        let meetingsPath = "bugbook://meetings"
        if let existingIndex = openTabs.firstIndex(where: { $0.isMeetings }) {
            activeTabIndex = existingIndex
            return
        }
        let tab = OpenFile(
            id: UUID(),
            path: meetingsPath,
            content: "",
            isDirty: false,
            isEmptyTab: false,
            kind: .meetings,
            displayName: "Meetings",
            icon: "person.2"
        )
        openTabs.append(tab)
        activeTabIndex = openTabs.count - 1
    }

    func toggleAiPanel(prompt: String? = nil) {
        guard BugbookFeatureGate.shouldExposeAgentSurfaces else {
            hideAgentSurfacesForCurrentMode()
            return
        }
        if aiSidePanelOpen {
            aiSidePanelOpen = false
            return
        }
        openAiPanel(prompt: prompt)
    }

    func openAiPanel(prompt: String? = nil, referencedItems: [AiContextItem] = []) {
        guard BugbookFeatureGate.shouldExposeAgentSurfaces else {
            hideAgentSurfacesForCurrentMode()
            return
        }
        aiInitialPrompt = prompt
        if !referencedItems.isEmpty {
            aiReferencedItems.append(contentsOf: referencedItems)
        }
        showSettings = false
        if currentView == .chat {
            currentView = .editor
        }
        aiSidePanelOpen = true
    }

    private func hideAgentSurfacesForCurrentMode() {
        aiSidePanelOpen = false
        aiInitialPrompt = nil
        aiSelectionContext = nil
        aiReferencedItems.removeAll()
        agentSkills = []
        mcpServers = []
        if currentView == .chat {
            currentView = .editor
        }
    }

    func newEmptyTab() {
        let tab = OpenFile(
            id: UUID(),
            path: "",
            content: "",
            isDirty: false,
            isEmptyTab: true
        )
        openTabs.append(tab)
        activeTabIndex = openTabs.count - 1
    }

    /// Update the icon for a file entry in the tree so the sidebar reflects the change immediately.
    func updateFileTreeIcon(for path: String, icon: String?) {
        func update(entries: inout [FileEntry]) -> Bool {
            for i in entries.indices {
                if entries[i].path == path {
                    entries[i].icon = icon
                    return true
                }
                if var children = entries[i].children {
                    if update(entries: &children) {
                        entries[i].children = children
                        return true
                    }
                }
            }
            return false
        }
        if update(entries: &fileTree) {
            // Also update sidebar references that mirror this path
            for i in sidebarReferences.indices where sidebarReferences[i].path == path {
                sidebarReferences[i].icon = icon
            }
        }
    }
}
