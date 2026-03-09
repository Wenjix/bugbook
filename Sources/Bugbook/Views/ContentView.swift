import SwiftUI
import AppKit
import os
import Sentry

struct ContentView: View {
    @StateObject private var appState = AppState()
    @StateObject private var fileSystem = FileSystemService()
    @StateObject private var aiService = AiService()
    @StateObject private var backlinkService = BacklinkService()
    @State private var blockDocuments: [UUID: BlockDocument] = [:]
    @State private var canvasDocuments: [UUID: CanvasDocument] = [:]
    @State private var saveTask: Task<Void, Never>?
    @State private var canvasSaveTask: Task<Void, Never>?
    @State private var focusModeActive = false
    @State private var focusModeTask: Task<Void, Never>?
    @State private var focusModeSuppress = false
    @State private var themeToast: ThemeMode?
    @State private var themeToastTask: Task<Void, Never>?
    @State private var formattingPanel: FormattingToolbarPanel?
    @State private var aiInitTask: Task<Void, Never>?
    @State private var aiInitCompleted = false
    @State private var workspaceWatcher: WorkspaceWatcher?

    // Database row peek / modal
    private struct RowTarget {
        let dbPath: String
        let rowId: String
    }
    @State private var peekTarget: RowTarget?
    @State private var dbInitialRowId: String?
    @State private var peekWidth: CGFloat = 640
    @State private var peekDragStartWidth: CGFloat?
    @State private var sidebarHiddenByPeek: Bool = false
    @State private var modalTarget: RowTarget?
    @State private var modalAutoFocusTitle: Bool = false

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

            sidebarToggleOverlay
            commandPaletteOverlay
            themeToastOverlay
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
            }
            .onChange(of: appState.settings.theme) { _, newTheme in
                applyTheme(newTheme)
            }
            .onChange(of: appState.settings.qmdSearchMode) { _, mode in
                QmdService.prewarmDaemonIfNeeded(mode: mode)
            }
            .onChange(of: appState.aiSidePanelOpen) { _, isOpen in
                if isOpen {
                    ensureAiInitializedIfNeeded()
                }
            }
            .onChange(of: appState.activeTab?.id) { _, _ in
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
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.willResignActiveNotification)) { _ in
                flushDirtyTabs()
            }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                flushDirtyTabs()
            }
            .onDisappear {
                flushDirtyTabs()
                aiInitTask?.cancel()
                aiInitTask = nil
                workspaceWatcher?.stop()
            }
            .onReceive(NotificationCenter.default.publisher(for: .fileDeleted)) { notification in
                if let path = notification.object as? String {
                    appState.closeTabsForPath(path)
                    removeDatabaseEmbedsFromOpenDocs(dbPath: path)
                }
            }
    }

    private func applyCommandNotifications<V: View>(to view: V) -> some View {
        view
            .onReceive(NotificationCenter.default.publisher(for: .newNote)) { _ in
                createNewFile()
            }
            .onReceive(NotificationCenter.default.publisher(for: .newTab)) { _ in
                appState.newEmptyTab()
            }
            .onReceive(NotificationCenter.default.publisher(for: .closeTab)) { _ in
                appState.closeTab(at: appState.activeTabIndex)
            }
            .onReceive(NotificationCenter.default.publisher(for: .saveFile)) { _ in
                forceSave()
            }
            .onReceive(NotificationCenter.default.publisher(for: .toggleSidebar)) { _ in
                if !appState.showSettings {
                    appState.sidebarOpen.toggle()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .quickOpen)) { _ in
                appState.commandPaletteMode = .search
                appState.commandPaletteOpen.toggle()
            }
            .onReceive(NotificationCenter.default.publisher(for: .quickOpenNewTab)) { _ in
                appState.commandPaletteMode = .newTab
                appState.commandPaletteOpen = true
            }
            .onReceive(NotificationCenter.default.publisher(for: .openSettings)) { _ in
                openSettingsTab()
            }
            .onReceive(NotificationCenter.default.publisher(for: .toggleTheme)) { _ in
                toggleTheme()
            }
            .onReceive(NotificationCenter.default.publisher(for: .openDailyNote)) { _ in
                openDailyNote()
            }
            .onReceive(NotificationCenter.default.publisher(for: .openGraphView)) { _ in
                appState.openGraphView()
            }
            .onReceive(NotificationCenter.default.publisher(for: .newDatabase)) { _ in
                createNewDatabase()
            }
            .onReceive(NotificationCenter.default.publisher(for: .newCanvas)) { _ in
                createNewCanvas()
            }
            .onReceive(NotificationCenter.default.publisher(for: .navigateBack)) { _ in
                navigateBackInActiveTab()
            }
            .onReceive(NotificationCenter.default.publisher(for: .navigateForward)) { _ in
                navigateForwardInActiveTab()
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
                onToggleSidebar: { appState.sidebarOpen.toggle() }
            )
            .layoutPriority(1)
        }
    }

    @ViewBuilder
    private var sidebarToggleOverlay: some View {
        if !appState.sidebarOpen {
            VStack {
                HStack {
                    sidebarChromeButton(icon: "sidebar.left", help: "Open Sidebar") {
                        appState.sidebarOpen = true
                    }
                    Spacer()
                }
                .padding(.leading, 84)
                .padding(.top, 10)
                Spacer()
            }
            .opacity(focusModeActive ? 0.0 : 1.0)
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
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(isEnabled ? .secondary : .secondary.opacity(0.45))
                .frame(width: 24, height: 24)
        }
        .buttonStyle(.borderless)
        .help(help)
        .disabled(!isEnabled)
    }

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
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.fallbackEditorBg)

            if appState.aiSidePanelOpen && appState.currentView == .editor {
                Divider()
                AiSidePanelView(appState: appState, aiService: aiService)
                    .transition(.move(edge: .trailing))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: appState.sidebarOpen ? 14 : 0,
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

    @ViewBuilder
    private var editorModeContent: some View {
        TabBarView(
            appState: appState,
            canGoBack: appState.canGoBackInActiveTab,
            canGoForward: appState.canGoForwardInActiveTab,
            onBack: { navigateBackInActiveTab() },
            onForward: { navigateForwardInActiveTab() }
        )
            .opacity(focusModeActive ? 0.0 : 1.0)

        VStack(spacing: 0) {
            if let tab = appState.activeTab, !tab.isEmptyTab {
                HStack {
                    BreadcrumbView(
                        items: breadcrumbs(for: tab),
                        onNavigate: { item in navigateToBreadcrumb(item) }
                    )

                    Spacer()

                    let backlinks = currentPageBacklinks(for: tab)
                    if !backlinks.isEmpty {
                        BacklinksMenuButton(backlinks: backlinks) { path in
                            navigateToFilePath(path)
                        }
                        .padding(.trailing, 4)
                    }

                    // Page options menu (notes only)
                    if !tab.isEmptyTab && !tab.isCanvas && !tab.isDatabase && !tab.isDatabaseRow,
                       let doc = blockDocuments[tab.id] {
                        Menu {
                            Button {
                                doc.fullWidth.toggle()
                                if appState.activeTabIndex < appState.openTabs.count {
                                    appState.openTabs[appState.activeTabIndex].isDirty = true
                                }
                                scheduleSave()
                            } label: {
                                HStack {
                                    Label("Full width", systemImage: "arrow.left.and.right")
                                    if doc.fullWidth { Spacer(); Image(systemName: "checkmark") }
                                }
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 13))
                                .foregroundStyle(.primary)
                                .frame(width: 28, height: 28)
                        }
                        .menuStyle(.borderlessButton)
                        .menuIndicator(.hidden)
                        .fixedSize()
                        .padding(.trailing, 4)
                    }
                }
                .padding(.leading, appState.sidebarOpen ? 0 : 78)
                .opacity(focusModeActive ? 0.0 : 1.0)
            }

            activeTabContent
        }
        .overlay(alignment: .trailing) {
            if let peek = peekTarget {
                HStack(spacing: 0) {
                    // Resize drag edge
                        Rectangle()
                            .fill(Color.clear)
                            .frame(width: 8)
                            .contentShape(Rectangle())
                            .onHover { hovering in
                                EditorCursorState.setOverride(hovering ? .resizeLeftRight : nil)
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
                        autoFocusTitle: modalAutoFocusTitle,
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
            peekTarget = RowTarget(dbPath: dbPath, rowId: rowId)
        }
        .onReceive(NotificationCenter.default.publisher(for: .databaseRowModalRequested)) { notification in
            guard let dbPath = notification.databasePath,
                  let rowId = notification.databaseRowId else { return }
            closePeekPanel()
            modalTarget = RowTarget(dbPath: dbPath, rowId: rowId)
            modalAutoFocusTitle = notification.databaseAutoFocusTitle
        }
    }

    @ViewBuilder
    private var activeTabContent: some View {
        if let tab = appState.activeTab {
            if tab.isEmptyTab {
                WelcomeView(
                    onNewNote: { createNewFile() },
                    onOpenFolder: { Task { await openWorkspace() } }
                )
                .onAppear { openDefaultPageIfConfigured() }
            } else if tab.isCanvas {
                canvasEditor(for: tab)
            } else if tab.isDatabaseRow, let dbPath = tab.databasePath, let rowId = tab.databaseRowId {
                DatabaseRowFullPageView(
                    dbPath: dbPath,
                    rowId: rowId,
                    onTitleChange: { title in
                        updateDatabaseRowTabTitle(tabId: tab.id, title: title)
                    }
                )
            } else if tab.isDatabase {
                DatabaseFullPageView(dbPath: tab.path, initialRowId: dbInitialRowId)
                    .onAppear { dbInitialRowId = nil }
            } else {
                editorView(for: tab)
            }
        }
    }

    // MARK: - Editor

    @ViewBuilder
    private func editorView(for tab: OpenFile) -> some View {
        if let document = blockDocuments[tab.id] {
            HStack(spacing: 0) {
                ScrollView {
                    HStack(spacing: 0) {
                        Spacer(minLength: 0)
                        VStack(alignment: .leading, spacing: 0) {
                        PageHeaderView(
                            icon: Binding(
                                get: { document.icon },
                                set: {
                                    document.icon = $0
                                    markActiveEditorTabDirty()
                                    if appState.activeTabIndex < appState.openTabs.count {
                                        appState.openTabs[appState.activeTabIndex].icon = $0
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
                            fullWidth: document.fullWidth
                        )

                        if let titleBlock = document.titleBlock {
                            TextBlockView(document: document, block: titleBlock, onTyping: { triggerFocusMode() })
                                .padding(.leading, 76)
                                .padding(.trailing, 52)
                                .padding(.top, 8)
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
                            onTyping: { triggerFocusMode() }
                        )

                    }
                    .frame(maxWidth: document.fullWidth ? .infinity : 860)
                    Spacer(minLength: 0)
                }
                }
                .background(Color.fallbackEditorBg)
                .editorIBeamCursor()
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
            }
        } else {
            Color.fallbackEditorBg
        }
    }

    private func wireUpDocumentCallbacks(_ doc: BlockDocument) {
        doc.onCreateDatabase = { [weak appState] name in
            guard let workspace = appState?.workspacePath else { return nil }
            let path = try? fileSystem.createDatabase(in: workspace, name: name)
            if path != nil { refreshFileTree() }
            return path
        }
        doc.onCreateSubPage = { [weak appState] name in
            guard let tab = appState?.activeTab else { return nil }
            let path = try? fileSystem.createSubPage(under: tab.path, name: name)
            if path != nil { refreshFileTree() }
            return path
        }
        doc.availablePages = appState.fileTree
        doc.onNavigateToPage = { pageName in
            navigateToPage(named: pageName)
        }
        doc.onOpenDatabaseTab = { dbPath in
            let name = (dbPath as NSString).lastPathComponent
            let entry = FileEntry(id: dbPath, name: name, path: dbPath, isDirectory: false, kind: .database)
            navigateToEntry(entry, preferExistingTab: false)
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
            onLink: { activeBlockTextView()?.formatLinkAction?() }
        )
        panel.show(above: rect)
    }

    private func activeBlockTextView() -> BlockNSTextView? {
        NSApp.keyWindow?.firstResponder as? BlockNSTextView
    }

    private func hideFormattingPanel() {
        formattingPanel?.hidePanel()
    }

    // MARK: - AI Notifications


    // MARK: - Actions

    private func handleSidebarFileSelect(_ entry: FileEntry) {
        // Switch back to editor when selecting a file from sidebar
        appState.currentView = .editor
        appState.showSettings = false
        let cmdHeld = NSEvent.modifierFlags.contains(.command)
        if cmdHeld {
            navigateToEntry(entry, inNewTab: true)
        } else {
            navigateToEntry(entry)
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
        let canvasPath = (defaultPage as NSString).appendingPathComponent("_canvas.json")
        let isCanvas = FileManager.default.fileExists(atPath: canvasPath)
        let kind: TabKind = isDatabase ? .database : isCanvas ? .canvas : .page
        let entry = FileEntry(
            id: defaultPage,
            name: name,
            path: defaultPage,
            isDirectory: isDatabase || isCanvas,
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

        if let existing = findEntryByPath(targetPath, in: appState.fileTree) {
            navigateToEntry(existing, preferExistingTab: false)
            return
        }

        let isDatabase = isDatabaseFolderPath(targetPath)
        let isCanvas = isCanvasFolderPath(targetPath)
        let kind: TabKind = isDatabase ? .database : isCanvas ? .canvas : .page
        let entry = FileEntry(
            id: targetPath,
            name: item.name,
            path: targetPath,
            isDirectory: isDatabase || isCanvas,
            kind: kind,
            icon: item.icon
        )
        navigateToEntry(entry, preferExistingTab: false)
    }

    private func isOpenableBreadcrumbPath(_ path: String) -> Bool {
        if isDatabaseFolderPath(path) { return true }
        if isCanvasFolderPath(path) { return true }
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir) else { return false }
        return !isDir.boolValue
    }

    private func isDatabaseFolderPath(_ path: String) -> Bool {
        let schemaPath = (path as NSString).appendingPathComponent("_schema.json")
        return FileManager.default.fileExists(atPath: schemaPath)
    }

    private func isCanvasFolderPath(_ path: String) -> Bool {
        let canvasPath = (path as NSString).appendingPathComponent("_canvas.json")
        return FileManager.default.fileExists(atPath: canvasPath)
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
        appState.workspacePath = workspacePath

        // Register workspace as a qmd collection in the background (no-op if qmd not installed)
        QmdService.registerCollectionInBackground(workspace: workspacePath)
        // Pre-warm the daemon now if hybrid mode is already selected
        QmdService.prewarmDaemonIfNeeded(mode: appState.settings.qmdSearchMode)

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

        startWorkspaceWatcher(path: workspacePath)
    }

    private func startWorkspaceWatcher(path: String) {
        workspaceWatcher?.stop()
        let fileSystem = self.fileSystem
        let watcher = WorkspaceWatcher { [weak appState] in
            guard let appState = appState,
                  let workspace = appState.workspacePath else { return }
            appState.fileTree = fileSystem.buildFileTree(at: workspace)
        }
        watcher.watch(path: path)
        workspaceWatcher = watcher
    }

    private func refreshFileTree() {
        guard let path = appState.workspacePath else { return }
        appState.fileTree = fileSystem.buildFileTree(at: path)
    }

    private func loadFileContent(for entry: FileEntry) {
        guard !entry.isDatabase, !entry.isCanvas, !entry.isDatabaseRow else { return }
        let signpostState = Log.signpost.beginInterval("loadFileContent")
        defer { Log.signpost.endInterval("loadFileContent", signpostState) }
        formattingPanel?.hidePanel()
        focusModeSuppress = true
        do {
            let content = try fileSystem.loadFile(at: entry.path)
            if let index = appState.openTabs.firstIndex(where: { $0.path == entry.path }) {
                appState.openTabs[index].content = content
                appState.openTabs[index].isDirty = false
                let doc = BlockDocument(markdown: content)
                wireUpDocumentCallbacks(doc)
                blockDocuments[appState.openTabs[index].id] = doc
                // Sync icon from parsed document
                appState.openTabs[index].icon = doc.icon
            }
        } catch {
            Log.editor.error("Failed to load file: \(error.localizedDescription)")
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 500_000_000)
            focusModeSuppress = false
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
        guard let action = action,
              appState.activeTabIndex < appState.openTabs.count else { return }
        let tab = appState.openTabs[appState.activeTabIndex]
        guard let doc = blockDocuments[tab.id],
              let blockId = doc.focusedBlockId else { return }

        if action == "createPage" {
            if let createPage = doc.onCreateSubPage,
               let pagePath = createPage("Untitled") {
                let pageName = (pagePath as NSString).lastPathComponent.replacingOccurrences(of: ".md", with: "")
                doc.updateBlockProperty(id: blockId) { block in
                    block.type = .pageLink
                    block.pageLinkName = pageName
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
                .foregroundColor(.primary)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(.ultraThinMaterial)
                .cornerRadius(10)
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

    // MARK: - Canvas

    @ViewBuilder
    private func canvasEditor(for tab: OpenFile) -> some View {
        if let doc = canvasDocuments[tab.id] {
            CanvasView(
                document: doc,
                onNavigateToFile: { path in navigateToFilePath(path) },
                availablePages: appState.fileTree
            )
            .onChange(of: doc.isDirty) { _, dirty in
                if dirty { scheduleCanvasSave(tabId: tab.id) }
            }
        } else {
            Color.fallbackEditorBg
                .onAppear { loadCanvasContent(for: tab) }
        }
    }

    private func loadCanvasContent(for tab: OpenFile) {
        guard tab.isCanvas else { return }
        let doc = CanvasDocument()
        doc.load(from: tab.path)
        canvasDocuments[tab.id] = doc
    }

    private func scheduleCanvasSave(tabId: UUID) {
        let docs = self.canvasDocuments
        canvasSaveTask?.cancel()
        canvasSaveTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard !Task.isCancelled else { return }
            docs[tabId]?.save()
        }
    }

    private func createNewCanvas() {
        guard let workspace = appState.workspacePath else { return }
        do {
            let path = try fileSystem.createCanvas(in: workspace, name: "Untitled Canvas")
            let displayName = (path as NSString).lastPathComponent
            let entry = FileEntry(id: path, name: displayName, path: path, isDirectory: false, kind: .canvas)
            appState.openFile(entry)
            if let tab = appState.activeTab {
                loadCanvasContent(for: tab)
            }
            refreshFileTree()
        } catch {
            Log.canvas.error("Failed to create canvas: \(error.localizedDescription)")
        }
    }

    private func createNewDatabase() {
        guard let workspace = appState.workspacePath else { return }
        do {
            let path = try fileSystem.createDatabase(in: workspace, name: "Untitled Database")
            let displayName = (path as NSString).lastPathComponent
            let entry = FileEntry(id: path, name: displayName, path: path, isDirectory: false, kind: .database)
            appState.openFile(entry)
            refreshFileTree()
        } catch {
            Log.database.error("Failed to create database: \(error.localizedDescription)")
        }
    }

    private func openWorkspace() async {
        if let path = await fileSystem.openFolder() {
            appState.workspacePath = path
            refreshFileTree()
            startWorkspaceWatcher(path: path)
        }
    }

    private func scheduleSave() {
        guard let tab = appState.activeTab, !tab.path.isEmpty else { return }
        let tabId = tab.id

        saveTask?.cancel()
        saveTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard !Task.isCancelled else { return }
            saveDocument(tabId: tabId)
        }
    }

    private func updatePageLinks(oldName: String, newName: String, docs: [UUID: BlockDocument]) {
        for (_, doc) in docs {
            for i in doc.blocks.indices {
                if doc.blocks[i].type == .pageLink && doc.blocks[i].pageLinkName == oldName {
                    doc.blocks[i].pageLinkName = newName
                }
            }
        }
    }

    private func triggerFocusMode() {
        guard appState.settings.focusModeOnType else { return }
        guard !focusModeSuppress else { return }
        if !focusModeActive {
            withAnimation(.easeInOut(duration: 0.6)) {
                focusModeActive = true
            }
        }
        focusModeTask?.cancel()
        focusModeTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.6)) {
                focusModeActive = false
            }
        }
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
                    && !$0.isCanvas
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
        if let document = blockDocuments[tabId] {
            let content = document.markdown
            appState.openTabs[index].content = content
            let oldPath = appState.openTabs[index].path
            try? fileSystem.saveFile(at: oldPath, content: content)

            if let rawTitle = document.titleBlock?.text, !rawTitle.isEmpty {
                let title = AttributedStringConverter.plainText(from: rawTitle)
                let currentName = (oldPath as NSString).lastPathComponent.replacingOccurrences(of: ".md", with: "")
                if title != currentName {
                    let dir = (oldPath as NSString).deletingLastPathComponent
                    let sanitized = title.replacingOccurrences(of: "[/\\\\?%*:|\"<>]", with: "-", options: .regularExpression)
                    let newPath = (dir as NSString).appendingPathComponent("\(sanitized).md")
                    if !FileManager.default.fileExists(atPath: newPath) {
                        try? fileSystem.renameFile(from: oldPath, to: newPath)
                        appState.openTabs[index].path = newPath
                        appState.updateNavigationPath(for: tabId, from: oldPath, to: newPath)
                        updatePageLinks(oldName: currentName, newName: sanitized, docs: blockDocuments)
                        refreshFileTree()
                    }
                }
            }
        }

        if let workspace = appState.workspacePath {
            let savedPath = appState.openTabs[index].path
            backlinkService.updateFile(at: savedPath, in: workspace)
        }
        appState.openTabs[index].isDirty = false
    }

    /// Removes any databaseEmbed blocks referencing `dbPath` from all currently open BlockDocuments.
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

        if let existing = findEntryByPath(path, in: appState.fileTree) {
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

    private func findEntryByPath(_ path: String, in entries: [FileEntry]) -> FileEntry? {
        for entry in entries {
            if entry.path == path {
                return entry
            }
            if let children = entry.children,
               let found = findEntryByPath(path, in: children) {
                return found
            }
        }
        return nil
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
        modalAutoFocusTitle = false
    }

    private func syncTitle(from document: BlockDocument) {
        guard appState.activeTabIndex < appState.openTabs.count else { return }
        if let rawTitle = document.titleBlock?.text, !rawTitle.isEmpty {
            let title = AttributedStringConverter.plainText(from: rawTitle)
            // Update tab display name
            appState.openTabs[appState.activeTabIndex].displayName = title
            // Update sidebar file tree entry name
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
        if let existing = findEntryByPath(path, in: appState.fileTree) {
            navigateToEntry(existing, preferExistingTab: true)
            return
        }
        let name = (path as NSString).lastPathComponent
        let isDatabase = isDatabaseFolderPath(path)
        let isCanvas = isCanvasFolderPath(path)
        let kind: TabKind = isDatabase ? .database : isCanvas ? .canvas : .page
        let entry = FileEntry(id: path, name: name, path: path, isDirectory: false, kind: kind)
        navigateToEntry(entry, preferExistingTab: true)
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
