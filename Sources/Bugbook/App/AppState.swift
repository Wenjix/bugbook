import Foundation
import SwiftUI
import Sentry

enum CommandPaletteMode {
    case search
    case commands
    case newTab
}

enum ViewMode {
    case editor
    case chat
    case graphView
}

@MainActor
@Observable class AppState {
    var openTabs: [OpenFile] = []
    var activeTabIndex: Int = 0
    var sidebarOpen: Bool = true
    var workspacePath: String?
    var fileTree: [FileEntry] = []
    var settings: AppSettings = .default
    var commandPaletteOpen: Bool = false
    var commandPaletteMode: CommandPaletteMode = .search
    var showSettings: Bool = false
    var selectedSettingsTab: String = "general"
    var aiSidePanelOpen: Bool = false
    var aiInitialPrompt: String?
    var currentView: ViewMode = .editor
    var movePagePath: String?  // non-nil triggers move page picker

    var activeTab: OpenFile? {
        guard activeTabIndex >= 0, activeTabIndex < openTabs.count else { return nil }
        return openTabs[activeTabIndex]
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
        SentrySDK.addBreadcrumb(crumb)
    }

    /// Replace the active tab's content with the given file. If the file is already open, switch to it instead.
    /// Returns true if an existing tab was switched to (no load needed), false if the tab was replaced (caller should load content).
    @discardableResult
    func openFileReplacingCurrentTab(
        _ entry: FileEntry,
        pushHistory: Bool = true,
        preferExistingTab: Bool = true
    ) -> Bool {
        // If already open in another tab, just switch
        if preferExistingTab, let existingIndex = openTabs.firstIndex(where: { $0.path == entry.path }) {
            activeTabIndex = existingIndex
            return true
        }

        // Replace the active tab
        guard activeTabIndex >= 0, activeTabIndex < openTabs.count else {
            // No active tab — fall back to opening a new one
            openFile(entry)
            return false
        }

        applyEntry(entry, toTabAt: activeTabIndex, pushHistory: pushHistory)
        return false
    }

    /// Always open a file in a new tab. If already open, switch to it instead.
    func openFileInNewTab(_ entry: FileEntry) {
        if let existingIndex = openTabs.firstIndex(where: { $0.path == entry.path }) {
            activeTabIndex = existingIndex
            return
        }
        let tab = makeTab(for: entry)
        openTabs.append(tab)
        activeTabIndex = openTabs.count - 1
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
        var tab = openTabs[tabIndex]
        tab.path = entry.path
        tab.content = ""
        tab.isDirty = false
        tab.isEmptyTab = entry.path.isEmpty
        tab.kind = entry.kind
        tab.displayName = cleanDisplayName(entry.name)
        tab.icon = entry.icon
        tab.openerPagePath = nil

        if pushHistory {
            pushHistoryPath(entry.path, into: &tab)
        } else {
            syncHistoryCurrentPath(entry.path, into: &tab)
        }

        openTabs[tabIndex] = tab
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
        let canvasPath = (path as NSString).appendingPathComponent("_canvas.json")
        let isCanvas = FileManager.default.fileExists(atPath: canvasPath)
        let kind: TabKind = isDatabase ? .database : isCanvas ? .canvas : .page
        return FileEntry(
            id: path,
            name: (path as NSString).lastPathComponent,
            path: path,
            isDirectory: isDatabase || isCanvas,
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
        for i in stride(from: openTabs.count - 1, through: 0, by: -1) {
            if openTabs[i].path == path {
                closeTab(at: i)
            }
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
        showSettings = false
        aiSidePanelOpen = false
        currentView = .chat
    }

    func closeNotesChat() {
        currentView = .editor
    }

    func openGraphView() {
        showSettings = false
        aiSidePanelOpen = false
        currentView = .graphView
    }

    func toggleAiPanel(prompt: String? = nil) {
        if aiSidePanelOpen {
            aiSidePanelOpen = false
            return
        }
        openAiPanel(prompt: prompt)
    }

    func openAiPanel(prompt: String? = nil) {
        aiInitialPrompt = prompt
        showSettings = false
        if currentView == .chat {
            currentView = .editor
        }
        aiSidePanelOpen = true
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
}
