import SwiftUI

struct SidebarView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var fileSystem: FileSystemService
    var canGoBack: Bool
    var canGoForward: Bool
    var onBack: () -> Void
    var onForward: () -> Void
    var onSelectFile: (FileEntry) -> Void
    var onToggleSidebar: () -> Void
    @State private var hoveredButton: String?
    @State private var isFullScreen: Bool = false

    private let settingsTabs: [(id: String, label: String, icon: String)] = [
        ("general", "General", "gearshape"),
        ("appearance", "Appearance", "paintbrush"),
        ("ai", "AI", "cpu"),
        ("agents", "Agents", "person.2"),
        ("search", "Search", "magnifyingglass"),
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
            HStack(spacing: 8) {
                if !isFullScreen {
                    Spacer()
                }
                chromeButton(icon: "sidebar.left", help: "Toggle Sidebar", action: onToggleSidebar)
                chromeButton(icon: "chevron.left", help: "Back", isEnabled: canGoBack, action: onBack)
                chromeButton(icon: "chevron.right", help: "Forward", isEnabled: canGoForward, action: onForward)
                newPageMenuButton
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

            // Daily note & Graph
            VStack(spacing: 2) {
                Button(action: { NotificationCenter.default.post(name: .openDailyNote, object: nil) }) {
                    HStack(spacing: 8) {
                        Image(systemName: "calendar")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                        Text("Today")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(hoveredButton == "today" ? Color.primary.opacity(0.06) : Color.clear)
                    .cornerRadius(6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { hovering in hoveredButton = hovering ? "today" : nil }

                Button(action: { NotificationCenter.default.post(name: .openGraphView, object: nil) }) {
                    HStack(spacing: 8) {
                        Image(systemName: "point.3.connected.trianglepath.dotted")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                        Text("Graph")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(hoveredButton == "graph" ? Color.primary.opacity(0.06) : Color.clear)
                    .cornerRadius(6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { hovering in hoveredButton = hovering ? "graph" : nil }
            }
            .padding(.horizontal, 8)

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
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .accessibilityIdentifier("sidebar-file-tree")
            .contextMenu {
                Button { createFile() } label: {
                    Label("New Page", systemImage: "doc.badge.plus")
                }
                Button { createCanvas() } label: {
                    Label("New Canvas", systemImage: "rectangle.on.rectangle.angled")
                }
                Button {
                    guard let workspace = appState.workspacePath else { return }
                    if let path = try? fileSystem.createDatabase(in: workspace, name: "Untitled Database") {
                        refreshTree()
                        let db = FileEntry(
                            id: path, name: (path as NSString).lastPathComponent,
                            path: path, isDirectory: false, isDatabase: true,
                            icon: nil, children: nil
                        )
                        onSelectFile(db)
                    }
                } label: {
                    Label("New Database", systemImage: "tablecells")
                }
            }

            // Bottom bar with settings and chat
            VStack(spacing: 2) {
                Button(action: { appState.openAgentHub() }) {
                    HStack(spacing: 8) {
                        Image(systemName: "list.bullet.clipboard")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                        Text("Agent Hub")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(hoveredButton == "agentHub" ? Color.primary.opacity(0.06) : Color.clear)
                    .cornerRadius(6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { hovering in hoveredButton = hovering ? "agentHub" : nil }

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
                    appState.openNotesChat()
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

    private func refreshTree() {
        guard let workspace = appState.workspacePath else { return }
        appState.fileTree = fileSystem.buildFileTree(at: workspace)
    }

    private func createFile() {
        NotificationCenter.default.post(name: .newNote, object: nil)
    }

    private func createCanvas() {
        NotificationCenter.default.post(name: .newCanvas, object: nil)
    }

    private var newPageMenuButton: some View {
        Menu {
            Button {
                createFile()
            } label: {
                Label("New Page", systemImage: "doc")
            }
            Button {
                createCanvas()
            } label: {
                Label("New Canvas", systemImage: "rectangle.on.rectangle.angled")
            }
        } label: {
            Image(systemName: "square.and.pencil")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.secondary)
                .frame(width: 24, height: 24)
        } primaryAction: {
            createFile()
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("New Page")
    }

    private func openSettings() {
        NotificationCenter.default.post(name: .openSettings, object: nil)
    }

    @ViewBuilder
    private func chromeButton(
        icon: String,
        help: String,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(isEnabled ? .secondary : .secondary.opacity(0.45))
                .frame(width: 24, height: 24)
        }
        .buttonStyle(.borderless)
        .help(help)
        .disabled(!isEnabled)
    }
}
