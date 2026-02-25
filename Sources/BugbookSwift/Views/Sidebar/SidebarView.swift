import SwiftUI

struct SidebarView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var fileSystem: FileSystemService
    var onSelectFile: (FileEntry) -> Void
    var onToggleSidebar: () -> Void

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
        .frame(minWidth: 200, idealWidth: 240, maxWidth: 300)
        .background(Color.fallbackSidebarBg)
    }

    // MARK: - File Tree (default sidebar)

    private var fileTreeNav: some View {
        VStack(spacing: 0) {
            // Traffic light spacing
            Spacer().frame(height: 12)

            // Action buttons
            HStack(spacing: 12) {
                Spacer()
                Button(action: createFile) {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.borderless)
                .help("New Page")
                Button(action: onToggleSidebar) {
                    Image(systemName: "sidebar.left")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Toggle Sidebar")
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 6)

            Divider()

            // Search & AI pills
            VStack(spacing: 4) {
                Button(action: { NotificationCenter.default.post(name: .quickOpen, object: nil) }) {
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        Text("Search")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("⌘K")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(Color(nsColor: .tertiaryLabelColor))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color.primary.opacity(0.04))
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)

                Button(action: { NotificationCenter.default.post(name: .openAIPanel, object: nil) }) {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        Text("Ask AI")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("⌘I")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(Color(nsColor: .tertiaryLabelColor))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color.primary.opacity(0.04))
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)

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
                .padding(.horizontal, 4)
                .padding(.vertical, 4)
            }

            Divider()

            // Bottom bar with settings and chat
            HStack {
                Button(action: openSettings) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Settings")
                Spacer()
                Button(action: { appState.currentView = .chat }) {
                    Image(systemName: "bubble.left.and.text.bubble.right")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Chat with Notes")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    // MARK: - Settings Nav

    private var settingsNav: some View {
        VStack(spacing: 0) {
            // Traffic light spacing
            Spacer().frame(height: 12)

            // Back button
            Button(action: { appState.showSettings = false }) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.left")
                        .font(.system(size: 13))
                    Text("Back to app")
                        .font(.system(size: 13))
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
                                .font(.system(size: 14))
                                .frame(width: 20)
                            Text(tab.label)
                                .font(.system(size: 13))
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
