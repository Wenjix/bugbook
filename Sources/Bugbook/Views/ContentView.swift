// swiftlint:disable file_length
import SwiftUI
import AppKit
import os
import Sentry
import BugbookCore
import GhosttyKit

struct ContentViewBootstrap {
    var workspaces: [Workspace]
    var activeWorkspaceIndex: Int
    var browserSnapshots: [UUID: BrowserPaneSnapshot] = [:]
    var layoutPersistenceEnabled: Bool = true
}

@MainActor
private final class LegacyPaneServices {
    let calendarService = CalendarService()
    let mailService = MailService()
    let calendarVM = CalendarViewModel()
    let meetingNotificationService = MeetingNotificationService()
    let terminalManager = TerminalManager()
    let browserManager = BrowserManager()
}

@MainActor
private enum ProfileMeetingAutoStartGate {
    static var consumed = false
}

private struct ShellTopChromeUnderlapModifier: ViewModifier {
    let enabled: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if enabled {
            content.ignoresSafeArea(.container, edges: .top)
        } else {
            content
        }
    }
}

// swiftlint:disable:next type_body_length
struct ContentView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let editorDraftStore = EditorDraftStore()
    private let editorSaveWorker = EditorSaveWorker()
    private let firstPartyIndexWorker = FirstPartyDatabaseIndexWorker()
    private let bootstrap: ContentViewBootstrap?

    @State private var appState = AppState()
    @State private var appSettingsStore = AppSettingsStore()
    @State private var fileSystem = FileSystemService()
    @State private var aiService: AiService?
    @State private var meetingNoteService = MeetingNoteService()
    @State private var transcriptionService = TranscriptionService()
    @State private var meetingsVM = MeetingsViewModel()
    @State private var meetingTranscriptStore = MeetingTranscriptStore()
    @State private var backlinkService = BacklinkService()
    @State private var blockDocuments: [UUID: BlockDocument] = [:]
    @State private var workspaceManager = WorkspaceManager()
    @State private var legacyPaneServices: LegacyPaneServices?

    @State private var saveTask: Task<Void, Never>?
    @State private var editorUI = EditorUIState()
    @State private var themeToast: ThemeMode?
    @State private var themeToastTask: Task<Void, Never>?
    @State private var formattingPanel: FormattingToolbarPanel?
    @State private var aiInitTask: Task<Void, Never>?
    @State private var aiInitCompleted = false
    @State private var fileTreeRefreshTask: Task<Void, Never>?
    @State private var fileTreeRefreshGeneration = 0
    @State private var pageLoadTasks: [UUID: Task<Void, Never>] = [:]
    @State private var pagePreloadTask: Task<Void, Never>?
    /// True once the app's own launch navigation (daily note / hub) has run, so an
    /// external file opened via "Open With" won't be clobbered by that async navigation.
    @State private var launchNavigationSettled = false
    @State private var workspaceWatcher: WorkspaceWatcher?
    @State private var restoredWorkspaceDocuments = false
    @State private var lastTrashPurgeWorkspace: String?
    @State private var recordingPillController = FloatingRecordingPillController()
    @State private var sidebarHoverVisible = false
    @AppStorage(EditorTypography.zoomScaleKey) private var editorZoomScale = Double(EditorTypography.defaultZoomScale)

    // Database row peek / modal
    private struct RowTarget {
        var dbPath: String
        let rowId: String
        var autoFocusTitle: Bool = false
    }

    private struct DocumentSaveSnapshot {
        let tabId: UUID
        let oldPath: String
        let content: String
        let title: String?
        let legacyIndex: Int?
        let hasWorkspaceFile: Bool
        let parentDirectory: String
        let isPhysicalDatabaseRowFile: Bool
    }
    @State private var peekTarget: RowTarget?
    @State private var dbInitialRowId: String?
    @State private var peekWidth: CGFloat = 640
    @State private var peekDragStartWidth: CGFloat?
    @State private var sidebarHiddenByPeek: Bool = false
    @State private var sidebarVisibleBeforePeekHide: Bool = true
    @State private var modalTarget: RowTarget?
    @State private var showPageOptionsMenu = false
    @State private var databaseRowFullWidth: [UUID: Bool] = [:]

    // Cmd+K deferred navigation: set by palette closure, consumed by .onChange in ContentView's own cycle
    @State private var pendingCmdKNavigation: CmdKNavRequest?

    // Pane replacement guard: amber warning for active terminal panes
    @State private var paneReplaceWarningId: UUID?
    @State private var paneReplaceWarningTask: Task<Void, Never>?

    private struct CmdKNavRequest: Equatable {
        let entry: FileEntry
        let inNewTab: Bool
        let searchQuery: String?
        let id: UUID  // unique per request so repeated selections of the same entry still fire
    }

    private struct WorkspaceDocumentRestoreTarget {
        let tabId: UUID
        let entry: FileEntry
    }

    init(bootstrap: ContentViewBootstrap? = nil) {
        self.bootstrap = bootstrap
    }

    private var loadedLegacyPaneServices: LegacyPaneServices? {
        legacyPaneServices
    }

    private var legacyAiService: AiService {
        if let aiService {
            return aiService
        }
        let service = AiService()
        aiService = service
        return service
    }

    private var legacyServices: LegacyPaneServices {
        if let legacyPaneServices {
            return legacyPaneServices
        }
        let services = LegacyPaneServices()
        legacyPaneServices = services
        return services
    }

    private var calendarService: CalendarService {
        legacyServices.calendarService
    }

    private var mailService: MailService {
        legacyServices.mailService
    }

    private var calendarVM: CalendarViewModel {
        legacyServices.calendarVM
    }

    private var meetingNotificationService: MeetingNotificationService {
        legacyServices.meetingNotificationService
    }

    private var terminalManager: TerminalManager {
        legacyServices.terminalManager
    }

    private var browserManager: BrowserManager {
        legacyServices.browserManager
    }

    var body: some View {
        configuredLayout
    }

    private var baseLayout: some View {
        ZStack(alignment: .leading) {
            Container.groutBg

            HStack(spacing: 0) {
                if appState.sidebarVisible {
                    if appState.showSettings {
                        SettingsSidebarView(appState: appState)
                            .frame(width: appState.sidebarWidth)
                    } else {
                        HarborSidebarView(
                            appState: appState,
                            fileSystem: fileSystem,
                            activeFilePath: contextualSidebarActiveFilePath,
                            onSelectEntry: { entry in handleSidebarFileSelect(entry) },
                            onRefreshTree: { refreshFileTree() },
                            onOpenSettings: { openSettingsTab() },
                            onNavItemTap: { item, inNewTab in handleNavItemTap(item, inNewTab: inNewTab) },
                            contextualLabel: sidebarContextLabel,
                            contextualContent: { sidebarContextualContent }
                        )
                        .frame(width: appState.sidebarWidth)
                    }

                    SidebarResizeHandle(width: $appState.sidebarWidth)
                }

                mainContentWithAiPanel
            }
            .animation(.easeInOut(duration: 0.15), value: appState.showSettings)
            .animation(.easeInOut(duration: 0.15), value: appState.sidebarVisible)

            // Hover-reveal sidebar when collapsed
            if !appState.sidebarVisible && !appState.showSettings {
                HStack(spacing: 0) {
                    // Invisible hover target at left edge
                    Color.clear
                        .frame(width: 6)
                        .contentShape(Rectangle())
                        .onHover { hovering in
                            if hovering { sidebarHoverVisible = true }
                        }

                    if sidebarHoverVisible {
                        HarborSidebarView(
                            appState: appState,
                            fileSystem: fileSystem,
                            activeFilePath: contextualSidebarActiveFilePath,
                            onSelectEntry: { entry in handleSidebarFileSelect(entry) },
                            onRefreshTree: { refreshFileTree() },
                            onOpenSettings: { openSettingsTab() },
                            onNavItemTap: { item, inNewTab in handleNavItemTap(item, inNewTab: inNewTab) },
                            contextualLabel: sidebarContextLabel,
                            contextualContent: { sidebarContextualContent }
                        )
                        .frame(width: appState.sidebarWidth)
                        .shadow(color: .black.opacity(0.15), radius: 8, x: 2, y: 0)
                        .onHover { hovering in
                            if !hovering { sidebarHoverVisible = false }
                        }
                        .transition(.move(edge: .leading).combined(with: .opacity))
                    }

                    Spacer(minLength: 0)
                }
                .frame(maxHeight: .infinity)
                .animation(.easeInOut(duration: 0.15), value: sidebarHoverVisible)
                .zIndex(10)
            }

            commandPaletteOverlay

            movePageOverlay
            themeToastOverlay
            editorZoomOverlay
            shortcutOverlay
        }
    }

    private var configuredLayout: some View {
        applyDatabaseNotifications(
            to: applyCommandNotifications(
                to: applyWorkspaceNotifications(
                    to: applyLifecycle(to: baseLayout)
                )
            )
        )
    }

    private func applyLifecycle<V: View>(to view: V) -> some View {
        let baseView = view
            .ignoresSafeArea()
            .frame(minWidth: 420, minHeight: 420)

        return applyLifecycleNotifications(
            to: applyLifecycleObservers(
                to: baseView.task {
                    performInitialLifecycleSetup()
                }
            )
        )
    }

    private func performInitialLifecycleSetup() {
        Log.profileMarker("appInitialLifecycleStart")
        loadAppSettings()
        initializeWorkspace()
        applyTheme(appState.settings.theme)
        if BugbookFeatureGate.shouldInitializeLegacyServices {
            applyTerminalColorScheme(appState.settings.terminalColorScheme)
        }
        editorZoomScale = clampedEditorZoomScale(editorZoomScale)
        editorUI.focusModeEnabled = appState.settings.focusModeOnType
        if BugbookFeatureGate.shouldWarmTranscriptionAtLaunch {
            warmUpTranscriptionModel()
        }
        drainPendingExternalFiles()
        Log.profileMarker("appInitialLifecycleComplete")
    }

    private func applyLifecycleObservers<V: View>(to view: V) -> some View {
        applyWorkspaceLifecycleObservers(
            to: applyInterfaceLifecycleObservers(
                to: applySettingsLifecycleObservers(to: view)
            )
        )
    }

    private func applySettingsLifecycleObservers<V: View>(to view: V) -> some View {
        view
            .onChange(of: appState.settings) { _, newSettings in
                appSettingsStore.save(newSettings)
                if BugbookFeatureGate.shouldInitializeLegacyServices {
                    applyTerminalColorScheme(newSettings.terminalColorScheme)
                }
            }
            .onChange(of: appState.settings.browserHistoryEnabled) { _, enabled in
                guard BugbookFeatureGate.shouldInitializeLegacyServices else { return }
                browserManager.setHistoryEnabled(enabled)
            }
            .onChange(of: appState.settings.browserExtensionPaths) { _, extensionPaths in
                guard BugbookFeatureGate.shouldInitializeLegacyServices else { return }
                browserManager.configureExtensions(extensionPaths)
            }
            .onChange(of: appState.settings.theme) { _, newTheme in
                applyTheme(newTheme)
            }
            .onChange(of: editorZoomScale) { oldValue, newValue in
                let clamped = clampedEditorZoomScale(newValue)
                if clamped != newValue {
                    editorZoomScale = clamped
                    return
                }
                guard oldValue != clamped else { return }
                editorUI.showZoomHud()
            }
    }

    private func applyInterfaceLifecycleObservers<V: View>(to view: V) -> some View {
        view
            .onChange(of: appState.settings.qmdSearchMode) { _, _ in
                // v2: no daemon needed, qmd query runs locally
            }
            .onChange(of: appState.showSettings) { _, showingSettings in
                // Ensure sidebar is visible when settings are opened
                if showingSettings && !appState.sidebarVisible {
                    appState.sidebarVisible = true
                }
                if showingSettings {
                    appState.selectedSettingsTab = BugbookFeatureGate.normalizedSettingsTab(appState.selectedSettingsTab)
                }
            }
            .onChange(of: appState.fileTree) { _, newTree in
                syncAvailablePages(newTree)
                refreshSidebarReferences(using: newTree)
                refreshFavorites(using: newTree)
            }
            .onChange(of: appState.aiSidePanelOpen) { _, isOpen in
                if isOpen && BugbookFeatureGate.legacyPanesEnabled {
                    ensureAiInitializedIfNeeded()
                } else if isOpen {
                    appState.aiSidePanelOpen = false
                }
            }
            .onChange(of: appState.settings.focusModeOnType) { _, enabled in
                editorUI.focusModeEnabled = enabled
            }
            .onChange(of: workspaceManager.activeWorkspace?.focusedPaneId) { _, _ in
                hideFormattingPanel()
                closeDatabaseRowModal()
                updateSidebarContextType()
            }
            .onChange(of: appState.currentView) { _, newView in
                handleCurrentViewChange(newView)
            }
    }

    private func applyWorkspaceLifecycleObservers<V: View>(to view: V) -> some View {
        view
            .onChange(of: workspaceManager.activeWorkspaceIndex) { _, _ in
                updateSidebarContextType()
            }
            .onChange(of: workspaceManager.workspaces) { _, workspaces in
                guard BugbookFeatureGate.shouldInitializeLegacyServices else { return }
                let paneIDs = Set(workspaces.flatMap { $0.allLeaves.map(\.id) })
                browserManager.cleanup(validPaneIDs: paneIDs)
            }
            .onChange(of: appState.isRecording) { _, recording in
                handleRecordingChange(recording)
            }
    }

    private func applyLifecycleNotifications<V: View>(to view: V) -> some View {
        view
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.willResignActiveNotification)) { _ in
                flushDirtyTabs()
            }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                flushDirtyTabs()
            }
            .onDisappear {
                handleViewDisappear()
            }
    }

    private func applyWorkspaceNotifications<V: View>(to view: V) -> some View {
        view
            .onReceive(NotificationCenter.default.publisher(for: .fileDeleted)) { notification in
                if let path = notification.object as? String {
                    saveTask?.cancel()
                    saveTask = nil
                    editorDraftStore.clearPageDraft(path: path)
                    let matchingWorkspaceTabIDs = workspaceManager.allDocumentLeaves()
                        .filter { $0.file.path == path }
                        .map(\.file.id)
                    for tabID in matchingWorkspaceTabIDs {
                        cleanupTabDocuments(tabID)
                        _ = workspaceManager.closeTab(tabId: tabID, closePaneWhenLastTab: true)
                    }
                    // Also clean up legacy tab system
                    let closingIds = appState.openTabs.filter { $0.path == path }.map(\.id)
                    appState.closeTabsForPath(path)
                    for id in closingIds { cleanupTabDocuments(id) }
                    removeDatabaseEmbedsFromOpenDocs(dbPath: path)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .fileMoved)) { notification in
                guard let info = notification.userInfo,
                      let oldPath = info["oldPath"] as? String,
                      let newPath = info["newPath"] as? String else {
                    return
                }
                handleFileMove(from: oldPath, to: newPath)
            }
            .onReceive(NotificationCenter.default.publisher(for: .movePage)) { notification in
                if let path = notification.object as? String {
                    appState.movePagePath = path
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .movePageToDir)) { notification in
                if let info = notification.userInfo,
                   let sourcePath = info["sourcePath"] as? String,
                   let destDir = info["destDir"] as? String {
                    let insertIndex = info["insertIndex"] as? Int
                    let siblingNames = info["siblings"] as? [String]
                    performMovePage(from: sourcePath, toDirectory: destDir, insertIndex: insertIndex, siblingNames: siblingNames)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .addToSidebar)) { notification in
                if let payload = notification.object as? SidebarReferenceDragPayload {
                    addSidebarReference(payload)
                }
            }
    }

    private func handleCurrentViewChange(_ newView: ViewMode) {
        let breadcrumb = Breadcrumb(level: .info, category: "view.change.\(String(describing: newView))")
        SentryBreadcrumbs.add(breadcrumb)
        hideFormattingPanel()
        closeDatabaseRowModal()
        if case .chat = newView {
            ensureAiInitializedIfNeeded()
        }
    }

    private func handleRecordingChange(_ recording: Bool) {
        if recording, let session = appState.activeMeetingSession {
            // Meeting page recording — pill navigates to the meeting tab (opens if closed)
            recordingPillController.onStop = {
                MeetingNavigationCoordinator.stopActiveRecordingFromFloatingPill(
                    session: session,
                    appState: appState,
                    navigateToFile: navigateToFilePath
                ) {
                    NotificationCenter.default.post(name: .stopMeetingRecording, object: nil)
                }
            }
            recordingPillController.onTap = {
                MeetingNavigationCoordinator.focusActiveRecordingPage(
                    session: session,
                    appState: appState,
                    navigateToFile: navigateToFilePath
                )
            }
        } else if recording, let blockId = appState.recordingBlockId {
            // Legacy inline block recording
            let doc = blockDocuments.values.first { $0.blocks.contains(where: { $0.id == blockId }) }
            recordingPillController.onStop = { [weak doc] in
                doc?.onStopMeeting?(blockId)
            }
            recordingPillController.onTap = { [weak doc] in
                doc?.scrollToBlockId = blockId
            }
        }
        recordingPillController.isRecording = recording
    }

    private func applyCommandNotifications<V: View>(to view: V) -> some View {
        applyPaneNotifications(
            to: applyZoomNotifications(
                to: applySecondaryCommandNotifications(
                    to: applyPrimaryCommandNotifications(to: view)
                )
            )
        )
    }

    private func applyPaneNotifications<V: View>(to view: V) -> some View {
        view
            .onChange(of: pendingCmdKNavigation) { _, request in
                handlePendingCmdKNavigation(request)
            }
            .onReceive(NotificationCenter.default.publisher(for: .splitPaneRight)) { _ in
                _ = workspaceManager.splitFocusedPane(
                    axis: .horizontal,
                    newContent: BugbookFeatureGate.defaultSplitPaneContent
                )
            }
            .onReceive(NotificationCenter.default.publisher(for: .splitPaneDown)) { _ in
                _ = workspaceManager.splitFocusedPane(
                    axis: .vertical,
                    newContent: BugbookFeatureGate.defaultSplitPaneContent
                )
            }
            .onReceive(NotificationCenter.default.publisher(for: .closeWorkspace)) { _ in
                closeActiveWorkspace()
            }
            .onReceive(NotificationCenter.default.publisher(for: .switchWorkspace)) { notification in
                if let index = notification.object as? Int {
                    workspaceManager.switchWorkspace(to: index)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .focusPaneByIndex)) { notification in
                if let index = notification.object as? Int,
                   let ws = workspaceManager.activeWorkspace {
                    let leaves = ws.root.allLeaves
                    if index < leaves.count {
                        workspaceManager.setFocusedPane(id: leaves[index].id)
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .movePaneFocusLeft)) { _ in
                moveFocusToAdjacentPane(direction: .left)
            }
            .onReceive(NotificationCenter.default.publisher(for: .movePaneFocusRight)) { _ in
                moveFocusToAdjacentPane(direction: .right)
            }
            .onReceive(NotificationCenter.default.publisher(for: .movePaneFocusUp)) { _ in
                moveFocusToAdjacentPane(direction: .up)
            }
            .onReceive(NotificationCenter.default.publisher(for: .movePaneFocusDown)) { _ in
                moveFocusToAdjacentPane(direction: .down)
            }
            .onReceive(NotificationCenter.default.publisher(for: .cyclePaneTabsForward)) { _ in
                cycleFocusedPaneTabs(step: 1)
            }
            .onReceive(NotificationCenter.default.publisher(for: .cyclePaneTabsBackward)) { _ in
                cycleFocusedPaneTabs(step: -1)
            }
    }

    private enum FocusDirection { case left, right, up, down }

    /// Move focus to the next pane in the given direction.
    /// Simple approach: cycle through all leaves in tree order.
    private func moveFocusToAdjacentPane(direction: FocusDirection) {
        guard let ws = workspaceManager.activeWorkspace else { return }
        let leaves = ws.allLeaves
        guard leaves.count > 1 else { return }
        guard let currentIndex = leaves.firstIndex(where: { $0.id == ws.focusedPaneId }) else { return }

        let nextIndex: Int
        switch direction {
        case .right, .down:
            nextIndex = (currentIndex + 1) % leaves.count
        case .left, .up:
            nextIndex = (currentIndex - 1 + leaves.count) % leaves.count
        }
        workspaceManager.setFocusedPane(id: leaves[nextIndex].id)
    }

    private func applyPrimaryCommandNotifications<V: View>(to view: V) -> some View {
        view
            .onReceive(NotificationCenter.default.publisher(for: .newNote)) { _ in
                createNewFile()
            }
            .onReceive(NotificationCenter.default.publisher(for: .newPaneTab)) { _ in
                guard let leaf = workspaceManager.focusedPane else { return }
                createPaneTab(in: leaf)
            }
            .onReceive(NotificationCenter.default.publisher(for: .newTab)) { _ in
                appState.newEmptyTab()
            }
            .onReceive(NotificationCenter.default.publisher(for: .closeTab)) { _ in
                closeFocusedPaneTabOrWorkspace()
            }
            .onReceive(NotificationCenter.default.publisher(for: .reopenClosedItem)) { _ in
                reopenClosedPaneItem()
            }
            .onReceive(NotificationCenter.default.publisher(for: .saveFile)) { _ in
                if !postBrowserCommandIfFocused(.browserSavePage) {
                    forceSave()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .openExternalFiles)) { _ in
                drainPendingExternalFiles()
            }
            .onOpenURL { url in
                Log.app.info("onOpenURL received: \(url.path)")
                guard url.isFileURL else { return }
                AppDelegate.enqueueExternalFilePaths([url.path])
                drainPendingExternalFiles()
            }
            .onReceive(NotificationCenter.default.publisher(for: .toggleSidebar)) { _ in
                guard !appState.showSettings else { return }
                withAnimation(.easeInOut(duration: 0.15)) {
                    appState.sidebarVisible.toggle()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .quickOpen)) { _ in
                flushDirtyTabContent()
                appState.commandPaletteMode = .search
                appState.commandPaletteOpen.toggle()
            }
            .onReceive(NotificationCenter.default.publisher(for: .findInPage)) { _ in
                if !postBrowserCommandIfFocused(.browserFind) {
                    NotificationCenter.default.post(name: .findInPane, object: nil)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .findInPane)) { _ in
                _ = postBrowserCommandIfFocused(.browserFind)
            }
            .onReceive(NotificationCenter.default.publisher(for: .quickOpenNewTab)) { _ in
                workspaceManager.addWorkspace()
            }
            .onReceive(NotificationCenter.default.publisher(for: .openSettings)) { _ in
                openSettingsTab()
            }
    }

    private func applySecondaryCommandNotifications<V: View>(to view: V) -> some View {
        view
            .onReceive(NotificationCenter.default.publisher(for: .toggleTheme)) { _ in
                toggleTheme()
            }
            .onReceive(NotificationCenter.default.publisher(for: .openDailyNote)) { _ in
                openDailyNote()
            }
            .onReceive(NotificationCenter.default.publisher(for: .openGraphView)) { _ in
                guard BugbookFeatureGate.allowsNotification(.openGraphView) else { return }
                presentEditorPane(.graphDocument())
            }
            .onReceive(NotificationCenter.default.publisher(for: .openMail)) { _ in
                guard BugbookFeatureGate.allowsNotification(.openMail) else { return }
                presentEditorPane(.mailDocument())
            }
            .onReceive(NotificationCenter.default.publisher(for: .openCalendar)) { _ in
                guard BugbookFeatureGate.allowsNotification(.openCalendar) else { return }
                presentEditorPane(.calendarDocument())
            }
            .onReceive(NotificationCenter.default.publisher(for: .openMeetings)) { _ in
                presentEditorPane(.meetingsDocument())
            }
            .onReceive(NotificationCenter.default.publisher(for: .meetingNotificationRecord)) { notification in
                guard BugbookFeatureGate.shouldStartMeetingNotificationPolling else { return }
                handleMeetingNotification(notification, startRecording: true)
            }
            .onReceive(NotificationCenter.default.publisher(for: .meetingNotificationOpenNotes)) { notification in
                guard BugbookFeatureGate.shouldStartMeetingNotificationPolling else { return }
                handleMeetingNotification(notification, startRecording: false)
            }
            .onReceive(NotificationCenter.default.publisher(for: .openGateway)) { _ in
                guard BugbookFeatureGate.allowsNotification(.openGateway) else { return }
                presentEditorPane(.gatewayDocument())
            }
            .onReceive(NotificationCenter.default.publisher(for: .openTerminal)) { _ in
                guard BugbookFeatureGate.allowsNotification(.openTerminal) else { return }
                presentEditorPane(.terminal())
            }
            .onReceive(NotificationCenter.default.publisher(for: .openBrowser)) { _ in
                guard BugbookFeatureGate.allowsNotification(.openBrowser) else { return }
                presentEditorPane(.browserDocument())
            }
            .onReceive(NotificationCenter.default.publisher(for: .toggleShortcutOverlay)) { _ in
                withAnimation(.easeInOut(duration: 0.15)) {
                    appState.showShortcutOverlay.toggle()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .newDatabase)) { _ in
                createNewDatabase()
            }
            .onReceive(NotificationCenter.default.publisher(for: .navigateBack)) { _ in
                if !postBrowserCommandIfFocused(.browserBack) {
                    navigateBackInActiveTab()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .navigateForward)) { _ in
                if !postBrowserCommandIfFocused(.browserForward) {
                    navigateForwardInActiveTab()
                }
            }
    }

    private func applyZoomNotifications<V: View>(to view: V) -> some View {
        view
            .onReceive(NotificationCenter.default.publisher(for: .editorZoomIn)) { _ in
                if !postBrowserCommandIfFocused(.browserZoomIn) {
                    adjustEditorZoom(by: 0.1)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .editorZoomOut)) { _ in
                if !postBrowserCommandIfFocused(.browserZoomOut) {
                    adjustEditorZoom(by: -0.1)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .editorZoomReset)) { _ in
                if !postBrowserCommandIfFocused(.browserZoomReset) {
                    resetEditorZoom()
                }
            }
    }

    private func applyDatabaseNotifications<V: View>(to view: V) -> some View {
        view
            .onReceive(NotificationCenter.default.publisher(for: .openAIPanel)) { _ in
                guard BugbookFeatureGate.allowsNotification(.openAIPanel) else { return }
                ensureAiInitializedIfNeeded()
                appState.toggleAiPanel()
            }
            .onReceive(NotificationCenter.default.publisher(for: .askAI)) { notification in
                guard BugbookFeatureGate.allowsNotification(.askAI) else { return }
                let prompt = notification.userInfo?["prompt"] as? String
                    ?? notification.userInfo?["query"] as? String
                ensureAiInitializedIfNeeded()
                appState.openAiPanel(prompt: prompt)
            }
            .onReceive(NotificationCenter.default.publisher(for: .blockTypeShortcut)) { notification in
                handleBlockTypeShortcut(notification.object as? String)
            }
            .onReceive(NotificationCenter.default.publisher(for: .databaseOpenRequested)) { notification in
                guard let dbPath = notification.databasePath else { return }
                openDatabase(at: dbPath)
            }
            .onReceive(NotificationCenter.default.publisher(for: .databaseNameDidChange)) { notification in
                guard let dbPath = notification.databasePath,
                      let newName = notification.databaseNewName else { return }
                for i in appState.openTabs.indices where appState.openTabs[i].path == dbPath {
                    appState.openTabs[i].displayName = newName
                }
                refreshFileTree()
            }
    }

    // MARK: - Sidebar

    private var effectiveSidebarContextType: SidebarContextType {
        if !BugbookFeatureGate.legacyPanesEnabled,
           appState.sidebarContextType != .workspace {
            return .workspace
        }
        return appState.sidebarContextType
    }

    private var sidebarContextLabel: String? {
        switch effectiveSidebarContextType {
        case .mail: return "Mail"
        case .calendar: return "Calendar"
        case .workspace: return BugbookFeatureGate.legacyPanesEnabled ? "Pages" : nil
        case .none: return nil
        }
    }

    @ViewBuilder
    private var sidebarContextualContent: some View {
        switch effectiveSidebarContextType {
        case .mail:
            MailContextualSidebarView(
                appState: appState,
                mailService: mailService,
                onRefresh: {
                    guard let token = appState.settings.googleToken else { return }
                    Task {
                        await mailService.refreshSelectedMailbox(token: token)
                    }
                }
            )
        case .calendar:
            CalendarContextualSidebarView(
                calendarVM: calendarVM,
                calendarService: calendarService,
                workspacePath: appState.workspacePath
            )
        case .workspace:
            WorkspaceContextualSidebarView(
                appState: appState,
                fileSystem: fileSystem,
                activeFilePath: contextualSidebarActiveFilePath,
                onSelectWorkspaceEntry: { entry in handleSidebarFileSelect(entry) },
                onRefreshTree: { refreshFileTree() }
            )
        case .none:
            EmptyView()
        }
    }

    private func updateSidebarContextType() {
        guard let ws = workspaceManager.activeWorkspace,
              let focusedLeaf = ws.focusedLeaf else { return }
        appState.sidebarContextType = SidebarContextType.from(focusedLeaf.content)
    }

    @ViewBuilder
    private var commandPaletteOverlay: some View {
        if appState.commandPaletteOpen {
            Color.black.opacity(0.3)
                .onTapGesture { appState.commandPaletteOpen = false }

            if appState.commandPaletteMode == .splitLauncher {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        PaneLauncher(
                            variant: .wide,
                            fileTree: appState.fileTree,
                            onSelect: { content, direction in
                                guard BugbookFeatureGate.allowsPaneContent(content) else { return }
                                appState.commandPaletteOpen = false
                                switch direction {
                                case .right:
                                    _ = workspaceManager.splitFocusedPane(axis: .horizontal, newContent: content)
                                case .down:
                                    _ = workspaceManager.splitFocusedPane(axis: .vertical, newContent: content)
                                case .newTab:
                                    workspaceManager.addWorkspaceWith(content: content)
                                }
                            },
                            onDismiss: { appState.commandPaletteOpen = false },
                            onNavigateInPlace: { content in
                                guard BugbookFeatureGate.allowsPaneContent(content) else { return }
                                appState.commandPaletteOpen = false
                                // For workspace pages, use proper file navigation (loads content from disk).
                                // For built-in panes (terminal, mail, etc.), use direct content replacement.
                                if case .document(let file) = content,
                                   !file.path.hasPrefix("bugbook://"),
                                   !file.path.isEmpty,
                                   !file.isEmptyTab {
                                    navigateToFilePath(file.path)
                                } else {
                                    openContentInFocusedPane(content)
                                }
                            }
                        )
                        .popoverSurface(cornerRadius: Radius.xl)
                        Spacer()
                    }
                    Spacer()
                }
            } else {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        CommandPaletteView(
                            appState: appState,
                            workspaceManager: workspaceManager,
                            isPresented: $appState.commandPaletteOpen,
                            onSelectFile: { entry, destination in
                                DispatchQueue.main.async {
                                    openLauncherFile(entry, destination: destination)
                                }
                            },
                            onCreate: { kind, destination in
                                DispatchQueue.main.async {
                                    createLauncherItem(kind, destination: destination)
                                }
                            },
                            onOpenPane: { reference, destination in
                                DispatchQueue.main.async {
                                    openLauncherPane(reference, destination: destination)
                                }
                            },
                            onAskAI: { prompt in
                                NotificationCenter.default.post(
                                    name: .askAI,
                                    object: nil,
                                    userInfo: ["prompt": prompt]
                                )
                            }
                        )
                        Spacer()
                    }
                    Spacer()
                }
            }
        }
    }

    @ViewBuilder
    private func sidebarChromeButton(
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

    @discardableResult
    private func postBrowserCommandIfFocused(_ name: Notification.Name, object: Any? = nil) -> Bool {
        guard let targetPaneID = browserCommandPaneID else { return false }
        guard loadedLegacyPaneServices?.browserManager != nil else { return false }
        NotificationCenter.default.post(name: name, object: object ?? targetPaneID)
        return true
    }

    private var browserCommandPaneID: UUID? {
        focusedBrowserPaneID ?? soleBrowserPaneID
    }

    private var activeWorkspaceLeaves: [PaneNode.Leaf] {
        workspaceManager.activeWorkspace?.allLeaves ?? []
    }

    private var shellShowsSidebarPanel: Bool {
        appState.sidebarVisible
    }

    private var focusedBrowserPaneID: UUID? {
        guard let leaf = workspaceManager.focusedPane else { return nil }
        guard case .document(let file) = leaf.content, file.isBrowser else { return nil }
        return leaf.id
    }

    private var soleBrowserPaneID: UUID? {
        let browserLeaves = activeWorkspaceLeaves.filter { leaf in
            guard case .document(let file) = leaf.content else { return false }
            return file.isBrowser
        }
        guard browserLeaves.count == 1 else { return nil }
        return browserLeaves.first?.id
    }

    private var contextualSidebarActiveFilePath: String? {
        guard let leaf = workspaceManager.activeWorkspace?.focusedLeaf,
              case .document(let file) = leaf.content,
              !file.path.isEmpty,
              !file.path.hasPrefix("bugbook://") else {
            return nil
        }
        return file.path
    }

    private func handleViewDisappear() {
        flushDirtyTabs()
        appSettingsStore.save(appState.settings)
        loadedLegacyPaneServices?.terminalManager.shutdown()
        loadedLegacyPaneServices?.browserManager.persistAllSessions()
        paneReplaceWarningTask?.cancel()
        aiInitTask?.cancel()
        aiInitTask = nil
        fileTreeRefreshTask?.cancel()
        fileTreeRefreshTask = nil
        pagePreloadTask?.cancel()
        pagePreloadTask = nil
        pageLoadTasks.values.forEach { $0.cancel() }
        pageLoadTasks.removeAll()
        editorUI.cleanUp()
        workspaceWatcher?.stop()
        recordingPillController.cleanup()
    }

    private func presentEditorPane(_ content: PaneContent) {
        guard BugbookFeatureGate.allowsPaneContent(content) else { return }
        appState.currentView = .editor
        appState.showSettings = false
        openOrFocusPane(content)
    }

    /// Handle a tap on a sidebar fixed-zone navigation item.
    /// Default: replace the focused pane. Cmd-click: open in a new workspace tab.
    private func handleNavItemTap(_ item: ShellNavItem, inNewTab: Bool) {
        guard BugbookFeatureGate.allowsSidebarItem(id: item.id) else { return }
        appState.currentView = .editor
        appState.showSettings = false
        if item.id != "search" {
            appState.commandPaletteOpen = false
        }

        // Modal / file actions don't have pane semantics — fall back to notifications.
        switch item.id {
        case "search":
            NotificationCenter.default.post(name: .quickOpen, object: nil)
            return
        case "notes":
            NotificationCenter.default.post(name: .openDailyNote, object: nil)
            return
        default:
            break
        }

        let content: PaneContent
        switch item.id {
        case "home": content = .gatewayDocument()
        case "meeting": content = .meetingsDocument()
        case "calendar": content = .calendarDocument()
        case "terminal": content = .terminal()
        case "browser": content = .browserDocument()
        case "mail": content = .mailDocument()
        default: return
        }

        if inNewTab {
            workspaceManager.addWorkspaceWith(content: content)
        } else {
            openContentInFocusedPane(content)
        }
    }

    private func handleSidebarToggle() {
        withAnimation(.easeInOut(duration: 0.15)) {
            appState.sidebarVisible.toggle()
        }
    }

    // MARK: - Move Page Overlay

    @ViewBuilder
    private var movePageOverlay: some View {
        if appState.movePagePath != nil {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { appState.movePagePath = nil }

            VStack {
                HStack {
                    Spacer()
                    if let workspace = appState.workspacePath,
                       let pagePath = appState.movePagePath {
                        MovePagePickerView(
                            fileTree: appState.fileTree,
                            movingPath: pagePath,
                            workspacePath: workspace,
                            onMove: { destDir in
                                performMovePage(from: pagePath, toDirectory: destDir)
                            },
                            isPresented: Binding(
                                get: { appState.movePagePath != nil },
                                set: { if !$0 { appState.movePagePath = nil } }
                            )
                        )
                        .padding(.top, 60)
                        .padding(.trailing, 20)
                    }
                }
                Spacer()
            }
        }
    }

    private func performMovePage(from sourcePath: String, toDirectory destDir: String, insertIndex: Int? = nil, siblingNames: [String]? = nil) {
        do {
            let newPath = try fileSystem.movePage(at: sourcePath, toDirectory: destDir)
            let oldPath = sourcePath

            // Update any open tabs pointing to the old path
            for tab in appState.openTabs {
                appState.updateNavigationPath(for: tab.id, from: oldPath, to: newPath)
            }

            let oldCompanion = oldPath.hasSuffix(".md") ? String(oldPath.dropLast(3)) : oldPath
            let newCompanion = newPath.hasSuffix(".md") ? String(newPath.dropLast(3)) : newPath

            // Rewrite absolute paths inside moved files (database embeds, etc.) in background
            let fs = fileSystem
            Task.detached(priority: .utility) {
                fs.rewritePathsInFile(at: newPath, oldBase: oldCompanion, newBase: newCompanion)
                fs.rewritePathsRecursively(in: newCompanion, oldBase: oldCompanion, newBase: newCompanion)
            }

            // Also update paths for children that moved (companion folder contents)
            for tab in appState.openTabs where tab.path.hasPrefix(oldCompanion + "/") {
                let relative = String(tab.path.dropFirst(oldCompanion.count))
                let updatedPath = newCompanion + relative
                appState.updateNavigationPath(for: tab.id, from: tab.path, to: updatedPath)
            }

            // Update block document file paths
            for (_, doc) in blockDocuments {
                if doc.filePath == oldPath {
                    doc.filePath = newPath
                } else if let fp = doc.filePath, fp.hasPrefix(oldCompanion + "/") {
                    let relative = String(fp.dropFirst(oldCompanion.count))
                    doc.filePath = newCompanion + relative
                }
            }

            // Apply reorder if a target position was specified (cross-parent .above drop)
            if let insertIndex, let siblingNames {
                let movedName = (newPath as NSString).lastPathComponent
                var names = siblingNames
                names.insert(movedName, at: min(insertIndex, names.count))
                fileSystem.saveCustomOrder(names, for: destDir)
            }

            appState.movePagePath = nil
            refreshFileTree()

            // Register undo
            NSApp.keyWindow?.undoManager?.registerUndo(withTarget: fileSystem) { fs in
                Task { @MainActor in
                    do {
                        let oldDir = (oldPath as NSString).deletingLastPathComponent
                        let restoredPath = try fs.movePage(at: newPath, toDirectory: oldDir)

                        let newCompanion = newPath.hasSuffix(".md") ? String(newPath.dropLast(3)) : newPath
                        let restoredCompanion = restoredPath.hasSuffix(".md") ? String(restoredPath.dropLast(3)) : restoredPath

                        for tab in self.appState.openTabs {
                            if tab.path == newPath {
                                self.appState.updateNavigationPath(for: tab.id, from: newPath, to: restoredPath)
                            } else if tab.path.hasPrefix(newCompanion + "/") {
                                let relative = String(tab.path.dropFirst(newCompanion.count))
                                self.appState.updateNavigationPath(for: tab.id, from: tab.path, to: restoredCompanion + relative)
                            }
                        }
                        for (_, doc) in self.blockDocuments {
                            if doc.filePath == newPath {
                                doc.filePath = restoredPath
                            } else if let fp = doc.filePath, fp.hasPrefix(newCompanion + "/") {
                                let relative = String(fp.dropFirst(newCompanion.count))
                                doc.filePath = restoredCompanion + relative
                            }
                        }

                        self.refreshFileTree()
                    } catch {
                        Log.fileSystem.error("Undo move failed: \(error.localizedDescription)")
                    }
                }
            }
            NSApp.keyWindow?.undoManager?.setActionName("Move Page")

            NotificationCenter.default.post(name: .fileMoved, object: nil, userInfo: [
                "oldPath": oldPath,
                "newPath": newPath
            ])
        } catch {
            Log.fileSystem.error("Move page failed: \(error.localizedDescription)")
        }
    }

    /// Handle a page path dropped from the sidebar into the editor.
    /// Inserts a page link block and moves the source file into the current page's companion folder.
    private func handleSidebarPageDrop(sourcePath: String, into document: BlockDocument, at insertIndex: Int) {
        guard let tab = appState.activeTab,
              sourcePath != tab.path,
              FileManager.default.fileExists(atPath: sourcePath) else { return }

        // Don't move databases into companion folders via editor drops
        guard !fileSystem.isDatabaseFolder(at: sourcePath) else { return }

        let pageName = ((sourcePath as NSString).lastPathComponent as NSString).deletingPathExtension

        let targetCompanionDir: String
        if tab.path.hasSuffix(".md") {
            targetCompanionDir = String(tab.path.dropLast(3))
        } else {
            targetCompanionDir = tab.path
        }

        guard !tab.path.hasPrefix(sourcePath.hasSuffix(".md") ? String(sourcePath.dropLast(3)) + "/" : sourcePath + "/") else { return }

        performMovePage(from: sourcePath, toDirectory: targetCompanionDir)

        let alreadyLinked = document.blocks.contains { $0.type == .pageLink && $0.pageLinkName == pageName }
        if !alreadyLinked {
            document.insertPageLinkBlock(at: insertIndex, name: pageName)
        }

        scheduleSave()
    }

    // MARK: - Main Content

    private var activeDocumentForAiDrawer: BlockDocument? {
        workspaceManager.activeWorkspace.flatMap { ws in
            ws.focusedLeaf.flatMap { blockDocuments[$0.activeTabID] }
        }
    }

    private var aiDrawerContext: AiDrawerContext {
        guard let leaf = workspaceManager.focusedPane else {
            return AiDrawerContext(placeholder: "Ask anything…")
        }

        switch leaf.content {
        case .terminal:
            return makeTerminalAiDrawerContext(for: leaf.activeTabID)
        case .document(let file):
            if file.isBrowser {
                return makeBrowserAiDrawerContext(for: leaf.id)
            }

            if file.isMail {
                return makeMailAiDrawerContext()
            }

            if file.isCalendar {
                return makeCalendarAiDrawerContext()
            }

            return makeDocumentAiDrawerContext(for: file)
        }
    }

    private func makeTerminalAiDrawerContext(for paneID: UUID) -> AiDrawerContext {
        let session = loadedLegacyPaneServices?.terminalManager.session(for: paneID)
        let title = session?.title ?? "Terminal"
        let workingDirectory = session?.workingDirectory ?? ""

        return AiDrawerContext(
            placeholder: "Ask about this terminal…",
            title: title,
            subtitle: workingDirectory.isEmpty ? nil : workingDirectory,
            contextProvider: {
                """
                Terminal title: \(title)
                Working directory: \(workingDirectory)

                Note: terminal scrollback is not currently exposed. Answer using the available session metadata.
                """
            }
        )
    }

    private func makeBrowserAiDrawerContext(for paneID: UUID) -> AiDrawerContext {
        guard let browserManager = loadedLegacyPaneServices?.browserManager else {
            return AiDrawerContext(placeholder: "Ask about this page…", title: "Browser")
        }
        guard let leaf = workspaceManager.leaf(id: paneID),
              let selectedTabID = leaf.activeOpenFile?.id,
              let tab = browserManager.activeTab(in: paneID) else {
            return AiDrawerContext(placeholder: "Ask about this page…", title: "Browser")
        }

        let title = tab.displayTitle
        let urlString = tab.urlString

        return AiDrawerContext(
            placeholder: "Ask about this page…",
            title: title,
            subtitle: urlString.isEmpty ? nil : urlString,
            contextProvider: {
                let extractedText = await BrowserAgentService().extractPageContent(
                    from: paneID,
                    tabID: selectedTabID,
                    browserManager: browserManager
                )
                return """
                Browser page title: \(title)
                URL: \(urlString)

                \(extractedText)
                """
            }
        )
    }

    private func makeMailAiDrawerContext() -> AiDrawerContext {
        let thread = loadedLegacyPaneServices?.mailService.selectedThread
        let subject = thread?.subject ?? "Selected Email"
        let subtitle = thread?.participants.joined(separator: ", ")

        return AiDrawerContext(
            placeholder: "Ask about this email…",
            title: subject,
            subtitle: subtitle,
            contextProvider: {
                let snippet = thread?.snippet ?? ""
                let body = thread?.messages.last?.bodyText ?? ""
                return """
                Email subject: \(subject)
                Participants: \(subtitle ?? "")
                Snippet: \(snippet)

                \(body)
                """
            }
        )
    }

    private func makeCalendarAiDrawerContext() -> AiDrawerContext {
        guard let legacyPaneServices else {
            return AiDrawerContext(placeholder: "Ask about this schedule…", title: "Calendar")
        }
        let visibleSources = legacyPaneServices.calendarService.sources
            .filter(\.isVisible)
            .map(\.name)
            .joined(separator: ", ")
        let selectedDate = legacyPaneServices.calendarVM.selectedDate.formatted(
            .dateTime.weekday(.wide).month(.wide).day().year()
        )
        let viewMode = legacyPaneServices.calendarVM.viewMode.rawValue

        return AiDrawerContext(
            placeholder: "Ask about this schedule…",
            title: selectedDate,
            subtitle: "\(viewMode) view",
            contextProvider: {
                """
                Calendar date: \(selectedDate)
                Calendar view: \(viewMode)
                Visible calendars: \(visibleSources)
                """
            }
        )
    }

    private func makeDocumentAiDrawerContext(for file: OpenFile) -> AiDrawerContext {
        if file.isMeetings {
            return AiDrawerContext(
                placeholder: "Ask about this meeting…",
                title: file.displayName ?? "Meetings"
            )
        }

        if file.isGateway {
            return AiDrawerContext(
                placeholder: "Ask about this workspace…",
                title: "Home"
            )
        }

        return AiDrawerContext(
            placeholder: "Ask about this note…",
            title: file.displayName
        )
    }

    private func usesImmersivePaneLayout(_ file: OpenFile) -> Bool {
        file.isMail || file.isCalendar || file.isMeetings || file.isGateway || file.isBrowser
    }

    private func showsPageOptionsMenu(for file: OpenFile) -> Bool {
        !file.isEmptyTab
            && !file.isDatabase
            && !file.isSkill
            && !usesImmersivePaneLayout(file)
            && !file.isChat
            && !file.isGraphView
    }

    private func isDocumentEditorFile(_ file: OpenFile) -> Bool {
        showsPageOptionsMenu(for: file) && !file.isDatabaseRow
    }

    private var shouldRenderGraphView: Bool {
        appState.currentView == .graphView && BugbookFeatureGate.allowsViewMode(.graphView)
    }

    @ViewBuilder
    private var mainContentWithAiPanel: some View {
        VStack(spacing: 0) {
            // Tab bar sits on the grout surface (above the card)
            if !appState.showSettings && !shouldRenderGraphView {
                WorkspaceTabBar(
                    workspaceManager: workspaceManager,
                    browserManager: loadedLegacyPaneServices?.browserManager,
                    sidebarOpen: shellShowsSidebarPanel,
                    currentView: appState.currentView,
                    recordingPagePath: appState.activeMeetingSession?.meetingPagePath,
                    onOpenNewTabLauncher: {
                        flushDirtyTabContent()
                        appState.commandPaletteMode = .newTab
                        appState.commandPaletteOpen = true
                    }
                )
                .opacity(editorUI.focusModeActive ? 0.0 : 1.0)
            }

            if !appState.legacyWorkspacesNeedingAttention.isEmpty {
                legacyWorkspaceBanners
            }

            // Content card with grout padding
            ZStack(alignment: .trailing) {
                contentCardBody
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .modifier(ShellTopChromeUnderlapModifier(enabled: shellUsesTopChromeUnderlap))

                if BugbookFeatureGate.legacyPanesEnabled,
                   appState.aiSidePanelOpen,
                   appState.currentView == .editor {
                    AiSidePanelView(
                        appState: appState,
                        aiService: legacyAiService,
                        activeDocument: activeDocumentForAiDrawer,
                        drawerContext: aiDrawerContext
                    )
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                    .zIndex(2)
                }
            }
            .padding(.leading, mainContentLeadingPadding)
            .padding(.trailing, mainContentTrailingPadding)
            .padding(.bottom, mainContentBottomPadding)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var contentCardBody: some View {
        if appState.showSettings {
            SettingsView(
                appState: appState,
                browserManager: loadedLegacyPaneServices?.browserManager,
                onSwitchWorkspace: { path in switchWorkspaceRoot(to: path) }
            )
                .background(Container.cardBg)
                .clipShape(RoundedRectangle(cornerRadius: Container.cardRadius))
        } else if shouldRenderGraphView {
            if let workspace = appState.workspacePath {
                GraphView(
                    backlinkService: backlinkService,
                    workspacePath: workspace,
                    currentPagePath: appState.activeTab?.path,
                    onNavigateToFile: { path in
                        navigateToFilePath(path)
                    }
                )
                .background(Container.cardBg)
                .clipShape(RoundedRectangle(cornerRadius: Container.cardRadius))
            }
        } else {
            paneTreeContent
        }
    }

    private var legacyWorkspaceBanners: some View {
        Group {
            if !appState.legacyWorkspacesNeedingAttention.isEmpty {
                LegacyWorkspaceMigrationBanner(
                    legacyWorkspaces: appState.legacyWorkspacesNeedingAttention,
                    isMigrating: appState.isMigratingAnyLegacyWorkspace,
                    errorMessage: appState.aggregatedLegacyMigrationError,
                    onMigrateAll: {
                        Task { await appState.migrateAllLegacyWorkspaces(using: fileSystem) }
                    },
                    onRevealInFinder: { appState.revealLegacyWorkspace($0) },
                    onDismissAll: { appState.dismissAllLegacyWorkspaces() }
                )
                .padding(.leading, appState.sidebarVisible ? 0 : Container.groutGap)
                .padding(.trailing, Container.groutGap)
                .padding(.bottom, Container.groutGap)
            }
        }
    }

    private var activeTabLeadingPadding: CGFloat {
        guard let activeTab = appState.activeTab else {
            return ShellZoomMetrics.size(8)
        }
        return usesImmersivePaneLayout(activeTab) ? 0 : ShellZoomMetrics.size(8)
    }

    private let shellUsesTopChromeUnderlap = false
    private let usesFullBleedShellLayout = false

    private var mainContentLeadingPadding: CGFloat {
        if usesFullBleedShellLayout {
            return 0
        }
        return appState.sidebarVisible ? 0 : Container.groutGap
    }

    private var mainContentTrailingPadding: CGFloat {
        usesFullBleedShellLayout ? 0 : Container.groutGap
    }

    private var mainContentBottomPadding: CGFloat {
        usesFullBleedShellLayout ? 0 : Container.groutGap
    }

    @ViewBuilder
    private var paneTreeContent: some View {
        Group {
            if let ws = workspaceManager.activeWorkspace {
                paneTreeView(for: ws)
            }
        }
        .environment(\.workspacePath, appState.workspacePath)
        .modifier(ShellTopChromeUnderlapModifier(enabled: shellUsesTopChromeUnderlap))
        .overlay(alignment: .trailing) {
            if let peek = peekTarget {
                HStack(spacing: 0) {
                    // Resize drag edge
                        Rectangle()
                            .fill(Color.clear)
                            .frame(width: 8)
                            .contentShape(Rectangle())
                            .onHover { hovering in
                                    if hovering { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
                            }
                            .gesture(
                                DragGesture(coordinateSpace: .global)
                                .onChanged { value in
                                    peekDragOnChanged(translationWidth: value.translation.width)
                                }
                                .onEnded { _ in
                                    peekDragStartWidth = nil
                                }
                        )

                    InlineRowPeekPanel(
                        dbPath: peek.dbPath,
                        rowId: peek.rowId,
                        onClose: { closePeekPanel() },
                        onOpenFullPage: {
                            closePeekPanel()
                            openDatabaseRowPage(dbPath: peek.dbPath, rowId: peek.rowId, preferExistingTab: true)
                        }
                    )
                    .id("\(peek.dbPath)|\(peek.rowId)")
                }
                .frame(width: peekWidth)
                .background(Color.fallbackEditorBg)
            }
        }
        .overlay {
            if let modal = modalTarget {
                ZStack {
                    Rectangle()
                        .fill(Color.black.opacity(0.28))
                        .contentShape(Rectangle())
                        .onTapGesture { closeDatabaseRowModal() }

                    DatabaseRowModalView(
                        dbPath: modal.dbPath,
                        rowId: modal.rowId,
                        autoFocusTitle: modal.autoFocusTitle,
                        onClose: { closeDatabaseRowModal() },
                        onOpenFullPage: {
                            closeDatabaseRowModal()
                            openDatabaseRowPage(dbPath: modal.dbPath, rowId: modal.rowId, preferExistingTab: true)
                        }
                    )
                    .padding(32)
                }
                .transition(.opacity)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .inlineDatabaseRowPeek)) { notification in
            guard let dbPath = notification.databasePath,
                  let rowId = notification.databaseRowId else { return }
            if peekTarget?.dbPath == dbPath && peekTarget?.rowId == rowId {
                closePeekPanel()
            } else {
                peekTarget = RowTarget(dbPath: dbPath, rowId: rowId)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .databaseRowModalRequested)) { notification in
            guard let dbPath = notification.databasePath,
                  let rowId = notification.databaseRowId else { return }
            closePeekPanel()
            modalTarget = RowTarget(dbPath: dbPath, rowId: rowId, autoFocusTitle: notification.databaseAutoFocusTitle)
        }
    }

    private func paneTreeView(for workspace: Workspace) -> some View {
        PaneTreeView(
            node: workspace.root,
            workspaceManager: workspaceManager,
            hasMultiplePanes: workspace.hasMultiplePanes,
            fileTree: appState.fileTree,
            documentContentBuilder: { leaf, file in
                AnyView(self.paneDocumentContent(leaf: leaf, file: file))
            },
            terminalContentBuilder: { leaf, _ in
                AnyView(self.paneTerminalContent(leaf: leaf))
            },
            breadcrumbProvider: { file in
                self.breadcrumbs(for: file)
            },
            onBreadcrumbNavigate: { item in
                self.navigateToBreadcrumb(item)
            },
            blockDocumentLookup: { tabId in
                self.blockDocuments[tabId]
            },
            paneActions: paneActions
        )
        .environment(\.paneReplaceWarningId, paneReplaceWarningId)
    }

    private var paneActions: PaneActions {
        PaneActions(
            createPaneTab: createPaneTab(in:),
            closePaneTab: closePaneTab(in:tabId:),
            closePane: closePane(_:),
            closeOtherPanes: closeOtherPanes(keeping:)
        )
    }

    // MARK: - Pane Document Content

    /// Renders document content for a single pane leaf. Handles breadcrumbs, options menu,
    /// and routes to the appropriate view based on the OpenFile's TabKind.
    @ViewBuilder
    private func paneDocumentContent(leaf: PaneNode.Leaf, file: OpenFile) -> some View {
        VStack(spacing: 0) {
            // Breadcrumb moved to chrome bar. Options menu stays in content area.
            if showsPageOptionsMenu(for: file) {
                HStack {
                    Spacer()
                    Button {
                        showPageOptionsMenu.toggle()
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(ShellZoomMetrics.font(Typography.bodySmall))
                            .foregroundStyle(.primary)
                            .frame(width: ShellZoomMetrics.size(32), height: ShellZoomMetrics.size(32))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, ShellZoomMetrics.size(4))
                    .floatingPopover(isPresented: $showPageOptionsMenu) {
                        if file.isDatabaseRow {
                            databaseRowOptionsMenu(for: file)
                        } else if let doc = blockDocuments[file.id] {
                            pageOptionsMenu(for: file, document: doc)
                        }
                    }
                }
                .opacity(editorUI.focusModeActive ? 0.0 : 1.0)
            }

            if file.path.contains("/.claude/skills/") {
                skillFileBanner(path: file.path)
            }

            paneContentRouting(leaf: leaf, file: file)
        }
        .padding(.leading, paneLeadingPadding(for: file))
    }

    private func paneLeadingPadding(for file: OpenFile) -> CGFloat {
        usesImmersivePaneLayout(file) ? 0 : ShellZoomMetrics.size(8)
    }

    @ViewBuilder
    private func paneTerminalContent(leaf: PaneNode.Leaf) -> some View {
        if !BugbookFeatureGate.legacyPanesEnabled {
            Color.clear
                .task { openDailyNote() }
        } else {
            let sessionID = leaf.activeTabID
            if let session = terminalManager.session(for: sessionID) {
                TerminalPaneView(session: session, paneId: leaf.id, workspaceManager: workspaceManager)
                    .id(sessionID)
            } else {
                Color.fallbackEditorBg
                    .onAppear {
                        terminalManager.createSession(
                            id: sessionID,
                            workingDirectory: appState.workspacePath
                        )
                    }
            }
        }
    }

    /// Replace the focused pane's content with the given PaneContent.
    /// Guards against replacing a live terminal — requires double-action confirmation.
    private func openContentInFocusedPane(_ content: PaneContent) {
        guard BugbookFeatureGate.allowsPaneContent(content) else { return }
        guard let leaf = workspaceManager.activeWorkspace?.focusedLeaf else { return }
        let paneId = leaf.id
        let activeTabId = leaf.activeTabID

        // Guard: if focused pane is a live terminal, require double-action
        if isTerminalAlive(tabId: activeTabId) {
            if paneReplaceWarningId == paneId {
                clearPaneReplaceWarning()
            } else {
                setPaneReplaceWarning(paneId: paneId)
                return
            }
        }

        replacePaneContent(paneId: paneId, with: content)
    }

    private func openOrFocusPane(_ content: PaneContent) {
        guard BugbookFeatureGate.allowsPaneContent(content) else { return }
        if let paneID = matchingPaneID(for: content) {
            workspaceManager.setFocusedPane(id: paneID)
            return
        }

        guard let workspace = workspaceManager.activeWorkspace else {
            workspaceManager.addWorkspaceWith(content: content)
            return
        }

        if workspace.allLeaves.count == 1,
           let leaf = workspace.focusedLeaf,
           isReplaceablePlaceholderPane(leaf) {
            replacePaneContent(paneId: leaf.id, with: content)
            workspaceManager.setFocusedPane(id: leaf.id)
            return
        }

        workspaceManager.addWorkspaceWith(content: content)
    }

    private func matchingPaneID(for content: PaneContent) -> UUID? {
        guard let workspace = workspaceManager.activeWorkspace else { return nil }
        return workspace.allLeaves.first { leaf in
            paneContent(leaf.content, matches: content)
        }?.id
    }

    private func paneContent(_ existing: PaneContent, matches target: PaneContent) -> Bool {
        switch (existing, target) {
        case (.terminal, .terminal):
            return false  // Each terminal gets its own workspace — no reuse
        case let (.document(file), .document(targetFile)):
            return file.kind == targetFile.kind
        default:
            return false
        }
    }

    private func isReplaceablePlaceholderPane(_ leaf: PaneNode.Leaf) -> Bool {
        switch leaf.content {
        case .terminal:
            return false
        case .document(let file):
            return file.isEmptyTab
        }
    }

    private func replacePaneContent(paneId: UUID, with content: PaneContent) {
        guard BugbookFeatureGate.allowsPaneContent(content) else { return }
        guard let leaf = workspaceManager.leaf(id: paneId) else { return }
        cleanupPaneTabResources(paneId: paneId, tabId: leaf.activeTabID)
        workspaceManager.updatePaneContent(
            paneId: paneId,
            content: content.reidentified(as: leaf.activeTabID)
        )
        updateSidebarContextType()
    }

    private func cleanupPaneTabResources(paneId: UUID, tabId: UUID) {
        guard let leaf = workspaceManager.leaf(id: paneId),
              let content = leaf.tabs.first(where: { $0.id == tabId }) else { return }

        switch content {
        case .terminal:
            loadedLegacyPaneServices?.terminalManager.closeSession(tabId)
        case .document(let file):
            if file.isBrowser {
                loadedLegacyPaneServices?.browserManager.discardTabResources(tabId, in: paneId)
            } else {
                cleanupTabDocuments(tabId)
            }
        }
    }

    private func cleanupPaneResources(_ paneId: UUID) {
        guard let leaf = workspaceManager.leaf(id: paneId) else { return }
        for content in leaf.tabs {
            switch content {
            case .terminal(let sessionID):
                loadedLegacyPaneServices?.terminalManager.closeSession(sessionID)
            case .document(let file):
                if file.isBrowser {
                    loadedLegacyPaneServices?.browserManager.discardTabResources(file.id, in: paneId)
                } else {
                    cleanupTabDocuments(file.id)
                }
            }
        }
        loadedLegacyPaneServices?.browserManager.closeSession(paneId)
    }

    private func createPaneTab(in leaf: PaneNode.Leaf) {
        guard let newContent = leaf.activeContent.defaultNewPaneTab() else { return }
        guard BugbookFeatureGate.allowsPaneContent(newContent) else { return }
        let insertedTabId = workspaceManager.addPaneTab(to: leaf.id, content: newContent)
        if newContent.isBrowser, let insertedTabId, BugbookFeatureGate.shouldInitializeLegacyServices {
            _ = browserManager.ensurePage(for: leaf.id, tabID: insertedTabId)
        }
        updateSidebarContextType()
    }

    private func closePaneTab(in leaf: PaneNode.Leaf, tabId: UUID) {
        cleanupPaneTabResources(paneId: leaf.id, tabId: tabId)
        _ = workspaceManager.closePaneTab(paneId: leaf.id, tabId: tabId)
        updateSidebarContextType()
    }

    private func closePane(_ leaf: PaneNode.Leaf) {
        cleanupPaneResources(leaf.id)
        workspaceManager.closePane(id: leaf.id)
        updateSidebarContextType()
    }

    private func closeOtherPanes(keeping leaf: PaneNode.Leaf) {
        guard let workspace = workspaceManager.activeWorkspace else { return }
        for otherLeaf in workspace.allLeaves where otherLeaf.id != leaf.id {
            cleanupPaneResources(otherLeaf.id)
        }
        workspaceManager.keepOnlyPane(id: leaf.id)
        updateSidebarContextType()
    }

    private func closeActiveWorkspace() {
        guard let workspace = workspaceManager.activeWorkspace else { return }
        for leaf in workspace.allLeaves {
            cleanupPaneResources(leaf.id)
        }
        workspaceManager.closeWorkspace(at: workspaceManager.activeWorkspaceIndex)
        updateSidebarContextType()
    }

    private func shouldAllowClosingFocusedTab(in leaf: PaneNode.Leaf) -> Bool {
        guard let session = appState.activeMeetingSession,
              let doc = blockDocuments[leaf.activeTabID],
              doc.filePath == session.meetingPagePath else {
            return true
        }

        let alert = NSAlert()
        alert.messageText = "Recording in Progress"
        alert.informativeText = """
        A meeting is being recorded in this tab. The recording will continue in the background. \
        You can get back via the floating pill.
        """
        alert.addButton(withTitle: "Close Tab")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func closeFocusedPaneTabOrWorkspace() {
        guard let leaf = workspaceManager.focusedPane else { return }
        guard shouldAllowClosingFocusedTab(in: leaf) else { return }

        if leaf.tabs.count > 1 {
            closePaneTab(in: leaf, tabId: leaf.activeTabID)
        } else {
            closePane(leaf)
        }
    }

    private func reopenClosedPaneItem() {
        guard let reopenedTabID = workspaceManager.reopenLastClosedItem() else { return }
        if let leaf = workspaceManager.leaf(containingTabId: reopenedTabID),
           let file = leaf.tabs.first(where: { $0.id == reopenedTabID })?.openFile,
           file.isBrowser,
           BugbookFeatureGate.shouldInitializeLegacyServices {
            _ = browserManager.ensurePage(for: leaf.id, tabID: reopenedTabID)
        }
        updateSidebarContextType()
    }

    private func cycleFocusedPaneTabs(step: Int) {
        guard let leaf = workspaceManager.focusedPane else { return }
        workspaceManager.cyclePaneTabs(in: leaf.id, step: step)
        updateSidebarContextType()
    }

    private func isEditorDocumentPane(_ leaf: PaneNode.Leaf) -> Bool {
        guard case .document(let file) = leaf.content else { return false }
        return isDocumentEditorFile(file)
    }

    private func nearestEditorDocumentLeaf(from paneId: UUID) -> PaneNode.Leaf? {
        guard let workspace = workspaceManager.activeWorkspace else { return nil }
        return workspace.allLeaves.first { $0.id != paneId && isEditorDocumentPane($0) }
    }

    /// Routes a pane's OpenFile to the correct content view based on its TabKind.
    @ViewBuilder
    private func paneContentRouting(leaf: PaneNode.Leaf, file: OpenFile) -> some View {
        if file.isEmptyTab {
            Color.clear
                .task {
                    if BugbookFeatureGate.legacyPanesEnabled {
                        openDefaultPageIfConfigured()
                    } else {
                        openDailyNote()
                    }
                }
        } else if file.isDatabaseRow, let dbPath = file.databasePath, let rowId = file.databaseRowId {
            DatabaseRowFullPageView(
                dbPath: dbPath,
                rowId: rowId,
                onTitleChange: { title in
                    updateDatabaseRowTabTitle(tabId: file.id, title: title)
                },
                fullWidth: databaseRowFullWidth[leaf.id, default: false]
            )
            .id(file.id)
        } else if file.isMeetings, !BugbookFeatureGate.legacyPanesEnabled {
            meetingsPaneView()
        } else if file.isDatabase {
            DatabaseFullPageView(dbPath: file.path, initialRowId: dbInitialRowId)
                .id(file.id)
                .onAppear { dbInitialRowId = nil }
        } else if let doc = blockDocuments[file.id], doc.isMeetingPage, !doc.isCompletedMeetingPage {
            meetingPageView(for: file, document: doc)
        } else if isLegacyPaneFile(file), BugbookFeatureGate.legacyPanesEnabled {
            legacyPaneContentRouting(leaf: leaf, file: file)
        } else if isLegacyPaneFile(file) {
            Color.clear
                .task { openDailyNote() }
        } else {
            editorView(for: file)
        }
    }

    private func isLegacyPaneFile(_ file: OpenFile) -> Bool {
        file.isMail ||
            file.isCalendar ||
            file.isMeetings ||
            file.isBrowser ||
            file.isGraphView ||
            file.isSkill ||
            file.isChat ||
            file.isGateway
    }

    @ViewBuilder
    private func legacyPaneContentRouting(leaf: PaneNode.Leaf, file: OpenFile) -> some View {
        if file.isMail {
            MailPaneView(
                appState: appState,
                mailService: mailService
            )
        } else if file.isCalendar {
            WorkspaceCalendarView(
                appState: appState,
                calendarService: calendarService,
                calendarVM: calendarVM,
                meetingNoteService: meetingNoteService,
                aiService: legacyAiService,
                onNavigateToFile: { path in
                    navigateToFilePath(path)
                }
            )
        } else if file.isMeetings {
            meetingsPaneView()
        } else if file.isBrowser {
            BrowserPaneView(
                leaf: leaf,
                paneID: leaf.id,
                session: browserManager.session(for: leaf.id),
                appState: appState,
                fileTree: appState.fileTree,
                isSinglePane: !(workspaceManager.activeWorkspace?.hasMultiplePanes ?? false),
                browserManager: browserManager,
                workspaceManager: workspaceManager,
                fileSystem: fileSystem,
                aiService: legacyAiService,
                onOpenBugbookEntry: { entry in
                    navigateToEntryInPane(entry)
                }
            )
        } else if file.isGraphView {
            if let workspace = appState.workspacePath {
                GraphView(
                    backlinkService: backlinkService,
                    workspacePath: workspace,
                    currentPagePath: workspaceManager.focusedOpenFile?.path,
                    onNavigateToFile: { path in
                        navigateToFilePath(path)
                    }
                )
            }
        } else if file.isSkill {
            SkillDetailView(
                filePath: file.path,
                displayName: file.displayName ?? (file.path as NSString).lastPathComponent
            )
        } else if file.isChat {
            NotesChatView(appState: appState, aiService: legacyAiService)
        } else if file.isGateway {
            GatewayView(
                appState: appState,
                workspacePath: appState.workspacePath,
                mailService: mailService,
                onNavigateToFile: { path in
                    navigateToFilePath(path)
                },
                onOpenGatewayLink: { link in
                    switch link {
                    case .calendar:
                        openContentInFocusedPane(.calendarDocument())
                    case .graph:
                        openContentInFocusedPane(.graphDocument())
                    case .meetings:
                        openContentInFocusedPane(.meetingsDocument())
                    case .database(let path):
                        navigateToFilePath(path)
                    case .terminal:
                        openContentInFocusedPane(.terminal())
                    }
                }
            )
        } else {
            editorView(for: file)
        }
    }

    // MARK: - Editor

    @ViewBuilder
    private func editorView(for tab: OpenFile) -> some View {
        if let document = blockDocuments[tab.id] {
            editorDocumentView(document)
        } else {
            editorLoadingView()
        }
    }

    private func editorLoadingView() -> some View {
        ZStack {
            Color.fallbackEditorBg
            ProgressView()
                .controlSize(.small)
                .opacity(0.45)
        }
        .accessibilityIdentifier("editor-loading")
    }

    private func editorDocumentView(_ document: BlockDocument) -> some View {
        HStack(spacing: 0) {
            ScrollViewReader { scrollProxy in
                editorScrollView(document: document, scrollProxy: scrollProxy)
            }
        }
    }

    private func editorScrollView(document: BlockDocument, scrollProxy: ScrollViewProxy) -> some View {
        ScrollView {
            VStack(spacing: 0) {
                editorPageHeader(document)
                editorTitleRow(document)
                editorBlockEditor(document)
            }
        }
        .background(Color.fallbackEditorBg)
        .accessibilityIdentifier("editor")
        .bugbookCompactScrollIndicators()
        .overlay {
            templatePickerOverlay(document)
        }
        .onChange(of: document.selectionRect) { _, rect in
            updateFormattingPanel(rect: rect)
        }
        .onChange(of: document.selectedBlockIds) { _, ids in
            if ids.isEmpty {
                if document.multiBlockTextSelection == nil {
                    hideFormattingPanel()
                }
            } else {
                showBlockSelectionToolbar()
            }
        }
        .onChange(of: document.multiBlockTextSelection) { _, mbs in
            if mbs != nil {
                showBlockSelectionToolbar()
            } else if document.selectedBlockIds.isEmpty {
                hideFormattingPanel()
            }
        }
        .onChange(of: document.scrollToBlockId) { _, blockId in
            guard let blockId else { return }
            withAnimation(.easeInOut(duration: 0.3)) {
                scrollProxy.scrollTo(blockId, anchor: .top)
            }
            document.scrollToBlockId = nil
        }
    }

    private func editorPageHeader(_ document: BlockDocument) -> some View {
        PageHeaderView(
            icon: Binding(
                get: { document.icon },
                set: { updateDocumentIcon($0, document: document) }
            ),
            coverUrl: Binding(
                get: { document.coverUrl },
                set: {
                    document.coverUrl = $0
                    markActiveEditorTabDirty()
                    scheduleSave()
                }
            ),
            coverPosition: Binding(
                get: { document.coverPosition },
                set: {
                    document.coverPosition = $0
                    markActiveEditorTabDirty()
                    scheduleSave()
                }
            ),
            fullWidth: document.fullWidth,
            contentColumnMaxWidth: document.fullWidth ? nil : 860
        )
    }

    @ViewBuilder
    private func editorTitleRow(_ document: BlockDocument) -> some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 0) {
                if let titleBlock = document.titleBlock {
                    TextBlockView(document: document, block: titleBlock, onTyping: { triggerFocusMode() })
                        .padding(.leading, 76)
                        .padding(.trailing, 52)
                        .padding(.top, 8)
                }
            }
            .frame(maxWidth: document.fullWidth ? .infinity : 860)
            Spacer(minLength: 0)
        }
    }

    private func editorBlockEditor(_ document: BlockDocument) -> some View {
        BlockEditorView(
            document: document,
            onTextChange: {
                markActiveEditorTabDirty()
                syncTitle(from: document)
                scheduleSave()
            },
            onTyping: { triggerFocusMode() },
            onPagePathDrop: { sourcePath, insertIndex in
                handleSidebarPageDrop(sourcePath: sourcePath, into: document, at: insertIndex)
            },
            contentColumnMaxWidth: document.fullWidth ? nil : 860
        )
    }

    @ViewBuilder
    private func templatePickerOverlay(_ document: BlockDocument) -> some View {
        if document.showTemplatePicker {
            ZStack {
                Color.black.opacity(0.2)
                    .onTapGesture { document.showTemplatePicker = false }
                TemplatePickerView(
                    templates: fileSystem.listTemplates(in: appState.workspacePath ?? ""),
                    onSelect: { template in
                        document.showTemplatePicker = false
                        createPageFromTemplate(template)
                    },
                    onDismiss: { document.showTemplatePicker = false },
                    onCreateTemplate: {
                        document.showTemplatePicker = false
                        saveCurrentNoteAsTemplate(document: document)
                    }
                )
                .onTapGesture { }
            }
        }
    }

    private func updateDocumentIcon(_ newIcon: String?, document: BlockDocument) {
        document.icon = newIcon
        markActiveEditorTabDirty()
        if let workspace = workspaceManager.activeWorkspace,
           let leaf = workspace.focusedLeaf,
           case .document(let openFile) = leaf.content {
            workspaceManager.updateOpenFile(tabId: openFile.id, persist: false) { file in
                file.icon = newIcon
            }
            appState.updateFileTreeIcon(for: openFile.path, icon: newIcon)
        }
        if appState.activeTabIndex < appState.openTabs.count {
            appState.openTabs[appState.activeTabIndex].icon = newIcon
            appState.updateFileTreeIcon(for: appState.openTabs[appState.activeTabIndex].path, icon: newIcon)
        }
        scheduleSave()
    }

    // MARK: - Meeting Notification Handling

    private func handleMeetingNotification(_ notification: Foundation.Notification, startRecording: Bool) {
        guard let eventId = notification.userInfo?["eventId"] as? String,
              let eventTitle = notification.userInfo?["eventTitle"] as? String,
              let workspace = appState.workspacePath else { return }

        // Find the calendar event
        let event = calendarService.events.first { $0.id == eventId }

        Task {
            // Create or open the meeting note page
            let path: String?
            if let event {
                path = await meetingNoteService.createOrOpenMeetingNote(
                    for: event,
                    workspace: workspace,
                    fileSystem: fileSystem
                )
            } else {
                // Event not found in cache — open the deterministic page for this title,
                // creating it only if it doesn't already exist. Writing unconditionally
                // would clobber prior edits if the notification action is triggered twice.
                let dateStr = MeetingNoteService.sanitize(eventTitle)
                let dateFmt = DateFormatter()
                dateFmt.dateFormat = "yyyy-MM-dd"
                let pageName = "\(dateFmt.string(from: Date())) — \(dateStr)"
                let pagePath = (workspace as NSString).appendingPathComponent("\(pageName).md")

                let content = """
                ---
                title: \(eventTitle)
                date: \(ISO8601DateFormatter().string(from: Date()))
                type: meeting
                meeting_id: \(UUID().uuidString)
                ---

                # \(eventTitle)

                ## Notes

                """
                await Task.detached(priority: .utility) {
                    guard !FileManager.default.fileExists(atPath: pagePath) else { return }
                    try? content.write(toFile: pagePath, atomically: true, encoding: .utf8)
                }.value
                path = pagePath
            }

            guard let path else { return }
            if startRecording {
                appState.pendingAutoRecordPath = path
            }
            navigateToFilePath(path)
        }
    }

    // MARK: - Meeting Page

    @ViewBuilder
    private func meetingPageView(for file: OpenFile, document: BlockDocument) -> some View {
        MeetingPageView(
            appState: appState,
            document: document,
            transcriptionService: transcriptionService,
            meetingNoteService: meetingNoteService,
            transcriptStore: meetingTranscriptStore,
            onTextChange: {
                markActiveEditorTabDirty()
                scheduleSave()
            },
            onTyping: { triggerFocusMode() },
            onNavigateToFile: { path in navigateToFilePath(path) },
            onMeetingFinalized: {
                markActiveEditorTabDirty()
                performSave(tabId: file.id) {
                    if let workspace = appState.workspacePath {
                        try? fileSystem.refreshMeetingsDatabaseIndex(in: workspace)
                    }
                    refreshFileTree()
                }
            }
        )
    }

    private func wireUpDocumentCallbacks(_ doc: BlockDocument, tabId: UUID) {
        wireUpDocumentPageCallbacks(doc, tabId: tabId)
        wireUpDocumentNavigationCallbacks(doc)
        wireUpDocumentAICallbacks(doc)
        wireUpDocumentMeetingBlockCallbacks(doc)
        wireUpDocumentDropCallbacks(doc)
    }

    private func wireUpDocumentPageCallbacks(_ doc: BlockDocument, tabId: UUID) {
        doc.onCreateDatabase = { [weak appState] name in
            guard appState?.workspacePath != nil else { return nil }
            let path = try? createDatabasePath(name: name, parentPagePath: doc.filePath)
            if path != nil { refreshFileTree() }
            return path
        }
        doc.onCreateMeetingDatabase = { [weak appState] in
            guard let workspace = appState?.workspacePath else { return nil }
            let path = ensureMeetingsDatabase(in: workspace)
            if path != nil { refreshFileTree() }
            return path
        }
        doc.onCreateSubPage = { [weak doc] name in
            guard let parentPath = doc?.filePath else { return nil }
            let path = try? fileSystem.createSubPage(under: parentPath, name: name)
            if path != nil { refreshFileTree() }
            return path
        }
        doc.onDeleteSubPage = { [weak appState, weak doc] pageName in
            guard let doc,
                  let tabPath = doc.filePath,
                  let workspace = appState?.workspacePath else { return }
            // Companion folder is the .md path with extension stripped
            let parentDir = tabPath.hasSuffix(".md") ? String(tabPath.dropLast(3)) : tabPath
            let childPath = (parentDir as NSString).appendingPathComponent("\(pageName).md")
            guard FileManager.default.fileExists(atPath: childPath) else { return }
            try? fileSystem.trashFile(at: childPath, workspace: workspace)
            NotificationCenter.default.post(name: .fileDeleted, object: childPath)
            // Immediately save the parent page so the deleted block doesn't reappear on reload
            performSave(tabId: tabId) {
                refreshFileTree()
            }
        }
        doc.onToggleFavorite = { path in
            self.toggleFavorite(path: path)
        }
        doc.onIsFavorite = { path in
            self.isPathFavorited(path)
        }
    }

    private func wireUpDocumentNavigationCallbacks(_ doc: BlockDocument) {
        doc.availablePages = appState.fileTree
        doc.workspacePath = appState.workspacePath
        doc.onNavigateToPage = { pageName in
            navigateToPage(named: pageName)
        }
        doc.onMoveBlock = { [weak appState] blockId, destDir in
            guard let appState else { return }
            guard let tab = appState.activeTab,
                  let doc = blockDocuments[tab.id],
                  let block = doc.block(for: blockId) else { return }
            let blockMarkdown = MarkdownBlockParser.serialize([block])
            let sourceTabId = tab.id
            let targetPagePath = destDir + ".md"
            guard targetPagePath != tab.path else { return }

            Task { @MainActor in
                let result = await editorSaveWorker.appendMarkdownToFile(
                    at: targetPagePath,
                    markdown: blockMarkdown
                )

                guard case .loaded(let loadedPage) = result else {
                    if case .failed(let message) = result {
                        Log.fileSystem.error("Move block failed: \(message)")
                    }
                    return
                }

                guard let doc = blockDocuments[sourceTabId],
                      doc.block(for: blockId) != nil else {
                    return
                }

                // Suppress sub-page deletion during move — we're relocating, not deleting
                let savedCallback = doc.onDeleteSubPage
                doc.onDeleteSubPage = nil
                doc.deleteBlock(id: blockId)
                doc.onDeleteSubPage = savedCallback
                doc.moveBlockId = nil
                doc.blockMenuBlockId = nil
                if let targetTab = appState.openTabs.first(where: { $0.path == targetPagePath }),
                   let targetDoc = blockDocuments[targetTab.id] {
                    targetDoc.replaceMarkdown(loadedPage.content, parsed: loadedPage.parsedDocument)
                }
            }
        }
        doc.onOpenDatabaseTab = { dbPath in
            openDatabase(at: dbPath)
        }
    }

    private func wireUpDocumentAICallbacks(_ doc: BlockDocument) {
        doc.onSubmitAiPrompt = { [weak appState, weak doc] prompt in
            guard let appState, let doc else { return }
            doc.dismissAiPrompt()
            guard BugbookFeatureGate.shouldExposeAgentSurfaces else { return }
            appState.openAiPanel(prompt: prompt)
        }
        doc.onCancelAiPrompt = { [weak doc] in
            doc?.dismissAiPrompt()
        }
    }

    private func wireUpDocumentMeetingBlockCallbacks(_ doc: BlockDocument) {
        let ts = transcriptionService
        doc.transcriptionService = ts
        doc.onStartMeeting = { [weak appState, weak doc] blockId in
            Task {
                await ts.startRecording()
                appState?.isRecording = true
                appState?.recordingBlockId = blockId
                // Poll confirmed segments and audio level after recording starts
                var lastSegmentCount = 0
                var lastVolatile = ""
                var lastLevel: Float = -1
                while ts.isRecording {
                    // Stop if the recording block was deleted
                    if let doc, doc.index(for: blockId) == nil {
                        _ = ts.stopRecording()
                        appState?.isRecording = false
                        appState?.recordingBlockId = nil
                        break
                    }

                    let level = ts.audioLevel
                    if level != lastLevel {
                        lastLevel = level
                        doc?.meetingAudioLevel = level
                    }

                    let segments = ts.confirmedSegments
                    let volatile = ts.volatileText
                    let segmentsChanged = segments.count != lastSegmentCount
                    let volatileChanged = volatile != lastVolatile
                    if segmentsChanged || volatileChanged {
                        lastSegmentCount = segments.count
                        lastVolatile = volatile
                        var entries = segments
                        if !volatile.isEmpty { entries.append(volatile) }
                        let fullText = entries.joined(separator: " ")
                        doc?.updateBlockProperty(id: blockId) { block in
                            block.transcriptEntries = entries
                            block.meetingTranscript = fullText
                            block.text = fullText
                        }
                        doc?.meetingVolatileText = volatile
                    }

                    try? await Task.sleep(for: .milliseconds(100))
                }
                doc?.meetingAudioLevel = 0
                doc?.meetingVolatileText = ""
            }
        }
        doc.onStopMeeting = { [weak appState, weak doc] blockId in
            _ = ts.stopRecording()
            appState?.isRecording = false
            appState?.recordingBlockId = nil
            guard let doc else { return }
            let transcript = ts.currentTranscript
            doc.updateBlockProperty(id: blockId) { block in
                block.meetingState = .complete
                block.meetingTranscript = transcript
                block.text = transcript
            }
        }
    }

    private func wireUpDocumentDropCallbacks(_ doc: BlockDocument) {
        doc.onDropPageFromSidebar = { [weak appState, weak doc] sourcePath, insertionIndex in
            guard let appState, let doc else { return }
            guard let tab = appState.activeTab else { return }
            // Don't drop a page onto itself
            guard sourcePath != tab.path else { return }
            // Don't move databases into companion folders via editor drops
            guard !fileSystem.isDatabaseFolder(at: sourcePath) else { return }

            let pageName = ((sourcePath as NSString).lastPathComponent as NSString)
                .deletingPathExtension

            // Insert the page link block at the drop location
            doc.insertPageLinkBlock(at: insertionIndex, name: pageName)

            // Mark dirty and save immediately so performMovePage sees the link
            // already in the file and doesn't append a duplicate at the bottom
            updateWorkspaceOpenFile(tabId: tab.id) { file in
                file.isDirty = true
            }
            if let tabIdx = appState.openTabs.firstIndex(where: { $0.id == tab.id }) {
                appState.openTabs[tabIdx].isDirty = true
            }
            let companionDir = tab.path.hasSuffix(".md") ? String(tab.path.dropLast(3)) : tab.path
            performSave(tabId: tab.id) {
                // Move the file into this page's companion folder
                performMovePage(from: sourcePath, toDirectory: companionDir)
            }
        }
    }

    // MARK: - Theme

    private func applyTheme(_ theme: ThemeMode) {
        switch theme {
        case .light:
            NSApp.appearance = NSAppearance(named: .aqua)
        case .dark:
            NSApp.appearance = NSAppearance(named: .darkAqua)
        case .system:
            NSApp.appearance = nil
        }
    }

    private func applyTerminalColorScheme(_ mode: TerminalColorSchemeMode) {
        let light = appState.settings.terminalLightTheme
        let dark = appState.settings.terminalDarkTheme
        if !light.isEmpty || !dark.isEmpty {
            // Custom themes selected — rebuild config with theme overlay
            terminalManager.applyTheme(lightTheme: light, darkTheme: dark, colorScheme: mode)
        } else {
            // No custom themes — just set color scheme hint
            // (uses whatever theme is in ~/.config/ghostty/config)
            let scheme: ghostty_color_scheme_e
            switch mode {
            case .light: scheme = GHOSTTY_COLOR_SCHEME_LIGHT
            case .dark: scheme = GHOSTTY_COLOR_SCHEME_DARK
            case .system:
                let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                scheme = isDark ? GHOSTTY_COLOR_SCHEME_DARK : GHOSTTY_COLOR_SCHEME_LIGHT
            }
            terminalManager.applyColorScheme(scheme)
        }
    }

    // MARK: - Formatting Toolbar

    private func updateFormattingPanel(rect: CGRect?) {
        guard let rect = rect else {
            hideFormattingPanel()
            return
        }
        guard let textView = activeBlockTextView(), textView.selectedRange().length > 0 else {
            hideFormattingPanel()
            return
        }
        let panel: FormattingToolbarPanel
        if let existing = formattingPanel {
            panel = existing
        } else {
            panel = FormattingToolbarPanel()
            formattingPanel = panel
        }
        // Wire actions to the currently focused BlockNSTextView via first responder
        panel.updateActions(
            onBold: { activeBlockTextView()?.formatBoldAction?() },
            onItalic: { activeBlockTextView()?.formatItalicAction?() },
            onCode: { activeBlockTextView()?.formatCodeAction?() },
            onStrikethrough: { activeBlockTextView()?.formatStrikethroughAction?() },
            onLink: { activeBlockTextView()?.formatLinkAction?() },
            onAskAI: BugbookFeatureGate.shouldExposeAgentSurfaces ? { [weak appState] in
                guard let appState,
                      let tab = appState.activeTab,
                      let doc = blockDocuments[tab.id],
                      let selectedMarkdown = doc.selectedBlocksMarkdown() else { return }
                hideFormattingPanel()
                let blockItems = doc.selectedBlockContextItems()
                appState.aiSelectionContext = selectedMarkdown
                appState.openAiPanel(referencedItems: blockItems)
            } : nil
        )
        panel.show(above: rect)
    }

    private func activeBlockTextView() -> BlockNSTextView? {
        NSApp.keyWindow?.firstResponder as? BlockNSTextView
    }

    private func showBlockSelectionToolbar() {
        guard let tab = appState.activeTab,
              let doc = blockDocuments[tab.id],
              let blockRect = doc.lastSelectedBlockRect else {
            hideFormattingPanel()
            return
        }
        let panel: FormattingToolbarPanel
        if let existing = formattingPanel {
            panel = existing
        } else {
            panel = FormattingToolbarPanel()
            formattingPanel = panel
        }
        // For block selection, only show the Ask AI action
        panel.updateActions(
            onBold: {},
            onItalic: {},
            onCode: {},
            onStrikethrough: {},
            onLink: {},
            onAskAI: BugbookFeatureGate.shouldExposeAgentSurfaces ? { [weak appState] in
                guard let appState,
                      let tab = appState.activeTab,
                      let doc = blockDocuments[tab.id],
                      let selectedMarkdown = doc.selectedBlocksMarkdown() else { return }
                hideFormattingPanel()
                let blockItems = doc.selectedBlockContextItems()
                appState.aiSelectionContext = selectedMarkdown
                appState.openAiPanel(referencedItems: blockItems)
            } : nil
        )
        panel.show(above: blockRect)
    }

    private func hideFormattingPanel() {
        formattingPanel?.hidePanel()
    }

    // MARK: - Actions

    private func handleSidebarFileSelect(_ entry: FileEntry) {
        appState.currentView = .editor
        appState.showSettings = false

        let cmdHeld = NSEvent.modifierFlags.contains(.command)
        if cmdHeld {
            // Cmd+click: split the focused pane and open in the new split
            let paneId = UUID()
            let file = makeOpenFile(for: entry, id: paneId)
            if let newPaneId = workspaceManager.splitFocusedPane(axis: .horizontal, newContent: .document(openFile: file)) {
                loadFileContentForPane(entry: entry, tabId: newPaneId)
            }
        } else {
            // Normal click: open in the focused pane (or nearest document pane)
            navigateToEntryInPane(entry)
        }
    }

    // MARK: - Pane Navigation Helpers

    /// Create an OpenFile from a FileEntry with a specific UUID (for pane leaf identity).
    private func makeOpenFile(for entry: FileEntry, id: UUID) -> OpenFile {
        let history = entry.path.isEmpty ? [] : [entry.path]
        let historyIndex = history.isEmpty ? -1 : 0
        let name = entry.name.hasSuffix(".md") ? String(entry.name.dropLast(3)) : entry.name
        return OpenFile(
            id: id,
            path: entry.path,
            content: "",
            isDirty: false,
            isEmptyTab: entry.path.isEmpty,
            kind: entry.kind,
            displayName: name,
            icon: entry.icon,
            navigationHistory: history,
            navigationHistoryIndex: historyIndex
        )
    }

    /// Navigate to a file entry in the appropriate pane.
    /// Uses the focused pane if it's a document pane, otherwise finds the nearest document pane.
    private func navigateToEntryInPane(_ entry: FileEntry, preferExistingTab: Bool = true) {
        appState.currentView = .editor
        appState.showSettings = false

        guard let ws = workspaceManager.activeWorkspace else { return }

        // Save current pane if dirty
        let focusedPaneId = ws.focusedPaneId
        let focusedTabId = ws.focusedLeaf?.activeTabID
        if let leaf = ws.focusedLeaf,
           case .document(let file) = leaf.content,
           file.isDirty {
            performSave(tabId: file.id)
        }

        // Guard: if focused pane is a live terminal, warn before replacing it
        if let focusedTabId, isTerminalAlive(tabId: focusedTabId) {
            if paneReplaceWarningId == focusedPaneId {
                // Second press within timeout — proceed: close terminal, replace in place
                clearPaneReplaceWarning()

                let willReuseExistingTab = workspaceManager.activeWorkspace?.allLeaves.contains { leaf in
                    leaf.tabs.compactMap(\.openFile).contains { $0.path == entry.path }
                } == true

                if !willReuseExistingTab {
                    cleanupPaneTabResources(paneId: focusedPaneId, tabId: focusedTabId)
                }

                let handledWithoutLoad = appState.openFileReplacingCurrentTab(
                    entry,
                    workspaceManager: workspaceManager,
                    paneId: focusedPaneId,
                    pushHistory: true,
                    preferExistingTab: preferExistingTab
                )
                updateSidebarContextType()

                if let updatedTabId = workspaceManager.focusedPaneTabID {
                    if handledWithoutLoad {
                        loadFileContentForPaneIfMissing(entry: entry, tabId: updatedTabId)
                    } else {
                        loadFileContentForPane(entry: entry, tabId: updatedTabId)
                    }
                }
                return
            } else {
                // First press — show amber warning on the terminal pane
                setPaneReplaceWarning(paneId: focusedPaneId)
                return
            }
        }

        // Determine target pane (non-terminal path)
        let targetPaneId: UUID
        if let focusedLeaf = workspaceManager.focusedPane, isEditorDocumentPane(focusedLeaf) {
            targetPaneId = focusedLeaf.id
        } else if let nearestDoc = nearestEditorDocumentLeaf(from: focusedPaneId) {
            targetPaneId = nearestDoc.id
        } else {
            targetPaneId = focusedPaneId
        }

        let willReuseExistingTab = workspaceManager.activeWorkspace?.allLeaves.contains { leaf in
            leaf.tabs.compactMap(\.openFile).contains { $0.path == entry.path }
        } == true

        if !willReuseExistingTab,
           let targetTabId = workspaceManager.leaf(id: targetPaneId)?.activeTabID {
            cleanupPaneTabResources(paneId: targetPaneId, tabId: targetTabId)
        }

        let handledWithoutLoad = appState.openFileReplacingCurrentTab(
            entry,
            workspaceManager: workspaceManager,
            paneId: targetPaneId,
            pushHistory: true,
            preferExistingTab: preferExistingTab
        )
        updateSidebarContextType()

        if let updatedTabId = workspaceManager.focusedPaneTabID {
            if handledWithoutLoad {
                loadFileContentForPaneIfMissing(entry: entry, tabId: updatedTabId)
            } else {
                loadFileContentForPane(entry: entry, tabId: updatedTabId)
            }
        }
    }

    private func loadFileContentForPaneIfMissing(entry: FileEntry, tabId: UUID) {
        guard blockDocuments[tabId] == nil else { return }
        loadFileContentForPane(entry: entry, tabId: tabId)
    }

    /// Check if a pane has an active terminal session.
    private func isTerminalAlive(tabId: UUID) -> Bool {
        guard let session = loadedLegacyPaneServices?.terminalManager.session(for: tabId) else { return false }
        return session.isAlive
    }

    /// Set the amber warning on a pane's chrome bar. Auto-clears after 2 seconds.
    private func setPaneReplaceWarning(paneId: UUID) {
        paneReplaceWarningTask?.cancel()
        paneReplaceWarningId = paneId
        paneReplaceWarningTask = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            await MainActor.run { clearPaneReplaceWarning() }
        }
    }

    private func clearPaneReplaceWarning() {
        paneReplaceWarningId = nil
        paneReplaceWarningTask?.cancel()
        paneReplaceWarningTask = nil
    }

    /// Open a file entry in a new workspace tab (used by Cmd+K new-tab mode).
    private func openEntryInNewWorkspaceTab(_ entry: FileEntry) {
        appState.currentView = .editor
        appState.showSettings = false

        let paneId = UUID()
        let file = makeOpenFile(for: entry, id: paneId)
        workspaceManager.addWorkspaceWith(content: .document(openFile: file))
        if let actualTabId = workspaceManager.activeWorkspace?.focusedLeaf?.activeTabID {
            loadFileContentForPane(entry: entry, tabId: actualTabId)
        }
    }

    // MARK: - External File Open ("Open With" handler)

    /// Drain any markdown files the macOS "Open With" handler buffered in `AppDelegate`.
    /// Waits until the app's own launch navigation (e.g. opening the daily note) has
    /// settled — otherwise that async navigation clobbers the external file's pane.
    /// Retries up to ~5s, then opens anyway so a buffered file is never lost.
    private func drainPendingExternalFiles(attempt: Int = 0) {
        guard !AppDelegate.peekPendingExternalFilePaths().isEmpty else { return }
        let ready = (workspaceManager.focusedPane != nil && launchNavigationSettled) || attempt >= 25
        guard ready else {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 200_000_000)
                drainPendingExternalFiles(attempt: attempt + 1)
            }
            return
        }
        let paths = AppDelegate.takePendingExternalFilePaths()
        Log.app.info("drainPendingExternalFiles: opening \(paths.count) external file(s) [attempt \(attempt)]")
        for path in paths {
            openExternalFile(at: path)
        }
    }

    /// Open a markdown file from outside the workspace as its own top-level workspace tab.
    /// External tabs are not autosaved — saving moves the file into the workspace
    /// (see `saveExternalFileToWorkspace`).
    private func openExternalFile(at path: String) {
        Log.app.info("openExternalFile: \(path)")
        guard FileManager.default.fileExists(atPath: path) else {
            Log.fileSystem.error("External file no longer exists: \(path)")
            return
        }
        appState.currentView = .editor
        appState.showSettings = false

        // Already open in a workspace — switch to that workspace instead of reopening.
        if let existingIndex = workspaceManager.workspaces.firstIndex(where: { ws in
            ws.allLeaves.contains { leaf in
                leaf.tabs.contains { $0.openFile?.path == path }
            }
        }) {
            workspaceManager.switchWorkspace(to: existingIndex)
            return
        }

        // Open as its own top-level workspace tab.
        let name = (path as NSString).lastPathComponent
        let entry = FileEntry(id: path, name: name, path: path, isDirectory: false, kind: .page)
        var file = makeOpenFile(for: entry, id: UUID())
        file.isExternal = true
        workspaceManager.addWorkspaceWith(content: .document(openFile: file))
        if let actualTabId = workspaceManager.activeWorkspace?.focusedLeaf?.activeTabID {
            loadFileContentForPane(entry: entry, tabId: actualTabId)
        }
        updateSidebarContextType()
    }

    /// Move an external markdown file into the workspace: write the current editor content
    /// to the workspace root, delete the original file, and convert the tab to a normal note.
    private func saveExternalFileToWorkspace(tabId: UUID) {
        guard let workspace = appState.workspacePath, !workspace.isEmpty,
              let file = workspaceManager.openFile(tabId: tabId),
              let document = blockDocuments[tabId] else { return }
        let originalPath = file.path
        let content = document.markdown
        let destPath = uniqueWorkspaceDestination(
            forName: (originalPath as NSString).lastPathComponent,
            in: workspace
        )

        do {
            try content.write(toFile: destPath, atomically: true, encoding: .utf8)
        } catch {
            Log.fileSystem.error("Failed to move external file into workspace: \(error.localizedDescription)")
            return
        }
        try? FileManager.default.removeItem(atPath: originalPath)

        document.filePath = destPath
        let cleanName = (destPath as NSString).lastPathComponent
        workspaceManager.updateOpenFile(tabId: tabId) { entry in
            entry.path = destPath
            entry.isExternal = false
            entry.isDirty = false
            entry.displayName = cleanName.hasSuffix(".md") ? String(cleanName.dropLast(3)) : cleanName
        }
        refreshFileTree()
        backlinkService.updateFile(at: destPath, in: workspace)
    }

    /// Finder-style non-colliding destination path in the workspace root (`name 2.md`, …).
    private func uniqueWorkspaceDestination(forName fileName: String, in directory: String) -> String {
        let ext = (fileName as NSString).pathExtension
        let base = (fileName as NSString).deletingPathExtension
        var candidate = fileName
        var counter = 2
        while FileManager.default.fileExists(
            atPath: (directory as NSString).appendingPathComponent(candidate)
        ) {
            candidate = ext.isEmpty ? "\(base) \(counter)" : "\(base) \(counter).\(ext)"
            counter += 1
        }
        return (directory as NSString).appendingPathComponent(candidate)
    }

    private func openLauncherFile(_ entry: FileEntry, destination: CommandPaletteDestination) {
        switch destination {
        case .inPlace:
            navigateToEntryInPane(entry, preferExistingTab: false)
        case .newWorkspaceTab:
            openEntryInNewWorkspaceTab(entry)
        case .splitRight:
            splitLauncherFileRight(entry)
        }
    }

    private func createLauncherItem(_ kind: CommandPaletteCreateKind, destination: CommandPaletteDestination) {
        guard kind.isAvailableInCurrentMode else { return }
        if kind == .page {
            createNewFile(destination: destination)
            return
        }

        guard let content = kind.content else { return }
        openLauncherContent(content, destination: destination)
    }

    private func openLauncherPane(
        _ reference: CommandPaletteOpenPaneReference,
        destination: CommandPaletteDestination
    ) {
        guard BugbookFeatureGate.allowsPaneContent(reference.content) else { return }
        switch destination {
        case .inPlace, .newWorkspaceTab:
            workspaceManager.focusPaneTab(
                workspaceIndex: reference.workspaceIndex,
                paneID: reference.paneID,
                tabID: reference.tabID
            )
            updateSidebarContextType()
        case .splitRight:
            _ = workspaceManager.splitFocusedPane(axis: .horizontal, newContent: reference.content)
            updateSidebarContextType()
        }
    }

    private func openLauncherContent(_ content: PaneContent, destination: CommandPaletteDestination) {
        guard BugbookFeatureGate.allowsPaneContent(content) else { return }
        switch destination {
        case .inPlace:
            openContentInFocusedPane(content)
        case .newWorkspaceTab:
            workspaceManager.addWorkspaceWith(content: content)
        case .splitRight:
            _ = workspaceManager.splitFocusedPane(axis: .horizontal, newContent: content)
        }
        updateSidebarContextType()
    }

    private func splitLauncherFileRight(_ entry: FileEntry) {
        let tabId = UUID()
        let content = PaneContent.document(openFile: makeOpenFile(for: entry, id: tabId))
        guard let newLeafId = workspaceManager.splitFocusedPane(axis: .horizontal, newContent: content),
              let insertedTabId = workspaceManager.leaf(id: newLeafId)?.activeTabID else {
            return
        }
        loadFileContentForPane(entry: entry, tabId: insertedTabId)
        updateSidebarContextType()
    }

    private func createNewFile(destination: CommandPaletteDestination) {
        guard let workspace = appState.workspacePath else { return }
        do {
            let path = try fileSystem.createNewFile(in: workspace)
            let entry = FileEntry(id: path, name: (path as NSString).lastPathComponent, path: path, isDirectory: false)
            openLauncherFile(entry, destination: destination)
            refreshFileTree()
        } catch {
            Log.fileSystem.error("Failed to create file: \(error.localizedDescription)")
        }
    }

    /// Handle deferred Cmd+K navigation in ContentView's own render cycle.
    private func handlePendingCmdKNavigation(_ request: CmdKNavRequest?) {
        guard let request else { return }
        pendingCmdKNavigation = nil
        if request.inNewTab {
            openEntryInNewWorkspaceTab(request.entry)
        } else {
            navigateToEntryInPane(request.entry)
        }
        if let query = request.searchQuery {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                guard let ws = workspaceManager.activeWorkspace,
                      let focusedLeaf = ws.focusedLeaf,
                      let doc = blockDocuments[focusedLeaf.activeTabID] else { return }
                let lowerQuery = query.lowercased()
                if let block = doc.blocks.first(where: {
                    $0.text.lowercased().contains(lowerQuery)
                }) {
                    doc.focusedBlockId = block.id
                    doc.cursorPosition = 0
                }
            }
        }
    }

    /// Load file content from disk into a pane's BlockDocument.
    private func loadFileContentForPane(entry: FileEntry, tabId: UUID) {
        guard !entry.isDatabase,
              !entry.isDatabaseRow,
              !entry.isSkill,
              !entry.isMail,
              !entry.isCalendar,
              !entry.isMeetings,
              !entry.isGateway,
              !entry.isBrowser,
              !entry.isChat,
              !entry.isGraphView else { return }
        let signpostState = Log.signpost.beginInterval("loadFileContent")
        defer { Log.signpost.endInterval("loadFileContent", signpostState) }
        pagePreloadTask?.cancel()
        formattingPanel?.hidePanel()
        editorUI.focusModeSuppress = true
        pageLoadTasks[tabId]?.cancel()
        pageLoadTasks[tabId] = Task { @MainActor in
            let result = await editorSaveWorker.loadPageContent(at: entry.path)
            guard !Task.isCancelled else { return }
            handleLoadedPanePage(result, entry: entry, tabId: tabId)
            pageLoadTasks[tabId] = nil
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            editorUI.focusModeSuppress = false
        }
    }

    private func handleLoadedPanePage(_ result: EditorLoadResult, entry: FileEntry, tabId: UUID) {
        switch result {
        case .loaded(let loadedPage):
            guard workspaceManager.openFile(tabId: tabId)?.path == entry.path else { return }
            let content = loadedPage.content
            let doc = BlockDocument(markdown: content, parsed: loadedPage.parsedDocument)
            doc.filePath = entry.path
            wireUpDocumentCallbacks(doc, tabId: tabId)
            injectChildPageLinks(into: doc, from: entry)

            blockDocuments[tabId] = doc

            // Sync icon and display name from parsed document
            workspaceManager.updateOpenFile(tabId: tabId, persist: false) { file in
                file.content = content
                file.isDirty = loadedPage.isRestoredDraft
                file.icon = doc.icon
                if let rawTitle = doc.titleBlock?.text, !rawTitle.isEmpty {
                    file.displayName = AttributedStringConverter.plainText(from: rawTitle)
                } else if doc.isMeetingPage,
                          let yamlTitle = MarkdownBlockParser.yamlValue(for: "title", in: doc.yamlFrontmatter) {
                    file.displayName = yamlTitle
                }
            }
        case .failed(let message):
            Log.editor.error("Failed to load file: \(message)")
        case .missing, .cancelled:
            return
        }
    }

    private func openSettingsTab() {
        appState.selectedSettingsTab = BugbookFeatureGate.normalizedSettingsTab(appState.selectedSettingsTab)
        appState.showSettings = true
    }

    private func navigateToEntry(
        _ entry: FileEntry,
        inNewTab: Bool = false,
        preferExistingTab: Bool = true
    ) {
        appState.currentView = .editor
        appState.showSettings = false

        if let activeTab = appState.activeTab, activeTab.isDirty {
            performSave(tabId: activeTab.id)
        }

        if inNewTab {
            appState.openFileInNewTab(entry)
            loadFileContent(for: entry)
            return
        }

        let switchedToExisting = appState.openFileReplacingCurrentTab(
            entry,
            pushHistory: true,
            preferExistingTab: preferExistingTab
        )
        if switchedToExisting {
            loadFileContentIfMissing(for: entry)
        } else {
            loadFileContent(for: entry)
        }
    }

    private func loadFileContentIfMissing(for entry: FileEntry) {
        guard let tabId = appState.openTabs.first(where: { $0.path == entry.path })?.id,
              blockDocuments[tabId] == nil else { return }
        loadFileContent(for: entry)
    }

    private func openDatabaseRowPage(
        dbPath: String,
        rowId: String,
        inNewTab: Bool = false,
        preferExistingTab: Bool = true
    ) {
        if let pagePath = fileSystem.firstPartyPagePathForDatabaseRow(dbPath: dbPath, rowId: rowId) {
            let name = (pagePath as NSString).lastPathComponent
            let entry = FileEntry(id: pagePath, name: name, path: pagePath, isDirectory: false, kind: .page)
            navigateToEntry(entry, inNewTab: inNewTab, preferExistingTab: preferExistingTab)
            return
        }

        let rowPath = DatabaseRowNavigationPath.make(dbPath: dbPath, rowId: rowId)
        let entry = FileEntry(
            id: rowPath,
            name: "New Page",
            path: rowPath,
            isDirectory: false,
            kind: .databaseRow(dbPath: dbPath, rowId: rowId)
        )
        navigateToEntry(entry, inNewTab: inNewTab, preferExistingTab: preferExistingTab)
    }

    private func openDefaultPageIfConfigured() {
        let defaultPage = appState.settings.defaultNewTabPage
        guard !defaultPage.isEmpty else { return }
        guard FileManager.default.fileExists(atPath: defaultPage) else { return }
        let name = (defaultPage as NSString).lastPathComponent
        let schemaPath = (defaultPage as NSString).appendingPathComponent("_schema.json")
        let isDatabase = FileManager.default.fileExists(atPath: schemaPath)
        let kind: TabKind = isDatabase ? .database : .page
        let entry = FileEntry(
            id: defaultPage,
            name: name,
            path: defaultPage,
            isDirectory: isDatabase,
            kind: kind
        )
        navigateToEntry(entry, preferExistingTab: false)
    }

    private func navigateBackInActiveTab() {
        SentryBreadcrumbs.add(Breadcrumb(level: .info, category: "navigation.back"))
        if let activeTab = appState.activeTab, activeTab.isDirty {
            performSave(tabId: activeTab.id)
        }
        if let entry = appState.goBackInActiveTab() {
            loadFileContent(for: entry)
        }
    }

    private func navigateForwardInActiveTab() {
        SentryBreadcrumbs.add(Breadcrumb(level: .info, category: "navigation.forward"))
        if let activeTab = appState.activeTab, activeTab.isDirty {
            performSave(tabId: activeTab.id)
        }
        if let entry = appState.goForwardInActiveTab() {
            loadFileContent(for: entry)
        }
    }

    private func navigateToBreadcrumb(_ item: BreadcrumbItem) {
        let candidates = [item.path, item.id].filter { !$0.isEmpty }
        guard let targetPath = candidates.first(where: isOpenableBreadcrumbPath(_:)) else { return }
        guard appState.activeTab?.path != targetPath else { return }

        if let existing = fileSystem.findEntry(path: targetPath, in: appState.fileTree) {
            navigateToEntry(existing, preferExistingTab: false)
            return
        }

        let isDatabase = fileSystem.isDatabaseFolder(at: targetPath)
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: targetPath, isDirectory: &isDir)
        let kind: TabKind = isDatabase ? .database : .page
        let entry = FileEntry(
            id: targetPath,
            name: item.name,
            path: targetPath,
            isDirectory: isDir.boolValue,
            kind: kind,
            icon: item.icon
        )
        navigateToEntry(entry, preferExistingTab: false)
    }

    private func isOpenableBreadcrumbPath(_ path: String) -> Bool {
        if fileSystem.isDatabaseFolder(at: path) { return true }
        return FileManager.default.fileExists(atPath: path)
    }

    private func warmUpTranscriptionModel() {
        Task(priority: .background) {
            try? await transcriptionService.prepareFluidAsrManager()
        }
    }

    private func loadAppSettings() {
        appState.settings = appSettingsStore.load()
        appState.selectedSettingsTab = BugbookFeatureGate.normalizedSettingsTab(appState.selectedSettingsTab)
        guard BugbookFeatureGate.shouldInitializeLegacyServices else { return }
        browserManager.setHistoryEnabled(appState.settings.browserHistoryEnabled)
        browserManager.configureExtensions(appState.settings.browserExtensionPaths)
    }

    private func migrateLegacyWorkspace(_ legacyWorkspace: FileSystemService.LegacyWorkspace) {
        Task { @MainActor in
            await appState.migrateLegacyWorkspace(legacyWorkspace, using: fileSystem)
        }
    }

    private func scheduleLegacyWorkspaceRefresh() {
        guard BugbookFeatureGate.shouldScanLegacyWorkspaces else {
            appState.legacyWorkspaces = []
            return
        }
        Task { @MainActor in
            await appState.refreshLegacyWorkspacesInBackground(using: fileSystem)
        }
    }

    private func initializeWorkspace() {
        // Start with the fast local path so the initial window can appear immediately.
        let configuredWorkspacePath = appState.settings.resolvedNotesFolderPath()
        let usesConfiguredWorkspace = !configuredWorkspacePath.isEmpty
        let workspacePath = usesConfiguredWorkspace ? configuredWorkspacePath : fileSystem.defaultWorkspacePath()
        if !FileManager.default.fileExists(atPath: workspacePath) {
            try? FileManager.default.createDirectory(atPath: workspacePath, withIntermediateDirectories: true)
        }
        fileSystem.setWorkspace(workspacePath)
        scheduleTrashPurgeIfNeeded(for: workspacePath)
        appState.workspacePath = workspacePath
        scheduleLegacyWorkspaceRefresh()
        refreshFileTree()

        // Always ensure at least one tab is open
        if appState.openTabs.isEmpty {
            appState.newEmptyTab()
        }

        // Initialize workspace manager (restore saved layout or migrate from tabs)
        restoredWorkspaceDocuments = false
        if let bootstrap {
            workspaceManager.layoutPersistenceEnabled = bootstrap.layoutPersistenceEnabled
            if bootstrap.workspaces.isEmpty {
                workspaceManager.restoreOrCreateDefault()
            } else {
                workspaceManager.workspaces = bootstrap.workspaces
                workspaceManager.activeWorkspaceIndex = min(bootstrap.activeWorkspaceIndex, bootstrap.workspaces.count - 1)
                workspaceManager.sanitizeForCurrentMode()
                if BugbookFeatureGate.shouldInitializeLegacyServices {
                    browserManager.bind(workspaceManager: workspaceManager)
                    for (paneID, snapshot) in bootstrap.browserSnapshots {
                        browserManager.restoreSessionSnapshot(snapshot, for: paneID)
                    }
                }
            }
        } else {
            workspaceManager.restoreOrCreateDefault()
        }
        workspaceManager.sanitizeForCurrentMode()
        if BugbookFeatureGate.shouldInitializeLegacyServices {
            browserManager.bind(workspaceManager: workspaceManager)
        }
        restoreWorkspaceDocumentsForCurrentModeIfNeeded()

        startWorkspaceWatcher(path: workspacePath)

        if usesConfiguredWorkspace {
            finalizeResolvedWorkspaceStartup(for: workspacePath)
        } else {
            // Upgrade to the canonical iCloud workspace in the background if available.
            Task { @MainActor in
                let resolvedWorkspacePath = await fileSystem.upgradeDefaultToICloudIfAvailable() ?? workspacePath
                if resolvedWorkspacePath != appState.workspacePath {
                    appState.workspacePath = resolvedWorkspacePath
                    scheduleLegacyWorkspaceRefresh()
                    scheduleTrashPurgeIfNeeded(for: resolvedWorkspacePath)
                    refreshFileTree()
                    startWorkspaceWatcher(path: resolvedWorkspacePath)
                }

                finalizeResolvedWorkspaceStartup(for: resolvedWorkspacePath)
            }
        }

        // Load MCP server configs only when agent surfaces are enabled.
        if BugbookFeatureGate.shouldExposeAgentSurfaces {
            let fs = self.fileSystem
            Task.detached {
                let servers = fs.parseMCPServers()
                await MainActor.run {
                    self.appState.mcpServers = servers
                }
            }
        } else {
            appState.mcpServers = []
        }

        if BugbookFeatureGate.shouldStartMeetingNotificationPolling {
            meetingNotificationService.setup()
            meetingNotificationService.startPolling(calendarService: calendarService)
        }
    }

    private func switchWorkspaceRoot(to path: String) {
        let trimmedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty else { return }
        if !FileManager.default.fileExists(atPath: trimmedPath) {
            try? FileManager.default.createDirectory(atPath: trimmedPath, withIntermediateDirectories: true)
        }

        workspaceWatcher?.stop()
        fileSystem.setWorkspace(trimmedPath)
        appState.workspacePath = trimmedPath
        appState.settings.notesFolderPath = trimmedPath
        scheduleLegacyWorkspaceRefresh()
        scheduleTrashPurgeIfNeeded(for: trimmedPath)
        refreshFileTree()
        blockDocuments.removeAll()
        restoredWorkspaceDocuments = true
        workspaceManager.workspaces = [Workspace.makeDefault(name: "Workspace")]
        workspaceManager.activeWorkspaceIndex = 0
        workspaceManager.schedulePersist()
        startWorkspaceWatcher(path: trimmedPath)
        finalizeResolvedWorkspaceStartup(for: trimmedPath)
    }

    private func finalizeResolvedWorkspaceStartup(for workspacePath: String) {
        Log.profileMarker("workspaceStartupFinalized")
        if BugbookFeatureGate.shouldRegisterSearchIndexAtLaunch {
            QmdService.registerCollectionInBackground(workspace: workspacePath)
        }

        if startProfileMeetingIfRequested(in: workspacePath) {
            return
        }

        if !BugbookFeatureGate.shouldAutoOpenOnboardingAtLaunch {
            openDailyNote()
            return
        }

        guard shouldAutoOpenOnboarding,
              let onboardingPath = OnboardingService.ensureOnboarding(workspacePath: workspacePath) else {
            refreshFileTree()
            return
        }

        refreshFileTree()
        navigateToEntryInPane(
            FileEntry(
                id: onboardingPath,
                name: (onboardingPath as NSString).lastPathComponent,
                path: onboardingPath,
                isDirectory: false
            )
        )
    }

    private func startProfileMeetingIfRequested(in workspacePath: String) -> Bool {
        guard !ProfileMeetingAutoStartGate.consumed,
              ProcessInfo.processInfo.environment["BUGBOOK_PROFILE_AUTO_START_MEETING"] == "1" else {
            return false
        }
        ProfileMeetingAutoStartGate.consumed = true
        Log.profileMarker("profileMeetingRequested")

        Task { @MainActor in
            guard let path = await meetingNoteService.createAdHocMeetingPageAsync(
                title: "Profile Meeting",
                date: Date(),
                workspace: workspacePath,
                fileSystem: fileSystem
            ) else {
                Log.app.error("Failed to create profiling meeting note")
                return
            }

            appState.pendingAutoRecordPath = path
            refreshFileTree()
            Log.profileMarker("profileMeetingCreated")
            navigateToFilePath(path)
        }

        return true
    }

    private var shouldAutoOpenOnboarding: Bool {
        let workspaceHasMeaningfulContent = workspaceManager.activeWorkspace?.allLeaves.contains { leaf in
            leaf.tabs.contains { content in
                switch content {
                case .terminal:
                    return true
                case .document(let file):
                    return !file.isEmptyTab
                }
            }
        } ?? false

        guard !workspaceHasMeaningfulContent else { return false }
        return appState.openTabs.allSatisfy(\.isEmptyTab)
    }

    private func restoreWorkspaceDocumentsIfNeeded() {
        guard !restoredWorkspaceDocuments else { return }
        restoredWorkspaceDocuments = true

        let targets = workspaceDocumentRestoreTargetsPrioritizingFocusedTab()
        guard !targets.isEmpty else { return }

        Task { @MainActor in
            var didRestoreAny = false
            for (index, target) in targets.enumerated() {
                let priority: TaskPriority = index == 0 ? .userInitiated : .utility
                let result = await editorSaveWorker.loadPageContent(at: target.entry.path, priority: priority)
                guard !Task.isCancelled else { return }
                if restoreWorkspaceDocument(result, target: target) {
                    didRestoreAny = true
                }
                await Task.yield()
            }
            if didRestoreAny {
                workspaceManager.schedulePersist()
            }
        }
    }

    private func workspaceDocumentRestoreTargetsPrioritizingFocusedTab() -> [WorkspaceDocumentRestoreTarget] {
        let focusedTabId = workspaceManager.focusedPaneTabID
        var targets = workspaceManager.allDocumentLeaves().compactMap { _, _, file -> WorkspaceDocumentRestoreTarget? in
            guard file.kind == .page,
                  !file.path.isEmpty,
                  let entry = restoredEntry(for: file) else { return nil }
            return WorkspaceDocumentRestoreTarget(tabId: file.id, entry: entry)
        }

        if let focusedTabId,
           let focusedIndex = targets.firstIndex(where: { $0.tabId == focusedTabId }) {
            let focusedTarget = targets.remove(at: focusedIndex)
            targets.insert(focusedTarget, at: 0)
        }

        return targets
    }

    @discardableResult
    private func restoreWorkspaceDocument(
        _ result: EditorLoadResult,
        target: WorkspaceDocumentRestoreTarget
    ) -> Bool {
        switch result {
        case .loaded(let loadedPage):
            guard let currentFile = workspaceManager.openFile(tabId: target.tabId),
                  currentFile.path == target.entry.path,
                  currentFile.kind == .page else {
                return false
            }

            let doc = BlockDocument(markdown: loadedPage.content, parsed: loadedPage.parsedDocument)
            doc.filePath = target.entry.path
            wireUpDocumentCallbacks(doc, tabId: target.tabId)
            injectChildPageLinks(into: doc, from: target.entry)
            blockDocuments[target.tabId] = doc

            workspaceManager.updateOpenFile(tabId: target.tabId, persist: false) { openFile in
                openFile.content = loadedPage.content
                openFile.isDirty = loadedPage.isRestoredDraft
                openFile.icon = doc.icon
                if let rawTitle = doc.titleBlock?.text, !rawTitle.isEmpty {
                    openFile.displayName = AttributedStringConverter.plainText(from: rawTitle)
                }
            }
            return true
        case .missing, .cancelled:
            return false
        case .failed(let message):
            Log.editor.error("Failed to restore workspace document: \(message)")
            return false
        }
    }

    private func restoreWorkspaceDocumentsForCurrentModeIfNeeded() {
        guard BugbookFeatureGate.shouldRestoreWorkspaceDocumentsAtLaunch else {
            restoredWorkspaceDocuments = true
            return
        }

        restoreWorkspaceDocumentsIfNeeded()
    }

    private func restoredEntry(for file: OpenFile) -> FileEntry? {
        if let entry = fileSystem.findEntry(path: file.path, in: appState.fileTree) {
            return entry
        }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: file.path, isDirectory: &isDirectory),
              !isDirectory.boolValue else {
            return nil
        }

        let companionPath = file.path.hasSuffix(".md") ? String(file.path.dropLast(3)) : file.path
        var children: [FileEntry]?
        if FileManager.default.fileExists(atPath: companionPath, isDirectory: &isDirectory),
           isDirectory.boolValue {
            children = fileSystem.buildFileTree(at: companionPath)
        }

        return FileEntry(
            id: file.path,
            name: (file.path as NSString).lastPathComponent,
            path: file.path,
            isDirectory: false,
            kind: file.kind,
            icon: file.icon,
            children: children
        )
    }

    private func injectChildPageLinks(into doc: BlockDocument, from entry: FileEntry) {
        guard let children = entry.children, !children.isEmpty else { return }
        let existingLinks = Set(doc.blocks.filter { $0.type == .pageLink }.map { $0.pageLinkName })
        for child in children where child.name.hasSuffix(".md") && !child.isDatabase {
            let pageName = String(child.name.dropLast(3))
            if !existingLinks.contains(pageName) {
                doc.blocks.append(Block(type: .pageLink, pageLinkName: pageName))
            }
        }
    }

    private func startWorkspaceWatcher(path: String) {
        workspaceWatcher?.stop()
        let watcher = WorkspaceWatcher {
            handleWorkspaceFileSystemChange()
        }
        watcher.watch(path: path)
        workspaceWatcher = watcher
    }

    private func handleWorkspaceFileSystemChange() {
        refreshFileTree()
        reloadCleanOpenDocumentsFromDisk()
    }

    private func reloadCleanOpenDocumentsFromDisk() {
        let openFilesByTabId = cleanReloadableOpenFilesByTabId()
        guard !openFilesByTabId.isEmpty else { return }

        for (tabId, file) in openFilesByTabId {
            pageLoadTasks[tabId]?.cancel()
            pageLoadTasks[tabId] = Task { @MainActor in
                let result = await editorSaveWorker.loadPageContent(at: file.path)
                guard !Task.isCancelled else { return }
                applyExternalPageReload(result, file: file, tabId: tabId)
                pageLoadTasks[tabId] = nil
            }
        }
    }

    private func cleanReloadableOpenFilesByTabId() -> [UUID: OpenFile] {
        var filesByTabId: [UUID: OpenFile] = [:]

        for file in appState.openTabs where shouldReloadFromDisk(file) {
            filesByTabId[file.id] = file
        }
        for file in workspaceManager.allDocumentLeaves().map(\.file) where shouldReloadFromDisk(file) {
            filesByTabId[file.id] = file
        }

        return filesByTabId
    }

    private func shouldReloadFromDisk(_ file: OpenFile) -> Bool {
        !file.isDirty &&
            !file.isEmptyTab &&
            !file.path.isEmpty &&
            file.kind == .page &&
            file.path.hasSuffix(".md")
    }

    private func applyExternalPageReload(_ result: EditorLoadResult, file: OpenFile, tabId: UUID) {
        defer { pageLoadTasks[tabId] = nil }

        guard let currentFile = workspaceManager.openFile(tabId: tabId) ??
                appState.openTabs.first(where: { $0.id == tabId }),
              currentFile.path == file.path,
              !currentFile.isDirty else {
            return
        }

        switch result {
        case .loaded(let loadedPage):
            let content = loadedPage.content
            guard blockDocuments[tabId]?.markdown != content || currentFile.content != content else {
                return
            }

            let document: BlockDocument
            if let existingDocument = blockDocuments[tabId] {
                existingDocument.replaceMarkdown(content, parsed: loadedPage.parsedDocument)
                existingDocument.filePath = file.path
                wireUpDocumentCallbacks(existingDocument, tabId: tabId)
                document = existingDocument
            } else {
                let newDocument = BlockDocument(markdown: content, parsed: loadedPage.parsedDocument)
                newDocument.filePath = file.path
                wireUpDocumentCallbacks(newDocument, tabId: tabId)
                blockDocuments[tabId] = newDocument
                document = newDocument
            }

            let entry = FileEntry(
                id: file.path,
                name: (file.path as NSString).lastPathComponent,
                path: file.path,
                isDirectory: false,
                kind: file.kind,
                icon: file.icon
            )
            injectChildPageLinks(into: document, from: entry)
            updateLoadedOpenFileMetadata(tabId: tabId, content: content, document: document, isDirty: loadedPage.isRestoredDraft)
        case .missing:
            return
        case .failed(let message):
            Log.editor.error("Failed to reload externally changed file: \(message)")
        case .cancelled:
            return
        }
    }

    private func updateLoadedOpenFileMetadata(
        tabId: UUID,
        content: String,
        document: BlockDocument,
        isDirty: Bool
    ) {
        if let index = appState.openTabs.firstIndex(where: { $0.id == tabId }) {
            appState.openTabs[index].content = content
            appState.openTabs[index].isDirty = isDirty
            appState.openTabs[index].icon = document.icon
            updateDisplayName(for: &appState.openTabs[index], document: document)
        }
        workspaceManager.updateOpenFile(tabId: tabId, persist: false) { file in
            file.content = content
            file.isDirty = isDirty
            file.icon = document.icon
            updateDisplayName(for: &file, document: document)
        }
    }

    private func updateDisplayName(for file: inout OpenFile, document: BlockDocument) {
        if let rawTitle = document.titleBlock?.text, !rawTitle.isEmpty {
            file.displayName = AttributedStringConverter.plainText(from: rawTitle)
        } else if document.isMeetingPage,
                  let yamlTitle = MarkdownBlockParser.yamlValue(for: "title", in: document.yamlFrontmatter) {
            file.displayName = yamlTitle
        }
    }

    private func refreshFileTree() {
        guard let path = appState.workspacePath else { return }
        let fileSystem = self.fileSystem
        let shouldScanAgentSurfaces = BugbookFeatureGate.shouldExposeAgentSurfaces
        fileTreeRefreshGeneration += 1
        let generation = fileTreeRefreshGeneration

        fileTreeRefreshTask?.cancel()
        fileTreeRefreshTask = Task.detached(priority: .utility) {
            let tree = fileSystem.buildFileTree(at: path)
            guard !Task.isCancelled else { return }
            let skills = shouldScanAgentSurfaces ? fileSystem.scanSkills() : []
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard self.fileTreeRefreshGeneration == generation,
                      self.appState.workspacePath == path else { return }
                self.appState.fileTree = tree
                self.appState.agentSkills = skills
                self.refreshSidebarReferences(using: tree)
                self.refreshFavorites(using: tree)
                self.schedulePagePreload(from: tree)
                self.fileTreeRefreshTask = nil
            }
        }
    }

    private func schedulePagePreload(from fileTree: [FileEntry]) {
        let paths = Self.pagePreloadCandidatePaths(from: fileTree, limit: 48)
        let workspacePath = appState.workspacePath
        pagePreloadTask?.cancel()
        guard !paths.isEmpty, let workspacePath else {
            pagePreloadTask = nil
            return
        }

        let worker = editorSaveWorker
        pagePreloadTask = Task.detached(priority: .utility) {
            try? await Task.sleep(nanoseconds: 300_000_000)
            for path in paths {
                guard !Task.isCancelled else { return }
                let result = await worker.loadPageContent(at: path, priority: .utility)
                if case .loaded(let loadedPage) = result {
                    let databasePaths = Self.databasePreloadCandidatePaths(
                        from: loadedPage.parsedDocument,
                        pagePath: path,
                        workspacePath: workspacePath,
                        limit: 4
                    )
                    if !databasePaths.isEmpty {
                        let databaseService = DatabaseService()
                        for databasePath in databasePaths {
                            guard !Task.isCancelled else { return }
                            databaseService.preloadDatabaseForDisplay(at: databasePath)
                        }
                    }
                }
                await Task.yield()
            }
        }
    }

    nonisolated private static func pagePreloadCandidatePaths(
        from entries: [FileEntry],
        limit: Int
    ) -> [String] {
        var paths: [String] = []
        var seen: Set<String> = []

        func collect(_ entry: FileEntry) {
            guard paths.count < limit else { return }
            if entry.kind == .page,
               !entry.isDirectory,
               entry.path.hasSuffix(".md"),
               seen.insert(entry.path).inserted {
                paths.append(entry.path)
            }
            for child in entry.children ?? [] {
                guard paths.count < limit else { return }
                collect(child)
            }
        }

        for entry in entries {
            guard paths.count < limit else { break }
            collect(entry)
        }
        return paths
    }

    nonisolated private static func databasePreloadCandidatePaths(
        from parsedDocument: BlockDocument.ParsedDocument?,
        pagePath: String,
        workspacePath: String,
        limit: Int
    ) -> [String] {
        guard let parsedDocument else { return [] }

        var paths: [String] = []
        var seen: Set<String> = []

        func collect(from blocks: [Block]) {
            for block in blocks {
                guard paths.count < limit else { return }
                if block.type == .databaseEmbed,
                   let resolution = resolveDatabaseEmbedPathForRendering(
                    block.databasePath,
                    pagePath: pagePath,
                    workspacePath: workspacePath
                   ),
                   resolution.isResolved,
                   seen.insert(resolution.renderPath).inserted {
                    paths.append(resolution.renderPath)
                }
                if !block.children.isEmpty {
                    collect(from: block.children)
                }
            }
        }

        collect(from: parsedDocument.blocks)
        return paths
    }

    private func syncAvailablePages(_ pages: [FileEntry]) {
        for document in blockDocuments.values {
            document.availablePages = pages
        }
    }

    private func refreshSidebarReferences(using fileTree: [FileEntry]? = nil) {
        guard let workspace = appState.workspacePath else {
            appState.sidebarReferences = []
            return
        }

        let tree = fileTree ?? appState.fileTree
        let storedPaths = fileSystem.sidebarReferencePaths(for: workspace)
        var resolvedPaths: [String] = []
        let resolvedEntries = storedPaths.compactMap { path -> FileEntry? in
            guard let entry = buildSidebarReferenceEntry(for: path, in: tree) else { return nil }
            resolvedPaths.append(path)
            return entry
        }

        if resolvedPaths != storedPaths {
            fileSystem.saveSidebarReferencePaths(resolvedPaths, for: workspace)
        }
        appState.sidebarReferences = resolvedEntries
    }

    private func buildSidebarReferenceEntry(for path: String, in fileTree: [FileEntry]) -> FileEntry? {
        if let entry = fileSystem.findEntry(path: path, in: fileTree) {
            return FileEntry(
                id: "sidebar-ref:\(path)",
                name: entry.name,
                path: entry.path,
                isDirectory: false,
                kind: entry.kind,
                icon: entry.icon,
                isSidebarReference: true
            )
        }

        guard FileManager.default.fileExists(atPath: path) else { return nil }

        let kind: TabKind
        let name: String
        if fileSystem.isDatabaseFolder(at: path) {
            kind = .database
            name = fileSystem.databaseDisplayName(at: path) ?? (path as NSString).lastPathComponent
        } else {
            kind = .page
            name = (path as NSString).lastPathComponent
        }

        return FileEntry(
            id: "sidebar-ref:\(path)",
            name: name,
            path: path,
            isDirectory: false,
            kind: kind,
            isSidebarReference: true
        )
    }

    /// Handles a page dragged from the sidebar into the editor at a specific block index.
    /// Creates a pageLink block at the drop position and moves the file to be a sub-page.
    private func handleSidebarPageDropIntoEditor(sourcePath: String, insertIndex: Int, document: BlockDocument) {
        guard let tab = appState.activeTab else { return }
        let currentPagePath = tab.path
        // Don't drop a page onto itself
        guard sourcePath != currentPagePath else { return }
        // Don't move databases into companion folders via editor drops
        guard !fileSystem.isDatabaseFolder(at: sourcePath) else { return }
        // Don't drop a page that's already a sub-page of the current page
        let currentCompanion = currentPagePath.hasSuffix(".md") ? String(currentPagePath.dropLast(3)) : currentPagePath
        guard !(sourcePath as NSString).deletingLastPathComponent.hasPrefix(currentCompanion) else { return }

        let pageName = (sourcePath as NSString).lastPathComponent.replacingOccurrences(of: ".md", with: "")

        // 1. Insert the pageLink block at the drop position
        document.insertPageLinkBlock(at: insertIndex, name: pageName)

        // 2. Save the current document so the link is persisted before move
        performSave(tabId: tab.id) {
            // 3. Move the file to be a sub-page of the current page
            performMovePage(from: sourcePath, toDirectory: currentCompanion)
        }
    }

    // MARK: - Favorites

    private func refreshFavorites(using fileTree: [FileEntry]? = nil) {
        guard let workspace = appState.workspacePath else {
            appState.favorites = []
            return
        }
        appState.favorites = fileSystem.resolveFavorites(for: workspace, fileTree: fileTree ?? appState.fileTree)
    }

    func toggleFavorite(path: String) {
        guard let workspace = appState.workspacePath else { return }
        if fileSystem.isFavorite(path, for: workspace) {
            fileSystem.removeFavoritePath(path, for: workspace)
        } else {
            fileSystem.addFavoritePath(path, for: workspace)
        }
        refreshFavorites()
    }

    func isPathFavorited(_ path: String) -> Bool {
        guard let workspace = appState.workspacePath else { return false }
        return fileSystem.isFavorite(path, for: workspace)
    }

    private func addSidebarReference(_ payload: SidebarReferenceDragPayload) {
        guard let workspace = appState.workspacePath else { return }

        let targetPath = payload.path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !targetPath.isEmpty else { return }
        guard !appState.sidebarReferences.contains(where: { $0.path == targetPath }) else { return }
        guard buildSidebarReferenceEntry(for: targetPath, in: appState.fileTree) != nil else { return }

        fileSystem.addSidebarReferencePath(targetPath, for: workspace)
        refreshSidebarReferences()
    }

    private func loadFileContent(for entry: FileEntry) {
        guard !entry.isDatabase, !entry.isDatabaseRow, !entry.isSkill else { return }
        let signpostState = Log.signpost.beginInterval("loadFileContent")
        defer { Log.signpost.endInterval("loadFileContent", signpostState) }
        pagePreloadTask?.cancel()
        formattingPanel?.hidePanel()
        editorUI.focusModeSuppress = true
        guard let tabId = appState.openTabs.first(where: { $0.path == entry.path })?.id else {
            editorUI.focusModeSuppress = false
            return
        }
        pageLoadTasks[tabId]?.cancel()
        pageLoadTasks[tabId] = Task { @MainActor in
            let result = await editorSaveWorker.loadPageContent(at: entry.path)
            guard !Task.isCancelled else { return }
            handleLoadedLegacyPage(result, entry: entry, tabId: tabId)
            pageLoadTasks[tabId] = nil
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            editorUI.focusModeSuppress = false
        }
    }

    private func handleLoadedLegacyPage(_ result: EditorLoadResult, entry: FileEntry, tabId: UUID) {
        switch result {
        case .loaded(let loadedPage):
            guard let index = appState.openTabs.firstIndex(where: { $0.id == tabId && $0.path == entry.path }) else {
                return
            }
            let content = loadedPage.content
            appState.openTabs[index].content = content
            appState.openTabs[index].isDirty = loadedPage.isRestoredDraft
            let doc = BlockDocument(markdown: content, parsed: loadedPage.parsedDocument)
            doc.filePath = entry.path
            wireUpDocumentCallbacks(doc, tabId: appState.openTabs[index].id)
            injectChildPageLinks(into: doc, from: entry)

            blockDocuments[appState.openTabs[index].id] = doc
            appState.openTabs[index].icon = doc.icon
            if let rawTitle = doc.titleBlock?.text, !rawTitle.isEmpty {
                appState.openTabs[index].displayName = AttributedStringConverter.plainText(from: rawTitle)
            }
        case .failed(let message):
            Log.editor.error("Failed to load file: \(message)")
        case .missing, .cancelled:
            return
        }
    }

    private func createNewFile() {
        guard let workspace = appState.workspacePath else { return }
        do {
            let path = try fileSystem.createNewFile(in: workspace)
            let entry = FileEntry(id: path, name: (path as NSString).lastPathComponent, path: path, isDirectory: false)
            appState.openFile(entry)
            loadFileContent(for: entry)
            if let tab = appState.activeTab,
               let doc = blockDocuments[tab.id],
               let firstBlock = doc.blocks.first {
                doc.focusedBlockId = firstBlock.id
                doc.cursorPosition = 0
            }
            refreshFileTree()
        } catch {
            Log.fileSystem.error("Failed to create file: \(error.localizedDescription)")
        }
    }

    private func createNewFileWithName(_ name: String) {
        guard let workspace = appState.workspacePath else { return }
        do {
            let path = try fileSystem.createNewFile(in: workspace, name: name)
            let entry = FileEntry(id: path, name: (path as NSString).lastPathComponent, path: path, isDirectory: false)
            navigateToEntry(entry, inNewTab: true)
            refreshFileTree()
        } catch {
            Log.fileSystem.error("Failed to create file: \(error.localizedDescription)")
        }
    }

    private func toggleTheme() {
        switch appState.settings.theme {
        case .system: appState.settings.theme = .light
        case .light: appState.settings.theme = .dark
        case .dark: appState.settings.theme = .system
        }
        showThemeToast(appState.settings.theme)
    }

    private func handleBlockTypeShortcut(_ action: String?) {
        guard let action = action else { return }

        // If a BlockNSTextView is focused, route through its closure so the
        // action targets the correct document (works in peek panel, modal, etc.)
        if let textView = NSApp.keyWindow?.firstResponder as? BlockNSTextView,
           let handler = textView.blockTypeShortcutAction {
            handler(action)
            return
        }

        // Fallback: use the active tab's document
        guard let tab = activeWorkspaceDocumentContext()?.file ?? appState.activeTab else { return }
        guard let doc = blockDocuments[tab.id],
              let blockId = doc.focusedBlockId else { return }

        if action == "createPage" {
            let currentText = doc.block(for: blockId)?.text ?? ""
            let pageName = currentText.isEmpty ? "Untitled" : currentText
            if let createPage = doc.onCreateSubPage,
               let pagePath = createPage(pageName) {
                let resolvedName = (pagePath as NSString).lastPathComponent.replacingOccurrences(of: ".md", with: "")
                doc.updateBlockProperty(id: blockId) { block in
                    block.type = .pageLink
                    block.pageLinkName = resolvedName
                    block.text = ""
                }
            }
            return
        }

        let mapping: [(String, BlockType, Int)] = [
            ("paragraph", .paragraph, 0),
            ("heading1", .heading, 1),
            ("heading2", .heading, 2),
            ("heading3", .heading, 3),
            ("taskItem", .taskItem, 0),
            ("bulletListItem", .bulletListItem, 0),
            ("numberedListItem", .numberedListItem, 0),
            ("toggle", .toggle, 0),
            ("codeBlock", .codeBlock, 0),
        ]
        guard let match = mapping.first(where: { $0.0 == action }) else { return }
        doc.changeBlockType(id: blockId, to: match.1)
        if match.1 == .heading {
            doc.setHeadingLevel(id: blockId, level: match.2)
        }
    }

    private func showThemeToast(_ mode: ThemeMode) {
        themeToastTask?.cancel()
        withAnimation(.easeOut(duration: 0.15)) { themeToast = mode }
        themeToastTask = Task {
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeIn(duration: 0.25)) { themeToast = nil }
        }
    }

    @ViewBuilder
    private var themeToastOverlay: some View {
        if let mode = themeToast {
            VStack {
                Spacer()
                HStack(spacing: 10) {
                    Image(systemName: themeIcon(mode))
                        .font(.system(size: 18))
                    Text(themeLabel(mode))
                        .font(.system(size: 14, weight: .medium))
                }
                .foregroundStyle(.primary)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(.ultraThinMaterial)
                .clipShape(.rect(cornerRadius: 10))
                .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
                .padding(.bottom, 40)
            }
            .frame(maxWidth: .infinity)
            .allowsHitTesting(false)
            .transition(.opacity)
        }
    }

    private func themeIcon(_ mode: ThemeMode) -> String {
        switch mode {
        case .light: return "sun.max.fill"
        case .dark: return "moon.fill"
        case .system: return "circle.lefthalf.filled"
        }
    }

    private func themeLabel(_ mode: ThemeMode) -> String {
        switch mode {
        case .light: return "Light"
        case .dark: return "Dark"
        case .system: return "System"
        }
    }

    // MARK: - Shortcut Overlay

    @ViewBuilder
    private var shortcutOverlay: some View {
        if appState.showShortcutOverlay {
            KeyboardShortcutOverlay {
                withAnimation(.easeInOut(duration: 0.15)) {
                    appState.showShortcutOverlay = false
                }
            }
            .transition(.opacity)
        }
    }

    private var editorZoomRange: ClosedRange<Double> {
        Double(EditorTypography.minZoomScale)...Double(EditorTypography.maxZoomScale)
    }

    private var editorZoomPercentageLabel: String {
        "\(Int((editorZoomScale * 100).rounded()))%"
    }

    private var editorZoomMinimumLabel: String {
        "\(Int((editorZoomRange.lowerBound * 100).rounded()))%"
    }

    private var editorZoomMaximumLabel: String {
        "\(Int((editorZoomRange.upperBound * 100).rounded()))%"
    }

    private func clampedEditorZoomScale(_ scale: Double) -> Double {
        min(max(scale, editorZoomRange.lowerBound), editorZoomRange.upperBound)
    }

    private func adjustEditorZoom(by delta: Double) {
        let updatedScale = clampedEditorZoomScale(editorZoomScale + delta)
        if updatedScale == editorZoomScale {
            editorUI.showZoomHud()
            return
        }
        editorZoomScale = updatedScale
    }

    private func resetEditorZoom() {
        let defaultScale = Double(EditorTypography.defaultZoomScale)
        if editorZoomScale == defaultScale {
            editorUI.showZoomHud()
            return
        }
        editorZoomScale = defaultScale
    }

    @ViewBuilder
    private var editorZoomOverlay: some View {
        if editorUI.zoomHudVisible {
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Interface Zoom")
                                .font(.system(size: 13, weight: .semibold))
                            Spacer()
                            Text(editorZoomPercentageLabel)
                                .font(.system(size: 13, weight: .medium, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }

                        Slider(
                            value: $editorZoomScale,
                            in: editorZoomRange,
                            step: 0.05
                        ) {
                            Text("Interface Zoom")
                        } minimumValueLabel: {
                            Text(editorZoomMinimumLabel)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        } maximumValueLabel: {
                            Text(editorZoomMaximumLabel)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }

                        HStack(spacing: 8) {
                            Button {
                                adjustEditorZoom(by: -0.1)
                            } label: {
                                Label("Zoom Out", systemImage: "minus.magnifyingglass")
                            }
                            .buttonStyle(.bordered)

                            Button {
                                resetEditorZoom()
                            } label: {
                                Label("Reset", systemImage: "arrow.counterclockwise")
                            }
                            .buttonStyle(.bordered)

                            Button {
                                adjustEditorZoom(by: 0.1)
                            } label: {
                                Label("Zoom In", systemImage: "plus.magnifyingglass")
                            }
                            .buttonStyle(.bordered)
                        }
                        .labelStyle(.titleAndIcon)
                        .font(.system(size: 12, weight: .medium))
                    }
                    .padding(14)
                    .frame(width: 300)
                    .background(.ultraThinMaterial)
                    .clipShape(.rect(cornerRadius: 14))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.white.opacity(0.18), lineWidth: 0.6)
                            .allowsHitTesting(false)
                    }
                    .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
                    .padding(.trailing, 24)
                    .padding(.bottom, 24)
                    .onHover { hovering in
                        editorUI.zoomHudHovered = hovering
                        if hovering {
                            // Cancel auto-hide while hovering
                        } else {
                            editorUI.scheduleZoomHudHide()
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .transition(.move(edge: .trailing).combined(with: .opacity))
        }
    }

    private func createPageFromTemplate(_ template: FileEntry) {
        guard let workspace = appState.workspacePath else { return }
        let templateName = template.name.hasSuffix(".md")
            ? String(template.name.dropLast(3))
            : template.name
        do {
            let path = try fileSystem.createFromTemplate(
                templatePath: template.path,
                in: workspace,
                name: templateName
            )
            let entry = FileEntry(
                id: path,
                name: (path as NSString).lastPathComponent,
                path: path,
                isDirectory: false
            )
            navigateToEntry(entry, inNewTab: true)
            refreshFileTree()
        } catch {
            Log.fileSystem.error("Failed to create page from template: \(error.localizedDescription)")
        }
    }

    private func saveCurrentNoteAsTemplate(document: BlockDocument) {
        guard let workspace = appState.workspacePath else { return }

        let rawName = document.titleBlock?.text.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let defaultName = AttributedStringConverter.plainText(from: rawName)
        let suggestedName = defaultName.isEmpty ? "Untitled Template" : defaultName

        let alert = NSAlert()
        alert.messageText = "Save as Template"
        alert.informativeText = "Enter a name for this template."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 22))
        input.stringValue = suggestedName
        input.placeholderString = "Template name"
        alert.accessoryView = input
        alert.window.initialFirstResponder = input

        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return }

        let name = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }

        do {
            try fileSystem.saveAsTemplate(content: document.markdown, name: name, in: workspace)
        } catch {
            Log.fileSystem.error("Failed to save template: \(error.localizedDescription)")
        }
    }

    private func openDailyNote() {
        guard let workspace = appState.workspacePath else {
            markLaunchNavigationSettled()
            return
        }

        Task { @MainActor in
            defer { markLaunchNavigationSettled() }
            do {
                let path = try await fileSystem.openOrCreateDailyNoteInBackground(in: workspace)
                guard !Task.isCancelled else { return }
                let name = (path as NSString).lastPathComponent
                let entry = FileEntry(id: path, name: name, path: path, isDirectory: false)
                navigateToEntryInPane(entry)
                refreshFileTree()
            } catch {
                Log.fileSystem.error("Failed to open daily note: \(error.localizedDescription)")
            }
        }
    }

    /// Mark the app's launch navigation as finished and release any external files
    /// the "Open With" handler buffered while waiting for it.
    private func markLaunchNavigationSettled() {
        guard !launchNavigationSettled else { return }
        launchNavigationSettled = true
        drainPendingExternalFiles()
    }

    private func openMeetingsHub() {
        guard let workspace = appState.workspacePath else {
            markLaunchNavigationSettled()
            return
        }

        Task { @MainActor in
            defer { markLaunchNavigationSettled() }
            do {
                let location = try await fileSystem.ensureMeetingsHubInBackground(in: workspace)
                guard !Task.isCancelled else { return }
                let name = (location.hubPath as NSString).lastPathComponent
                let entry = FileEntry(id: location.hubPath, name: name, path: location.hubPath, isDirectory: false)
                navigateToEntryInPane(entry)
                refreshFileTree()
            } catch {
                Log.fileSystem.error("Failed to open meetings hub: \(error.localizedDescription)")
            }
        }
    }

    private func createNewDatabase() {
        do {
            let path = try createDatabasePath(name: "")
            let displayName = (path as NSString).lastPathComponent
            let entry = FileEntry(id: path, name: displayName, path: path, isDirectory: false, kind: .database)
            appState.openFile(entry)
            refreshFileTree()
        } catch {
            Log.database.error("Failed to create database: \(error.localizedDescription)")
        }
    }

    private func createDatabasePath(name: String, parentPagePath: String? = nil) throws -> String {
        guard let workspace = appState.workspacePath else {
            throw NSError(
                domain: NSCocoaErrorDomain,
                code: NSFileNoSuchFileError,
                userInfo: [NSLocalizedDescriptionKey: "No workspace is open."]
            )
        }

        if let pagePath = parentPagePath ?? activePagePathForDatabaseCreation(),
           pagePath.hasSuffix(".md"),
           !fileSystem.isDatabaseFolder(at: (pagePath as NSString).deletingLastPathComponent) {
            return try fileSystem.createDatabase(underPage: pagePath, name: name)
        }
        return try fileSystem.createDatabase(in: workspace, name: name)
    }

    private func ensureMeetingsDatabase(in workspace: String) -> String? {
        try? FirstPartyDatabaseFiles.ensureMeetingsHub(in: workspace).databasePath
    }

    private func activePagePathForDatabaseCreation() -> String? {
        guard let tab = appState.activeTab,
              tab.kind == .page,
              tab.path.hasSuffix(".md") else {
            return nil
        }
        return tab.path
    }

    private func handleFileMove(from oldPath: String, to newPath: String) {
        guard oldPath != newPath,
              fileSystem.isDatabaseFolder(at: newPath) else {
            return
        }

        updateOpenDatabaseTabs(from: oldPath, to: newPath)

        let updatedOpenDocPaths = retargetDatabaseEmbedsInOpenDocs(from: oldPath, to: newPath)
        if let workspace = appState.workspacePath {
            let fs = fileSystem
            Task.detached(priority: .utility) {
                fs.retargetDatabaseEmbedsInWorkspace(
                    from: oldPath,
                    to: newPath,
                    workspace: workspace,
                    excluding: updatedOpenDocPaths
                )
            }
        }

        if peekTarget?.dbPath == oldPath {
            peekTarget?.dbPath = newPath
        }
        if modalTarget?.dbPath == oldPath {
            modalTarget?.dbPath = newPath
        }
    }

    private func meetingsPaneView() -> some View {
        MeetingsView(
            appState: appState,
            viewModel: meetingsVM,
            meetingNoteService: meetingNoteService,
            fileSystem: fileSystem,
            onNavigateToFile: { path in
                navigateToFilePath(path)
            }
        )
    }

    private func updateOpenDatabaseTabs(from oldPath: String, to newPath: String) {
        for tab in appState.openTabs {
            appState.updateNavigationPath(for: tab.id, from: oldPath, to: newPath)
        }

        for index in appState.openTabs.indices {
            guard case let .databaseRow(dbPath, rowId) = appState.openTabs[index].kind,
                  dbPath == oldPath else {
                continue
            }

            let oldRowPath = DatabaseRowNavigationPath.make(dbPath: dbPath, rowId: rowId)
            let newRowPath = DatabaseRowNavigationPath.make(dbPath: newPath, rowId: rowId)
            appState.openTabs[index].kind = .databaseRow(dbPath: newPath, rowId: rowId)
            appState.updateNavigationPath(for: appState.openTabs[index].id, from: oldRowPath, to: newRowPath)
        }
    }

    private func retargetDatabaseEmbedsInOpenDocs(from oldPath: String, to newPath: String) -> Set<String> {
        var updatedPaths: Set<String> = []

        for (tabId, doc) in blockDocuments {
            guard let filePath = doc.filePath,
                  filePath.hasSuffix(".md") else {
                continue
            }

            guard updateDatabasePaths(in: &doc.blocks, from: oldPath, to: newPath) else {
                continue
            }

            updatedPaths.insert(filePath)
            if let tabIndex = appState.openTabs.firstIndex(where: { $0.id == tabId }) {
                appState.openTabs[tabIndex].content = doc.markdown
                if !appState.openTabs[tabIndex].isDirty {
                    try? fileSystem.saveFile(at: filePath, content: doc.markdown)
                }
            }
        }

        return updatedPaths
    }

    private func updateDatabasePaths(in blocks: inout [Block], from oldPath: String, to newPath: String) -> Bool {
        var didUpdate = false

        for index in blocks.indices {
            if blocks[index].type == .databaseEmbed,
               blocks[index].databasePath == oldPath {
                blocks[index].databasePath = newPath
                didUpdate = true
            }

            if updateDatabasePaths(in: &blocks[index].children, from: oldPath, to: newPath) {
                didUpdate = true
            }
        }

        return didUpdate
    }

    private func openWorkspace() async {
        if let path = await fileSystem.openFolder() {
            scheduleTrashPurgeIfNeeded(for: path)
            appState.workspacePath = path
            refreshFileTree()
            startWorkspaceWatcher(path: path)
        }
    }

    private func scheduleTrashPurgeIfNeeded(for workspace: String) {
        guard lastTrashPurgeWorkspace != workspace else { return }
        lastTrashPurgeWorkspace = workspace
        let fs = fileSystem
        Task.detached(priority: .background) {
            fs.purgeOldTrash(in: workspace)
        }
    }

    /// Syncs in-memory BlockDocument content into openTabs[].content for every
    /// dirty tab so the command palette's content index sees the latest edits,
    /// even if the 1-second save debounce hasn't fired yet.
    private func flushDirtyTabContent() {
        for i in appState.openTabs.indices where appState.openTabs[i].isDirty {
            let tabId = appState.openTabs[i].id
            if let doc = blockDocuments[tabId] {
                appState.openTabs[i].content = doc.markdown
            }
        }
    }

    private func activeWorkspaceDocumentContext() -> (paneId: UUID, file: OpenFile)? {
        guard let leaf = workspaceManager.focusedPane,
              case .document(let file) = leaf.content else {
            return nil
        }
        return (leaf.id, file)
    }

    private func updateWorkspaceOpenFile(tabId: UUID, transform: (inout OpenFile) -> Void) {
        guard let paneId = workspaceManager.leaf(containingTabId: tabId)?.id else { return }
        workspaceManager.updatePaneOpenFile(paneId: paneId, tabId: tabId, transform: transform)
    }

    private func rewriteOpenDocumentPathsAfterPageRename(from oldPath: String, to newPath: String) {
        guard oldPath != newPath else { return }

        let oldCompanion = oldPath.hasSuffix(".md") ? String(oldPath.dropLast(3)) : oldPath
        let newCompanion = newPath.hasSuffix(".md") ? String(newPath.dropLast(3)) : newPath

        for index in appState.openTabs.indices {
            rewriteOpenFilePath(
                &appState.openTabs[index],
                oldPath: oldPath,
                newPath: newPath,
                oldCompanion: oldCompanion,
                newCompanion: newCompanion
            )
        }

        let workspaceTabIDs = Set(workspaceManager.allDocumentLeaves().map(\.file.id))
        for tabID in workspaceTabIDs {
            workspaceManager.updateOpenFile(tabId: tabID, persist: false) { file in
                rewriteOpenFilePath(
                    &file,
                    oldPath: oldPath,
                    newPath: newPath,
                    oldCompanion: oldCompanion,
                    newCompanion: newCompanion
                )
            }
        }

        for document in blockDocuments.values {
            if let filePath = document.filePath {
                document.filePath = rewrittenPagePath(
                    filePath,
                    oldPath: oldPath,
                    newPath: newPath,
                    oldCompanion: oldCompanion,
                    newCompanion: newCompanion
                )
            }
        }

        if let session = appState.activeMeetingSession {
            session.meetingPagePath = rewrittenPagePath(
                session.meetingPagePath,
                oldPath: oldPath,
                newPath: newPath,
                oldCompanion: oldCompanion,
                newCompanion: newCompanion
            )
        }
        if let pendingPath = appState.pendingAutoRecordPath {
            appState.pendingAutoRecordPath = rewrittenPagePath(
                pendingPath,
                oldPath: oldPath,
                newPath: newPath,
                oldCompanion: oldCompanion,
                newCompanion: newCompanion
            )
        }
        if let movePagePath = appState.movePagePath {
            appState.movePagePath = rewrittenPagePath(
                movePagePath,
                oldPath: oldPath,
                newPath: newPath,
                oldCompanion: oldCompanion,
                newCompanion: newCompanion
            )
        }
    }

    private func rewriteOpenFilePath(
        _ file: inout OpenFile,
        oldPath: String,
        newPath: String,
        oldCompanion: String,
        newCompanion: String
    ) {
        file.path = rewrittenPagePath(
            file.path,
            oldPath: oldPath,
            newPath: newPath,
            oldCompanion: oldCompanion,
            newCompanion: newCompanion
        )
        file.openerPagePath = file.openerPagePath.map {
            rewrittenPagePath(
                $0,
                oldPath: oldPath,
                newPath: newPath,
                oldCompanion: oldCompanion,
                newCompanion: newCompanion
            )
        }
        for index in file.navigationHistory.indices {
            file.navigationHistory[index] = rewrittenPagePath(
                file.navigationHistory[index],
                oldPath: oldPath,
                newPath: newPath,
                oldCompanion: oldCompanion,
                newCompanion: newCompanion
            )
        }
    }

    private func rewrittenPagePath(
        _ path: String,
        oldPath: String,
        newPath: String,
        oldCompanion: String,
        newCompanion: String
    ) -> String {
        if path == oldPath {
            return newPath
        }
        guard path.hasPrefix(oldCompanion + "/") else {
            return path
        }
        let relativePath = String(path.dropFirst(oldCompanion.count))
        return newCompanion + relativePath
    }

    private func scheduleSave() {
        let file: OpenFile
        if let context = activeWorkspaceDocumentContext() {
            file = context.file
        } else if let activeTab = appState.activeTab {
            file = activeTab
        } else {
            return
        }
        guard !file.path.isEmpty else { return }
        // External files are never autosaved — saving moves them into the workspace instead.
        guard !file.isExternal else { return }
        let tabId = file.id
        persistPageDraft(for: tabId, path: file.path)

        saveTask?.cancel()
        saveTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            await saveDocumentInBackground(tabId: tabId)
        }
    }

    private func persistPageDraft(for tabId: UUID, path: String) {
        guard let document = blockDocuments[tabId] else { return }
        let content = document.markdown
        Task(priority: .utility) {
            await editorSaveWorker.savePageDraft(content: content, path: path)
        }
    }

    private func updatePageLinks(oldName: String, newName: String, docs: [UUID: BlockDocument]) {
        // Update in-memory documents (open tabs)
        for (_, doc) in docs {
            for i in doc.blocks.indices {
                if doc.blocks[i].type == .pageLink && doc.blocks[i].pageLinkName == oldName {
                    doc.blocks[i].pageLinkName = newName
                }
            }
        }

        // Update on-disk markdown files that aren't currently open
        guard let workspace = appState.workspacePath else { return }
        let workspaceOpenPaths = Set(workspaceManager.allDocumentLeaves().map(\.file.path))
        let openPaths = Set(appState.openTabs.map(\.path)).union(workspaceOpenPaths)
        let oldLink = "[[\(oldName)]]"
        let newLink = "[[\(newName)]]"
        let fs = fileSystem
        Task.detached(priority: .utility) {
            fs.updateWikiLinksOnDisk(in: workspace, oldLink: oldLink, newLink: newLink, excludingPaths: openPaths)
        }
    }

    private func triggerFocusMode() {
        editorUI.triggerFocusMode()
    }

    private func markActiveEditorTabDirty() {
        if let context = activeWorkspaceDocumentContext() {
            updateWorkspaceOpenFile(tabId: context.file.id) { file in
                if !file.isDirty {
                    file.isDirty = true
                }
            }
        }
        guard appState.activeTabIndex >= 0, appState.activeTabIndex < appState.openTabs.count else { return }
        if !appState.openTabs[appState.activeTabIndex].isDirty {
            appState.openTabs[appState.activeTabIndex].isDirty = true
        }
    }

    private func performSave(tabId: UUID) {
        saveTask?.cancel()
        saveTask = Task { @MainActor in
            await saveDocumentInBackground(tabId: tabId)
        }
    }

    private func performSave(tabId: UUID, then action: @escaping @MainActor () -> Void) {
        saveTask?.cancel()
        saveTask = Task { @MainActor in
            await saveDocumentInBackground(tabId: tabId)
            guard !Task.isCancelled else { return }
            action()
        }
    }

    private func flushDirtyTabs() {
        saveTask?.cancel()
        saveTask = nil
        let workspaceDirtyIds = workspaceManager.allDocumentLeaves()
            .map(\.file)
            .filter {
                $0.isDirty
                    && !$0.path.isEmpty
                    && !$0.isDatabase
                    && !$0.isDatabaseRow
            }
            .map(\.id)
        let legacyDirtyIds = appState.openTabs
            .filter {
                $0.isDirty
                    && !$0.path.isEmpty
                    && !$0.isDatabase
                    && !$0.isDatabaseRow
            }
            .map(\.id)
        let dirtyTabIds = Array(Set(workspaceDirtyIds + legacyDirtyIds))

        for tabId in dirtyTabIds {
            saveDocument(tabId: tabId)
        }
    }

    private func documentSaveSnapshot(tabId: UUID) -> DocumentSaveSnapshot? {
        let legacyIndex = appState.openTabs.firstIndex(where: { $0.id == tabId })
        let workspaceFile = workspaceManager.openFile(tabId: tabId)
        guard let currentFile = workspaceFile ?? legacyIndex.map({ appState.openTabs[$0] }),
              currentFile.isDirty,
              !currentFile.isExternal,
              let document = blockDocuments[tabId] else { return nil }

        let oldPath = currentFile.path
        guard !oldPath.isEmpty else { return nil }

        let title = plainDocumentTitle(in: document)
        synchronizeFirstPartyRowFrontmatterName(document: document, path: oldPath, title: title)
        let content = document.markdown
        if let legacyIndex {
            appState.openTabs[legacyIndex].content = content
        }

        let parentDirectory = (oldPath as NSString).deletingLastPathComponent
        return DocumentSaveSnapshot(
            tabId: tabId,
            oldPath: oldPath,
            content: content,
            title: title,
            legacyIndex: legacyIndex,
            hasWorkspaceFile: workspaceFile != nil,
            parentDirectory: parentDirectory,
            isPhysicalDatabaseRowFile: fileSystem.isDatabaseFolder(at: parentDirectory)
        )
    }

    private func saveDocumentInBackground(tabId: UUID) async {
        guard let snapshot = documentSaveSnapshot(tabId: tabId) else { return }

        let result = await editorSaveWorker.saveMarkdownFile(at: snapshot.oldPath, content: snapshot.content)
        guard !Task.isCancelled else { return }

        switch result {
        case .saved:
            completeBackgroundSave(snapshot)
        case .missing:
            markMissingSavedDocumentClean(snapshot)
        case .cancelled:
            return
        case .failed(let message):
            Log.editor.error("Failed to save file: \(message)")
        }
    }

    private func completeBackgroundSave(_ snapshot: DocumentSaveSnapshot) {
        guard let document = blockDocuments[snapshot.tabId],
              document.markdown == snapshot.content else { return }

        var savedPath = snapshot.oldPath
        if let title = snapshot.title {
            if snapshot.isPhysicalDatabaseRowFile {
                savedPath = synchronizeFirstPartyRowFilename(oldPath: snapshot.oldPath, title: title)
            } else {
                savedPath = synchronizePlainMarkdownFilename(
                    oldPath: snapshot.oldPath,
                    parentDir: snapshot.parentDirectory,
                    title: title,
                    legacyIndex: snapshot.legacyIndex,
                    tabId: snapshot.tabId
                )
            }
        }
        if savedPath != snapshot.oldPath {
            rewriteOpenDocumentPathsAfterPageRename(from: snapshot.oldPath, to: savedPath)
        }

        Task(priority: .utility) {
            await editorSaveWorker.clearPageDraft(path: snapshot.oldPath)
            if savedPath != snapshot.oldPath {
                await editorSaveWorker.clearPageDraft(path: savedPath)
            }
        }

        if let workspace = appState.workspacePath {
            backlinkService.updateFile(at: savedPath, in: workspace)
        }
        refreshFirstPartyIndexInBackground(rowPath: savedPath)
        if let legacyIndex = snapshot.legacyIndex {
            appState.openTabs[legacyIndex].isDirty = false
        }
        updateWorkspaceOpenFile(tabId: snapshot.tabId) { file in
            file.content = document.markdown
            file.path = savedPath
            file.isDirty = false
            if let title = plainDocumentTitle(in: document) {
                file.displayName = title
            }
        }
        if MarkdownBlockParser.yamlValue(for: "type", in: document.yamlFrontmatter) == "meeting" {
            Log.profileMarker("meetingNotePersist")
        }
    }

    private func markMissingSavedDocumentClean(_ snapshot: DocumentSaveSnapshot) {
        if let legacyIndex = snapshot.legacyIndex {
            appState.openTabs[legacyIndex].isDirty = false
        }
        if snapshot.hasWorkspaceFile {
            updateWorkspaceOpenFile(tabId: snapshot.tabId) { file in
                file.isDirty = false
            }
        }
    }

    private func saveDocument(tabId: UUID) {
        let legacyIndex = appState.openTabs.firstIndex(where: { $0.id == tabId })
        let workspaceFile = workspaceManager.openFile(tabId: tabId)
        guard let currentFile = workspaceFile ?? legacyIndex.map({ appState.openTabs[$0] }),
              currentFile.isDirty else { return }
        let oldPath = currentFile.path
        // Don't recreate a file that was deleted/trashed
        guard !oldPath.isEmpty, FileManager.default.fileExists(atPath: oldPath) else {
            if let legacyIndex {
                appState.openTabs[legacyIndex].isDirty = false
            }
            if workspaceFile != nil {
                updateWorkspaceOpenFile(tabId: tabId) { file in
                    file.isDirty = false
                }
            }
            return
        }
        var didPersistDocument = false
        var savedPath = oldPath
        if let document = blockDocuments[tabId] {
            let title = plainDocumentTitle(in: document)
            synchronizeFirstPartyRowFrontmatterName(document: document, path: oldPath, title: title)
            let content = document.markdown
            if let legacyIndex {
                appState.openTabs[legacyIndex].content = content
            }
            do {
                try fileSystem.saveFile(at: oldPath, content: content)
                didPersistDocument = true
            } catch {
                Log.editor.error("Failed to save file: \(error.localizedDescription)")
            }

            let parentDir = (oldPath as NSString).deletingLastPathComponent
            let isPhysicalDatabaseRowFile = fileSystem.isDatabaseFolder(at: parentDir)
            if didPersistDocument,
               let title {
                if isPhysicalDatabaseRowFile {
                    savedPath = synchronizeFirstPartyRowFilename(oldPath: oldPath, title: title)
                } else {
                    savedPath = synchronizePlainMarkdownFilename(
                        oldPath: oldPath,
                        parentDir: parentDir,
                        title: title,
                        legacyIndex: legacyIndex,
                        tabId: tabId
                    )
                }
            }
            if savedPath != oldPath {
                rewriteOpenDocumentPathsAfterPageRename(from: oldPath, to: savedPath)
            }
        }

        guard didPersistDocument else { return }

        editorDraftStore.clearPageDraft(path: oldPath)
        if savedPath != oldPath {
            editorDraftStore.clearPageDraft(path: savedPath)
        }

        if let workspace = appState.workspacePath {
            backlinkService.updateFile(at: savedPath, in: workspace)
        }
        refreshFirstPartyIndexInBackground(rowPath: savedPath)
        if let legacyIndex {
            appState.openTabs[legacyIndex].isDirty = false
        }
        updateWorkspaceOpenFile(tabId: tabId) { file in
            file.content = blockDocuments[tabId]?.markdown ?? file.content
            file.path = savedPath
            file.isDirty = false
            if let document = blockDocuments[tabId],
               let title = plainDocumentTitle(in: document) {
                file.displayName = title
            }
        }
    }

    private func plainDocumentTitle(in document: BlockDocument) -> String? {
        guard let rawTitle = document.titleBlock?.text else { return nil }
        let title = AttributedStringConverter.plainText(from: rawTitle)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? nil : title
    }

    private func refreshFirstPartyIndexInBackground(rowPath: String) {
        guard let schema = fileSystem.firstPartySchemaForRowFile(at: rowPath) else { return }
        let worker = firstPartyIndexWorker
        Task(priority: .utility) {
            do {
                try await worker.refreshRowFile(at: rowPath, schema: schema)
            } catch {
                Log.fileSystem.error("Failed to refresh first-party database index: \(error.localizedDescription)")
            }
        }
    }

    private func synchronizeFirstPartyRowFrontmatterName(
        document: BlockDocument,
        path: String,
        title: String?
    ) {
        guard let title,
              fileSystem.firstPartyDatabaseKindForRowFile(at: path) == .meetings else {
            return
        }
        document.yamlFrontmatter = Self.upsertingYAMLScalar("name", value: title, in: document.yamlFrontmatter)
    }

    private func synchronizeFirstPartyRowFilename(oldPath: String, title: String) -> String {
        do {
            return try fileSystem.synchronizeMeetingRowFilename(rowPath: oldPath, title: title)
        } catch {
            Log.fileSystem.error("Failed to rename meeting row file: \(error.localizedDescription)")
            return oldPath
        }
    }

    private func synchronizePlainMarkdownFilename(
        oldPath: String,
        parentDir: String,
        title: String,
        legacyIndex: Int?,
        tabId: UUID
    ) -> String {
        let currentName = (oldPath as NSString).lastPathComponent.replacingOccurrences(of: ".md", with: "")
        guard title != currentName else { return oldPath }

        let sanitized = title.replacingOccurrences(of: "[/\\\\?%*:|\"<>]", with: "-", options: .regularExpression)
        guard !sanitized.isEmpty else { return oldPath }

        let newPath = (parentDir as NSString).appendingPathComponent("\(sanitized).md")
        guard !FileManager.default.fileExists(atPath: newPath) else { return oldPath }

        do {
            try fileSystem.renameFile(from: oldPath, to: newPath)
            if let legacyIndex {
                appState.openTabs[legacyIndex].path = newPath
                appState.updateNavigationPath(for: tabId, from: oldPath, to: newPath)
            }
            updatePageLinks(oldName: currentName, newName: sanitized, docs: blockDocuments)
            refreshFileTree()
            return newPath
        } catch {
            Log.fileSystem.error("Failed to rename file: \(error.localizedDescription)")
            return oldPath
        }
    }

    private static func upsertingYAMLScalar(_ key: String, value: String, in yaml: String) -> String {
        var lines = yaml.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let serializedValue = "\"\(Self.escapeYAMLScalar(value))\""
        for index in lines.indices {
            let indentation = lines[index].prefix { $0 == " " || $0 == "\t" }
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("\(key):") else { continue }
            lines[index] = "\(indentation)\(key): \(serializedValue)"
            return lines.joined(separator: "\n")
        }

        lines.append("\(key): \(serializedValue)")
        return lines.joined(separator: "\n")
    }

    private static func escapeYAMLScalar(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    /// Removes any databaseEmbed blocks referencing `dbPath` from all currently open BlockDocuments.
    private func cleanupTabDocuments(_ tabId: UUID) {
        blockDocuments.removeValue(forKey: tabId)
        databaseRowFullWidth.removeValue(forKey: tabId)
    }

    private func pageOptionsMenu(for tab: OpenFile, document: BlockDocument) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Button {
                toggleFavorite(path: tab.path)
                showPageOptionsMenu = false
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: isPathFavorited(tab.path) ? "star.fill" : "star")
                        .frame(width: 16)
                    Text(isPathFavorited(tab.path) ? "Unfavorite page" : "Favorite page")
                    Spacer()
                }
                .font(.system(size: Typography.bodySmall))
                .foregroundStyle(.primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                document.fullWidth.toggle()
                markActiveEditorTabDirty()
                scheduleSave()
                showPageOptionsMenu = false
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.left.and.right")
                        .frame(width: 16)
                    Text("Full width")
                    Spacer()
                    if document.fullWidth {
                        Image(systemName: "checkmark")
                            .font(.caption)
                    }
                }
                .font(.system(size: Typography.bodySmall))
                .foregroundStyle(.primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(tab.path, forType: .string)
                showPageOptionsMenu = false
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "doc.on.doc")
                        .frame(width: 16)
                    Text("Copy file path")
                    Spacer()
                }
                .font(.system(size: Typography.bodySmall))
                .foregroundStyle(.primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(document.markdown, forType: .string)
                showPageOptionsMenu = false
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "doc.plaintext")
                        .frame(width: 16)
                    Text("Copy page content")
                    Spacer()
                }
                .font(.system(size: Typography.bodySmall))
                .foregroundStyle(.primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                appState.movePagePath = tab.path
                showPageOptionsMenu = false
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.right")
                        .frame(width: 16)
                    Text("Move to")
                    Spacer()
                }
                .font(.system(size: Typography.bodySmall))
                .foregroundStyle(.primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(4)
        .frame(width: 200)
        .popoverSurface()
    }

    private func databaseRowOptionsMenu(for tab: OpenFile) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Button {
                databaseRowFullWidth[tab.id, default: false].toggle()
                showPageOptionsMenu = false
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.left.and.right")
                        .frame(width: 16)
                    Text("Full width")
                    Spacer()
                    if databaseRowFullWidth[tab.id, default: false] {
                        Image(systemName: "checkmark")
                            .font(.caption)
                    }
                }
                .font(.system(size: Typography.bodySmall))
                .foregroundStyle(.primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                if let path = databaseRowFilePath(for: tab) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(path, forType: .string)
                }
                showPageOptionsMenu = false
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "doc.on.doc")
                        .frame(width: 16)
                    Text("Copy file path")
                    Spacer()
                }
                .font(.system(size: Typography.bodySmall))
                .foregroundStyle(.primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                deleteDatabaseRow(for: tab)
                showPageOptionsMenu = false
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "trash")
                        .frame(width: 16)
                    Text("Delete")
                    Spacer()
                }
                .font(.system(size: Typography.bodySmall))
                .foregroundStyle(.red)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(4)
        .frame(width: 200)
        .popoverSurface()
    }

    private func databaseRowFilePath(for tab: OpenFile) -> String? {
        guard let dbPath = tab.databasePath,
              let rowId = tab.databaseRowId else {
            return nil
        }
        return fileSystem.rowFilePathForDatabaseRow(dbPath: dbPath, rowId: rowId)
    }

    private func deleteDatabaseRow(for tab: OpenFile) {
        guard let dbPath = tab.databasePath,
              let rowId = tab.databaseRowId else {
            return
        }

        let dbService = DatabaseService()
        // Load schema before deleting so we can do an incremental index removal
        let schemaForIndex = try? dbService.loadDatabase(at: dbPath).0
        try? dbService.deleteRow(rowId, in: dbPath)
        if let schema = schemaForIndex {
            try? dbService.incrementalIndexDelete(rowId: rowId, schema: schema, at: dbPath)
        }

        NotificationCenter.default.post(
            name: .databaseRowDeleted,
            object: nil,
            userInfo: [DatabaseNotificationKey.dbPath: dbPath, DatabaseNotificationKey.rowId: rowId]
        )
        postDatabaseChangeNotification(dbPath: dbPath, origin: "contentView.databaseRowMenu")
        appState.closeTab(at: appState.activeTabIndex)
    }

    private func removeDatabaseEmbedsFromOpenDocs(dbPath: String) {
        for (_, doc) in blockDocuments {
            let toRemove = doc.blocks.filter { $0.type == .databaseEmbed && $0.databasePath == dbPath }.map(\.id)
            for id in toRemove {
                doc.deleteBlock(id: id)
            }
        }
    }

    private func forceSave() {
        guard let tab = activeWorkspaceDocumentContext()?.file ?? appState.activeTab,
              !tab.path.isEmpty else { return }
        SentryBreadcrumbs.add(Breadcrumb(level: .info, category: "editor.save"))
        if tab.isExternal {
            saveExternalFileToWorkspace(tabId: tab.id)
            return
        }
        performSave(tabId: tab.id)
    }

    private func ensureAiInitializedIfNeeded() {
        guard BugbookFeatureGate.legacyPanesEnabled else { return }
        if aiInitCompleted { return }
        if aiInitTask != nil { return }

        let aiService = legacyAiService
        aiInitTask = Task {
            await aiService.detectEngines()
            guard !Task.isCancelled else { return }
            await aiService.prewarmSession()
            guard !Task.isCancelled else { return }
            aiInitCompleted = true
            aiInitTask = nil
        }
    }

    private func navigateToPage(named pageName: String) {
        if let dbPath = resolveDatabasePath(from: pageName) {
            openDatabase(at: dbPath)
            return
        }

        func findEntry(in entries: [FileEntry]) -> FileEntry? {
            for entry in entries {
                let entryName = entry.name.replacingOccurrences(of: ".md", with: "")
                if entryName.localizedCaseInsensitiveCompare(pageName) == .orderedSame {
                    return entry
                }
                if let children = entry.children, let found = findEntry(in: children) {
                    return found
                }
            }
            return nil
        }

        if let entry = findEntry(in: appState.fileTree) {
            navigateToEntryInPane(entry)
        }
    }

    private func openDatabase(at path: String) {
        guard FileManager.default.fileExists(atPath: path) else { return }

        if let existing = fileSystem.findEntry(path: path, in: appState.fileTree) {
            navigateToEntryInPane(existing)
            return
        }

        let entry = FileEntry(
            id: path,
            name: (path as NSString).lastPathComponent,
            path: path,
            isDirectory: false,
            kind: .database
        )
        navigateToEntryInPane(entry)
    }

    private func resolveDatabasePath(from raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.lowercased().hasPrefix("database:") else { return nil }

        var target = String(trimmed.dropFirst("database:".count))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if target.isEmpty { return nil }

        if target.lowercased().hasPrefix("file://"), let url = URL(string: target) {
            target = url.path
        } else if target.hasPrefix("///") {
            target = "/" + String(target.dropFirst(3))
        } else if target.hasPrefix("//") {
            target = "/" + String(target.dropFirst(2))
        }

        if target.hasPrefix("~") {
            target = (target as NSString).expandingTildeInPath
        }
        if target.contains("%"), let decoded = target.removingPercentEncoding {
            target = decoded
        }
        if target.hasSuffix("/_schema.json") {
            target = (target as NSString).deletingLastPathComponent
        }

        guard target.hasPrefix("/") else { return nil }
        return target
    }

    private func peekDragOnChanged(translationWidth: CGFloat) {
        if peekDragStartWidth == nil {
            peekDragStartWidth = peekWidth
        }
        let startWidth = peekDragStartWidth ?? peekWidth
        let proposed = startWidth - translationWidth
        let clamped = max(360, min(1200, proposed))
        peekWidth = clamped
        // Auto-hide sidebar when peek is wide
        if clamped > 600 && !sidebarHiddenByPeek {
            sidebarHiddenByPeek = true
            sidebarVisibleBeforePeekHide = appState.sidebarVisible
            appState.sidebarVisible = false
        } else if clamped <= 600 && sidebarHiddenByPeek {
            sidebarHiddenByPeek = false
            appState.sidebarVisible = sidebarVisibleBeforePeekHide
        }
    }

    private func closePeekPanel() {
        peekTarget = nil
        if sidebarHiddenByPeek {
            sidebarHiddenByPeek = false
            appState.sidebarVisible = sidebarVisibleBeforePeekHide
        }
    }

    private func closeDatabaseRowModal() {
        modalTarget = nil
    }

    private func syncTitle(from document: BlockDocument) {
        guard let rawTitle = document.titleBlock?.text, !rawTitle.isEmpty else { return }
        let title = AttributedStringConverter.plainText(from: rawTitle)
        if let context = activeWorkspaceDocumentContext() {
            updateWorkspaceOpenFile(tabId: context.file.id) { file in
                file.displayName = title
            }
            updateFileTreeName(path: context.file.path, newName: title)
        }
        if appState.activeTabIndex < appState.openTabs.count,
           appState.openTabs[appState.activeTabIndex].displayName != title {
            appState.openTabs[appState.activeTabIndex].displayName = title
            let path = appState.openTabs[appState.activeTabIndex].path
            updateFileTreeName(path: path, newName: title)
        }
    }

    private func updateFileTreeName(path: String, newName: String) {
        func update(entries: inout [FileEntry]) {
            for i in entries.indices {
                if entries[i].path == path {
                    entries[i].name = newName
                    return
                }
                if var children = entries[i].children {
                    update(entries: &children)
                    entries[i].children = children
                }
            }
        }
        update(entries: &appState.fileTree)
    }

    private func currentPageBacklinks(for tab: OpenFile) -> [Backlink] {
        guard !tab.isDatabaseRow else { return [] }
        guard let workspace = appState.workspacePath else { return [] }
        backlinkService.ensureIndex(workspace: workspace)

        let filename = (tab.path as NSString).lastPathComponent
        guard filename.hasSuffix(".md") else { return [] }
        let pageName = String(filename.dropLast(3))
        return backlinkService.backlinksFor(pageName: pageName)
    }

    private func navigateToFilePath(_ path: String) {
        let entry: FileEntry
        if let existing = fileSystem.findEntry(path: path, in: appState.fileTree) {
            entry = existing
        } else {
            let name = (path as NSString).lastPathComponent
            let isDatabase = fileSystem.isDatabaseFolder(at: path)
            let kind: TabKind = isDatabase ? .database : .page
            entry = FileEntry(id: path, name: name, path: path, isDirectory: false, kind: kind)
        }
        navigateToEntryInPane(entry)
    }

    @ViewBuilder
    private func skillFileBanner(path: String) -> some View {
        let home = NSHomeDirectory()
        let display = path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
        HStack(spacing: ShellZoomMetrics.size(6)) {
            Image(systemName: "pencil.line")
                .font(ShellZoomMetrics.font(Typography.caption))
                .foregroundStyle(.secondary)
            Text("Editing skill file \u{00B7} \(display)")
                .font(ShellZoomMetrics.font(Typography.caption))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, ShellZoomMetrics.size(16))
        .padding(.vertical, ShellZoomMetrics.size(6))
        .background(Color.primary.opacity(0.04))
    }

    private func breadcrumbs(for tab: OpenFile) -> [BreadcrumbItem] {
        guard let workspace = appState.workspacePath else { return [] }
        if tab.isDatabaseRow, let dbPath = tab.databasePath {
            var crumbs = fileSystem.getBreadcrumbs(for: dbPath, relativeTo: workspace)
            crumbs.append(
                BreadcrumbItem(
                    id: tab.path,
                    name: tab.displayName ?? "New Page",
                    path: "",
                    icon: nil
                )
            )
            return crumbs
        }
        var crumbs = fileSystem.getBreadcrumbs(for: tab.path, relativeTo: workspace)
        // Use live title for the last breadcrumb
        if let displayName = tab.displayName, !displayName.isEmpty, !crumbs.isEmpty {
            crumbs[crumbs.count - 1].name = displayName
        }
        return crumbs
    }

    private func updateDatabaseRowTabTitle(tabId: UUID, title: String) {
        guard let index = appState.openTabs.firstIndex(where: { $0.id == tabId }) else { return }
        appState.openTabs[index].displayName = title
    }
}

// Safe array subscript
extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

extension View {
    func bugbookCompactScrollIndicators() -> some View {
        background(BugbookScrollIndicatorConfigurator())
    }
}

private struct BugbookScrollIndicatorConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        Task { @MainActor in
            Self.configureNearestScrollView(from: view)
        }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        Task { @MainActor in
            Self.configureNearestScrollView(from: view)
        }
    }

    @MainActor
    private static func configureNearestScrollView(from view: NSView) {
        guard let scrollView = nearestScrollView(from: view) else { return }
        scrollView.scrollerStyle = .overlay
        scrollView.verticalScroller?.controlSize = .mini
        scrollView.horizontalScroller?.controlSize = .mini
    }

    @MainActor
    private static func nearestScrollView(from view: NSView) -> NSScrollView? {
        var currentView: NSView? = view
        while let candidate = currentView {
            if let scrollView = candidate as? NSScrollView {
                return scrollView
            }
            if let scrollView = firstDescendantScrollView(in: candidate) {
                return scrollView
            }
            currentView = candidate.superview
        }
        return nil
    }

    @MainActor
    private static func firstDescendantScrollView(in view: NSView) -> NSScrollView? {
        for subview in view.subviews {
            if let scrollView = subview as? NSScrollView {
                return scrollView
            }
            if let scrollView = firstDescendantScrollView(in: subview) {
                return scrollView
            }
        }
        return nil
    }
}
