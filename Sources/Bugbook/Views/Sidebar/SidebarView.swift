import SwiftUI
import UniformTypeIdentifiers

struct SidebarView: View {
    enum LayoutMode {
        case full
        case compact
    }

    var appState: AppState
    var fileSystem: FileSystemService
    var onSelectFile: (FileEntry) -> Void
    var onToggleSidebar: () -> Void
    var onAddSidebarReference: (SidebarReferenceDragPayload) -> Void
    var layoutMode: LayoutMode = .full
    var onActionInvoked: (() -> Void)? = nil
    var trashPopoverOverride: Binding<Bool>? = nil
    @State private var hoveredButton: String?
    @State private var isFullScreen: Bool = false
    @State private var localTrashPopoverPresented: Bool = false
    @State private var isSidebarReferenceDropTargeted = false

    private let settingsTabs: [(id: String, label: String, icon: String)] = [
        ("general", "General", "gearshape"),
        ("appearance", "Appearance", "paintbrush"),
        ("ai", "AI", "cpu"),
        ("calendar", "Calendar", "calendar"),
        ("agents", "Agents", "person.2"),
        ("search", "Search", "magnifyingglass"),
        ("shortcuts", "Shortcuts", "keyboard"),
    ]

    private var isCompact: Bool {
        layoutMode == .compact
    }

    private var sidebarMinWidth: CGFloat {
        ShellZoomMetrics.size(isCompact ? 170 : 160)
    }

    private var sidebarIdealWidth: CGFloat {
        ShellZoomMetrics.size(isCompact ? 185 : 190)
    }

    private var sidebarMaxWidth: CGFloat {
        ShellZoomMetrics.size(isCompact ? 195 : 240)
    }

    private var topSpacerHeight: CGFloat {
        ShellZoomMetrics.size(isCompact ? 4 : 12)
    }

    private var chromeButtonSpacing: CGFloat {
        ShellZoomMetrics.size(isCompact ? 4 : 8)
    }

    private var sectionSpacing: CGFloat {
        ShellZoomMetrics.size(isCompact ? 0 : 2)
    }

    private var sectionHorizontalPadding: CGFloat {
        ShellZoomMetrics.size(isCompact ? 5 : 8)
    }

    private var sectionVerticalPadding: CGFloat {
        ShellZoomMetrics.size(isCompact ? 3 : 6)
    }

    private var rowHorizontalPadding: CGFloat {
        ShellZoomMetrics.size(isCompact ? 8 : 12)
    }

    private var rowVerticalPadding: CGFloat {
        ShellZoomMetrics.size(isCompact ? 3 : 6)
    }

    private var headerTopPadding: CGFloat {
        ShellZoomMetrics.size(isCompact ? 1 : 4)
    }

    private var treeVerticalPadding: CGFloat {
        ShellZoomMetrics.size(isCompact ? 2 : 4)
    }

    private var trashPopoverPresented: Binding<Bool> {
        trashPopoverOverride ?? $localTrashPopoverPresented
    }

    var body: some View {
        VStack(spacing: 0) {
            if appState.showSettings {
                settingsNav
            } else {
                fileTreeNav
            }
        }
        .frame(
            minWidth: sidebarMinWidth,
            idealWidth: sidebarIdealWidth,
            maxWidth: sidebarMaxWidth
        )
        .background(isCompact ? Color.fallbackEditorBg : Color.fallbackSidebarBg)
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
            Spacer().frame(height: topSpacerHeight)

            // Action buttons
            HStack(spacing: chromeButtonSpacing) {
                if isCompact {
                    Spacer()
                    newPageMenuButton
                } else {
                    if !isFullScreen {
                        Spacer()
                    }
                    chromeButton(icon: "sidebar.left", help: "Toggle Sidebar", action: onToggleSidebar)
                    newPageMenuButton
                    if isFullScreen {
                        Spacer()
                    }
                }
            }
            .padding(.horizontal, ShellZoomMetrics.size(isCompact ? 10 : 12))
            .padding(.leading, !isCompact && isFullScreen ? ShellZoomMetrics.size(8) : 0)
            .padding(.bottom, ShellZoomMetrics.size(isCompact ? 2 : 6))

            // Search & AI
            VStack(spacing: sectionSpacing) {
                Button(action: { invokeAction { NotificationCenter.default.post(name: .quickOpen, object: nil) } }) {
                    HStack(spacing: chromeButtonSpacing) {
                        Image(systemName: "magnifyingglass")
                            .font(ShellZoomMetrics.font(Typography.body))
                            .foregroundStyle(.secondary)
                        Text("Search")
                            .font(ShellZoomMetrics.font(Typography.body))
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, rowHorizontalPadding)
                    .padding(.vertical, rowVerticalPadding)
                    .background(hoveredButton == "search" ? Color.primary.opacity(0.06) : Color.clear)
                    .clipShape(.rect(cornerRadius: ShellZoomMetrics.size(Radius.sm)))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { hovering in hoveredButton = hovering ? "search" : nil }

                Button(action: { invokeAction { NotificationCenter.default.post(name: .openAIPanel, object: nil) } }) {
                    HStack(spacing: chromeButtonSpacing) {
                        Image(systemName: "ladybug")
                            .font(ShellZoomMetrics.font(Typography.body))
                            .foregroundStyle(.secondary)
                        Text("Ask AI")
                            .font(ShellZoomMetrics.font(Typography.body))
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, rowHorizontalPadding)
                    .padding(.vertical, rowVerticalPadding)
                    .background(hoveredButton == "ai" ? Color.primary.opacity(0.06) : Color.clear)
                    .clipShape(.rect(cornerRadius: ShellZoomMetrics.size(Radius.sm)))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { hovering in hoveredButton = hovering ? "ai" : nil }
            }
            .padding(.horizontal, sectionHorizontalPadding)
            .padding(.vertical, sectionVerticalPadding)

            // Daily note & Graph (hidden in compact/peek mode)
            if !isCompact {
            VStack(spacing: sectionSpacing) {
                Button(action: { invokeAction { NotificationCenter.default.post(name: .openDailyNote, object: nil) } }) {
                    HStack(spacing: chromeButtonSpacing) {
                        Image(systemName: "calendar")
                            .font(ShellZoomMetrics.font(Typography.body))
                            .foregroundStyle(.secondary)
                        Text("Today")
                            .font(ShellZoomMetrics.font(Typography.body))
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, rowHorizontalPadding)
                    .padding(.vertical, rowVerticalPadding)
                    .background(hoveredButton == "today" ? Color.primary.opacity(0.06) : Color.clear)
                    .clipShape(.rect(cornerRadius: ShellZoomMetrics.size(Radius.sm)))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { hovering in hoveredButton = hovering ? "today" : nil }

                Button(action: { invokeAction { NotificationCenter.default.post(name: .openGraphView, object: nil) } }) {
                    HStack(spacing: chromeButtonSpacing) {
                        Image(systemName: "point.3.connected.trianglepath.dotted")
                            .font(ShellZoomMetrics.font(Typography.body))
                            .foregroundStyle(.secondary)
                        Text("Graph")
                            .font(ShellZoomMetrics.font(Typography.body))
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, rowHorizontalPadding)
                    .padding(.vertical, rowVerticalPadding)
                    .background(hoveredButton == "graph" ? Color.primary.opacity(0.06) : Color.clear)
                    .clipShape(.rect(cornerRadius: ShellZoomMetrics.size(Radius.sm)))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { hovering in hoveredButton = hovering ? "graph" : nil }

                Button(action: { invokeAction { NotificationCenter.default.post(name: .openCalendar, object: nil) } }) {
                    HStack(spacing: chromeButtonSpacing) {
                        Image(systemName: "calendar.badge.clock")
                            .font(ShellZoomMetrics.font(Typography.body))
                            .foregroundStyle(.secondary)
                        Text("Calendar")
                            .font(ShellZoomMetrics.font(Typography.body))
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, rowHorizontalPadding)
                    .padding(.vertical, rowVerticalPadding)
                    .background(hoveredButton == "calendar" ? Color.primary.opacity(0.06) : Color.clear)
                    .clipShape(.rect(cornerRadius: ShellZoomMetrics.size(Radius.sm)))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { hovering in hoveredButton = hovering ? "calendar" : nil }

                Button(action: { invokeAction { NotificationCenter.default.post(name: .openMeetings, object: nil) } }) {
                    HStack(spacing: chromeButtonSpacing) {
                        Image(systemName: "person.2")
                            .font(ShellZoomMetrics.font(Typography.body))
                            .foregroundStyle(.secondary)
                        Text("Meetings")
                            .font(ShellZoomMetrics.font(Typography.body))
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, rowHorizontalPadding)
                    .padding(.vertical, rowVerticalPadding)
                    .background(hoveredButton == "meetings" ? Color.primary.opacity(0.06) : Color.clear)
                    .clipShape(.rect(cornerRadius: ShellZoomMetrics.size(Radius.sm)))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { hovering in hoveredButton = hovering ? "meetings" : nil }
            }
            .padding(.horizontal, sectionHorizontalPadding)
            }

            // Pages header
            HStack {
                Text("Pages")
                    .font(ShellZoomMetrics.font(Typography.caption, weight: .medium))
                    .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                Spacer()
            }
            .padding(.horizontal, ShellZoomMetrics.size(isCompact ? 12 : 14))
            .padding(.top, headerTopPadding)
            .padding(.bottom, ShellZoomMetrics.size(2))

            // File tree
            ScrollView {
                VStack(spacing: ShellZoomMetrics.size(isCompact ? 3 : 4)) {
                    if !appState.sidebarReferences.isEmpty {
                        VStack(spacing: ShellZoomMetrics.size(1)) {
                            ForEach(appState.sidebarReferences) { entry in
                                FileTreeItemView(
                                    entry: entry,
                                    activeFilePath: appState.activeTab?.path,
                                    fileSystem: fileSystem,
                                    workspacePath: appState.workspacePath,
                                    onSelectFile: onSelectFile,
                                    onRefreshTree: refreshTree,
                                    isSidebarReference: true
                                )
                            }
                        }
                    }

                    FileTreeView(
                        entries: appState.fileTree,
                        activeFilePath: appState.activeTab?.path,
                        fileSystem: fileSystem,
                        workspacePath: appState.workspacePath,
                        onSelectFile: onSelectFile,
                        onRefreshTree: refreshTree,
                        onAddSidebarReference: onAddSidebarReference
                    )
                }
                .padding(.horizontal, sectionHorizontalPadding)
                .padding(.vertical, treeVerticalPadding)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .onDrop(of: [.sidebarReference], isTargeted: Binding(
                get: { isSidebarReferenceDropTargeted },
                set: { isSidebarReferenceDropTargeted = $0 }
            )) { providers in
                guard let provider = providers.first else { return false }
                provider.loadDataRepresentation(forTypeIdentifier: UTType.sidebarReference.identifier) { data, _ in
                    guard let data, let payload = try? JSONDecoder().decode(SidebarReferenceDragPayload.self, from: data) else { return }
                    DispatchQueue.main.async {
                        onAddSidebarReference(payload)
                    }
                }
                return true
            }
            .overlay {
                RoundedRectangle(cornerRadius: ShellZoomMetrics.size(Radius.sm))
                    .stroke(isSidebarReferenceDropTargeted ? Color.dragIndicator.opacity(0.8) : Color.clear, lineWidth: 1.5)
                    .padding(.horizontal, sectionHorizontalPadding)
                    .padding(.vertical, treeVerticalPadding)
                    .allowsHitTesting(false)
            }
            .accessibilityIdentifier("sidebar-file-tree")

            // Bottom bar with trash and settings
            VStack(spacing: sectionSpacing) {
                Button(action: { trashPopoverPresented.wrappedValue.toggle() }) {
                    HStack(spacing: chromeButtonSpacing) {
                        Image(systemName: "trash")
                            .font(ShellZoomMetrics.font(Typography.body))
                            .foregroundStyle(.secondary)
                        Text("Trash")
                            .font(ShellZoomMetrics.font(Typography.body))
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, rowHorizontalPadding)
                    .padding(.vertical, rowVerticalPadding)
                    .background((hoveredButton == "trash" || trashPopoverPresented.wrappedValue) ? Color.primary.opacity(0.06) : Color.clear)
                    .clipShape(.rect(cornerRadius: ShellZoomMetrics.size(Radius.sm)))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { hovering in hoveredButton = hovering ? "trash" : nil }
                .floatingPopover(isPresented: trashPopoverPresented) {
                    TrashPopoverView(
                        appState: appState,
                        fileSystem: fileSystem,
                        onRestore: {
                            refreshTree()
                        }
                    )
                }

                Button(action: openSettings) {
                    HStack(spacing: chromeButtonSpacing) {
                        Image(systemName: "gearshape")
                            .font(ShellZoomMetrics.font(Typography.body))
                            .foregroundStyle(.secondary)
                        Text("Settings")
                            .font(ShellZoomMetrics.font(Typography.body))
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, rowHorizontalPadding)
                    .padding(.vertical, rowVerticalPadding)
                    .background(hoveredButton == "settings" ? Color.primary.opacity(0.06) : Color.clear)
                    .clipShape(.rect(cornerRadius: ShellZoomMetrics.size(Radius.sm)))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { hovering in hoveredButton = hovering ? "settings" : nil }
            }
            .padding(.horizontal, sectionHorizontalPadding)
            .padding(.vertical, sectionVerticalPadding)
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
        let fileSystem = self.fileSystem
        Task.detached {
            let tree = fileSystem.buildFileTree(at: workspace)
            await MainActor.run {
                self.appState.fileTree = tree
            }
        }
    }

    private func invokeAction(_ action: () -> Void) {
        action()
        onActionInvoked?()
    }

    private func createFile() {
        invokeAction {
            NotificationCenter.default.post(name: .newNote, object: nil)
        }
    }

    private var newPageMenuButton: some View {
        Button {
            createFile()
        } label: {
            Image(systemName: "square.and.pencil")
                .font(ShellZoomMetrics.font(Typography.body, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: ShellZoomMetrics.size(24), height: ShellZoomMetrics.size(24))
        }
        .buttonStyle(.borderless)
        .help("New Page")
    }

    private func openSettings() {
        invokeAction {
            NotificationCenter.default.post(name: .openSettings, object: nil)
        }
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
