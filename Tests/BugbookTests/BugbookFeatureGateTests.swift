import XCTest
@testable import Bugbook

@MainActor
final class BugbookFeatureGateTests: XCTestCase {
    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: BugbookFeatureGate.legacyPanesDefaultsKey)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: BugbookFeatureGate.legacyPanesDefaultsKey)
        super.tearDown()
    }

    func testDefaultModeShowsOnlyMeetingAndNotesSidebarItems() {
        XCTAssertEqual(ShellNavigationItems.visible.map(\.id), ["meeting", "notes"])
    }

    func testEnvironmentOverrideCanEnableLegacyPanes() {
        XCTAssertTrue(BugbookFeatureGate.resolvedLegacyPanesEnabled(
            defaultsEnabled: false,
            environment: ["BUGBOOK_LEGACY_PANES": "true"]
        ))
        XCTAssertTrue(BugbookFeatureGate.resolvedLegacyPanesEnabled(
            defaultsEnabled: false,
            environment: ["BUGBOOK_LEGACY_PANES": "1"]
        ))
    }

    func testEnvironmentOverrideCanDisablePersistedLegacyPanes() {
        XCTAssertFalse(BugbookFeatureGate.resolvedLegacyPanesEnabled(
            defaultsEnabled: true,
            environment: ["BUGBOOK_LEGACY_PANES": "false"]
        ))
        XCTAssertFalse(BugbookFeatureGate.resolvedLegacyPanesEnabled(
            defaultsEnabled: true,
            environment: ["BUGBOOK_LEGACY_PANES": "0"]
        ))
    }

    func testInvalidEnvironmentOverrideFallsBackToDefaults() {
        XCTAssertTrue(BugbookFeatureGate.resolvedLegacyPanesEnabled(
            defaultsEnabled: true,
            environment: ["BUGBOOK_LEGACY_PANES": "unexpected"]
        ))
        XCTAssertFalse(BugbookFeatureGate.resolvedLegacyPanesEnabled(
            defaultsEnabled: false,
            environment: [:]
        ))
    }

    func testDefaultModeKeepsOnlyDailyDriverSettingsVisible() {
        XCTAssertEqual(
            BugbookFeatureGate.visibleSettingsTabs.map(\.id),
            ["general", "appearance", "meetings", "search", "shortcuts"]
        )
        XCTAssertEqual(BugbookFeatureGate.normalizedSettingsTab("ai"), "general")
    }

    func testDefaultModeHidesAgentSurfaces() {
        XCTAssertFalse(BugbookFeatureGate.shouldExposeAgentSurfaces)
        XCTAssertFalse(BugbookFeatureGate.allowsTabKind(.skill))
    }

    func testDefaultModeDirectAgentSurfaceCallsClearTransientState() {
        let state = AppState()
        state.aiSidePanelOpen = true
        state.aiInitialPrompt = "summarize this"
        state.aiSelectionContext = "selected blocks"
        state.aiReferencedItems = [.page(path: "/tmp/Daily.md", name: "Daily.md")]
        state.agentSkills = [
            FileEntry(id: "/tmp/skill.md", name: "skill.md", path: "/tmp/skill.md", isDirectory: false)
        ]
        state.mcpServers = [MCPServerInfo(name: "local", command: "qmd")]
        state.currentView = .chat

        state.openNotesChat()

        XCTAssertFalse(state.aiSidePanelOpen)
        XCTAssertNil(state.aiInitialPrompt)
        XCTAssertNil(state.aiSelectionContext)
        XCTAssertTrue(state.aiReferencedItems.isEmpty)
        XCTAssertTrue(state.agentSkills.isEmpty)
        XCTAssertTrue(state.mcpServers.isEmpty)
        XCTAssertEqual(state.currentView, .editor)

        state.aiInitialPrompt = "ask again"
        state.toggleAiPanel(prompt: "ask again")
        XCTAssertFalse(state.aiSidePanelOpen)
        XCTAssertNil(state.aiInitialPrompt)

        state.aiSelectionContext = "selection"
        state.openAiPanel(prompt: "direct")
        XCTAssertFalse(state.aiSidePanelOpen)
        XCTAssertNil(state.aiSelectionContext)
        XCTAssertNil(state.aiInitialPrompt)
    }

    func testDefaultModeDisablesLegacyRuntimeWork() {
        XCTAssertFalse(BugbookFeatureGate.shouldInitializeLegacyServices)
        XCTAssertFalse(BugbookFeatureGate.shouldStartMeetingNotificationPolling)
        XCTAssertFalse(BugbookFeatureGate.shouldWarmTranscriptionAtLaunch)
        XCTAssertFalse(BugbookFeatureGate.shouldExposeAgentSurfaces)
        XCTAssertFalse(BugbookFeatureGate.shouldRestoreWorkspaceDocumentsAtLaunch)
        XCTAssertFalse(BugbookFeatureGate.shouldScanLegacyWorkspaces)
        XCTAssertFalse(BugbookFeatureGate.shouldRegisterSearchIndexAtLaunch)
        XCTAssertFalse(BugbookFeatureGate.shouldAutoOpenOnboardingAtLaunch)

        let blockedNotifications: [Notification.Name] = [
            .openAIPanel,
            .askAI,
            .openGraphView,
            .openMail,
            .openCalendar,
            .openGateway,
            .openTerminal,
            .openBrowser,
            .browserFocusAddressBar,
            .browserPrint
        ]
        for notification in blockedNotifications {
            XCTAssertFalse(BugbookFeatureGate.allowsNotification(notification), "\(notification.rawValue) should be gated")
        }

        XCTAssertTrue(BugbookFeatureGate.allowsNotification(.openDailyNote))
        XCTAssertTrue(BugbookFeatureGate.allowsNotification(.openMeetings))
    }

    func testAppStateLegacyWorkspaceRefreshIsNoopInDefaultMode() async {
        let state = AppState()
        let legacyWorkspace = FileSystemService.LegacyWorkspace(
            path: URL(fileURLWithPath: "/tmp/legacy-workspace", isDirectory: true),
            kind: .applicationSupportBugbook
        )

        state.legacyWorkspaces = [legacyWorkspace]
        state.refreshLegacyWorkspaces(using: FileSystemService())
        XCTAssertTrue(state.legacyWorkspaces.isEmpty)

        state.legacyWorkspaces = [legacyWorkspace]
        await state.refreshLegacyWorkspacesInBackground(using: FileSystemService())
        XCTAssertTrue(state.legacyWorkspaces.isEmpty)
    }

    func testDefaultModeAllowsOnlyNotesMeetingAndDatabasePaneContent() {
        XCTAssertTrue(BugbookFeatureGate.allowsPaneContent(.emptyDocument()))
        XCTAssertTrue(BugbookFeatureGate.allowsPaneContent(.meetingsDocument()))
        XCTAssertTrue(BugbookFeatureGate.allowsPaneContent(.document(openFile: OpenFile(
            id: UUID(),
            path: "/tmp/Note.md",
            content: "",
            isDirty: false,
            isEmptyTab: false,
            kind: .page
        ))))
        XCTAssertTrue(BugbookFeatureGate.allowsTabKind(.database))

        XCTAssertFalse(BugbookFeatureGate.allowsPaneContent(.browserDocument()))
        XCTAssertFalse(BugbookFeatureGate.allowsPaneContent(.terminal()))
        XCTAssertFalse(BugbookFeatureGate.allowsPaneContent(.mailDocument()))
        XCTAssertFalse(BugbookFeatureGate.allowsPaneContent(.calendarDocument()))
        XCTAssertFalse(BugbookFeatureGate.allowsPaneContent(.gatewayDocument()))
        XCTAssertFalse(BugbookFeatureGate.allowsPaneContent(.graphDocument()))
    }

    func testDefaultModeAllowsOnlyEditorViewMode() {
        XCTAssertTrue(BugbookFeatureGate.allowsViewMode(.editor))
        XCTAssertFalse(BugbookFeatureGate.allowsViewMode(.chat))
        XCTAssertFalse(BugbookFeatureGate.allowsViewMode(.graphView))
        XCTAssertFalse(BugbookFeatureGate.allowsViewMode(.calendar))
    }

    func testDefaultPaneLaunchersExposeOnlyNotesAndMeeting() {
        XCTAssertEqual(BugbookFeatureGate.paneLauncherBuiltInPanes.map(\.label), ["Notes", "Meeting"])
        XCTAssertEqual(CommandPaletteCreateKind.availableCases.map(\.id), ["page", "meetings"])
    }

    func testDefaultShortcutCatalogsHideLegacyPaneShortcuts() {
        let overlayLabels = (
            KeyboardShortcutCatalog.primarySections + KeyboardShortcutCatalog.secondarySections
        ).flatMap(\.shortcuts).map(\.label) + KeyboardShortcutCatalog.workflows.map(\.label)
        let settingsLabels = ShortcutsSettingsCatalog.sections.flatMap(\.shortcuts).map(\.label)

        for hiddenLabel in [
            "Home",
            "Mail",
            "Calendar",
            "Chat drawer",
            "Focus browser URL bar",
            "Print",
            "Open Calendar beside current pane",
            "Open Mail beside current pane",
            "New workspace tab with Home",
            "Toggle Chat Drawer",
            "Focus URL Bar",
            "Save Browser Page",
        ] {
            XCTAssertFalse(overlayLabels.contains(hiddenLabel), "\(hiddenLabel) should be hidden in overlay")
            XCTAssertFalse(settingsLabels.contains(hiddenLabel), "\(hiddenLabel) should be hidden in settings")
        }

        XCTAssertTrue(overlayLabels.contains("Today's note"))
        XCTAssertTrue(settingsLabels.contains("Today's Note"))
        XCTAssertTrue(settingsLabels.contains("Save Note"))

        let overlayShortcuts = (
            KeyboardShortcutCatalog.primarySections + KeyboardShortcutCatalog.secondarySections
        ).flatMap(\.shortcuts)
        XCTAssertEqual(overlayShortcuts.first { $0.label == "Quick open" }?.keys, "\u{2318}K / \u{2318}\u{21E7}P")
        XCTAssertEqual(overlayShortcuts.first { $0.label == "Split pane down" }?.keys, "\u{2318}\u{2303}D")
        XCTAssertEqual(overlayShortcuts.first { $0.label == "Toggle sidebar" }?.keys, "\u{2318}.")
        XCTAssertFalse(overlayShortcuts.contains { $0.label == "Toggle rail" })
        XCTAssertEqual(settingsShortcutKeys(label: "Quick Open"), "Cmd + K / Cmd + Shift + P")
        XCTAssertEqual(settingsShortcutKeys(label: "Split Pane Down"), "Cmd + Ctrl + D")
        XCTAssertEqual(settingsShortcutKeys(label: "Toggle Sidebar"), "Cmd + .")
    }

    func testLegacyFlagRestoresHiddenPaneAccess() {
        UserDefaults.standard.set(true, forKey: BugbookFeatureGate.legacyPanesDefaultsKey)

        XCTAssertTrue(BugbookFeatureGate.allowsPaneContent(.browserDocument()))
        XCTAssertTrue(BugbookFeatureGate.allowsPaneContent(.terminal()))
        XCTAssertTrue(ShellNavigationItems.visible.contains { $0.id == "browser" })
        XCTAssertTrue(BugbookFeatureGate.visibleSettingsTabs.contains { $0.id == "ai" })
        XCTAssertTrue(BugbookFeatureGate.shouldExposeAgentSurfaces)
        XCTAssertTrue(BugbookFeatureGate.shouldInitializeLegacyServices)
        XCTAssertTrue(BugbookFeatureGate.shouldStartMeetingNotificationPolling)
        XCTAssertTrue(BugbookFeatureGate.shouldRestoreWorkspaceDocumentsAtLaunch)
        XCTAssertTrue(BugbookFeatureGate.shouldScanLegacyWorkspaces)
        XCTAssertTrue(BugbookFeatureGate.shouldRegisterSearchIndexAtLaunch)
        XCTAssertTrue(BugbookFeatureGate.shouldAutoOpenOnboardingAtLaunch)
        XCTAssertTrue(BugbookFeatureGate.allowsNotification(.openBrowser))

        let overlayLabels = (
            KeyboardShortcutCatalog.primarySections + KeyboardShortcutCatalog.secondarySections
        ).flatMap(\.shortcuts).map(\.label) + KeyboardShortcutCatalog.workflows.map(\.label)
        let settingsLabels = ShortcutsSettingsCatalog.sections.flatMap(\.shortcuts).map(\.label)
        XCTAssertTrue(overlayLabels.contains("Mail"))
        XCTAssertTrue(overlayLabels.contains("Calendar"))
        XCTAssertTrue(overlayLabels.contains("Chat drawer"))
        XCTAssertTrue(overlayLabels.contains("Open Mail beside current pane"))
        XCTAssertTrue(settingsLabels.contains("Toggle Chat Drawer"))
        XCTAssertTrue(settingsLabels.contains("Focus URL Bar"))
        XCTAssertTrue(settingsLabels.contains("Save Browser Page"))
    }

    private func settingsShortcutKeys(label: String) -> String? {
        ShortcutsSettingsCatalog.sections
            .flatMap(\.shortcuts)
            .first { $0.label == label }?
            .keys
    }

    func testWorkspaceSanitizationDropsHiddenTabsAndKeepsAllowedSelection() {
        let paneID = UUID()
        let browserID = UUID()
        let meetingsID = UUID()
        let leaf = PaneNode.Leaf(
            id: paneID,
            tabs: [
                .browserDocument(id: browserID),
                .meetingsDocument(id: meetingsID)
            ],
            selectedTabIndex: 0
        )
        let workspace = Workspace(
            id: UUID(),
            name: "Restored",
            icon: nil,
            root: .leaf(leaf),
            focusedPaneId: paneID,
            createdAt: Date()
        )

        let result = workspace.sanitizedForCurrentMode()

        XCTAssertTrue(result.changed)
        guard case .leaf(let sanitizedLeaf) = result.workspace.root else {
            XCTFail("Expected a single leaf workspace")
            return
        }
        XCTAssertEqual(sanitizedLeaf.tabs.map(\.id), [meetingsID])
        XCTAssertEqual(sanitizedLeaf.activeTabID, meetingsID)
    }

    func testWorkspaceSanitizationReplacesAllHiddenTabsWithEmptyDocument() {
        let paneID = UUID()
        let workspace = Workspace(
            id: UUID(),
            name: "Restored",
            icon: nil,
            root: .leaf(.init(id: paneID, tabs: [.browserDocument(), .terminal()], selectedTabIndex: 0)),
            focusedPaneId: paneID,
            createdAt: Date()
        )

        let result = workspace.sanitizedForCurrentMode()

        XCTAssertTrue(result.changed)
        guard case .leaf(let sanitizedLeaf) = result.workspace.root,
              case .document(let file) = sanitizedLeaf.activeContent else {
            XCTFail("Expected hidden content to become an empty document")
            return
        }
        XCTAssertEqual(sanitizedLeaf.tabs.count, 1)
        XCTAssertTrue(file.isEmptyTab)
    }

    func testWorkspaceManagerSanitizesDirectHiddenPaneInsertion() {
        let manager = WorkspaceManager()
        manager.layoutPersistenceEnabled = false

        manager.addWorkspaceWith(content: .browserDocument())

        guard case .document(let file) = manager.activeWorkspace?.focusedLeaf?.activeContent else {
            XCTFail("Expected sanitized document content")
            return
        }
        XCTAssertTrue(file.isEmptyTab)
    }
}
