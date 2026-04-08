import SwiftUI
import BugbookCore

enum ShellSidebarMetrics {
    static var defaultWidth: CGFloat { 200 }
    static var minWidth: CGFloat { 150 }
    static var maxWidth: CGFloat { 300 }
    static var windowChromeTopInset: CGFloat { ShellZoomMetrics.size(32) }

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
    let contextualLabel: String?
    @ViewBuilder let contextualContent: () -> ContextualContent

    // All sidebar content shares one horizontal inset so everything aligns.
    private var inset: CGFloat { ShellSidebarMetrics.sectionHorizontalPadding }

    @AppStorage("sidebar_favorites_expanded") private var favoritesExpanded = true
    @State private var expandedFolders: Set<String> = {
        let stored = UserDefaults.standard.stringArray(forKey: "expandedFolders") ?? []
        return Set(stored)
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Sidebar toggle — in the title bar band, aligned with tabs
            HStack {
                Spacer(minLength: 0)
                fixedIconButton("sidebar.left", help: "Toggle Sidebar") {
                    NotificationCenter.default.post(name: .toggleSidebar, object: nil)
                }
            }
            .padding(.top, ShellZoomMetrics.size(6))
            .padding(.trailing, inset)

            // ── Fixed Zone ──────────────────────────────────
            // Icon row: Home, Search
            HStack(spacing: ShellZoomMetrics.size(2)) {
                fixedIconButton("house", help: "Home") {
                    NotificationCenter.default.post(name: .openGateway, object: nil)
                }
                fixedIconButton("magnifyingglass", help: "Search") {
                    NotificationCenter.default.post(name: .quickOpen, object: nil)
                }
                Spacer(minLength: 0)
            }
            .padding(.top, ShellZoomMetrics.size(2))
            .padding(.horizontal, inset)
            .padding(.bottom, ShellZoomMetrics.size(6))

            // Favorites
            if !appState.favorites.isEmpty {
                VStack(alignment: .leading, spacing: ShellZoomMetrics.size(3)) {
                    ShellSidebarSectionHeaderView(title: "Favorites", isExpanded: $favoritesExpanded)

                    if favoritesExpanded {
                        VStack(spacing: ShellZoomMetrics.size(2)) {
                            ForEach(appState.favorites) { entry in
                                FileTreeItemView(
                                    entry: entry,
                                    activeFilePath: activeFilePath,
                                    fileSystem: fileSystem,
                                    workspacePath: appState.workspacePath,
                                    onSelectFile: onSelectEntry,
                                    onRefreshTree: onRefreshTree,
                                    expandedFolders: $expandedFolders
                                )
                            }
                        }
                    }
                }
                .padding(.horizontal, inset)
                .padding(.bottom, ShellZoomMetrics.size(8))
            }

            // ── Contextual Zone ─────────────────────────────
            if let label = contextualLabel {
                Divider()
                    .padding(.horizontal, inset)

                Text(label.uppercased())
                    .font(ShellZoomMetrics.font(Typography.caption, weight: .medium))
                    .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                    .padding(.horizontal, inset)
                    .padding(.top, ShellZoomMetrics.size(8))
                    .padding(.bottom, ShellZoomMetrics.size(4))

                contextualContent()
                    .transition(.opacity.animation(.easeInOut(duration: 0.15)))
            }

            Spacer(minLength: 0)

            // Footer — settings
            Button(action: onOpenSettings) {
                HStack(spacing: ShellZoomMetrics.size(8)) {
                    Image(systemName: "gearshape")
                        .font(ShellZoomMetrics.font(Typography.bodySmall))
                    Text("Settings")
                        .font(ShellZoomMetrics.font(Typography.body))
                    Spacer(minLength: 0)
                }
                .foregroundStyle(.secondary)
                .padding(.vertical, ShellZoomMetrics.size(10))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, inset)
            .padding(.bottom, ShellZoomMetrics.size(8))
        }
        .frame(maxHeight: .infinity)
        .background(Color.fallbackSidebarBg)
        .clipped()
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Color.fallbackChromeBorder)
                .frame(width: 1)
        }
    }

    private func fixedIconButton(_ icon: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(ShellZoomMetrics.font(13, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: ShellZoomMetrics.size(28), height: ShellZoomMetrics.size(28))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
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
    var trailingText: String? = nil
    var isSelected = false
    var action: () -> Void

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
            .padding(.vertical, ShellSidebarMetrics.rowVerticalPadding)
            .background(
                RoundedRectangle(cornerRadius: ShellZoomMetrics.size(Radius.sm))
                    .fill(isSelected ? Color.accentColor.opacity(0.08) : Color.clear)
            )
        }
        .buttonStyle(.plain)
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
            VStack(alignment: .leading, spacing: ShellSidebarMetrics.sectionSpacing) {
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
                if !appState.agentSkills.isEmpty || !appState.mcpServers.isEmpty {
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
    }
}

// MARK: - Settings Sidebar

struct SettingsSidebarView: View {
    @Bindable var appState: AppState

    private let tabs: [(id: String, label: String, icon: String)] = [
        ("general", "General", "gearshape"),
        ("appearance", "Appearance", "paintbrush"),
        ("ai", "AI", "cpu"),
        ("google", "Google", "person.badge.key"),
        ("terminal", "Terminal", "terminal"),
        ("browser", "Browser", "globe"),
        ("agents", "Agents", "person.2"),
        ("search", "Search", "magnifyingglass"),
        ("shortcuts", "Shortcuts", "keyboard"),
    ]

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
        .background(Color.fallbackSidebarBg)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Color.fallbackChromeBorder)
                .frame(width: 1)
        }
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

                    HStack(spacing: ShellZoomMetrics.size(8)) {
                        ForEach(CalendarViewMode.allCases, id: \.self) { mode in
                            Button {
                                calendarVM.viewMode = mode
                            } label: {
                                Text(mode.rawValue)
                                    .font(ShellZoomMetrics.font(11, weight: calendarVM.viewMode == mode ? .medium : .regular))
                                    .foregroundStyle(calendarVM.viewMode == mode ? Color.accentColor : .primary)
                                    .padding(.horizontal, ShellZoomMetrics.size(8))
                                    .padding(.vertical, ShellZoomMetrics.size(5))
                                    .background(
                                        RoundedRectangle(cornerRadius: ShellZoomMetrics.size(Radius.sm))
                                            .fill(calendarVM.viewMode == mode ? Color.accentColor.opacity(0.08) : Color.primary.opacity(0.04))
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, ShellZoomMetrics.size(12))
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

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: ShellZoomMetrics.size(4)), count: 7), spacing: ShellZoomMetrics.size(4)) {
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
                            .font(ShellZoomMetrics.font(11, weight: calendar.isDate(day, inSameDayAs: selectedDate) ? .semibold : .regular))
                            .foregroundStyle(calendar.isDate(day, inSameDayAs: selectedDate) ? .white : (calendar.isDate(day, equalTo: selectedDate, toGranularity: .month) ? .primary : .secondary))
                            .frame(maxWidth: .infinity, minHeight: ShellZoomMetrics.size(22))
                            .background(
                                RoundedRectangle(cornerRadius: ShellZoomMetrics.size(Radius.sm))
                                    .fill(calendar.isDate(day, inSameDayAs: selectedDate) ? Color.accentColor : Color.clear)
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
}
