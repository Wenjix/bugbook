import SwiftUI
import AppKit
import os
import Sentry
import BugbookCore

struct ContentView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let editorDraftStore = EditorDraftStore()

    @State private var appState = AppState()
    @State private var fileSystem = FileSystemService()
    @State private var aiService = AiService()
    @State private var calendarService = CalendarService()
    @State private var calendarVM = CalendarViewModel()
    @State private var meetingNoteService = MeetingNoteService()
    @State private var transcriptionService = TranscriptionService()
    @State private var meetingsVM = MeetingsViewModel()
    @State private var backlinkService = BacklinkService()
    @State private var blockDocuments: [UUID: BlockDocument] = [:]
    @State private var workspaceManager = WorkspaceManager()
    @State private var terminalManager = TerminalManager()

    @State private var saveTask: Task<Void, Never>?
    @State private var sidebarPeek = SidebarPeekState()
    @State private var editorUI = EditorUIState()
    @State private var themeToast: ThemeMode?
    @State private var themeToastTask: Task<Void, Never>?
    @State private var formattingPanel: FormattingToolbarPanel?
    @State private var aiInitTask: Task<Void, Never>?
    @State private var aiInitCompleted = false
    @State private var workspaceWatcher: WorkspaceWatcher?
    @State private var lastTrashPurgeWorkspace: String?
    @State private var recordingPillController = FloatingRecordingPillController()
    @AppStorage(EditorTypography.zoomScaleKey) private var editorZoomScale = Double(EditorTypography.defaultZoomScale)

    // Database row peek / modal
    private struct RowTarget {
        var dbPath: String
        let rowId: String
        var autoFocusTitle: Bool = false
    }
    @State private var peekTarget: RowTarget?
    @State private var dbInitialRowId: String?
    @State private var peekWidth: CGFloat = 640
    @State private var peekDragStartWidth: CGFloat?
    @State private var sidebarHiddenByPeek: Bool = false
    @State private var sidebarWasOpenBeforeSettings: Bool = true
    @State private var modalTarget: RowTarget?
    @State private var showPageOptionsMenu = false
    @State private var databaseRowFullWidth: [UUID: Bool] = [:]

    var body: some View {
        configuredLayout
    }

    private var baseLayout: some View {
        ZStack(alignment: .leading) {
            // Solid backdrop so the content area's rounded corner reveals sidebar color
            Color.fallbackSidebarBg

            HStack(spacing: 0) {
                sidebarSection
                mainContentWithAiPanel
            }

            sidebarPeekEdgeHotspot
            sidebarToggleOverlay
            sidebarPeekOverlay
            commandPaletteOverlay

            movePageOverlay
            themeToastOverlay
            editorZoomOverlay
        }
    }

    private var configuredLayout: some View {
        applyDatabaseNotifications(
            to: applyCommandNotifications(
                to: applyLifecycle(to: baseLayout)
            )
        )
    }

    private func applyLifecycle<V: View>(to view: V) -> some View {
        view
            .ignoresSafeArea()
            .frame(minWidth: 800, minHeight: 500)
            .task {
                initializeWorkspace()
                applyTheme(appState.settings.theme)
                editorZoomScale = clampedEditorZoomScale(editorZoomScale)
                editorUI.focusModeEnabled = appState.settings.focusModeOnType
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
            .onChange(of: appState.settings.qmdSearchMode) { _, _ in
                // v2: no daemon needed, qmd query runs locally
            }
            .onChange(of: appState.sidebarOpen) { _, _ in
                sidebarPeek.sync(eligible: sidebarPeekEligible, reduceMotion: reduceMotion)
            }
            .onChange(of: appState.showSettings) { _, showingSettings in
                if showingSettings {
                    sidebarPeek.dismiss(immediately: true, reduceMotion: reduceMotion)
                    sidebarWasOpenBeforeSettings = appState.sidebarOpen
                    appState.sidebarOpen = true
                } else {
                    appState.sidebarOpen = sidebarWasOpenBeforeSettings
                }
                sidebarPeek.sync(eligible: sidebarPeekEligible, reduceMotion: reduceMotion)
            }
            .onChange(of: appState.fileTree) { _, newTree in
                syncAvailablePages(newTree)
                refreshSidebarReferences(using: newTree)
                refreshFavorites(using: newTree)
            }
            .onChange(of: appState.aiSidePanelOpen) { _, isOpen in
                if isOpen {
                    ensureAiInitializedIfNeeded()
                }
            }
            .onChange(of: editorUI.focusModeActive) { _, _ in
                sidebarPeek.sync(eligible: sidebarPeekEligible, reduceMotion: reduceMotion)
            }
            .onChange(of: sidebarPeek.trashPopoverPresented) { _, _ in
                sidebarPeek.sync(eligible: sidebarPeekEligible, reduceMotion: reduceMotion)
            }
            .onChange(of: appState.settings.focusModeOnType) { _, enabled in
                editorUI.focusModeEnabled = enabled
            }
            .onChange(of: workspaceManager.activeWorkspace?.focusedPaneId) { _, _ in
                hideFormattingPanel()
                closeDatabaseRowModal()
            }
            .onChange(of: appState.currentView) { _, newView in
                SentrySDK.addBreadcrumb(Breadcrumb(level: .info, category: "view.change.\(newView)"))
                hideFormattingPanel()
                closeDatabaseRowModal()
                if newView == .chat {
                    ensureAiInitializedIfNeeded()
                }
            }
            .onChange(of: appState.isRecording) { _, recording in
                recordingPillController.isRecording = recording
            }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.willResignActiveNotification)) { _ in
                flushDirtyTabs()
            }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                flushDirtyTabs()
            }
            .onDisappear {
                flushDirtyTabs()
                terminalManager.shutdown()
                aiInitTask?.cancel()
                aiInitTask = nil
                editorUI.cleanUp()
                sidebarPeek.cleanUp()
                workspaceWatcher?.stop()
                recordingPillController.cleanup()
            }
            .onReceive(NotificationCenter.default.publisher(for: .fileDeleted)) { notification in
                if let path = notification.object as? String {
                    saveTask?.cancel()
                    saveTask = nil
                    editorDraftStore.clearPageDraft(path: path)
                    // Close panes showing the deleted file
                    for ws in workspaceManager.workspaces {
                        for leaf in ws.allLeaves {
                            if case .document(let file) = leaf.content, file.path == path {
                                cleanupTabDocuments(leaf.id)
                                workspaceManager.closePane(id: leaf.id)
                            }
                        }
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
            .onReceive(NotificationCenter.default.publisher(for: .splitPaneRight)) { _ in
                _ = workspaceManager.splitFocusedPane(axis: .horizontal, newContent: .terminal)
            }
            .onReceive(NotificationCenter.default.publisher(for: .splitPaneDown)) { _ in
                _ = workspaceManager.splitFocusedPane(axis: .vertical, newContent: .terminal)
            }
            .onReceive(NotificationCenter.default.publisher(for: .closeWorkspace)) { _ in
                workspaceManager.closeWorkspace(at: workspaceManager.activeWorkspaceIndex)
            }
            .onReceive(NotificationCenter.default.publisher(for: .switchWorkspace)) { notification in
                if let index = notification.object as? Int {
                    workspaceManager.switchWorkspace(to: index)
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
            .onReceive(NotificationCenter.default.publisher(for: .newTab)) { _ in
                appState.newEmptyTab()
            }
            .onReceive(NotificationCenter.default.publisher(for: .closeTab)) { _ in
                guard let paneId = workspaceManager.activeWorkspace?.focusedPaneId else { return }
                cleanupTabDocuments(paneId)
                terminalManager.closeSession(paneId)
                workspaceManager.closePane(id: paneId)
            }
            .onReceive(NotificationCenter.default.publisher(for: .saveFile)) { _ in
                forceSave()
            }
            .onReceive(NotificationCenter.default.publisher(for: .toggleSidebar)) { _ in
                handleSidebarToggleRequest()
            }
            .onReceive(NotificationCenter.default.publisher(for: .quickOpen)) { _ in
                flushDirtyTabContent()
                appState.commandPaletteMode = .search
                appState.commandPaletteOpen.toggle()
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
                appState.openGraphView()
            }
            .onReceive(NotificationCenter.default.publisher(for: .openCalendar)) { _ in
                appState.openCalendar()
            }
            .onReceive(NotificationCenter.default.publisher(for: .openMeetings)) { _ in
                appState.openMeetings()
            }
            .onReceive(NotificationCenter.default.publisher(for: .newDatabase)) { _ in
                createNewDatabase()
            }
            .onReceive(NotificationCenter.default.publisher(for: .navigateBack)) { _ in
                navigateBackInActiveTab()
            }
            .onReceive(NotificationCenter.default.publisher(for: .navigateForward)) { _ in
                navigateForwardInActiveTab()
            }
    }

    private func applyZoomNotifications<V: View>(to view: V) -> some View {
        view
            .onReceive(NotificationCenter.default.publisher(for: .editorZoomIn)) { _ in
                adjustEditorZoom(by: 0.1)
            }
            .onReceive(NotificationCenter.default.publisher(for: .editorZoomOut)) { _ in
                adjustEditorZoom(by: -0.1)
            }
            .onReceive(NotificationCenter.default.publisher(for: .editorZoomReset)) { _ in
                resetEditorZoom()
            }
    }

    private func applyDatabaseNotifications<V: View>(to view: V) -> some View {
        view
            .onReceive(NotificationCenter.default.publisher(for: .openAIPanel)) { _ in
                ensureAiInitializedIfNeeded()
                appState.toggleAiPanel()
            }
            .onReceive(NotificationCenter.default.publisher(for: .askAI)) { notification in
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

    @ViewBuilder
    private var sidebarSection: some View {
        if appState.sidebarOpen {
            SidebarView(
                appState: appState,
                fileSystem: fileSystem,
                onSelectFile: { entry in
                    handleSidebarFileSelect(entry)
                },
                onToggleSidebar: { handleSidebarToggleRequest() },
                onAddSidebarReference: { payload in
                    addSidebarReference(payload)
                }
            )
            .layoutPriority(1)
        }
    }

    @ViewBuilder
    private var sidebarPeekEdgeHotspot: some View {
        if sidebarPeekEligible {
            HStack(spacing: 0) {
                Color.clear
                    .frame(width: 4)
                    .contentShape(Rectangle())
                    .onHover { hovering in
                        sidebarPeek.setEdgeHovering(hovering, eligible: sidebarPeekEligible, reduceMotion: reduceMotion)
                    }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var sidebarToggleOverlay: some View {
        if sidebarPeekEligible {
            VStack {
                HStack {
                    sidebarChromeButton(icon: "sidebar.left", help: "Open Sidebar") {
                        openSidebarPinned()
                    }
                    .padding(ShellZoomMetrics.size(4))
                    .contentShape(Rectangle())
                    .onHover { hovering in
                        sidebarPeek.setToggleHovering(hovering, eligible: sidebarPeekEligible, reduceMotion: reduceMotion)
                    }
                    .padding(.leading, ShellZoomMetrics.size(80))
                    Spacer()
                }
                .padding(.top, ShellZoomMetrics.size(4))
                Spacer()
            }
            .opacity(editorUI.focusModeActive ? 0.0 : 1.0)
        }
    }

    @ViewBuilder
    private var sidebarPeekOverlay: some View {
        if sidebarPeekEligible {
            SidebarView(
                appState: appState,
                fileSystem: fileSystem,
                onSelectFile: { entry in
                    handleSidebarFileSelect(entry)
                    sidebarPeek.dismiss(immediately: true, reduceMotion: reduceMotion)
                },
                onToggleSidebar: {
                    openSidebarPinned()
                },
                onAddSidebarReference: { payload in
                    addSidebarReference(payload)
                },
                layoutMode: .compact,
                onActionInvoked: {
                    sidebarPeek.dismiss(immediately: true, reduceMotion: reduceMotion)
                },
                trashPopoverOverride: Binding(
                    get: { sidebarPeek.trashPopoverPresented },
                    set: { sidebarPeek.trashPopoverPresented = $0 }
                )
            )
            .frame(width: ShellZoomMetrics.size(208))
            .frame(maxHeight: ShellZoomMetrics.size(430), alignment: .topLeading)
            .clipShape(.rect(cornerRadius: ShellZoomMetrics.size(Radius.md)))
            .overlay {
                RoundedRectangle(cornerRadius: ShellZoomMetrics.size(Radius.md))
                    .stroke(Color.fallbackChromeBorder, lineWidth: 0.5)
                    .allowsHitTesting(false)
            }
            .shadow(color: Color.black.opacity(0.10), radius: 10, x: 4, y: 4)
            .contentShape(Rectangle())
            .offset(x: sidebarPeek.isVisible ? 0 : sidebarPeekHiddenOffset)
            .opacity(sidebarPeek.isVisible ? 1 : 0)
            .allowsHitTesting(sidebarPeek.isVisible)
            .onHover { hovering in
                // Only track overlay hover when peek is actually visible —
                // .onHover fires even with allowsHitTesting(false)
                guard sidebarPeek.isVisible else {
                    if sidebarPeek.overlayHovering {
                        sidebarPeek.setOverlayHovering(false, eligible: sidebarPeekEligible, reduceMotion: reduceMotion)
                    }
                    return
                }
                sidebarPeek.setOverlayHovering(hovering, eligible: sidebarPeekEligible, reduceMotion: reduceMotion)
            }
            .padding(.top, ShellZoomMetrics.size(72))
            .padding(.leading, ShellZoomMetrics.size(8))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .zIndex(1)
        }
    }

    @ViewBuilder
    private var commandPaletteOverlay: some View {
        if appState.commandPaletteOpen {
            Color.black.opacity(0.3)
                .onTapGesture { appState.commandPaletteOpen = false }

            VStack {
                Spacer()
                HStack {
                    Spacer()
                    CommandPaletteView(
                        appState: appState,
                        isPresented: $appState.commandPaletteOpen,
                        onSelectFile: { entry in
                            navigateToEntry(entry)
                        },
                        onSelectFileNewTab: { entry in
                            navigateToEntry(entry, inNewTab: true)
                        },
                        onCreateFile: { name in
                            createNewFileWithName(name)
                        },
                        onSelectContentMatch: { entry, query in
                            if appState.commandPaletteMode == .newTab {
                                navigateToEntry(entry, inNewTab: true)
                            } else {
                                navigateToEntry(entry)
                            }
                            // Jump to the block containing the match
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                guard let tab = appState.activeTab,
                                      let doc = blockDocuments[tab.id] else { return }
                                let lowerQuery = query.lowercased()
                                if let block = doc.blocks.first(where: {
                                    $0.text.lowercased().contains(lowerQuery)
                                }) {
                                    doc.focusedBlockId = block.id
                                    doc.cursorPosition = 0
                                }
                            }
                        }
                    )
                    Spacer()
                }
                Spacer()
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

    private var sidebarPeekEligible: Bool {
        !appState.sidebarOpen && !appState.showSettings && !editorUI.focusModeActive && !sidebarHiddenByPeek
    }

    private var sidebarPeekHiddenOffset: CGFloat {
        reduceMotion ? 0 : -ShellZoomMetrics.size(18)
    }

    private func openSidebarPinned() {
        sidebarPeek.dismiss(immediately: true, reduceMotion: reduceMotion)
        appState.sidebarOpen = true
    }

    private func handleSidebarToggleRequest() {
        guard !appState.showSettings else { return }
        if appState.sidebarOpen {
            appState.sidebarOpen = false
            sidebarPeek.dismiss(immediately: true, reduceMotion: reduceMotion)
        } else {
            openSidebarPinned()
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
            DispatchQueue.global(qos: .utility).async {
                fs.rewritePathsInFile(at: newPath, oldBase: oldCompanion, newBase: newCompanion)
                fs.rewritePathsRecursively(in: newCompanion, oldBase: oldCompanion, newBase: newCompanion)
            }

            // Also update paths for children that moved (companion folder contents)
            for tab in appState.openTabs {
                if tab.path.hasPrefix(oldCompanion + "/") {
                    let relative = String(tab.path.dropFirst(oldCompanion.count))
                    let updatedPath = newCompanion + relative
                    appState.updateNavigationPath(for: tab.id, from: tab.path, to: updatedPath)
                }
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

    /// Rewrite absolute paths inside a single .md file (e.g. database embed paths).
    // MARK: - Main Content

    @ViewBuilder
    private var mainContentWithAiPanel: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                if appState.showSettings {
                    SettingsView(appState: appState)
                } else if appState.currentView == .chat {
                    NotesChatView(appState: appState, aiService: aiService)
                } else if appState.currentView == .graphView {
                    if let workspace = appState.workspacePath {
                        GraphView(
                            backlinkService: backlinkService,
                            workspacePath: workspace,
                            currentPagePath: appState.activeTab?.path,
                            onNavigateToFile: { path in
                                navigateToFilePath(path)
                            }
                        )
                    }
                } else {
                    editorModeContent
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .ignoresSafeArea(.container, edges: .top)
            .background(Color.fallbackEditorBg)

            if appState.aiSidePanelOpen && appState.currentView == .editor {
                Divider()
                AiSidePanelView(
                    appState: appState,
                    aiService: aiService,
                    activeDocument: workspaceManager.activeWorkspace.flatMap { ws in blockDocuments[ws.focusedPaneId] }
                )
                    .transition(.move(edge: .trailing))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: appState.sidebarOpen ? ShellZoomMetrics.size(14) : 0,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: 0
            )
        )
        .overlay(alignment: .leading) {
            if appState.sidebarOpen {
                Rectangle()
                    .fill(Color.fallbackChromeBorder)
                    .frame(width: 1)
                    .allowsHitTesting(false)
            }
        }
    }

    private var activeTabLeadingPadding: CGFloat {
        let isCalendar = appState.activeTab?.isCalendar ?? false
        let isMeetings = appState.activeTab?.isMeetings ?? false
        if isCalendar || isMeetings { return 0 }
        return appState.sidebarOpen ? ShellZoomMetrics.size(8) : ShellZoomMetrics.size(78)
    }

    @ViewBuilder
    private var editorModeContent: some View {
        WorkspaceTabBar(
            workspaceManager: workspaceManager,
            sidebarOpen: appState.sidebarOpen
        )
            .opacity(editorUI.focusModeActive ? 0.0 : 1.0)

        Group {
            if let ws = workspaceManager.activeWorkspace {
                PaneTreeView(
                    node: ws.root,
                    workspaceManager: workspaceManager,
                    hasMultiplePanes: ws.hasMultiplePanes,
                    documentContentBuilder: { leaf, file in
                        AnyView(self.paneDocumentContent(leaf: leaf, file: file))
                    },
                    terminalContentBuilder: { leaf, _ in
                        AnyView(self.paneTerminalContent(leaf: leaf))
                    }
                )
            }
        }
        .environment(\.workspacePath, appState.workspacePath)
        .ignoresSafeArea(.container, edges: .top)
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

    // MARK: - Pane Document Content

    /// Renders document content for a single pane leaf. Handles breadcrumbs, options menu,
    /// and routes to the appropriate view based on the OpenFile's TabKind.
    @ViewBuilder
    private func paneDocumentContent(leaf: PaneNode.Leaf, file: OpenFile) -> some View {
        VStack(spacing: 0) {
            if !file.isEmptyTab && !file.isCalendar && !file.isMeetings {
                HStack {
                    BreadcrumbView(
                        items: breadcrumbs(for: file),
                        onNavigate: { item in navigateToBreadcrumb(item) },
                        sidebarOpen: appState.sidebarOpen
                    )

                    Spacer()

                    if !file.isEmptyTab && !file.isDatabase {
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
                            } else if let doc = blockDocuments[leaf.id] {
                                pageOptionsMenu(for: file, document: doc)
                            }
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
        if file.isCalendar || file.isMeetings { return 0 }
        return appState.sidebarOpen ? ShellZoomMetrics.size(8) : ShellZoomMetrics.size(78)
    }

    @ViewBuilder
    private func paneTerminalContent(leaf: PaneNode.Leaf) -> some View {
        if let session = terminalManager.session(for: leaf.id) {
            TerminalPaneView(session: session, paneId: leaf.id, workspaceManager: workspaceManager)
        } else {
            Color.fallbackEditorBg
                .onAppear {
                    terminalManager.createSession(
                        id: leaf.id,
                        workingDirectory: appState.workspacePath
                    )
                }
        }
    }

    /// Routes a pane's OpenFile to the correct content view based on its TabKind.
    @ViewBuilder
    private func paneContentRouting(leaf: PaneNode.Leaf, file: OpenFile) -> some View {
        if file.isEmptyTab {
            WelcomeView(
                onNewNote: { createNewFile() },
                onOpenFolder: { Task { await openWorkspace() } }
            )
            .onAppear { openDefaultPageIfConfigured() }
        } else if file.isDatabaseRow, let dbPath = file.databasePath, let rowId = file.databaseRowId {
            DatabaseRowFullPageView(
                dbPath: dbPath,
                rowId: rowId,
                onTitleChange: { title in
                    updateDatabaseRowTabTitle(tabId: leaf.id, title: title)
                },
                fullWidth: databaseRowFullWidth[leaf.id, default: false]
            )
            .id(leaf.id)
        } else if file.isCalendar {
            WorkspaceCalendarView(
                appState: appState,
                calendarService: calendarService,
                calendarVM: calendarVM,
                meetingNoteService: meetingNoteService,
                aiService: aiService,
                onNavigateToFile: { path in
                    navigateToFilePath(path)
                }
            )
        } else if file.isMeetings {
            MeetingsView(
                appState: appState,
                viewModel: meetingsVM,
                onNavigateToFile: { path in
                    navigateToFilePath(path)
                }
            )
        } else if file.isDatabase {
            DatabaseFullPageView(dbPath: file.path, initialRowId: dbInitialRowId)
                .id(leaf.id)
                .onAppear { dbInitialRowId = nil }
        } else {
            editorView(for: file)
        }
    }

    // MARK: - Editor

    @ViewBuilder
    private func editorView(for tab: OpenFile) -> some View {
        if let document = blockDocuments[tab.id] {
            HStack(spacing: 0) {
                ScrollViewReader { scrollProxy in
                ScrollView {
                    VStack(spacing: 0) {
                        PageHeaderView(
                            icon: Binding(
                                get: { document.icon },
                                set: {
                                    document.icon = $0
                                    markActiveEditorTabDirty()
                                    if appState.activeTabIndex < appState.openTabs.count {
                                        let tab = appState.openTabs[appState.activeTabIndex]
                                        appState.openTabs[appState.activeTabIndex].icon = $0
                                        appState.updateFileTreeIcon(for: tab.path, icon: $0)
                                    }
                                    scheduleSave()
                                }
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

                        BlockEditorView(
                            document: document,
                            onTextChange: {
                                guard appState.activeTabIndex < appState.openTabs.count else { return }
                                if !appState.openTabs[appState.activeTabIndex].isDirty {
                                    appState.openTabs[appState.activeTabIndex].isDirty = true
                                }
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
                }
                .background(Color.fallbackEditorBg)
                .accessibilityIdentifier("editor")
                .overlay {
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
                } // ScrollViewReader
            }
        } else {
            Color.fallbackEditorBg
        }
    }

    private func wireUpDocumentCallbacks(_ doc: BlockDocument) {
        doc.onCreateDatabase = { [weak appState] name in
            guard appState?.workspacePath != nil else { return nil }
            let path = try? createDatabasePath(name: name, parentPagePath: doc.filePath)
            if path != nil { refreshFileTree() }
            return path
        }
        doc.onCreateMeetingDatabase = { [weak appState] in
            guard let workspace = appState?.workspacePath else { return nil }
            let path = findOrCreateMeetingsDatabase(in: workspace)
            if path != nil { refreshFileTree() }
            return path
        }
        doc.onCreateSubPage = { [weak appState] name in
            guard let tab = appState?.activeTab else { return nil }
            let path = try? fileSystem.createSubPage(under: tab.path, name: name)
            if path != nil { refreshFileTree() }
            return path
        }
        doc.onDeleteSubPage = { [weak appState] pageName in
            guard let tab = appState?.activeTab,
                  let workspace = appState?.workspacePath else { return }
            // Companion folder is the .md path with extension stripped
            let tabPath = tab.path
            let parentDir = tabPath.hasSuffix(".md") ? String(tabPath.dropLast(3)) : tabPath
            let childPath = (parentDir as NSString).appendingPathComponent("\(pageName).md")
            guard FileManager.default.fileExists(atPath: childPath) else { return }
            try? fileSystem.trashFile(at: childPath, workspace: workspace)
            NotificationCenter.default.post(name: .fileDeleted, object: childPath)
            // Immediately save the parent page so the deleted block doesn't reappear on reload
            performSave(tabId: tab.id)
            refreshFileTree()
        }
        doc.onToggleFavorite = { path in
            self.toggleFavorite(path: path)
        }
        doc.onIsFavorite = { path in
            self.isPathFavorited(path)
        }
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
            let targetPagePath: String
            let possibleMd = destDir + ".md"
            if FileManager.default.fileExists(atPath: possibleMd) {
                targetPagePath = possibleMd
            } else { return }
            guard targetPagePath != tab.path else { return }
            do {
                var content = try fileSystem.loadFile(at: targetPagePath)
                if !content.hasSuffix("\n") { content += "\n" }
                content += blockMarkdown
                try fileSystem.saveFile(at: targetPagePath, content: content)
                // Suppress sub-page deletion during move — we're relocating, not deleting
                let savedCallback = doc.onDeleteSubPage
                doc.onDeleteSubPage = nil
                doc.deleteBlock(id: blockId)
                doc.onDeleteSubPage = savedCallback
                doc.moveBlockId = nil
                doc.blockMenuBlockId = nil
                if let targetTab = appState.openTabs.first(where: { $0.path == targetPagePath }),
                   let targetDoc = blockDocuments[targetTab.id] {
                    targetDoc.blocks = MarkdownBlockParser.parse(content)
                }
            } catch {
                Log.fileSystem.error("Move block failed: \(error.localizedDescription)")
            }
        }
        doc.onOpenDatabaseTab = { dbPath in
            openDatabase(at: dbPath)
        }
        doc.onSubmitAiPrompt = { [weak appState, weak doc] prompt in
            guard let appState, let doc else { return }
            doc.dismissAiPrompt()
            appState.openAiPanel(prompt: prompt)
        }
        doc.onCancelAiPrompt = { [weak doc] in
            doc?.dismissAiPrompt()
        }
        let ts = transcriptionService
        doc.transcriptionService = ts
        doc.onStartMeeting = { [weak doc] blockId in
            Task {
                await ts.startRecording()
                // Poll confirmed segments and audio level after recording starts
                var lastSegmentCount = 0
                var lastVolatile = ""
                var lastLevel: Float = -1
                while ts.isRecording {
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
                        doc?.updateBlockProperty(id: blockId) { block in
                            block.transcriptEntries = entries
                            block.meetingTranscript = entries.joined(separator: " ")
                        }
                        doc?.meetingVolatileText = volatile
                    }

                    try? await Task.sleep(for: .milliseconds(100))
                }
                doc?.meetingAudioLevel = 0
                doc?.meetingVolatileText = ""
            }
        }
        doc.onStopMeeting = { [weak doc] blockId in
            _ = ts.stopRecording()
            guard let doc else { return }
            let transcript = ts.currentTranscript
            doc.updateBlockProperty(id: blockId) { block in
                block.meetingState = .complete
                block.meetingTranscript = transcript
            }
        }
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
            if let tabIdx = appState.openTabs.firstIndex(where: { $0.id == tab.id }) {
                appState.openTabs[tabIdx].isDirty = true
            }
            performSave(tabId: tab.id)

            // Move the file into this page's companion folder
            let companionDir = tab.path.hasSuffix(".md") ? String(tab.path.dropLast(3)) : tab.path
            performMovePage(from: sourcePath, toDirectory: companionDir)
        }
    }

    // MARK: - Meeting Finalization

    private static let meetingTitleDateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "MMM d, yyyy"
        return df
    }()

    private func finalizeMeeting(doc: BlockDocument, blockId: UUID, transcript: String, appState: AppState?) async {
        let fallbackTitle = "Meeting \(Self.meetingTitleDateFormatter.string(from: Date()))"

        guard !transcript.isEmpty else {
            doc.updateBlockProperty(id: blockId) { block in
                block.meetingState = .complete
                if block.meetingTitle.isEmpty { block.meetingTitle = fallbackTitle }
                block.meetingSummary = "No audio was captured."
                block.meetingActionItems = ""
            }
            return
        }

        // Include user notes if they wrote any during the meeting
        let userNotes = doc.blocks.first(where: { $0.id == blockId })?.meetingNotes ?? ""

        let prompt = """
        You are a meeting notes assistant. Produce clean, structured notes like a skilled executive assistant would.

        Output format (use EXACTLY):

        TITLE: <descriptive title from content — e.g. "Q2 Planning & AutoLoRA Demo", NOT "Meeting" or a date>

        ### <Topic or Presenter Name>
        - **Bold key entity** followed by concise detail
          - Supporting specifics (numbers, names, decisions) as sub-bullets
        - Another key point
          1. Use numbered sub-items for sequential steps or features

        ### Action Items
        - [ ] Owner: specific action item with deadline if mentioned

        Style rules:
        - **Bold** speaker names, project names, and key terms on first mention
        - ### for section headings (topic-based, not "Summary")
        - Top-level bullets: one key point each, specific and factual
        - Sub-bullets: only for supporting details that add real information
        - Numbered sub-lists for features, steps, or ordered items
        - NO meta-commentary ("participants discussed", "the team talked about") — state facts directly
        - NO filler or padding — every bullet should carry information
        - Keep total output under 30 bullet points. For long meetings, prioritize: decisions > action items > key facts > discussion details
        - If nothing actionable, omit Action Items entirely
        \(userNotes.isEmpty ? "" : "\nUser's notes during the meeting (integrate into relevant sections):\n\(userNotes)\n")
        Transcript:
        \(transcript)
        """

        let engine = appState?.settings.preferredAIEngine ?? .auto
        let apiKey = appState?.settings.anthropicApiKey ?? ""
        let workspace = appState?.workspacePath ?? ""

        do {
            let result = try await aiService.generateContent(
                engine: engine,
                workspacePath: workspace,
                prompt: prompt,
                apiKey: apiKey
            )

            // Extract title from first line if present
            var title = fallbackTitle
            var body = result
            if let titleLine = result.components(separatedBy: "\n").first,
               titleLine.hasPrefix("TITLE:") {
                title = titleLine.replacingOccurrences(of: "TITLE:", with: "").trimmingCharacters(in: .whitespaces)
                body = result.components(separatedBy: "\n").dropFirst().joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            }

            doc.updateBlockProperty(id: blockId) { block in
                block.meetingState = .complete
                // Only override title if user didn't set one manually
                if block.meetingTitle.isEmpty || block.meetingTitle == "New Meeting" {
                    block.meetingTitle = title
                }
                block.meetingSummary = body
                // Store full structured output for the summary view parser
                block.language = body
            }
        } catch {
            doc.updateBlockProperty(id: blockId) { block in
                block.meetingState = .complete
                if block.meetingTitle.isEmpty { block.meetingTitle = fallbackTitle }
                block.meetingSummary = "AI summary unavailable: \(error.localizedDescription)"
                block.meetingActionItems = ""
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
            onAskAI: { [weak appState] in
                guard let appState,
                      let tab = appState.activeTab,
                      let doc = blockDocuments[tab.id],
                      let selectedMarkdown = doc.selectedBlocksMarkdown() else { return }
                hideFormattingPanel()
                let blockItems = doc.selectedBlockContextItems()
                appState.aiSelectionContext = selectedMarkdown
                appState.openAiPanel(referencedItems: blockItems)
            }
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
            onAskAI: { [weak appState] in
                guard let appState,
                      let tab = appState.activeTab,
                      let doc = blockDocuments[tab.id],
                      let selectedMarkdown = doc.selectedBlocksMarkdown() else { return }
                hideFormattingPanel()
                let blockItems = doc.selectedBlockContextItems()
                appState.aiSelectionContext = selectedMarkdown
                appState.openAiPanel(referencedItems: blockItems)
            }
        )
        panel.show(above: blockRect)
    }

    private func hideFormattingPanel() {
        formattingPanel?.hidePanel()
    }

    // MARK: - AI Notifications


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
                loadFileContentForPane(entry: entry, paneId: newPaneId)
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
    private func navigateToEntryInPane(_ entry: FileEntry) {
        appState.currentView = .editor
        appState.showSettings = false

        guard let ws = workspaceManager.activeWorkspace else { return }

        // Save current pane if dirty
        let focusedPaneId = ws.focusedPaneId
        if let leaf = ws.focusedLeaf,
           case .document(let file) = leaf.content,
           file.isDirty {
            performSave(tabId: focusedPaneId)
        }

        // Determine target pane
        let targetPaneId: UUID
        if let focusedLeaf = workspaceManager.focusedPane, case .document = focusedLeaf.content {
            targetPaneId = focusedLeaf.id
        } else if let nearestDoc = workspaceManager.nearestDocumentLeaf(from: focusedPaneId) {
            targetPaneId = nearestDoc.id
        } else {
            targetPaneId = focusedPaneId
        }

        // Update pane content
        let file = makeOpenFile(for: entry, id: targetPaneId)
        workspaceManager.updatePaneContent(paneId: targetPaneId, content: .document(openFile: file))
        workspaceManager.setFocusedPane(id: targetPaneId)
        loadFileContentForPane(entry: entry, paneId: targetPaneId)
    }

    /// Load file content from disk into a pane's BlockDocument.
    private func loadFileContentForPane(entry: FileEntry, paneId: UUID) {
        guard !entry.isDatabase, !entry.isDatabaseRow else { return }
        let signpostState = Log.signpost.beginInterval("loadFileContent")
        defer { Log.signpost.endInterval("loadFileContent", signpostState) }
        formattingPanel?.hidePanel()
        editorUI.focusModeSuppress = true
        do {
            let diskContent = try fileSystem.loadFile(at: entry.path)
            let restoredDraft = editorDraftStore.restorePageDraftIfNewer(path: entry.path)
            let content = restoredDraft ?? diskContent

            let doc = BlockDocument(markdown: content)
            doc.filePath = entry.path
            wireUpDocumentCallbacks(doc)

            // Inject pageLink blocks for child pages
            if let children = entry.children, !children.isEmpty {
                let existingLinks = Set(doc.blocks.filter { $0.type == .pageLink }.map { $0.pageLinkName })
                for child in children where child.name.hasSuffix(".md") && !child.isDatabase {
                    let pageName = String(child.name.dropLast(3))
                    if !existingLinks.contains(pageName) {
                        doc.blocks.append(Block(type: .pageLink, pageLinkName: pageName))
                    }
                }
            }

            blockDocuments[paneId] = doc

            // Sync icon and display name from parsed document
            workspaceManager.updatePaneOpenFile(paneId: paneId) { file in
                file.content = content
                file.isDirty = restoredDraft != nil
                file.icon = doc.icon
                if let rawTitle = doc.titleBlock?.text, !rawTitle.isEmpty {
                    file.displayName = AttributedStringConverter.plainText(from: rawTitle)
                }
            }
        } catch {
            Log.editor.error("Failed to load file: \(error.localizedDescription)")
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 500_000_000)
            editorUI.focusModeSuppress = false
        }
    }

    private func openSettingsTab() {
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
        if !switchedToExisting {
            loadFileContent(for: entry)
        }
    }

    private func openDatabaseRowPage(
        dbPath: String,
        rowId: String,
        inNewTab: Bool = false,
        preferExistingTab: Bool = true
    ) {
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
        SentrySDK.addBreadcrumb(Breadcrumb(level: .info, category: "navigation.back"))
        if let activeTab = appState.activeTab, activeTab.isDirty {
            performSave(tabId: activeTab.id)
        }
        if let entry = appState.goBackInActiveTab() {
            loadFileContent(for: entry)
        }
    }

    private func navigateForwardInActiveTab() {
        SentrySDK.addBreadcrumb(Breadcrumb(level: .info, category: "navigation.forward"))
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
        let kind: TabKind = isDatabase ? .database : .page
        let entry = FileEntry(
            id: targetPath,
            name: item.name,
            path: targetPath,
            isDirectory: isDatabase,
            kind: kind,
            icon: item.icon
        )
        navigateToEntry(entry, preferExistingTab: false)
    }

    private func isOpenableBreadcrumbPath(_ path: String) -> Bool {
        if fileSystem.isDatabaseFolder(at: path) { return true }
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir) else { return false }
        return !isDir.boolValue
    }


    private func initializeWorkspace() {
        // Restore the most recently used workspace, falling back to the default
        let restoredPath = fileSystem.recentWorkspaces.first(where: {
            FileManager.default.fileExists(atPath: $0)
        })
        let workspacePath = restoredPath ?? fileSystem.defaultWorkspacePath()
        if !FileManager.default.fileExists(atPath: workspacePath) {
            try? FileManager.default.createDirectory(atPath: workspacePath, withIntermediateDirectories: true)
        }
        fileSystem.setWorkspace(workspacePath)
        scheduleTrashPurgeIfNeeded(for: workspacePath)
        appState.workspacePath = workspacePath

        // Register workspace as a qmd collection in the background (no-op if qmd not installed)
        QmdService.registerCollectionInBackground(workspace: workspacePath)

        // Create onboarding file for empty workspaces before building the file tree
        if let onboardingPath = OnboardingService.ensureOnboarding(workspacePath: workspacePath) {
            refreshFileTree()
            let entry = FileEntry(
                id: onboardingPath,
                name: (onboardingPath as NSString).lastPathComponent,
                path: onboardingPath,
                isDirectory: false
            )
            appState.openFile(entry)
            loadFileContent(for: entry)
        } else {
            refreshFileTree()
        }

        // Always ensure at least one tab is open
        if appState.openTabs.isEmpty {
            appState.newEmptyTab()
        }

        // Initialize workspace manager (restore saved layout or migrate from tabs)
        workspaceManager.restoreOrCreateDefault()

        startWorkspaceWatcher(path: workspacePath)

        // Load MCP server configs
        let fs = self.fileSystem
        Task.detached {
            let servers = fs.parseMCPServers()
            await MainActor.run {
                self.appState.mcpServers = servers
            }
        }
    }

    private func startWorkspaceWatcher(path: String) {
        workspaceWatcher?.stop()
        let fileSystem = self.fileSystem
        let watcher = WorkspaceWatcher { [weak appState] in
            guard let appState = appState,
                  let workspace = appState.workspacePath else { return }
            Task.detached {
                let tree = fileSystem.buildFileTree(at: workspace)
                let skills = fileSystem.scanSkills()
                await MainActor.run {
                    appState.fileTree = tree
                    appState.agentSkills = skills
                    self.refreshSidebarReferences(using: tree)
                    self.refreshFavorites(using: tree)
                }
            }
        }
        watcher.watch(path: path)
        workspaceWatcher = watcher
    }

    private func refreshFileTree() {
        guard let path = appState.workspacePath else { return }
        let fileSystem = self.fileSystem
        Task.detached {
            let tree = fileSystem.buildFileTree(at: path)
            let skills = fileSystem.scanSkills()
            await MainActor.run {
                self.appState.fileTree = tree
                self.appState.agentSkills = skills
                self.refreshSidebarReferences(using: tree)
                self.refreshFavorites(using: tree)
            }
        }
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
        performSave(tabId: tab.id)

        // 3. Move the file to be a sub-page of the current page
        performMovePage(from: sourcePath, toDirectory: currentCompanion)
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
        guard !entry.isDatabase, !entry.isDatabaseRow else { return }
        let signpostState = Log.signpost.beginInterval("loadFileContent")
        defer { Log.signpost.endInterval("loadFileContent", signpostState) }
        formattingPanel?.hidePanel()
        editorUI.focusModeSuppress = true
        do {
            let diskContent = try fileSystem.loadFile(at: entry.path)
            let restoredDraft = editorDraftStore.restorePageDraftIfNewer(path: entry.path)
            let content = restoredDraft ?? diskContent
            if let index = appState.openTabs.firstIndex(where: { $0.path == entry.path }) {
                appState.openTabs[index].content = content
                appState.openTabs[index].isDirty = restoredDraft != nil
                let doc = BlockDocument(markdown: content)
                doc.filePath = entry.path
                wireUpDocumentCallbacks(doc)

                // Inject pageLink blocks for child pages (from file tree, no extra disk I/O)
                if let children = entry.children, !children.isEmpty {
                    let existingLinks = Set(doc.blocks
                        .filter { $0.type == .pageLink }
                        .map { $0.pageLinkName })
                    for child in children where child.name.hasSuffix(".md") && !child.isDatabase {
                        let pageName = String(child.name.dropLast(3))
                        if !existingLinks.contains(pageName) {
                            doc.blocks.append(Block(type: .pageLink, pageLinkName: pageName))
                        }
                    }
                }

                blockDocuments[appState.openTabs[index].id] = doc
                // Sync icon from parsed document
                appState.openTabs[index].icon = doc.icon
                if let rawTitle = doc.titleBlock?.text, !rawTitle.isEmpty {
                    appState.openTabs[index].displayName = AttributedStringConverter.plainText(from: rawTitle)
                }
            }
        } catch {
            Log.editor.error("Failed to load file: \(error.localizedDescription)")
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 500_000_000)
            editorUI.focusModeSuppress = false
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
        guard appState.activeTabIndex < appState.openTabs.count else { return }
        let tab = appState.openTabs[appState.activeTabIndex]
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
        guard let workspace = appState.workspacePath else { return }
        do {
            let path = try fileSystem.openOrCreateDailyNote(in: workspace)
            let name = (path as NSString).lastPathComponent
            let entry = FileEntry(id: path, name: name, path: path, isDirectory: false)
            appState.currentView = .editor
            appState.showSettings = false
            navigateToEntry(entry, preferExistingTab: true)
            refreshFileTree()
        } catch {
            Log.fileSystem.error("Failed to open daily note: \(error.localizedDescription)")
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

    private func findOrCreateMeetingsDatabase(in workspace: String) -> String? {
        // Look for an existing "Meetings" database at the workspace root
        if let contents = try? FileManager.default.contentsOfDirectory(atPath: workspace) {
            for name in contents where !name.hasPrefix(".") {
                let fullPath = (workspace as NSString).appendingPathComponent(name)
                guard fileSystem.isDatabaseFolder(at: fullPath) else { continue }
                let schemaPath = (fullPath as NSString).appendingPathComponent("_schema.json")
                guard let data = try? Data(contentsOf: URL(fileURLWithPath: schemaPath)),
                      let schema = try? JSONDecoder().decode(DatabaseSchema.self, from: data),
                      schema.name.lowercased().contains("meeting") else { continue }
                return fullPath
            }
        }

        return try? fileSystem.createDatabase(in: workspace, name: "Meetings")
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
            fileSystem.retargetDatabaseEmbedsInWorkspace(
                from: oldPath,
                to: newPath,
                workspace: workspace,
                excluding: updatedOpenDocPaths
            )
        }

        if peekTarget?.dbPath == oldPath {
            peekTarget?.dbPath = newPath
        }
        if modalTarget?.dbPath == oldPath {
            modalTarget?.dbPath = newPath
        }
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
        Task { @MainActor in
            fileSystem.purgeOldTrash(in: workspace)
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

    private func scheduleSave() {
        guard let tab = appState.activeTab, !tab.path.isEmpty else { return }
        let tabId = tab.id
        persistPageDraft(for: tabId, path: tab.path)

        saveTask?.cancel()
        saveTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard !Task.isCancelled else { return }
            saveDocument(tabId: tabId)
        }
    }

    private func persistPageDraft(for tabId: UUID, path: String) {
        guard let document = blockDocuments[tabId] else { return }
        editorDraftStore.savePageDraft(content: document.markdown, path: path)
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
        let openPaths = Set(appState.openTabs.map(\.path))
        let oldLink = "[[\(oldName)]]"
        let newLink = "[[\(newName)]]"
        fileSystem.updateWikiLinksOnDisk(in: workspace, oldLink: oldLink, newLink: newLink, excludingPaths: openPaths)
    }

    private func triggerFocusMode() {
        editorUI.triggerFocusMode()
    }

    private func markActiveEditorTabDirty() {
        guard appState.activeTabIndex >= 0, appState.activeTabIndex < appState.openTabs.count else { return }
        if !appState.openTabs[appState.activeTabIndex].isDirty {
            appState.openTabs[appState.activeTabIndex].isDirty = true
        }
    }

    private func performSave(tabId: UUID) {
        saveTask?.cancel()
        saveTask = nil
        saveDocument(tabId: tabId)
    }

    private func flushDirtyTabs() {
        saveTask?.cancel()
        saveTask = nil
        let dirtyTabIds = appState.openTabs
            .filter {
                $0.isDirty
                    && !$0.path.isEmpty
                    && !$0.isDatabase
                    && !$0.isDatabaseRow
            }
            .map(\.id)

        for tabId in dirtyTabIds {
            saveDocument(tabId: tabId)
        }
    }

    private func saveDocument(tabId: UUID) {
        guard let index = appState.openTabs.firstIndex(where: { $0.id == tabId }),
              appState.openTabs[index].isDirty else { return }
        let oldPath = appState.openTabs[index].path
        // Don't recreate a file that was deleted/trashed
        guard !oldPath.isEmpty, FileManager.default.fileExists(atPath: oldPath) else {
            appState.openTabs[index].isDirty = false
            return
        }
        var didPersistDocument = false
        var savedPath = oldPath
        if let document = blockDocuments[tabId] {
            let content = document.markdown
            appState.openTabs[index].content = content
            do {
                try fileSystem.saveFile(at: oldPath, content: content)
                didPersistDocument = true
            } catch {
                Log.editor.error("Failed to save file: \(error.localizedDescription)")
            }

            if didPersistDocument, let rawTitle = document.titleBlock?.text, !rawTitle.isEmpty {
                let title = AttributedStringConverter.plainText(from: rawTitle)
                let currentName = (oldPath as NSString).lastPathComponent.replacingOccurrences(of: ".md", with: "")
                if title != currentName {
                    let dir = (oldPath as NSString).deletingLastPathComponent
                    let sanitized = title.replacingOccurrences(of: "[/\\\\?%*:|\"<>]", with: "-", options: .regularExpression)
                    let newPath = (dir as NSString).appendingPathComponent("\(sanitized).md")
                    if !FileManager.default.fileExists(atPath: newPath) {
                        do {
                            try fileSystem.renameFile(from: oldPath, to: newPath)
                            savedPath = newPath
                            appState.openTabs[index].path = newPath
                            appState.updateNavigationPath(for: tabId, from: oldPath, to: newPath)
                            updatePageLinks(oldName: currentName, newName: sanitized, docs: blockDocuments)
                            refreshFileTree()
                        } catch {
                            Log.fileSystem.error("Failed to rename file: \(error.localizedDescription)")
                        }
                    }
                }
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
        appState.openTabs[index].isDirty = false
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
                if appState.activeTabIndex < appState.openTabs.count {
                    appState.openTabs[appState.activeTabIndex].isDirty = true
                }
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
            .background(
                RoundedRectangle(cornerRadius: Radius.xs)
                    .fill(Color.clear)
            )

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
              let rowId = tab.databaseRowId,
              let contents = try? FileManager.default.contentsOfDirectory(atPath: dbPath) else {
            return nil
        }

        let suffix = rowId.hasPrefix("row_") ? String(rowId.dropFirst(4)) : rowId
        for name in contents where name.hasSuffix(".md") && name.contains("(\(suffix))") {
            return (dbPath as NSString).appendingPathComponent(name)
        }
        return nil
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
        guard let tab = appState.activeTab, !tab.path.isEmpty else { return }
        SentrySDK.addBreadcrumb(Breadcrumb(level: .info, category: "editor.save"))
        performSave(tabId: tab.id)
    }

    private func ensureAiInitializedIfNeeded() {
        if aiInitCompleted { return }
        if aiInitTask != nil { return }

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
            navigateToEntry(entry, preferExistingTab: false)
        }
    }

    private func openDatabase(at path: String) {
        guard FileManager.default.fileExists(atPath: path) else { return }

        if let existing = fileSystem.findEntry(path: path, in: appState.fileTree) {
            navigateToEntry(existing, preferExistingTab: false)
            return
        }

        var displayName = (path as NSString).lastPathComponent
        let schemaPath = (path as NSString).appendingPathComponent("_schema.json")
        if let data = try? Data(contentsOf: URL(fileURLWithPath: schemaPath)),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let schemaName = json["name"] as? String,
           !schemaName.isEmpty {
            displayName = schemaName
        }

        let entry = FileEntry(
            id: path,
            name: displayName,
            path: path,
            isDirectory: false,
            kind: .database
        )
        navigateToEntry(entry, preferExistingTab: false)
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
            appState.sidebarOpen = false
        } else if clamped <= 600 && sidebarHiddenByPeek {
            sidebarHiddenByPeek = false
            appState.sidebarOpen = true
        }
    }

    private func closePeekPanel() {
        peekTarget = nil
        if sidebarHiddenByPeek {
            sidebarHiddenByPeek = false
            appState.sidebarOpen = true
        }
    }

    private func closeDatabaseRowModal() {
        modalTarget = nil
    }

    private func syncTitle(from document: BlockDocument) {
        guard appState.activeTabIndex < appState.openTabs.count else { return }
        if let rawTitle = document.titleBlock?.text, !rawTitle.isEmpty {
            let title = AttributedStringConverter.plainText(from: rawTitle)
            // Only write if actually changed — avoid triggering @Observable for no-op
            if appState.openTabs[appState.activeTabIndex].displayName != title {
                appState.openTabs[appState.activeTabIndex].displayName = title
                let path = appState.openTabs[appState.activeTabIndex].path
                updateFileTreeName(path: path, newName: title)
            }
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
        if let existing = fileSystem.findEntry(path: path, in: appState.fileTree) {
            navigateToEntry(existing, preferExistingTab: true)
            return
        }
        let name = (path as NSString).lastPathComponent
        let isDatabase = fileSystem.isDatabaseFolder(at: path)
        let kind: TabKind = isDatabase ? .database : .page
        let entry = FileEntry(id: path, name: name, path: path, isDirectory: false, kind: kind)
        navigateToEntry(entry, preferExistingTab: true)
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
