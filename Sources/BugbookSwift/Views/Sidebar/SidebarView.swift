import SwiftUI

struct SidebarView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var fileSystem: FileSystemService
    var onSelectFile: (FileEntry) -> Void
    var onToggleSidebar: () -> Void
    @State private var hoveredButton: String?
    @State private var isFullScreen: Bool = false

    private let settingsTabs: [(id: String, label: String, icon: String)] = [
        ("general", "General", "gearshape"),
        ("appearance", "Appearance", "paintbrush"),
        ("ai", "AI", "cpu"),
        ("agents", "Agents", "person.2"),
        ("shortcuts", "Shortcuts", "keyboard"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            if appState.showSettings {
                settingsNav
            } else {
                fileTreeNav
            }
        }
        .frame(minWidth: 160, idealWidth: 190, maxWidth: 240)
        .background(Color.fallbackSidebarBg)
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didEnterFullScreenNotification)) { _ in
            isFullScreen = true
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didExitFullScreenNotification)) { _ in
            isFullScreen = false
        }
        .onAppear {
            isFullScreen = NSApp.mainWindow?.styleMask.contains(.fullScreen) ?? false
        }
    }

    // MARK: - File Tree (default sidebar)

    private var fileTreeNav: some View {
        VStack(spacing: 0) {
            // Traffic light spacing
            Spacer().frame(height: 12)

            // Action buttons
            HStack(spacing: 12) {
                if !isFullScreen {
                    Spacer()
                }
                Button(action: createFile) {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.borderless)
                .help("New Page")
                Button(action: onToggleSidebar) {
                    Image(systemName: "sidebar.left")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Toggle Sidebar")
                if isFullScreen {
                    Spacer()
                }
            }
            .padding(.horizontal, 12)
            .padding(.leading, isFullScreen ? 8 : 0)
            .padding(.bottom, 6)

            // Search & AI
            VStack(spacing: 2) {
                Button(action: { NotificationCenter.default.post(name: .quickOpen, object: nil) }) {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                        Text("Search")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(hoveredButton == "search" ? Color.primary.opacity(0.06) : Color.clear)
                    .cornerRadius(6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { hovering in hoveredButton = hovering ? "search" : nil }

                Button(action: { NotificationCenter.default.post(name: .openAIPanel, object: nil) }) {
                    HStack(spacing: 8) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                        Text("Ask AI")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(hoveredButton == "ai" ? Color.primary.opacity(0.06) : Color.clear)
                    .cornerRadius(6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { hovering in hoveredButton = hovering ? "ai" : nil }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)

            // Pages header
            HStack {
                Text("Pages")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Color(nsColor: .tertiaryLabelColor))
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.top, 4)
            .padding(.bottom, 2)

            // File tree
            ScrollView {
                FileTreeView(
                    entries: appState.fileTree,
                    activeFilePath: appState.activeTab?.path,
                    fileSystem: fileSystem,
                    workspacePath: appState.workspacePath,
                    onSelectFile: onSelectFile,
                    onRefreshTree: refreshTree
                )
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            }

            // Bottom bar with settings and chat
            VStack(spacing: 2) {
                Button(action: openSettings) {
                    HStack(spacing: 8) {
                        Image(systemName: "gearshape")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                        Text("Settings")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(hoveredButton == "settings" ? Color.primary.opacity(0.06) : Color.clear)
                    .cornerRadius(6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { hovering in hoveredButton = hovering ? "settings" : nil }

                Button(action: {
                    appState.currentView = .chat
                    appState.aiSidePanelOpen = false
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "bubble.left.and.text.bubble.right")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                        Text("Chat with Notes")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(hoveredButton == "chat" ? Color.primary.opacity(0.06) : Color.clear)
                    .cornerRadius(6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { hovering in hoveredButton = hovering ? "chat" : nil }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
    }

    // MARK: - Settings Nav

    private var settingsNav: some View {
        VStack(spacing: 0) {
            // Traffic light spacing
            Spacer().frame(height: 38)

            // Back button
            Button(action: { appState.showSettings = false }) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.left")
                        .font(.system(size: 14))
                    Text("Back to app")
                        .font(.system(size: 14))
                    Spacer()
                }
                .foregroundColor(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Settings categories
            VStack(spacing: 2) {
                ForEach(settingsTabs, id: \.id) { tab in
                    Button(action: { appState.selectedSettingsTab = tab.id }) {
                        HStack(spacing: 10) {
                            Image(systemName: tab.icon)
                                .font(.system(size: 15))
                                .frame(width: 20)
                            Text(tab.label)
                                .font(.system(size: 14))
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            appState.selectedSettingsTab == tab.id
                                ? Color.primary.opacity(0.08)
                                : Color.clear
                        )
                        .cornerRadius(6)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.primary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.top, 4)

            Spacer()
        }
    }

    // MARK: - Helpers

    private var workspaceName: String {
        guard let path = appState.workspacePath else { return "Workspace" }
        return (path as NSString).lastPathComponent
    }

    private func refreshTree() {
        guard let workspace = appState.workspacePath else { return }
        appState.fileTree = fileSystem.buildFileTree(at: workspace)
    }

    private func createFile() {
        NotificationCenter.default.post(name: .newNote, object: nil)
    }

    private func openSettings() {
        NotificationCenter.default.post(name: .openSettings, object: nil)
    }
}
