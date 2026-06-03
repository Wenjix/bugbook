import SwiftUI
import AppKit
import BugbookCore

enum ShellSidebarMetrics {
    static var defaultWidth: CGFloat { 200 }
    static var minWidth: CGFloat { 150 }
    static var maxWidth: CGFloat { 300 }
    static var windowChromeTopInset: CGFloat { ShellZoomMetrics.size(56) }

    static var titleTopPadding: CGFloat { ShellZoomMetrics.size(14) }
    static var titleBottomPadding: CGFloat { ShellZoomMetrics.size(10) }
    static var sectionSpacing: CGFloat { ShellZoomMetrics.size(12) }
    static var sectionHeaderTopPadding: CGFloat { ShellZoomMetrics.size(2) }
    static var sectionHorizontalPadding: CGFloat { ShellZoomMetrics.size(8) }
    static var rowHorizontalPadding: CGFloat { ShellZoomMetrics.size(12) }
    static var rowVerticalPadding: CGFloat { ShellZoomMetrics.size(6) }
    static var rowSpacing: CGFloat { ShellZoomMetrics.size(6) }
    static var dividerSpacing: CGFloat { ShellZoomMetrics.size(10) }
    static var smallLabelSpacing: CGFloat { ShellZoomMetrics.size(8) }
}

// MARK: - Unified Sidebar

struct HarborSidebarView<ContextualContent: View>: View {
    @Bindable var appState: AppState
    var fileSystem: FileSystemService
    let activeFilePath: String?
    let onSelectEntry: (FileEntry) -> Void
    let onRefreshTree: () -> Void
    let onOpenSettings: () -> Void
    let onNavItemTap: (ShellNavItem, _ inNewTab: Bool) -> Void
    let contextualLabel: String?
    @ViewBuilder let contextualContent: () -> ContextualContent

    // All sidebar content shares one horizontal inset so everything aligns.
    private var inset: CGFloat { ShellSidebarMetrics.sectionHorizontalPadding }
    // Matches WorkspaceTabBar height so the sidebar toggle aligns with the tabs row.
    private var windowChromeBandHeight: CGFloat { ShellZoomMetrics.size(36) }

    @AppStorage("sidebar_favorites_expanded") private var favoritesExpanded = true
    @AppStorage("sidebar_contextual_expanded") private var contextualExpanded = true
    @State private var expandedFolders: Set<String> = {
        let stored = UserDefaults.standard.stringArray(forKey: "expandedFolders") ?? []
        return Set(stored)
    }()
    @State private var showTrashPopover = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Top band — sits next to the traffic lights and holds the sidebar toggle.
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                SidebarToggleButton()
                    .padding(.bottom, ShellZoomMetrics.size(2))
            }
            .frame(height: ShellZoomMetrics.size(36), alignment: .bottom)
            .padding(.trailing, -ShellZoomMetrics.size(2))

            // ── Fixed Zone ──────────────────────────────────
            // Vertical navigation list. Click replaces focused pane; Cmd+click opens new workspace tab.
            VStack(alignment: .leading, spacing: ShellZoomMetrics.size(1)) {
                ForEach(ShellNavigationItems.visible) { item in
                    ShellSidebarShortcutRow(
                        title: item.label,
                        systemImage: item.icon,
                        accessibilityIdentifier: "shell-nav-\(item.id)",
                        verticalPadding: ShellZoomMetrics.size(5),
                        action: {
                            let cmdHeld = NSEvent.modifierFlags.contains(.command)
                            onNavItemTap(item, cmdHeld)
                        }
                    )
                }
            }
            .padding(.top, ShellZoomMetrics.size(4))
            .padding(.horizontal, inset)
            .padding(.bottom, ShellZoomMetrics.size(8))

            if let dailyNotesEntry {
                FileTreeItemView(
                    entry: dailyNotesEntry,
                    activeFilePath: activeFilePath,
                    fileSystem: fileSystem,
                    workspacePath: appState.workspacePath,
                    onSelectFile: onSelectEntry,
                    onRefreshTree: onRefreshTree,
                    isSidebarReference: dailyNotesEntry.isSidebarReference,
                    expandedFolders: $expandedFolders
                )
                .padding(.horizontal, inset)
                .padding(.bottom, ShellZoomMetrics.size(8))
            }

            // Favorites
            if !userFavoriteEntries.isEmpty {
                SidebarFavoritesSectionView(
                    appState: appState,
                    fileSystem: fileSystem,
                    favoriteEntries: userFavoriteEntries,
                    activeFilePath: activeFilePath,
                    onSelectEntry: onSelectEntry,
                    onRefreshTree: onRefreshTree,
                    isExpanded: $favoritesExpanded,
                    expandedFolders: $expandedFolders
                )
                .padding(.horizontal, inset)
                .padding(.bottom, ShellZoomMetrics.size(8))
            }

            // ── Contextual Zone ─────────────────────────────
            if let label = contextualLabel {
                ShellSidebarSectionHeaderView(title: label.uppercased(), isExpanded: $contextualExpanded)
                    .padding(.horizontal, inset)
                    .padding(.top, ShellZoomMetrics.size(8))

                if contextualExpanded {
                    contextualContent()
                        .transition(.opacity.animation(.easeInOut(duration: 0.15)))
                }
            }

            Spacer(minLength: 0)

            // Footer — Trash above Settings
            VStack(alignment: .leading, spacing: 0) {
                Button(action: { showTrashPopover.toggle() }) {
                    HStack(spacing: ShellZoomMetrics.size(8)) {
                        Image(systemName: "trash")
                            .font(ShellZoomMetrics.font(Typography.bodySmall))
                        Text("Trash")
                            .font(ShellZoomMetrics.font(Typography.body))
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(.secondary)
                    .padding(.vertical, ShellZoomMetrics.size(6))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .floatingPopover(isPresented: $showTrashPopover) {
                    TrashPopoverView(
                        appState: appState,
                        fileSystem: fileSystem,
                        onRestore: { onRefreshTree() }
                    )
                    .frame(width: 360, height: 480)
                    .popoverSurface()
                }

                Button(action: onOpenSettings) {
                    HStack(spacing: ShellZoomMetrics.size(8)) {
                        Image(systemName: "gearshape")
                            .font(ShellZoomMetrics.font(Typography.bodySmall))
                        Text("Settings")
                            .font(ShellZoomMetrics.font(Typography.body))
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(.secondary)
                    .padding(.vertical, ShellZoomMetrics.size(6))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, inset)
            .padding(.bottom, ShellZoomMetrics.size(8))
        }
        .frame(maxHeight: .infinity)
        .background(Container.groutBg)
        .clipped()
        .onChange(of: contextualLabel) { _, _ in
            // Auto-expand when switching areas so the new context is visible.
            // A user-driven collapse only sticks within the same area.
            if !contextualExpanded { contextualExpanded = true }
        }
    }

    private var userFavoriteEntries: [FileEntry] {
        var seenPaths = Set<String>()
        if let dailyNotesEntry {
            seenPaths.insert(dailyNotesEntry.path)
        }
        return appState.favorites.filter { entry in
            seenPaths.insert(entry.path).inserted
        }
    }

    private var dailyNotesEntry: FileEntry? {
        guard let workspacePath = appState.workspacePath else { return nil }
        let path = (workspacePath as NSString).appendingPathComponent("Daily Notes/Daily Notes Database")
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
              isDirectory.boolValue else { return nil }
        return FileEntry(
            id: "system:\(path)",
            name: "Daily Notes",
            path: path,
            isDirectory: true,
            kind: .database,
            icon: "sf:calendar",
            isSidebarReference: true
        )
    }
}

private struct SidebarFavoritesSectionView: View {
    @Bindable var appState: AppState
    var fileSystem: FileSystemService
    let favoriteEntries: [FileEntry]
    let activeFilePath: String?
    let onSelectEntry: (FileEntry) -> Void
    let onRefreshTree: () -> Void
    @Binding var isExpanded: Bool
    @Binding var expandedFolders: Set<String>

    @StateObject private var dropState = DropIndicatorState()

    var body: some View {
        VStack(alignment: .leading, spacing: ShellZoomMetrics.size(3)) {
            ShellSidebarSectionHeaderView(title: "Favorites", isExpanded: $isExpanded)

            if isExpanded {
                VStack(spacing: ShellZoomMetrics.size(2)) {
                    ForEach(Array(favoriteEntries.enumerated()), id: \.element.id) { index, entry in
                        favoriteRow(entry, index: index)
                    }

                    favoriteDropZone
                }
            }
        }
    }

    private func sidebarRow(_ entry: FileEntry) -> some View {
        FileTreeItemView(
            entry: entry,
            activeFilePath: activeFilePath,
            fileSystem: fileSystem,
            workspacePath: appState.workspacePath,
            onSelectFile: onSelectEntry,
            onRefreshTree: onRefreshTree,
            isSidebarReference: entry.isSidebarReference,
            expandedFolders: $expandedFolders
        )
    }

    private func favoriteRow(_ entry: FileEntry, index: Int) -> some View {
        sidebarRow(entry)
            .overlay(alignment: .top) {
                dropIndicator(visibleWhen: dropState.mode == .above(index))
            }
            .overlay(alignment: .bottom) {
                dropIndicator(visibleWhen: dropState.mode == .above(index + 1))
            }
            .onDrag {
                dropState.mode = nil
                return NSItemProvider(object: entry.path as NSString)
            }
            .onDrop(of: [.text], delegate: FavoriteSidebarDropDelegate(
                targetIndex: index,
                entries: favoriteEntries,
                workspacePath: appState.workspacePath,
                fileSystem: fileSystem,
                dropState: dropState,
                onDidReorder: refreshFavoritesFromStorage
            ))
    }

    private var favoriteDropZone: some View {
        Color.clear
            .frame(height: favoriteEntries.isEmpty ? ShellZoomMetrics.size(4) : ShellZoomMetrics.size(12))
            .overlay(alignment: .top) {
                dropIndicator(visibleWhen: dropState.mode == .above(favoriteEntries.count))
            }
            .onDrop(of: [.text], delegate: FavoriteSidebarDropDelegate(
                targetIndex: favoriteEntries.count,
                entries: favoriteEntries,
                workspacePath: appState.workspacePath,
                fileSystem: fileSystem,
                dropState: dropState,
                onDidReorder: refreshFavoritesFromStorage
            ))
    }

    private func dropIndicator(visibleWhen isVisible: Bool) -> some View {
        Rectangle()
            .fill(isVisible ? Color.accentColor : Color.clear)
            .frame(height: 2)
            .padding(.horizontal, ShellZoomMetrics.size(8))
    }

    private func refreshFavoritesFromStorage() {
        guard let workspacePath = appState.workspacePath else { return }
        appState.favorites = fileSystem.resolveFavorites(
            for: workspacePath,
            fileTree: appState.fileTree
        )
    }
}

private struct FavoriteSidebarDropDelegate: DropDelegate {
    let targetIndex: Int
    let entries: [FileEntry]
    let workspacePath: String?
    let fileSystem: FileSystemService
    let dropState: DropIndicatorState
    var onDidReorder: () -> Void

    func dropEntered(info: DropInfo) {
        updateDropMode(info: info)
    }

    func dropExited(info: DropInfo) {
        dropState.mode = nil
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        updateDropMode(info: info)
        return DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        let insertIndex = dropIndex
        dropState.mode = nil

        guard let workspacePath,
              let provider = info.itemProviders(for: [.text]).first else { return false }
        let visiblePaths = entries.map(\.path)

        provider.loadItem(forTypeIdentifier: "public.text", options: nil) { item, _ in
            guard let draggedPath = draggedPath(from: item),
                  visiblePaths.contains(draggedPath) else { return }

            Task { @MainActor in
                fileSystem.reorderFavoritePath(
                    draggedPath,
                    toVisibleIndex: insertIndex,
                    visiblePaths: visiblePaths,
                    for: workspacePath
                )
                onDidReorder()
            }
        }

        return true
    }

    private var dropIndex: Int {
        if case .above(let index) = dropState.mode {
            return index
        }
        return targetIndex
    }

    private func updateDropMode(info: DropInfo) {
        guard targetIndex < entries.count else {
            dropState.mode = .above(entries.count)
            return
        }

        let rowHeight = ShellZoomMetrics.size(28)
        let isLowerHalf = info.location.y > rowHeight / 2
        dropState.mode = .above(targetIndex + (isLowerHalf ? 1 : 0))
    }

    private func draggedPath(from item: NSSecureCoding?) -> String? {
        if let data = item as? Data {
            return String(data: data, encoding: .utf8)
        }
        if let string = item as? String {
            return string
        }
        if let string = item as? NSString {
            return string as String
        }
        return nil
    }
}

// MARK: - Sidebar Toggle Button

struct SidebarToggleButton: View {
    @State private var isHovered = false

    var body: some View {
        Button {
            NotificationCenter.default.post(name: .toggleSidebar, object: nil)
        } label: {
            Image(systemName: "sidebar.left")
                .font(ShellZoomMetrics.font(13, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: ShellZoomMetrics.size(28), height: ShellZoomMetrics.size(28))
                .background(
                    RoundedRectangle(cornerRadius: ShellZoomMetrics.size(Radius.sm))
                        .fill(isHovered ? Color.primary.opacity(0.08) : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .help("Toggle Sidebar")
        .onHover { isHovered = $0 }
    }
}

// MARK: - Fixed Navigation Items

/// A row in the fixed top navigation list of HarborSidebarView.
struct ShellNavItem: Identifiable {
    let id: String
    let label: String
    let icon: String
    let notification: Notification.Name
}

enum ShellNavigationItems {
    static let all: [ShellNavItem] = [
        ShellNavItem(id: "home", label: "Home", icon: "house", notification: .openGateway),
        ShellNavItem(id: "search", label: "Search", icon: "magnifyingglass", notification: .quickOpen),
        ShellNavItem(id: "meeting", label: "Meeting", icon: "waveform", notification: .openMeetings),
        ShellNavItem(id: "calendar", label: "Calendar", icon: "calendar.badge.clock", notification: .openCalendar),
        ShellNavItem(id: "terminal", label: "Terminal", icon: "terminal", notification: .openTerminal),
        ShellNavItem(id: "browser", label: "Browser", icon: "globe", notification: .openBrowser),
        ShellNavItem(id: "mail", label: "Mail", icon: "envelope", notification: .openMail),
        ShellNavItem(id: "notes", label: "Notes", icon: "doc.text", notification: .openDailyNote)
    ]

    static var visible: [ShellNavItem] {
        all.filter { BugbookFeatureGate.allowsSidebarItem(id: $0.id) }
    }
}

// MARK: - Sidebar Resize Handle

struct SidebarResizeHandle: View {
    @Binding var width: CGFloat
    @State private var dragStartWidth: CGFloat?

    var body: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(width: 6)
            .contentShape(Rectangle())
            .onHover { hovering in
                if hovering {
                    NSCursor.resizeLeftRight.push()
                } else {
                    NSCursor.pop()
                }
            }
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        if dragStartWidth == nil { dragStartWidth = width }
                        let proposed = (dragStartWidth ?? width) + value.translation.width
                        width = max(ShellSidebarMetrics.minWidth, min(ShellSidebarMetrics.maxWidth, proposed))
                    }
                    .onEnded { _ in
                        dragStartWidth = nil
                    }
            )
    }
}

// MARK: - Sidebar Section Header

private struct ShellSidebarSectionHeaderView: View {
    let title: String
    @Binding var isExpanded: Bool
    @State private var isHovering = false

    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                isExpanded.toggle()
            }
        } label: {
            HStack(spacing: ShellZoomMetrics.size(4)) {
                Text(title)
                    .font(ShellZoomMetrics.font(Typography.caption, weight: .medium))
                    .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                Image(systemName: "chevron.right")
                    .font(.system(size: ShellZoomMetrics.size(8), weight: .semibold))
                    .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .opacity(isHovering ? 1 : 0)
                Spacer()
            }
            .padding(.horizontal, ShellZoomMetrics.size(4))
            .padding(.vertical, ShellZoomMetrics.size(3))
            .background(
                RoundedRectangle(cornerRadius: ShellZoomMetrics.size(Radius.sm))
                    .fill(isHovering ? Color.primary.opacity(0.06) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.top, ShellSidebarMetrics.sectionHeaderTopPadding)
        .padding(.bottom, ShellZoomMetrics.size(2))
        .onHover { isHovering = $0 }
    }
}

// MARK: - Sidebar Shortcut Row

private struct ShellSidebarShortcutRow: View {
    let title: String
    let systemImage: String
    var trailingText: String?
    var isSelected = false
    var accessibilityIdentifier: String?
    var verticalPadding: CGFloat?
    var action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: ShellSidebarMetrics.rowSpacing) {
                Image(systemName: systemImage)
                    .font(ShellZoomMetrics.font(Typography.bodySmall))
                    .frame(width: ShellZoomMetrics.size(14))
                Text(title)
                    .font(ShellZoomMetrics.font(Typography.body, weight: isSelected ? .medium : .regular))
                    .lineLimit(1)
                Spacer(minLength: 0)
                if let trailingText, !trailingText.isEmpty {
                    Text(trailingText)
                        .font(ShellZoomMetrics.font(Typography.caption, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .foregroundStyle(isSelected ? Color.accentColor : .primary)
            .padding(.horizontal, ShellSidebarMetrics.rowHorizontalPadding)
            .padding(.vertical, verticalPadding ?? ShellSidebarMetrics.rowVerticalPadding)
            .background(
                RoundedRectangle(cornerRadius: ShellZoomMetrics.size(Radius.sm))
                    .fill(rowBackground)
            )
        }
        .buttonStyle(.plain)
        .optionalAccessibilityIdentifier(accessibilityIdentifier)
        .onHover { isHovering = $0 }
    }

    private var rowBackground: Color {
        if isSelected { return Color.accentColor.opacity(0.08) }
        if isHovering { return Color.primary.opacity(0.07) }
        return .clear
    }
}

private struct OptionalAccessibilityIdentifier: ViewModifier {
    let identifier: String?

    func body(content: Content) -> some View {
        if let identifier {
            content.accessibilityIdentifier(identifier)
        } else {
            content
        }
    }
}

private extension View {
    func optionalAccessibilityIdentifier(_ identifier: String?) -> some View {
        modifier(OptionalAccessibilityIdentifier(identifier: identifier))
    }
}

// MARK: - Workspace Contextual Sidebar (Pages + Agents)

struct WorkspaceContextualSidebarView: View {
    @Bindable var appState: AppState
    var fileSystem: FileSystemService
    let activeFilePath: String?
    let onSelectWorkspaceEntry: (FileEntry) -> Void
    let onRefreshTree: () -> Void

    @AppStorage("sidebar_workspace_expanded") private var workspaceExpanded = true
    @AppStorage("sidebar_agents_expanded") private var agentsExpanded = true
    @State private var expandedFolders: Set<String> = {
        let stored = UserDefaults.standard.stringArray(forKey: "expandedFolders") ?? []
        return Set(stored)
    }()

    var body: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: ShellSidebarMetrics.sectionSpacing) {
                // Sidebar references (pinned workspace shortcuts like Today, Graph)
                if !appState.sidebarReferences.isEmpty {
                    VStack(spacing: ShellZoomMetrics.size(1)) {
                        ForEach(appState.sidebarReferences) { entry in
                            FileTreeItemView(
                                entry: entry,
                                activeFilePath: activeFilePath,
                                fileSystem: fileSystem,
                                workspacePath: appState.workspacePath,
                                onSelectFile: onSelectWorkspaceEntry,
                                onRefreshTree: onRefreshTree,
                                isSidebarReference: true,
                                expandedFolders: $expandedFolders
                            )
                        }
                    }
                }

                // Full file tree
                FileTreeView(
                    entries: appState.fileTree,
                    activeFilePath: activeFilePath,
                    fileSystem: fileSystem,
                    workspacePath: appState.workspacePath,
                    onSelectFile: onSelectWorkspaceEntry,
                    onRefreshTree: onRefreshTree,
                    expandedFolders: $expandedFolders
                )

                // Agents section
                if BugbookFeatureGate.shouldExposeAgentSurfaces,
                   hasAgentSidebarEntries {
                    VStack(alignment: .leading, spacing: ShellZoomMetrics.size(4)) {
                        ShellSidebarSectionHeaderView(title: "Agents", isExpanded: $agentsExpanded)

                        if agentsExpanded {
                            VStack(alignment: .leading, spacing: ShellZoomMetrics.size(4)) {
                                ForEach(appState.agentSkills) { entry in
                                    FileTreeItemView(
                                        entry: entry,
                                        activeFilePath: activeFilePath,
                                        fileSystem: fileSystem,
                                        workspacePath: appState.workspacePath,
                                        onSelectFile: onSelectWorkspaceEntry,
                                        onRefreshTree: onRefreshTree,
                                        expandedFolders: $expandedFolders
                                    )
                                }

                                ForEach(appState.mcpServers) { server in
                                    HStack(spacing: ShellSidebarMetrics.rowSpacing) {
                                        Image(systemName: "powerplug")
                                            .font(ShellZoomMetrics.font(Typography.bodySmall))
                                            .foregroundStyle(.secondary)
                                            .frame(width: ShellZoomMetrics.size(14))
                                        VStack(alignment: .leading, spacing: 0) {
                                            Text(server.name)
                                                .font(ShellZoomMetrics.font(Typography.body))
                                                .lineLimit(1)
                                            Text(server.command)
                                                .font(ShellZoomMetrics.font(Typography.caption))
                                                .foregroundStyle(.secondary)
                                                .lineLimit(1)
                                                .truncationMode(.middle)
                                        }
                                        Spacer(minLength: 0)
                                    }
                                    .padding(.horizontal, ShellSidebarMetrics.rowHorizontalPadding)
                                    .padding(.vertical, ShellSidebarMetrics.rowVerticalPadding)
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, ShellSidebarMetrics.sectionHorizontalPadding)
            .padding(.bottom, ShellZoomMetrics.size(14))
        }
        .task(id: appState.workspacePath) {
            guard appState.workspacePath != nil,
                  appState.fileTree.isEmpty else { return }
            onRefreshTree()
        }
    }

    private var hasAgentSidebarEntries: Bool {
        !appState.agentSkills.isEmpty || !appState.mcpServers.isEmpty
    }
}

// MARK: - Settings Sidebar

struct SettingsSidebarView: View {
    @Bindable var appState: AppState

    private var tabs: [SettingsTabDescriptor] {
        BugbookFeatureGate.visibleSettingsTabs
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                appState.showSettings = false
            } label: {
                HStack(spacing: ShellZoomMetrics.size(6)) {
                    Image(systemName: "arrow.left")
                        .font(ShellZoomMetrics.font(Typography.bodySmall))
                    Text("Back to app")
                        .font(ShellZoomMetrics.font(Typography.bodySmall))
                }
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, ShellZoomMetrics.size(12))
            .padding(.top, ShellSidebarMetrics.windowChromeTopInset + ShellSidebarMetrics.titleTopPadding)
            .padding(.bottom, ShellZoomMetrics.size(16))

            Text("Settings")
                .font(ShellZoomMetrics.font(Typography.caption, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, ShellZoomMetrics.size(12))
                .padding(.bottom, ShellSidebarMetrics.titleBottomPadding)

            VStack(spacing: ShellZoomMetrics.size(2)) {
                ForEach(tabs, id: \.id) { tab in
                    Button {
                        appState.selectedSettingsTab = tab.id
                    } label: {
                        HStack(spacing: ShellZoomMetrics.size(10)) {
                            Image(systemName: tab.icon)
                                .font(ShellZoomMetrics.font(12))
                                .frame(width: ShellZoomMetrics.size(14))
                            Text(tab.label)
                                .font(ShellZoomMetrics.font(Typography.body, weight: appState.selectedSettingsTab == tab.id ? .medium : .regular))
                            Spacer(minLength: 0)
                        }
                        .foregroundStyle(appState.selectedSettingsTab == tab.id ? Color.accentColor : .primary)
                        .padding(.horizontal, ShellSidebarMetrics.rowHorizontalPadding)
                        .padding(.vertical, ShellSidebarMetrics.rowVerticalPadding)
                        .background(
                            RoundedRectangle(cornerRadius: ShellZoomMetrics.size(Radius.sm))
                                .fill(appState.selectedSettingsTab == tab.id ? Color.accentColor.opacity(0.08) : Color.clear)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, ShellSidebarMetrics.sectionHorizontalPadding)

            Spacer(minLength: 0)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Container.groutBg)
    }
}

// MARK: - Mail Contextual Sidebar

struct MailContextualSidebarView: View {
    @Bindable var appState: AppState
    var mailService: MailService
    let onRefresh: () -> Void

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: ShellSidebarMetrics.sectionSpacing) {
                VStack(alignment: .leading, spacing: 0) {
                    if !appState.settings.googleConnectedEmail.isEmpty {
                        HStack(spacing: ShellZoomMetrics.size(8)) {
                            Circle()
                                .fill(Color.accentColor)
                                .frame(width: ShellZoomMetrics.size(8), height: ShellZoomMetrics.size(8))
                            Text(appState.settings.googleConnectedEmail)
                                .font(ShellZoomMetrics.font(Typography.caption))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, ShellZoomMetrics.size(12))
                        .padding(.bottom, ShellZoomMetrics.size(10))
                    }

                    Button(action: { mailService.presentNewComposer() }) {
                        Label("Compose", systemImage: "square.and.pencil")
                            .font(ShellZoomMetrics.font(Typography.body, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, ShellZoomMetrics.size(10))
                            .background(
                                RoundedRectangle(cornerRadius: ShellZoomMetrics.size(Radius.md))
                                    .fill(Color.accentColor)
                            )
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, ShellSidebarMetrics.sectionHorizontalPadding)
                    .padding(.bottom, ShellZoomMetrics.size(8))

                    VStack(spacing: ShellZoomMetrics.size(4)) {
                        ForEach(MailMailbox.allCases) { mailbox in
                            ShellSidebarShortcutRow(
                                title: mailbox.displayName,
                                systemImage: mailbox.systemImage,
                                trailingText: badgeCount(for: mailbox),
                                isSelected: mailService.selectedMailbox == mailbox
                            ) {
                                mailService.selectMailbox(mailbox)
                                onRefresh()
                            }
                        }
                    }
                    .padding(.horizontal, ShellSidebarMetrics.sectionHorizontalPadding)
                }
            }
            .padding(.bottom, ShellZoomMetrics.size(14))
        }
    }

    private func badgeCount(for mailbox: MailMailbox) -> String? {
        let count = mailService.mailboxThreads[mailbox]?.count ?? 0
        return count > 0 ? "\(count)" : nil
    }
}

// MARK: - Calendar Contextual Sidebar

struct CalendarContextualSidebarView: View {
    @Bindable var calendarVM: CalendarViewModel
    var calendarService: CalendarService
    let workspacePath: String?

    var body: some View {
        let sources = calendarService.sources.map { $0 }

        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: ShellSidebarMetrics.sectionSpacing) {
                VStack(alignment: .leading, spacing: 0) {
                    MiniCalendarView(selectedDate: $calendarVM.selectedDate)
                        .padding(.horizontal, ShellZoomMetrics.size(10))
                        .padding(.bottom, ShellZoomMetrics.size(12))

                    Text("Calendars")
                        .font(ShellZoomMetrics.font(Typography.caption, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, ShellZoomMetrics.size(12))
                        .padding(.bottom, ShellZoomMetrics.size(8))

                    CalendarSourceListView(
                        sources: sources,
                        workspacePath: workspacePath,
                        calendarService: calendarService
                    )
                    .padding(.horizontal, ShellSidebarMetrics.sectionHorizontalPadding)
                }
            }
            .padding(.bottom, ShellZoomMetrics.size(14))
        }
    }
}

// MARK: - Calendar Source Views

private struct CalendarSourceRow: View {
    let source: CalendarSource
    let workspacePath: String?
    let calendarService: CalendarService
    @State private var isHovering = false

    var body: some View {
        Button {
            guard let workspacePath else { return }
            calendarService.toggleSourceVisibility(id: source.id, workspace: workspacePath)
        } label: {
            HStack(spacing: ShellZoomMetrics.size(8)) {
                Circle()
                    .fill(TagColor.color(for: source.color))
                    .frame(width: ShellZoomMetrics.size(8), height: ShellZoomMetrics.size(8))
                Text(source.name)
                    .font(ShellZoomMetrics.font(Typography.bodySmall))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if isHovering || !source.isVisible {
                    Image(systemName: source.isVisible ? "eye" : "eye.slash")
                        .font(ShellZoomMetrics.font(Typography.caption))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, ShellSidebarMetrics.rowHorizontalPadding)
            .padding(.vertical, ShellZoomMetrics.size(3))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .contextMenu {
            ForEach(CalendarSourceListView.tagColorNames, id: \.self) { colorName in
                Button {
                    guard let workspacePath else { return }
                    calendarService.updateSourceColor(id: source.id, color: colorName, workspace: workspacePath)
                } label: {
                    Label {
                        Text(colorName.capitalized)
                    } icon: {
                        Image(systemName: source.color == colorName ? "checkmark.circle.fill" : "circle.fill")
                    }
                }
                .tint(TagColor.color(for: colorName))
            }
        }
    }
}

private struct CalendarSourceListView: View {
    static let tagColorNames = ["blue", "green", "red", "yellow", "purple", "pink", "orange", "teal", "gray"]

    let sources: [CalendarSource]
    let workspacePath: String?
    let calendarService: CalendarService

    var body: some View {
        VStack(alignment: .leading, spacing: ShellZoomMetrics.size(1)) {
            ForEach(sources, id: \CalendarSource.id) { (source: CalendarSource) in
                CalendarSourceRow(source: source, workspacePath: workspacePath, calendarService: calendarService)
            }
        }
    }
}

// MARK: - Mini Calendar

private struct MiniCalendarView: View {
    @Binding var selectedDate: Date
    private let calendar = Calendar.current

    private var monthInterval: DateInterval {
        calendar.dateInterval(of: .month, for: selectedDate) ?? DateInterval(start: selectedDate, duration: 86400 * 31)
    }

    private var displayDays: [Date] {
        guard let firstWeek = calendar.dateInterval(of: .weekOfMonth, for: monthInterval.start),
              let lastWeek = calendar.dateInterval(of: .weekOfMonth, for: monthInterval.end.addingTimeInterval(-1)) else {
            return [selectedDate]
        }

        var days: [Date] = []
        var current = firstWeek.start
        while current < lastWeek.end {
            days.append(current)
            current = calendar.date(byAdding: .day, value: 1, to: current) ?? current.addingTimeInterval(86400)
        }
        return days
    }

    var body: some View {
        VStack(spacing: ShellZoomMetrics.size(6)) {
            Text(selectedDate.formatted(.dateTime.month(.wide).year()))
                .font(ShellZoomMetrics.font(Typography.caption, weight: .semibold))

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: ShellZoomMetrics.size(4)), count: 7),
                spacing: ShellZoomMetrics.size(4)
            ) {
                ForEach(calendar.shortWeekdaySymbols.map { String($0.prefix(2)).uppercased() }, id: \.self) { symbol in
                    Text(symbol)
                        .font(ShellZoomMetrics.font(9, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }

                ForEach(displayDays, id: \.self) { day in
                    Button {
                        selectedDate = day
                    } label: {
                        Text("\(calendar.component(.day, from: day))")
                            .font(ShellZoomMetrics.font(11, weight: dayFontWeight(day)))
                            .foregroundStyle(dayForeground(day))
                            .frame(maxWidth: .infinity, minHeight: ShellZoomMetrics.size(22))
                            .background(
                                RoundedRectangle(cornerRadius: ShellZoomMetrics.size(Radius.sm))
                                    .fill(dayBackground(day))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(ShellZoomMetrics.size(10))
        .background(
            RoundedRectangle(cornerRadius: ShellZoomMetrics.size(Radius.md))
            .fill(Color.primary.opacity(0.03))
        )
    }

    private func isSelectedDay(_ day: Date) -> Bool {
        calendar.isDate(day, inSameDayAs: selectedDate)
    }

    private func dayFontWeight(_ day: Date) -> Font.Weight {
        isSelectedDay(day) ? .semibold : .regular
    }

    private func dayForeground(_ day: Date) -> Color {
        if isSelectedDay(day) {
            return .white
        }
        if calendar.isDate(day, equalTo: selectedDate, toGranularity: .month) {
            return .primary
        }
        return .secondary
    }

    private func dayBackground(_ day: Date) -> Color {
        isSelectedDay(day) ? Color.accentColor : Color.clear
    }
}
