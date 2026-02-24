import SwiftUI

struct ContentView: View {
    @StateObject private var appState = AppState()
    @StateObject private var fileSystem = FileSystemService()
    @State private var showSettings = false
    @State private var blockDocuments: [UUID: BlockDocument] = [:]
    @State private var saveTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            HSplitView {
                // Sidebar
                if appState.sidebarOpen {
                    SidebarView(
                        appState: appState,
                        fileSystem: fileSystem,
                        onSelectFile: { entry in
                            appState.openFile(entry)
                            loadFileContent(for: entry)
                        },
                        onToggleSidebar: { appState.sidebarOpen.toggle() }
                    )
                }

                // Main content
                VStack(spacing: 0) {
                    // Tab bar
                    if !appState.openTabs.isEmpty {
                        TabBarView(appState: appState)
                    }

                    // Breadcrumbs
                    if let tab = appState.activeTab, !tab.isEmptyTab {
                        BreadcrumbView(
                            items: breadcrumbs(for: tab),
                            onNavigate: { _ in }
                        )
                    }

                    // Content area
                    if showSettings {
                        SettingsView(appState: appState)
                    } else if let tab = appState.activeTab {
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
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            // Command palette overlay
            if appState.commandPaletteOpen {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .onTapGesture { appState.commandPaletteOpen = false }

                VStack {
                    CommandPaletteView(
                        appState: appState,
                        isPresented: $appState.commandPaletteOpen,
                        onSelectFile: { entry in
                            appState.openFile(entry)
                            loadFileContent(for: entry)
                        }
                    )
                    .padding(.top, 80)
                    Spacer()
                }
            }
        }
        .frame(minWidth: 800, minHeight: 500)
        .onAppear { initializeWorkspace() }
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
            appState.sidebarOpen.toggle()
        }
        .onReceive(NotificationCenter.default.publisher(for: .quickOpen)) { _ in
            appState.commandPaletteOpen.toggle()
        }
        .onReceive(NotificationCenter.default.publisher(for: .openSettings)) { _ in
            showSettings.toggle()
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

                    // Title — rendered outside the block editor (no drag handle or block menu)
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

    // MARK: - Actions

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
            // Focus the title block
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
        // Capture reference types and a snapshot of blockDocuments (values are class refs)
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
        // Find the page in the file tree by name (case-insensitive, strip .md)
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
