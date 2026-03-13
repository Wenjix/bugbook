import SwiftUI

struct SidebarView: View {
    var appState: AppState
    var fileSystem: FileSystemService
    var onSelectFile: (FileEntry) -> Void
    var onToggleSidebar: () -> Void
    @State private var hoveredButton: String?
    @State private var isFullScreen: Bool = false
    @State private var showTrashPopover: Bool = false

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
        .frame(
            minWidth: ShellZoomMetrics.size(160),
            idealWidth: ShellZoomMetrics.size(190),
            maxWidth: ShellZoomMetrics.size(240)
        )
        .background(Color.fallbackSidebarBg)
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didEnterFullScreenNotification)) { _ in
            isFullScreen = true
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didExitFullScreenNotification)) { _ in
            isFullScreen = false
        }
        .onAppear {
            isFullScreen = NSApp.mainWindow?.styleMask.contains(.fullScreen) ?? false
            if let workspace = appState.workspacePath {
                Task {
                    fileSystem.purgeOldTrash(in: workspace)
                }
            }
        }
    }

    // MARK: - File Tree (default sidebar)

    private var fileTreeNav: some View {
        VStack(spacing: 0) {
            // Traffic light spacing
            Spacer().frame(height: ShellZoomMetrics.size(12))

            // Action buttons
            HStack(spacing: ShellZoomMetrics.size(8)) {
                if !isFullScreen {
                    Spacer()
                }
                chromeButton(icon: "sidebar.left", help: "Toggle Sidebar", action: onToggleSidebar)
                newPageMenuButton
                if isFullScreen {
                    Spacer()
                }
            }
            .padding(.horizontal, ShellZoomMetrics.size(12))
            .padding(.leading, isFullScreen ? ShellZoomMetrics.size(8) : 0)
            .padding(.bottom, ShellZoomMetrics.size(6))

            // Search & AI
            VStack(spacing: ShellZoomMetrics.size(2)) {
                Button(action: { NotificationCenter.default.post(name: .quickOpen, object: nil) }) {
                    HStack(spacing: ShellZoomMetrics.size(8)) {
                        Image(systemName: "magnifyingglass")
                            .font(ShellZoomMetrics.font(Typography.body))
                            .foregroundStyle(.secondary)
                        Text("Search")
                            .font(ShellZoomMetrics.font(Typography.body))
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, ShellZoomMetrics.size(12))
                    .padding(.vertical, ShellZoomMetrics.size(6))
                    .background(hoveredButton == "search" ? Color.primary.opacity(0.06) : Color.clear)
                    .clipShape(.rect(cornerRadius: ShellZoomMetrics.size(Radius.sm)))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { hovering in hoveredButton = hovering ? "search" : nil }

                Button(action: { NotificationCenter.default.post(name: .openAIPanel, object: nil) }) {
                    HStack(spacing: ShellZoomMetrics.size(8)) {
                        Image(systemName: "sparkles")
                            .font(ShellZoomMetrics.font(Typography.body))
                            .foregroundStyle(.secondary)
                        Text("Ask AI")
                            .font(ShellZoomMetrics.font(Typography.body))
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, ShellZoomMetrics.size(12))
                    .padding(.vertical, ShellZoomMetrics.size(6))
                    .background(hoveredButton == "ai" ? Color.primary.opacity(0.06) : Color.clear)
                    .clipShape(.rect(cornerRadius: ShellZoomMetrics.size(Radius.sm)))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { hovering in hoveredButton = hovering ? "ai" : nil }
            }
            .padding(.horizontal, ShellZoomMetrics.size(8))
            .padding(.vertical, ShellZoomMetrics.size(6))

            // Daily note & Graph
            VStack(spacing: ShellZoomMetrics.size(2)) {
                Button(action: { NotificationCenter.default.post(name: .openDailyNote, object: nil) }) {
                    HStack(spacing: ShellZoomMetrics.size(8)) {
                        Image(systemName: "calendar")
                            .font(ShellZoomMetrics.font(Typography.body))
                            .foregroundStyle(.secondary)
                        Text("Today")
                            .font(ShellZoomMetrics.font(Typography.body))
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, ShellZoomMetrics.size(12))
                    .padding(.vertical, ShellZoomMetrics.size(6))
                    .background(hoveredButton == "today" ? Color.primary.opacity(0.06) : Color.clear)
                    .clipShape(.rect(cornerRadius: ShellZoomMetrics.size(Radius.sm)))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { hovering in hoveredButton = hovering ? "today" : nil }

                Button(action: { NotificationCenter.default.post(name: .openGraphView, object: nil) }) {
                    HStack(spacing: ShellZoomMetrics.size(8)) {
                        Image(systemName: "point.3.connected.trianglepath.dotted")
                            .font(ShellZoomMetrics.font(Typography.body))
                            .foregroundStyle(.secondary)
                        Text("Graph")
                            .font(ShellZoomMetrics.font(Typography.body))
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, ShellZoomMetrics.size(12))
                    .padding(.vertical, ShellZoomMetrics.size(6))
                    .background(hoveredButton == "graph" ? Color.primary.opacity(0.06) : Color.clear)
                    .clipShape(.rect(cornerRadius: ShellZoomMetrics.size(Radius.sm)))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { hovering in hoveredButton = hovering ? "graph" : nil }
            }
            .padding(.horizontal, ShellZoomMetrics.size(8))

            // Pages header
            HStack {
                Text("Pages")
                    .font(ShellZoomMetrics.font(Typography.caption, weight: .medium))
                    .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                Spacer()
            }
            .padding(.horizontal, ShellZoomMetrics.size(14))
            .padding(.top, ShellZoomMetrics.size(4))
            .padding(.bottom, ShellZoomMetrics.size(2))

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
                .padding(.horizontal, ShellZoomMetrics.size(8))
                .padding(.vertical, ShellZoomMetrics.size(4))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .accessibilityIdentifier("sidebar-file-tree")

            // Bottom bar with settings, trash, and chat
            VStack(spacing: ShellZoomMetrics.size(2)) {
                Button(action: openSettings) {
                    HStack(spacing: ShellZoomMetrics.size(8)) {
                        Image(systemName: "gearshape")
                            .font(ShellZoomMetrics.font(Typography.body))
                            .foregroundStyle(.secondary)
                        Text("Settings")
                            .font(ShellZoomMetrics.font(Typography.body))
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, ShellZoomMetrics.size(12))
                    .padding(.vertical, ShellZoomMetrics.size(6))
                    .background(hoveredButton == "settings" ? Color.primary.opacity(0.06) : Color.clear)
                    .clipShape(.rect(cornerRadius: ShellZoomMetrics.size(Radius.sm)))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { hovering in hoveredButton = hovering ? "settings" : nil }

                Button(action: { showTrashPopover.toggle() }) {
                    HStack(spacing: ShellZoomMetrics.size(8)) {
                        Image(systemName: "trash")
                            .font(ShellZoomMetrics.font(Typography.body))
                            .foregroundStyle(.secondary)
                        Text("Trash")
                            .font(ShellZoomMetrics.font(Typography.body))
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, ShellZoomMetrics.size(12))
                    .padding(.vertical, ShellZoomMetrics.size(6))
                    .background((hoveredButton == "trash" || showTrashPopover) ? Color.primary.opacity(0.06) : Color.clear)
                    .clipShape(.rect(cornerRadius: ShellZoomMetrics.size(Radius.sm)))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { hovering in hoveredButton = hovering ? "trash" : nil }
                .floatingPopover(isPresented: $showTrashPopover) {
                    TrashPopoverView(
                        appState: appState,
                        fileSystem: fileSystem,
                        onRestore: {
                            refreshTree()
                        }
                    )
                }

                Button(action: {
                    appState.openNotesChat()
                }) {
                    HStack(spacing: ShellZoomMetrics.size(8)) {
                        Image(systemName: "bubble.left.and.text.bubble.right")
                            .font(ShellZoomMetrics.font(Typography.body))
                            .foregroundStyle(.secondary)
                        Text("Chat with Notes")
                            .font(ShellZoomMetrics.font(Typography.body))
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, ShellZoomMetrics.size(12))
                    .padding(.vertical, ShellZoomMetrics.size(6))
                    .background(hoveredButton == "chat" ? Color.primary.opacity(0.06) : Color.clear)
                    .clipShape(.rect(cornerRadius: ShellZoomMetrics.size(Radius.sm)))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { hovering in hoveredButton = hovering ? "chat" : nil }
            }
            .padding(.horizontal, ShellZoomMetrics.size(8))
            .padding(.vertical, ShellZoomMetrics.size(6))
        }
    }

    // MARK: - Settings Nav

    private var settingsNav: some View {
        VStack(spacing: 0) {
            // Traffic light spacing
            Spacer().frame(height: ShellZoomMetrics.size(38))

            // Back button
            Button(action: { appState.showSettings = false }) {
                HStack(spacing: ShellZoomMetrics.size(6)) {
                    Image(systemName: "arrow.left")
                        .font(ShellZoomMetrics.font(Typography.body))
                    Text("Back to app")
                        .font(ShellZoomMetrics.font(Typography.body))
                    Spacer()
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, ShellZoomMetrics.size(12))
                .padding(.vertical, ShellZoomMetrics.size(10))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Settings categories
            VStack(spacing: ShellZoomMetrics.size(2)) {
                ForEach(settingsTabs, id: \.id) { tab in
                    Button(action: { appState.selectedSettingsTab = tab.id }) {
                        HStack(spacing: ShellZoomMetrics.size(10)) {
                            Image(systemName: tab.icon)
                                .font(ShellZoomMetrics.font(15))
                                .frame(width: ShellZoomMetrics.size(20))
                            Text(tab.label)
                                .font(ShellZoomMetrics.font(Typography.body))
                            Spacer()
                        }
                        .padding(.horizontal, ShellZoomMetrics.size(12))
                        .padding(.vertical, ShellZoomMetrics.size(8))
                        .background(
                            appState.selectedSettingsTab == tab.id
                                ? Color.primary.opacity(0.08)
                                : Color.clear
                        )
                        .clipShape(.rect(cornerRadius: ShellZoomMetrics.size(Radius.sm)))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.primary)
                }
            }
            .padding(.horizontal, ShellZoomMetrics.size(8))
            .padding(.top, ShellZoomMetrics.size(4))

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
                .font(ShellZoomMetrics.font(Typography.body, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: ShellZoomMetrics.size(24), height: ShellZoomMetrics.size(24))
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
                .font(ShellZoomMetrics.font(Typography.body, weight: .medium))
                .foregroundStyle(isEnabled ? Color.secondary : Color.secondary.opacity(0.45))
                .frame(width: ShellZoomMetrics.size(24), height: ShellZoomMetrics.size(24))
        }
        .buttonStyle(.borderless)
        .help(help)
        .disabled(!isEnabled)
    }
}
