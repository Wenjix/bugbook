import Foundation

enum BugbookAppMode: String {
    case notesMeetings
    case legacyPanes
}

struct SettingsTabDescriptor: Identifiable, Equatable {
    let id: String
    let label: String
    let icon: String
}

enum BugbookFeatureGate {
    static let legacyPanesDefaultsKey = "Bugbook.LegacyPanesEnabled"
    private static let legacyPanesEnvironmentKey = "BUGBOOK_LEGACY_PANES"

    static var mode: BugbookAppMode {
        legacyPanesEnabled ? .legacyPanes : .notesMeetings
    }

    static var legacyPanesEnabled: Bool {
        resolvedLegacyPanesEnabled(
            defaultsEnabled: UserDefaults.standard.bool(forKey: legacyPanesDefaultsKey),
            environment: ProcessInfo.processInfo.environment
        )
    }

    static func resolvedLegacyPanesEnabled(defaultsEnabled: Bool, environment: [String: String]) -> Bool {
        let value = environment[legacyPanesEnvironmentKey]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        switch value {
        case "1", "true", "yes", "on":
            return true
        case "0", "false", "no", "off":
            return false
        default:
            return defaultsEnabled
        }
    }

    static var shouldInitializeLegacyServices: Bool {
        legacyPanesEnabled
    }

    static var shouldWarmTranscriptionAtLaunch: Bool {
        false
    }

    static var shouldStartMeetingNotificationPolling: Bool {
        legacyPanesEnabled
    }

    static var shouldExposeAgentSurfaces: Bool {
        legacyPanesEnabled
    }

    static var shouldRestoreWorkspaceDocumentsAtLaunch: Bool {
        legacyPanesEnabled
    }

    static var shouldScanLegacyWorkspaces: Bool {
        legacyPanesEnabled
    }

    static var shouldRegisterSearchIndexAtLaunch: Bool {
        legacyPanesEnabled
    }

    static var shouldAutoOpenOnboardingAtLaunch: Bool {
        legacyPanesEnabled
    }

    static var defaultSplitPaneContent: PaneContent {
        legacyPanesEnabled ? .terminal() : .emptyDocument()
    }

    static var visibleSettingsTabs: [SettingsTabDescriptor] {
        if legacyPanesEnabled {
            return [
                SettingsTabDescriptor(id: "general", label: "General", icon: "gearshape"),
                SettingsTabDescriptor(id: "appearance", label: "Appearance", icon: "paintbrush"),
                SettingsTabDescriptor(id: "meetings", label: "Meetings", icon: "waveform"),
                SettingsTabDescriptor(id: "search", label: "Search", icon: "magnifyingglass"),
                SettingsTabDescriptor(id: "ai", label: "AI", icon: "cpu"),
                SettingsTabDescriptor(id: "google", label: "Google", icon: "person.badge.key"),
                SettingsTabDescriptor(id: "terminal", label: "Terminal", icon: "terminal"),
                SettingsTabDescriptor(id: "browser", label: "Browser", icon: "globe"),
                SettingsTabDescriptor(id: "agents", label: "Agents", icon: "person.2"),
                SettingsTabDescriptor(id: "shortcuts", label: "Shortcuts", icon: "keyboard"),
            ]
        }

        return [
            SettingsTabDescriptor(id: "general", label: "General", icon: "gearshape"),
            SettingsTabDescriptor(id: "appearance", label: "Appearance", icon: "paintbrush"),
            SettingsTabDescriptor(id: "meetings", label: "Meetings", icon: "waveform"),
            SettingsTabDescriptor(id: "search", label: "Search", icon: "magnifyingglass"),
            SettingsTabDescriptor(id: "shortcuts", label: "Shortcuts", icon: "keyboard"),
        ]
    }

    static func allowsSettingsTab(_ tabID: String) -> Bool {
        visibleSettingsTabs.contains { $0.id == tabID }
    }

    static func normalizedSettingsTab(_ tabID: String) -> String {
        allowsSettingsTab(tabID) ? tabID : "general"
    }

    static func allowsTabKind(_ kind: TabKind) -> Bool {
        switch kind {
        case .page, .database, .databaseRow, .meetings:
            return true
        case .mail, .calendar, .browser, .graphView, .skill, .gateway, .chat:
            return legacyPanesEnabled
        }
    }

    static func allowsViewMode(_ viewMode: ViewMode) -> Bool {
        switch viewMode {
        case .editor:
            return true
        case .chat, .graphView, .calendar:
            return legacyPanesEnabled
        }
    }

    static func allowsPaneContent(_ content: PaneContent) -> Bool {
        switch content {
        case .terminal:
            return legacyPanesEnabled
        case .document(let file):
            if file.isEmptyTab {
                return true
            }
            return allowsTabKind(file.kind)
        }
    }

    static func sanitizedContent(_ content: PaneContent) -> PaneContent {
        guard !allowsPaneContent(content) else { return content }
        return .emptyDocument(id: content.id)
    }

    static var paneLauncherBuiltInPanes: [(label: String, icon: String, content: PaneContent)] {
        if legacyPanesEnabled {
            return [
                ("Browser", "globe", .browserDocument()),
                ("Terminal", "terminal", .terminal()),
                ("Home", "house", .emptyDocument()),
                ("Mail", "envelope", .mailDocument()),
                ("Calendar", "calendar", .calendarDocument()),
                ("Meetings", "person.2", .meetingsDocument()),
                ("Gateway", "square.grid.2x2", .gatewayDocument()),
            ]
        }

        return [
            ("Notes", "doc.text", .emptyDocument()),
            ("Meeting", "waveform", .meetingsDocument()),
        ]
    }

    static func allowsNotification(_ name: Notification.Name) -> Bool {
        guard !legacyPanesEnabled else { return true }
        let blocked: Set<String> = [
            Notification.Name.openAIPanel.rawValue,
            Notification.Name.askAI.rawValue,
            Notification.Name.openGraphView.rawValue,
            Notification.Name.openMail.rawValue,
            Notification.Name.openCalendar.rawValue,
            Notification.Name.openGateway.rawValue,
            Notification.Name.openTerminal.rawValue,
            Notification.Name.openBrowser.rawValue,
            Notification.Name.browserFocusAddressBar.rawValue,
            Notification.Name.browserPrint.rawValue,
        ]
        return !blocked.contains(name.rawValue)
    }

    static func allowsSidebarItem(id: String) -> Bool {
        guard !legacyPanesEnabled else { return true }
        return id == "meeting" || id == "notes"
    }
}

extension PaneNode.Leaf {
    func sanitizedForCurrentMode() -> (leaf: PaneNode.Leaf, changed: Bool) {
        var changed = false
        let selectedID = activeTabID
        var nextTabs: [PaneContent] = []
        nextTabs.reserveCapacity(tabs.count)

        for tab in tabs {
            guard BugbookFeatureGate.allowsPaneContent(tab) else {
                changed = true
                continue
            }
            nextTabs.append(tab)
        }

        if nextTabs.isEmpty {
            nextTabs = [.emptyDocument(id: id)]
            changed = true
        }

        var nextSelectedIndex = nextTabs.firstIndex { $0.id == selectedID } ?? 0
        nextSelectedIndex = min(max(nextSelectedIndex, 0), nextTabs.count - 1)

        if nextSelectedIndex != selectedTabIndex {
            changed = true
        }

        return (
            PaneNode.Leaf(id: id, tabs: nextTabs, selectedTabIndex: nextSelectedIndex),
            changed
        )
    }
}

extension PaneNode {
    func sanitizedForCurrentMode() -> (node: PaneNode, changed: Bool) {
        switch self {
        case .leaf(let leaf):
            let result = leaf.sanitizedForCurrentMode()
            return (.leaf(result.leaf), result.changed)
        case .split(let split):
            let first = split.first.sanitizedForCurrentMode()
            let second = split.second.sanitizedForCurrentMode()
            return (
                .split(PaneNode.Split(
                    id: split.id,
                    axis: split.axis,
                    ratio: split.ratio,
                    first: first.node,
                    second: second.node
                )),
                first.changed || second.changed
            )
        }
    }
}

extension Workspace {
    func sanitizedForCurrentMode() -> (workspace: Workspace, changed: Bool) {
        let result = root.sanitizedForCurrentMode()
        let nextFocusedPaneId = result.node.findLeaf(id: focusedPaneId)?.id
            ?? result.node.firstLeaf?.id
            ?? focusedPaneId
        let changed = result.changed || nextFocusedPaneId != focusedPaneId

        return (
            Workspace(
                id: id,
                name: name,
                icon: icon,
                root: result.node,
                focusedPaneId: nextFocusedPaneId,
                createdAt: createdAt
            ),
            changed
        )
    }
}
