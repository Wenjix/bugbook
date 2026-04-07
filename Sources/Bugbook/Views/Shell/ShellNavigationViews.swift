import SwiftUI
import BugbookCore

enum ShellSidebarMetrics {
    static var railWidth: CGFloat { ShellZoomMetrics.size(46) }
    static var railButtonSize: CGFloat { ShellZoomMetrics.size(30) }
    static var railGroupSpacing: CGFloat { ShellZoomMetrics.size(6) }
    static var railInset: CGFloat { ShellZoomMetrics.size(6) }
    static var windowChromeTopInset: CGFloat { ShellZoomMetrics.size(32) }

    static var sidebarWidth: CGFloat { ShellZoomMetrics.size(196) }
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

enum RailItemID: String, CaseIterable, Identifiable {
    case home
    case mail
    case calendar
    case browser
    case terminal
    case workspace
    case settings

    var id: String { rawValue }

    var label: String {
        switch self {
        case .home: return "Home"
        case .mail: return "Mail"
        case .calendar: return "Calendar"
        case .browser: return "Browser"
        case .terminal: return "Terminal"
        case .workspace: return "Workspace"
        case .settings: return "Settings"
        }
    }

    var icon: String {
        switch self {
        case .home: return "house"
        case .mail: return "envelope"
        case .calendar: return "calendar.badge.clock"
        case .browser: return "globe"
        case .terminal: return "terminal"
        case .workspace: return "doc.text"
        case .settings: return "gearshape"
        }
    }
}

enum RailIndicatorState {
    case none
    case open
    case focused
}

struct NavigationRailView: View {
    let indicatorProvider: (RailItemID) -> RailIndicatorState
    let onSelect: (RailItemID) -> Void

    @State private var hoveredItem: RailItemID?

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: ShellSidebarMetrics.railGroupSpacing) {
                railButton(.home)
            }

            Divider()
                .padding(.vertical, ShellZoomMetrics.size(10))
                .padding(.horizontal, ShellSidebarMetrics.railInset)

            VStack(spacing: ShellSidebarMetrics.railGroupSpacing) {
                railButton(.mail)
                railButton(.calendar)
                railButton(.browser)
                railButton(.terminal)
                railButton(.workspace)
            }

            Spacer(minLength: ShellZoomMetrics.size(12))

            railButton(.settings)
                .padding(.bottom, ShellZoomMetrics.size(14))
        }
        .padding(.top, ShellSidebarMetrics.windowChromeTopInset)
        .frame(width: ShellSidebarMetrics.railWidth)
        .frame(maxHeight: .infinity)
        .background(Color.fallbackSidebarBg)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Color.fallbackChromeBorder)
                .frame(width: 1)
        }
    }

    private func railButton(_ item: RailItemID) -> some View {
        let indicator = indicatorProvider(item)
        let isHovered = hoveredItem == item

        return Button {
            onSelect(item)
        } label: {
            HStack(spacing: 0) {
                indicatorView(indicator)

                Spacer(minLength: 0)

                Image(systemName: item.icon)
                    .font(ShellZoomMetrics.font(14, weight: .medium))
                    .foregroundStyle(foregroundColor(for: indicator))
                    .frame(width: ShellSidebarMetrics.railButtonSize, height: ShellSidebarMetrics.railButtonSize)

                Spacer(minLength: 0)
            }
            .frame(height: ShellSidebarMetrics.railButtonSize)
            .background(
                RoundedRectangle(cornerRadius: ShellZoomMetrics.size(Radius.sm))
                    .fill(isHovered ? Color.primary.opacity(0.05) : Color.clear)
            )
            .padding(.horizontal, ShellSidebarMetrics.railInset)
        }
        .buttonStyle(.plain)
        .help(item.label)
        .onHover { hovering in
            hoveredItem = hovering ? item : nil
        }
    }

    @ViewBuilder
    private func indicatorView(_ indicator: RailIndicatorState) -> some View {
        switch indicator {
        case .none:
            Color.clear.frame(width: 2)
        case .open:
            Capsule()
                .fill(Color.secondary.opacity(0.45))
                .frame(width: 2, height: ShellZoomMetrics.size(18))
        case .focused:
            Capsule()
                .fill(Color.accentColor)
                .frame(width: 2, height: ShellZoomMetrics.size(18))
        }
    }

    private func foregroundColor(for indicator: RailIndicatorState) -> Color {
        switch indicator {
        case .none:
            return .secondary
        case .open:
            return .primary
        case .focused:
            return .accentColor
        }
    }
}

private struct ShellSidebarFrame<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .padding(.top, ShellSidebarMetrics.windowChromeTopInset)
        .frame(width: ShellSidebarMetrics.sidebarWidth)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color.fallbackSidebarBg)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Color.fallbackChromeBorder)
                .frame(width: 1)
        }
    }
}

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

private struct WorkspaceSidebarModuleView: View {
    @Bindable var appState: AppState
    var fileSystem: FileSystemService
    let activeFilePath: String?
    let onSelectEntry: (FileEntry) -> Void
    let onRefreshTree: () -> Void

    @AppStorage("sidebar_favorites_expanded") private var favoritesExpanded = true
    @AppStorage("sidebar_agents_expanded") private var agentsExpanded = true
    @AppStorage("sidebar_workspace_expanded") private var workspaceExpanded = true
    @State private var expandedFolders: Set<String> = {
        let stored = UserDefaults.standard.stringArray(forKey: "expandedFolders") ?? []
        return Set(stored)
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: ShellSidebarMetrics.sectionSpacing) {
            if !appState.favorites.isEmpty {
                VStack(alignment: .leading, spacing: ShellZoomMetrics.size(4)) {
                    ShellSidebarSectionHeaderView(title: "Favorites", isExpanded: $favoritesExpanded)
                    if favoritesExpanded {
                        VStack(spacing: ShellZoomMetrics.size(3)) {
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
            }

            VStack(alignment: .leading, spacing: ShellZoomMetrics.size(4)) {
                ShellSidebarSectionHeaderView(title: "Workspace", isExpanded: $workspaceExpanded)

                if workspaceExpanded {
                    VStack(alignment: .leading, spacing: ShellZoomMetrics.size(4)) {
                        ShellSidebarShortcutRow(title: "Today", systemImage: "calendar") {
                            NotificationCenter.default.post(name: .openDailyNote, object: nil)
                        }

                        ShellSidebarShortcutRow(title: "Graph", systemImage: "point.3.connected.trianglepath.dotted") {
                            NotificationCenter.default.post(name: .openGraphView, object: nil)
                        }

                        if !appState.sidebarReferences.isEmpty {
                            VStack(spacing: ShellZoomMetrics.size(1)) {
                                ForEach(appState.sidebarReferences) { entry in
                                    FileTreeItemView(
                                        entry: entry,
                                        activeFilePath: activeFilePath,
                                        fileSystem: fileSystem,
                                        workspacePath: appState.workspacePath,
                                        onSelectFile: onSelectEntry,
                                        onRefreshTree: onRefreshTree,
                                        isSidebarReference: true,
                                        expandedFolders: $expandedFolders
                                    )
                                }
                            }
                            .padding(.top, ShellZoomMetrics.size(2))
                        }

                        FileTreeView(
                            entries: fileTreeWithoutFavorites,
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
                                    onSelectFile: onSelectEntry,
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
    }

    private var fileTreeWithoutFavorites: [FileEntry] {
        let favoritePaths = Set(appState.favorites.map(\.path))
        guard !favoritePaths.isEmpty else { return appState.fileTree }
        return appState.fileTree.filter { !favoritePaths.contains($0.path) }
    }
}

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
        ShellSidebarFrame {
            VStack(alignment: .leading, spacing: 0) {
                Text("Settings")
                    .font(ShellZoomMetrics.font(Typography.caption, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, ShellZoomMetrics.size(12))
                    .padding(.top, ShellSidebarMetrics.titleTopPadding)
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
        }
    }
}

struct MailContextualSidebarView: View {
    @Bindable var appState: AppState
    var mailService: MailService
    let onRefresh: () -> Void

    var body: some View {
        ShellSidebarFrame {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: ShellSidebarMetrics.sectionSpacing) {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack {
                            Text("Mail")
                                .font(ShellZoomMetrics.font(Typography.caption, weight: .semibold))
                                .foregroundStyle(.secondary)
                            Spacer(minLength: 0)
                            Button(action: onRefresh) {
                                Image(systemName: "arrow.clockwise")
                                    .font(ShellZoomMetrics.font(11, weight: .medium))
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, ShellZoomMetrics.size(12))
                        .padding(.top, ShellSidebarMetrics.titleTopPadding)
                        .padding(.bottom, ShellZoomMetrics.size(8))

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
    }

    private func badgeCount(for mailbox: MailMailbox) -> String? {
        let count = mailService.mailboxThreads[mailbox]?.count ?? 0
        return count > 0 ? "\(count)" : nil
    }
}

struct CalendarContextualSidebarView: View {
    @Bindable var calendarVM: CalendarViewModel
    var calendarService: CalendarService
    let workspacePath: String?

    var body: some View {
        let sources = calendarService.sources.map { $0 }

        ShellSidebarFrame {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: ShellSidebarMetrics.sectionSpacing) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Calendar")
                            .font(ShellZoomMetrics.font(Typography.caption, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, ShellZoomMetrics.size(12))
                            .padding(.top, ShellSidebarMetrics.titleTopPadding)
                            .padding(.bottom, ShellSidebarMetrics.titleBottomPadding)

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
}

struct WorkspaceContextualSidebarView: View {
    @Bindable var appState: AppState
    var fileSystem: FileSystemService
    let activeFilePath: String?
    var title = "Workspace"
    let onSelectWorkspaceEntry: (FileEntry) -> Void
    let onRefreshTree: () -> Void

    var body: some View {
        ShellSidebarFrame {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(title)
                        .font(ShellZoomMetrics.font(Typography.caption, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, ShellZoomMetrics.size(12))
                        .padding(.top, ShellSidebarMetrics.titleTopPadding)
                        .padding(.bottom, ShellSidebarMetrics.titleBottomPadding)

                    WorkspaceSidebarModuleView(
                        appState: appState,
                        fileSystem: fileSystem,
                        activeFilePath: activeFilePath,
                        onSelectEntry: onSelectWorkspaceEntry,
                        onRefreshTree: onRefreshTree
                    )
                }
                .padding(.bottom, ShellZoomMetrics.size(14))
            }
        }
    }
}

private struct CalendarSourceListView: View {
    private static let tagColorNames = ["blue", "green", "red", "yellow", "purple", "pink", "orange", "teal", "gray"]

    let sources: [CalendarSource]
    let workspacePath: String?
    let calendarService: CalendarService

    var body: some View {
        VStack(alignment: .leading, spacing: ShellZoomMetrics.size(6)) {
            ForEach(sources, id: \CalendarSource.id) { (source: CalendarSource) in
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
                        Image(systemName: source.isVisible ? "checkmark.circle.fill" : "circle")
                            .font(ShellZoomMetrics.font(Typography.bodySmall))
                            .foregroundStyle(source.isVisible ? Color.accentColor : .secondary)
                    }
                    .padding(.horizontal, ShellSidebarMetrics.rowHorizontalPadding)
                    .padding(.vertical, ShellSidebarMetrics.rowVerticalPadding)
                    .background(
                        RoundedRectangle(cornerRadius: ShellZoomMetrics.size(Radius.sm))
                            .fill(Color.primary.opacity(0.03))
                    )
                }
                .buttonStyle(.plain)
                .contextMenu {
                    ForEach(Self.tagColorNames, id: \.self) { colorName in
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
    }
}

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
