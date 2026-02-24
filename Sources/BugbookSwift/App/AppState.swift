import Foundation
import SwiftUI

@MainActor
class AppState: ObservableObject {
    @Published var openTabs: [OpenFile] = []
    @Published var activeTabIndex: Int = 0
    @Published var sidebarOpen: Bool = true
    @Published var workspacePath: String?
    @Published var fileTree: [FileEntry] = []
    @Published var settings: AppSettings = .default
    @Published var commandPaletteOpen: Bool = false
    @Published var showSettings: Bool = false
    @Published var selectedSettingsTab: String = "general"

    var activeTab: OpenFile? {
        guard activeTabIndex >= 0, activeTabIndex < openTabs.count else { return nil }
        return openTabs[activeTabIndex]
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
            displayName: entry.name,
            openerPagePath: nil
        )
        openTabs.append(tab)
        activeTabIndex = openTabs.count - 1
    }

    func closeTab(at index: Int) {
        guard index >= 0, index < openTabs.count else { return }
        openTabs.remove(at: index)
        if activeTabIndex >= openTabs.count {
            activeTabIndex = max(0, openTabs.count - 1)
        }
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
            openerPagePath: nil
        )
        openTabs.append(tab)
        activeTabIndex = openTabs.count - 1
    }
}
