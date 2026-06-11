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

    /// Always on: in the tabs-only model every restored tab needs its document
    /// loaded at launch, otherwise restored/migrated/reopened tabs render blank.
    static var shouldRestoreWorkspaceDocumentsAtLaunch: Bool {
        true
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

    static var visibleSettingsTabs: [SettingsTabDescriptor] {
        if legacyPanesEnabled {
            return [
                SettingsTabDescriptor(id: "general", label: "General", icon: "gearshape"),
                SettingsTabDescriptor(id: "appearance", label: "Appearance", icon: "paintbrush"),
                SettingsTabDescriptor(id: "meetings", label: "Meetings", icon: "waveform"),
                SettingsTabDescriptor(id: "search", label: "Search", icon: "magnifyingglass"),
                SettingsTabDescriptor(id: "ai", label: "AI", icon: "cpu"),
                SettingsTabDescriptor(id: "google", label: "Google", icon: "person.badge.key"),
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
        case .mail, .calendar, .graphView, .skill, .gateway, .chat:
            return legacyPanesEnabled
        case .removed:
            return false
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

    static func allowsNotification(_ name: Notification.Name) -> Bool {
        guard !legacyPanesEnabled else { return true }
        let blocked: Set<String> = [
            Notification.Name.openAIPanel.rawValue,
            Notification.Name.askAI.rawValue,
            Notification.Name.openGraphView.rawValue,
            Notification.Name.openMail.rawValue,
            Notification.Name.openCalendar.rawValue,
            Notification.Name.openGateway.rawValue,
        ]
        return !blocked.contains(name.rawValue)
    }

    static func allowsSidebarItem(id: String) -> Bool {
        guard !legacyPanesEnabled else { return true }
        return id == "meeting"
    }
}

extension Workspace {
    /// nil = this tab's content is not allowed in the current mode (e.g. a
    /// `.removed`-kind sentinel from an old layout); the caller prunes the tab.
    func sanitizedForCurrentMode() -> Workspace? {
        BugbookFeatureGate.allowsPaneContent(content) ? self : nil
    }
}
