import SwiftUI
import AppKit

struct ContentView: View {
    @StateObject private var appState = AppState()
    @StateObject private var fileSystem = FileSystemService()
    @StateObject private var aiService = AiService()
    @State private var blockDocuments: [UUID: BlockDocument] = [:]
    @State private var saveTask: Task<Void, Never>?
    @State private var sidebarPeekVisible = false

    var body: some View {
        ZStack(alignment: .leading) {
            HStack(spacing: 0) {
                sidebarSection
                mainContentWithAiPanel
            }

            sidebarPeekOverlay
            commandPaletteOverlay
        }
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
        .onReceive(NotificationCenter.default.publisher(for: .newDatabase)) { _ in
            createNewDatabase()
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
                onSelectFile: { entry in
                    handleSidebarFileSelect(entry)
                },
                onToggleSidebar: { appState.sidebarOpen.toggle() }
            )
        } else {
            VStack {
                Button(action: { appState.sidebarOpen = true }) {
                    Image(systemName: "sidebar.left")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.borderless)
                .padding(.top, 12)
                .help("Open Sidebar")
                Spacer()
            }
            .frame(width: 32)
            .background(Color.fallbackSidebarBg.opacity(0.5))
            .onHover { hovering in
                if hovering { sidebarPeekVisible = true }
            }
        }
    }

    @ViewBuilder
    private var sidebarPeekOverlay: some View {
        if !appState.sidebarOpen && sidebarPeekVisible {
            HStack(spacing: 0) {
                SidebarView(
                    appState: appState,
                    fileSystem: fileSystem,
                    onSelectFile: { entry in
                        handleSidebarFileSelect(entry)
                        sidebarPeekVisible = false
                    },
                    onToggleSidebar: {
                        appState.sidebarOpen = true
                        sidebarPeekVisible = false
                    }
                )
                .shadow(color: .black.opacity(0.15), radius: 8, x: 4, y: 0)
                .transition(.move(edge: .leading))

                Color.clear
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                    .onTapGesture { sidebarPeekVisible = false }
            }
            .onHover { hovering in
                if !hovering { sidebarPeekVisible = false }
            }
            .animation(.easeInOut(duration: 0.2), value: sidebarPeekVisible)
        }
    }

    @ViewBuilder
    private var commandPaletteOverlay: some View {
        if appState.commandPaletteOpen {
            Color.black.opacity(0.3)
                .onTapGesture { appState.commandPaletteOpen = false }

            VStack {
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
                .padding(.top, 80)
                Spacer()
            }
        }
    }

    // MARK: - Main Content

    @ViewBuilder
    private var mainContentWithAiPanel: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                if appState.currentView == .chat {
                    NotesChatView(appState: appState, aiService: aiService)
                } else {
                    editorModeContent
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if appState.aiSidePanelOpen {
                Divider()
                AiSidePanelView(appState: appState, aiService: aiService)
                    .transition(.move(edge: .trailing))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var editorModeContent: some View {
        if !appState.openTabs.isEmpty {
            TabBarView(appState: appState)
        }

        if let tab = appState.activeTab, !tab.isEmptyTab, tab.path != "__settings__" {
            BreadcrumbView(
                items: breadcrumbs(for: tab),
                onNavigate: { _ in }
            )
        }

        activeTabContent
    }

    @ViewBuilder
    private var activeTabContent: some View {
        if let tab = appState.activeTab {
            if tab.path == "__settings__" {
                SettingsView(appState: appState)
            } else if tab.isEmptyTab {
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
                            set: { document.icon = $0; scheduleSave() }
                        ),
                        coverUrl: Binding(
                            get: { document.coverUrl },
                            set: { document.coverUrl = $0; scheduleSave() }
                        ),
                        fullWidth: document.fullWidth
                    )

                    if let titleBlock = document.titleBlock {
                        TextBlockView(document: document, block: titleBlock)
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
                            scheduleSave()
                        }
                    )
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
        doc.availablePages = appState.fileTree
        doc.onNavigateToPage = { pageName in
            navigateToPage(named: pageName)
        }
        doc.onOpenDatabaseTab = { [weak appState] dbPath in
            guard let appState else { return }
            let name = (dbPath as NSString).lastPathComponent
            let entry = FileEntry(id: dbPath, name: name, path: dbPath, isDirectory: true, isDatabase: true)
            appState.openFile(entry)
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
                withAnimation(.easeInOut(duration: 0.2)) {
                    appState.aiSidePanelOpen.toggle()
                }
            }
        }
        NotificationCenter.default.addObserver(
            forName: .askAI,
            object: nil,
            queue: .main
        ) { [appState] notification in
            let prompt = notification.userInfo?["prompt"] as? String
            Task { @MainActor in
                appState.openAiPanel(prompt: prompt)
            }
        }
    }

    // MARK: - Actions

    private func handleSidebarFileSelect(_ entry: FileEntry) {
        let cmdHeld = NSEvent.modifierFlags.contains(.command)
        if cmdHeld {
            appState.openFileInNewTab(entry)
            loadFileContent(for: entry)
        } else {
            if let activeTab = appState.activeTab, activeTab.isDirty {
                performSave(tabId: activeTab.id)
            }
            let alreadyOpen = appState.openFileReplacingCurrentTab(entry)
            if !alreadyOpen {
                loadFileContent(for: entry)
            }
        }
    }

    private func openSettingsTab() {
        if let index = appState.openTabs.firstIndex(where: { $0.path == "__settings__" }) {
            appState.activeTabIndex = index
            return
        }
        let tab = OpenFile(id: UUID(), path: "__settings__", content: "", isDirty: false, isEmptyTab: false, isDatabase: false, displayName: "Settings", openerPagePath: nil)
        appState.openTabs.append(tab)
        appState.activeTabIndex = appState.openTabs.count - 1
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
        do {
            let content = try fileSystem.loadFile(at: entry.path)
            if let index = appState.openTabs.firstIndex(where: { $0.path == entry.path }) {
                appState.openTabs[index].content = content
                appState.openTabs[index].isDirty = false
                let doc = BlockDocument(markdown: content)
                wireUpDocumentCallbacks(doc)
                blockDocuments[appState.openTabs[index].id] = doc
            }
        } catch {
            print("Failed to load file: \(error)")
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
            appState.openFileInNewTab(entry)
            loadFileContent(for: entry)
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
    }

    private func createNewDatabase() {
        guard let workspace = appState.workspacePath else { return }
        do {
            let path = try fileSystem.createDatabase(in: workspace, name: "Untitled Database")
            let entry = FileEntry(id: path, name: "Untitled Database", path: path, isDirectory: true, isDatabase: true)
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
                try? fileSystem.saveFile(at: appState.openTabs[index].path, content: content)
            }
            appState.openTabs[index].isDirty = false
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
            appState.openFile(entry)
            loadFileContent(for: entry)
        }
    }

    private func breadcrumbs(for tab: OpenFile) -> [BreadcrumbItem] {
        guard let workspace = appState.workspacePath else { return [] }
        return fileSystem.getBreadcrumbs(for: tab.path, relativeTo: workspace)
    }
}

// Safe array subscript
extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
