import Foundation
import SwiftUI

enum CommandPaletteMode {
    case search
    case commands
    case newTab
}

enum ViewMode {
    case editor
    case chat
}

@MainActor
class AppState: ObservableObject {
    @Published var openTabs: [OpenFile] = []
    @Published var activeTabIndex: Int = 0
    @Published var sidebarOpen: Bool = true
    @Published var workspacePath: String?
    @Published var fileTree: [FileEntry] = []
    @Published var settings: AppSettings = .default
    @Published var commandPaletteOpen: Bool = false
    @Published var commandPaletteMode: CommandPaletteMode = .search
    @Published var showSettings: Bool = false
    @Published var selectedSettingsTab: String = "general"
    @Published var aiSidePanelOpen: Bool = false
    @Published var aiInitialPrompt: String?
    @Published var currentView: ViewMode = .editor

    var activeTab: OpenFile? {
        guard activeTabIndex >= 0, activeTabIndex < openTabs.count else { return nil }
        return openTabs[activeTabIndex]
    }

    private func cleanDisplayName(_ name: String) -> String {
        name.hasSuffix(".md") ? String(name.dropLast(3)) : name
    }

    func openFile(_ entry: FileEntry) {
        if let existingIndex = openTabs.firstIndex(where: { $0.path == entry.path }) {
            activeTabIndex = existingIndex
            return
        }
        let tab = OpenFile(
            id: UUID(),
            path: entry.path,
            content: "",
            isDirty: false,
            isEmptyTab: false,
            isDatabase: entry.isDatabase,
            displayName: cleanDisplayName(entry.name),
            openerPagePath: nil,
            icon: entry.icon
        )
        openTabs.append(tab)
        activeTabIndex = openTabs.count - 1
    }

    /// Replace the active tab's content with the given file. If the file is already open, switch to it instead.
    /// Returns true if an existing tab was switched to (no load needed), false if the tab was replaced (caller should load content).
    @discardableResult
    func openFileReplacingCurrentTab(_ entry: FileEntry) -> Bool {
        // If already open in another tab, just switch
        if let existingIndex = openTabs.firstIndex(where: { $0.path == entry.path }) {
            activeTabIndex = existingIndex
            return true
        }

        // Replace the active tab
        guard activeTabIndex >= 0, activeTabIndex < openTabs.count else {
            // No active tab — fall back to opening a new one
            openFile(entry)
            return false
        }

        let newTab = OpenFile(
            id: UUID(),
            path: entry.path,
            content: "",
            isDirty: false,
            isEmptyTab: false,
            isDatabase: entry.isDatabase,
            displayName: cleanDisplayName(entry.name),
            openerPagePath: nil,
            icon: entry.icon
        )
        openTabs[activeTabIndex] = newTab
        return false
    }

    /// Always open a file in a new tab. If already open, switch to it instead.
    func openFileInNewTab(_ entry: FileEntry) {
        if let existingIndex = openTabs.firstIndex(where: { $0.path == entry.path }) {
            activeTabIndex = existingIndex
            return
        }
        let tab = OpenFile(
            id: UUID(),
            path: entry.path,
            content: "",
            isDirty: false,
            isEmptyTab: false,
            isDatabase: entry.isDatabase,
            displayName: cleanDisplayName(entry.name),
            openerPagePath: nil,
            icon: entry.icon
        )
        openTabs.append(tab)
        activeTabIndex = openTabs.count - 1
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

    func closeTab(at index: Int) {
        guard index >= 0, index < openTabs.count else { return }
        let wasActive = index == activeTabIndex
        openTabs.remove(at: index)
        if openTabs.isEmpty {
            activeTabIndex = 0
        } else if wasActive {
            // Select same index position, or last tab
            activeTabIndex = min(index, openTabs.count - 1)
        } else if activeTabIndex > index {
            activeTabIndex -= 1
        }
    }

    func openAiPanel(prompt: String? = nil) {
        aiInitialPrompt = prompt
        aiSidePanelOpen = true
    }

    func newEmptyTab() {
        let tab = OpenFile(
            id: UUID(),
            path: "",
            content: "",
            isDirty: false,
            isEmptyTab: true,
            isDatabase: false,
            displayName: nil,
            openerPagePath: nil,
            icon: nil
        )
        openTabs.append(tab)
        activeTabIndex = openTabs.count - 1
    }
}
