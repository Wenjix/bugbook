import SwiftUI
import AppKit

struct ContentView: View {
    @StateObject private var appState = AppState()
    @StateObject private var fileSystem = FileSystemService()
    @StateObject private var aiService = AiService()
    @State private var blockDocuments: [UUID: BlockDocument] = [:]
    @State private var saveTask: Task<Void, Never>?
    @State private var focusModeActive = false
    @State private var focusModeTask: Task<Void, Never>?
    @State private var focusModeSuppress = false
    @State private var themeToast: ThemeMode?
    @State private var themeToastTask: Task<Void, Never>?

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
            .onAppear {
                initializeWorkspace()
                applyTheme(appState.settings.theme)
                setupAiNotifications()
            }
            .task {
                await aiService.detectEngines()
                Task { await aiService.prewarmSession() }
            }
            .onChange(of: appState.settings.theme) { _, newTheme in
                applyTheme(newTheme)
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
            .onReceive(NotificationCenter.default.publisher(for: .openAgentHub)) { _ in
                appState.openAgentHub()
            }
            .onReceive(NotificationCenter.default.publisher(for: .toggleTheme)) { _ in
                toggleTheme()
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

    private func applyDatabaseNotifications<V: View>(to view: V) -> some View {
        view
            .onReceive(NotificationCenter.default.publisher(for: .blockTypeShortcut)) { notification in
                handleBlockTypeShortcut(notification.object as? String)
            }
            .onReceive(NotificationCenter.default.publisher(for: .databaseNameDidChange)) { notification in
                guard let dbPath = notification.userInfo?["dbPath"] as? String,
                      let newName = notification.userInfo?["newName"] as? String else { return }
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
                canGoBack: appState.canGoBackInActiveTab,
                canGoForward: appState.canGoForwardInActiveTab,
                onBack: { navigateBackInActiveTab() },
                onForward: { navigateForwardInActiveTab() },
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
                    sidebarChromeButton(
                        icon: "chevron.left",
                        help: "Back",
                        isEnabled: appState.canGoBackInActiveTab
                    ) {
                        navigateBackInActiveTab()
                    }
                    sidebarChromeButton(
                        icon: "chevron.right",
                        help: "Forward",
                        isEnabled: appState.canGoForwardInActiveTab
                    ) {
                        navigateForwardInActiveTab()
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
                            appState.openFile(entry)
                            loadFileContent(for: entry)
                        },
                        onSelectFileNewTab: { entry in
                            appState.openFileInNewTab(entry)
                            loadFileContent(for: entry)
                        },
                        onCreateFile: { name in
                            createNewFileWithName(name)
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
                } else if appState.currentView == .agentHub {
                    AgentHubView(workspacePath: appState.workspacePath)
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
    }

    @ViewBuilder
    private var editorModeContent: some View {
        if !appState.openTabs.isEmpty {
            TabBarView(appState: appState)
                .opacity(focusModeActive ? 0.0 : 1.0)
        }

        if let tab = appState.activeTab, !tab.isEmptyTab {
            BreadcrumbView(
                items: breadcrumbs(for: tab),
                onNavigate: { item in navigateToBreadcrumb(item) }
            )
            .opacity(focusModeActive ? 0.0 : 1.0)
        }

        activeTabContent
    }

    @ViewBuilder
    private var activeTabContent: some View {
        if let tab = appState.activeTab {
            if tab.isEmptyTab {
                WelcomeView(
                    onNewNote: { createNewFile() },
                    onOpenFolder: { Task { await openWorkspace() } }
                )
            } else if tab.isDatabase {
                DatabaseFullPageView(dbPath: tab.path)
            } else {
                editorView(for: tab)
            }
        } else {
            WelcomeView(
                onNewNote: { createNewFile() },
                onOpenFolder: { Task { await openWorkspace() } }
            )
        }
    }

    // MARK: - Editor

    @ViewBuilder
    private func editorView(for tab: OpenFile) -> some View {
        if let document = blockDocuments[tab.id] {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    PageHeaderView(
                        icon: Binding(
                            get: { document.icon },
                            set: {
                                document.icon = $0
                                if appState.activeTabIndex < appState.openTabs.count {
                                    appState.openTabs[appState.activeTabIndex].icon = $0
                                }
                                scheduleSave()
                            }
                        ),
                        coverUrl: Binding(
                            get: { document.coverUrl },
                            set: { document.coverUrl = $0; scheduleSave() }
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
                            // Sync title to tab, sidebar, and breadcrumbs in real time
                            syncTitle(from: document)
                            scheduleSave()
                        },
                        onTyping: { triggerFocusMode() }
                    )

                    // Click target below blocks — focuses last block
                    Color.clear
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 200)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if let lastBlock = document.blocks.last {
                                document.focusedBlockId = lastBlock.id
                                document.cursorPosition = lastBlock.text.count
                            }
                        }
                }
            }
            .background(Color.fallbackEditorBg)
        } else {
            Color.fallbackEditorBg
                .onAppear {
                    if blockDocuments[tab.id] == nil {
                        let doc = BlockDocument(markdown: tab.content)
                        wireUpDocumentCallbacks(doc)
                        blockDocuments[tab.id] = doc
                    }
                }
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
            let entry = FileEntry(id: dbPath, name: name, path: dbPath, isDirectory: true, isDatabase: true)
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

    // MARK: - AI Notifications

    private func setupAiNotifications() {
        NotificationCenter.default.addObserver(
            forName: .openAIPanel,
            object: nil,
            queue: .main
        ) { [appState] _ in
            Task { @MainActor in
                appState.toggleAiPanel()
            }
        }
        NotificationCenter.default.addObserver(
            forName: .askAI,
            object: nil,
            queue: .main
        ) { [appState] notification in
            let prompt = notification.userInfo?["prompt"] as? String
                ?? notification.userInfo?["query"] as? String
            Task { @MainActor in
                appState.openAiPanel(prompt: prompt)
            }
        }
    }

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

    private func navigateBackInActiveTab() {
        if let activeTab = appState.activeTab, activeTab.isDirty {
            performSave(tabId: activeTab.id)
        }
        if let entry = appState.goBackInActiveTab() {
            loadFileContent(for: entry)
        }
    }

    private func navigateForwardInActiveTab() {
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
        let entry = FileEntry(
            id: targetPath,
            name: item.name,
            path: targetPath,
            isDirectory: isDatabase,
            isDatabase: isDatabase,
            icon: item.icon
        )
        navigateToEntry(entry, preferExistingTab: false)
    }

    private func isOpenableBreadcrumbPath(_ path: String) -> Bool {
        if isDatabaseFolderPath(path) { return true }
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir) else { return false }
        return !isDir.boolValue
    }

    private func isDatabaseFolderPath(_ path: String) -> Bool {
        let schemaPath = (path as NSString).appendingPathComponent("_schema.json")
        return FileManager.default.fileExists(atPath: schemaPath)
    }

    private func initializeWorkspace() {
        let defaultPath = fileSystem.defaultWorkspacePath()
        if !FileManager.default.fileExists(atPath: defaultPath) {
            try? FileManager.default.createDirectory(atPath: defaultPath, withIntermediateDirectories: true)
        }
        fileSystem.setWorkspace(defaultPath)
        appState.workspacePath = defaultPath
        refreshFileTree()
    }

    private func refreshFileTree() {
        guard let path = appState.workspacePath else { return }
        appState.fileTree = fileSystem.buildFileTree(at: path)
    }

    private func loadFileContent(for entry: FileEntry) {
        guard !entry.isDatabase else { return }
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
            print("Failed to load file: \(error)")
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
            let entry = FileEntry(id: path, name: (path as NSString).lastPathComponent, path: path, isDirectory: false, isDatabase: false)
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
            print("Failed to create file: \(error)")
        }
    }

    private func createNewFileWithName(_ name: String) {
        guard let workspace = appState.workspacePath else { return }
        do {
            let path = try fileSystem.createNewFile(in: workspace, name: name)
            let entry = FileEntry(id: path, name: (path as NSString).lastPathComponent, path: path, isDirectory: false, isDatabase: false)
            navigateToEntry(entry, inNewTab: true)
            refreshFileTree()
        } catch {
            print("Failed to create file: \(error)")
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

    private func createNewDatabase() {
        guard let workspace = appState.workspacePath else { return }
        do {
            let path = try fileSystem.createDatabase(in: workspace, name: "Untitled Database")
            let displayName = (path as NSString).lastPathComponent
            let entry = FileEntry(id: path, name: displayName, path: path, isDirectory: true, isDatabase: true)
            appState.openFile(entry)
            refreshFileTree()
        } catch {
            print("Failed to create database: \(error)")
        }
    }

    private func openWorkspace() async {
        if let path = await fileSystem.openFolder() {
            appState.workspacePath = path
            refreshFileTree()
        }
    }

    private func scheduleSave() {
        guard let tab = appState.activeTab, !tab.path.isEmpty else { return }
        let tabId = tab.id
        let appState = self.appState
        let fileSystem = self.fileSystem
        let docs = self.blockDocuments

        saveTask?.cancel()
        saveTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard !Task.isCancelled else { return }
            guard let index = appState.openTabs.firstIndex(where: { $0.id == tabId }),
                  appState.openTabs[index].isDirty else { return }
            if let document = docs[tabId] {
                let content = document.markdown
                appState.openTabs[index].content = content
                let oldPath = appState.openTabs[index].path
                try? fileSystem.saveFile(at: oldPath, content: content)

                // Rename file on disk if title changed
                if let title = document.titleBlock?.text, !title.isEmpty {
                    let currentName = (oldPath as NSString).lastPathComponent.replacingOccurrences(of: ".md", with: "")
                    if title != currentName {
                        let dir = (oldPath as NSString).deletingLastPathComponent
                        let sanitized = title.replacingOccurrences(of: "[/\\\\?%*:|\"<>]", with: "-", options: .regularExpression)
                        let newPath = (dir as NSString).appendingPathComponent("\(sanitized).md")
                        if !FileManager.default.fileExists(atPath: newPath) {
                            try? fileSystem.renameFile(from: oldPath, to: newPath)
                            appState.openTabs[index].path = newPath
                            appState.updateNavigationPath(for: tabId, from: oldPath, to: newPath)
                            // Update any pageLink blocks in other open documents that reference old name
                            updatePageLinks(oldName: currentName, newName: sanitized, docs: docs)
                            refreshFileTree()
                        }
                    }
                }
            }
            appState.openTabs[index].isDirty = false
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

    private func performSave(tabId: UUID) {
        guard let index = appState.openTabs.firstIndex(where: { $0.id == tabId }),
              appState.openTabs[index].isDirty else { return }
        if let document = blockDocuments[tabId] {
            let content = document.markdown
            appState.openTabs[index].content = content
            try? fileSystem.saveFile(at: appState.openTabs[index].path, content: content)
        }
        appState.openTabs[index].isDirty = false
    }

    private func forceSave() {
        guard let tab = appState.activeTab, !tab.path.isEmpty else { return }
        performSave(tabId: tab.id)
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
            isDirectory: true,
            isDatabase: true
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

    private func syncTitle(from document: BlockDocument) {
        guard appState.activeTabIndex < appState.openTabs.count else { return }
        if let title = document.titleBlock?.text, !title.isEmpty {
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

    private func breadcrumbs(for tab: OpenFile) -> [BreadcrumbItem] {
        guard let workspace = appState.workspacePath else { return [] }
        var crumbs = fileSystem.getBreadcrumbs(for: tab.path, relativeTo: workspace)
        // Use live title for the last breadcrumb
        if let displayName = tab.displayName, !displayName.isEmpty, !crumbs.isEmpty {
            crumbs[crumbs.count - 1].name = displayName
        }
        return crumbs
    }
}

// Safe array subscript
extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
