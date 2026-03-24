import SwiftUI
import AppKit
import BugbookCore

// MARK: - Result Types

/// A single item in the command palette results list.
private enum PaletteItem: Identifiable {
    case file(FileEntry)
    case contentMatch(ContentMatch)
    case command(PaletteCommand)
    case createPage(String)
    case askAI(String)

    var id: String {
        switch self {
        case .file(let entry): return "file_\(entry.id)"
        case .contentMatch(let match): return "content_\(match.filePath)_\(match.lineNumber)"
        case .command(let cmd): return "cmd_\(cmd.id)"
        case .createPage(let name): return "create_\(name)"
        case .askAI(let query): return "ask_\(query)"
        }
    }
}

private struct ContentMatch {
    let filePath: String
    let fileName: String
    let lineNumber: Int
    let lineText: String
}

private struct IndexedContentLine: Sendable {
    let filePath: String
    let fileName: String
    let lineNumber: Int
    let lineText: String
    let lowercasedLine: String
}

private struct PaletteCommand {
    let id: String
    let name: String
    let icon: String
    let shortcut: String?
    let action: () -> Void
}

// MARK: - Section Header

private struct SectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 2)
    }
}

// MARK: - CommandPaletteView

struct CommandPaletteView: View {
    var appState: AppState
    @State private var searchText = ""
    @State private var selectedIndex = 0
    @State private var contentResults: [ContentMatch] = []
    @State private var contentSearchTask: Task<Void, Never>?
    @State private var contentIndex: [IndexedContentLine] = []
    @State private var contentIndexWorkspace: String?
    @State private var contentIndexTask: Task<[IndexedContentLine], Never>?
    @State private var cachedFlatEntries: [FileEntry] = []
    @State private var qmdBinaryPath: String?   // nil = pending, "" = not found, else path
    @FocusState private var isSearchFieldFocused: Bool
    @Binding var isPresented: Bool
    var onSelectFile: (FileEntry) -> Void
    var onSelectFileNewTab: ((FileEntry) -> Void)?
    var onCreateFile: ((String) -> Void)?
    var onSelectContentMatch: ((FileEntry, String) -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            // Search field
            HStack {
                Image(systemName: searchIcon)
                    .foregroundStyle(.secondary)
                TextField(placeholderText, text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 17))
                    .focused($isSearchFieldFocused)
                    .onSubmit { selectCurrent() }
            }
            .padding(12)

            Divider()

            // Results
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 1) {
                        let items = allItems
                        let sections = groupedSections(items)

                        if items.isEmpty && !searchText.isEmpty {
                            Text("No results")
                                .foregroundStyle(.secondary)
                                .font(.callout)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 20)
                        }

                        ForEach(sections, id: \.title) { section in
                            SectionHeader(title: section.title)
                            ForEach(section.items.enumerated(), id: \.element.id) { _, item in
                                let idx = globalIndex(of: item, in: items)
                                paletteRow(item: item, index: idx)
                                    .id(item.id)
                            }
                        }
                    }
                    .padding(8)
                }
                .frame(maxHeight: 350)
                .onChange(of: selectedIndex) { _, newIndex in
                    let items = allItems
                    if newIndex >= 0, newIndex < items.count {
                        proxy.scrollTo(items[newIndex].id, anchor: .center)
                    }
                }
            }
        }
        .frame(width: 600)
        .popoverSurface(cornerRadius: Radius.xl)
        .onKeyPress(.upArrow) {
            selectedIndex = max(0, selectedIndex - 1)
            return .handled
        }
        .onKeyPress(.downArrow) {
            selectedIndex = min(allItems.count - 1, selectedIndex + 1)
            return .handled
        }
        .onKeyPress(.escape) {
            isPresented = false
            return .handled
        }
        .onChange(of: searchText) { _, newValue in
            selectedIndex = 0
            scheduleContentSearch(query: effectiveQuery(from: newValue))
        }
        .onAppear {
            // Resign any AppKit first responder (e.g. block NSTextView) so TextField gets focus
            NSApp.keyWindow?.makeFirstResponder(nil)
            if appState.commandPaletteMode == .commands {
                searchText = ">"
            }
            cachedFlatEntries = flattenFileTree(appState.fileTree)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                isSearchFieldFocused = true
            }
            // Invalidate cached content index so it rebuilds from disk on next search
            contentIndex = []
            contentIndexWorkspace = nil
            contentIndexTask?.cancel()
            contentIndexTask = nil
            Task { @MainActor in
                await warmContentIndexIfNeeded()
            }
            // Detect qmd once; in-memory index remains the fallback
            Task {
                let path = await Task.detached(priority: .utility) {
                    QmdService.findBinaryPath() ?? ""
                }.value
                qmdBinaryPath = path
            }
        }
        .onDisappear {
            contentSearchTask?.cancel()
            contentSearchTask = nil
            contentIndexTask?.cancel()
            contentIndexTask = nil
        }
        .onChange(of: appState.fileTree) { _, newTree in
            cachedFlatEntries = flattenFileTree(newTree)
        }
        .onChange(of: appState.workspacePath) { _, _ in
            contentIndex = []
            contentIndexWorkspace = nil
            contentIndexTask?.cancel()
            contentIndexTask = nil
            cachedFlatEntries = flattenFileTree(appState.fileTree)
            scheduleContentSearch(query: effectiveQuery(from: searchText))
            Task { @MainActor in
                await warmContentIndexIfNeeded()
            }
        }
    }

    // MARK: - Search Icon & Placeholder

    private var searchIcon: String {
        if isCommandMode { return "terminal" }
        if appState.commandPaletteMode == .newTab { return "plus.square" }
        return "magnifyingglass"
    }

    private var placeholderText: String {
        if isCommandMode { return "Type a command..." }
        if appState.commandPaletteMode == .newTab { return "Open or create a page..." }
        return "Search pages and content..."
    }

    // MARK: - Mode Detection

    private var isCommandMode: Bool {
        searchText.hasPrefix(">")
    }

    private func effectiveQuery(from text: String) -> String {
        if text.hasPrefix(">") {
            return String(text.dropFirst()).trimmingCharacters(in: .whitespaces)
        }
        return text
    }

    // MARK: - All Flat Items

    private var allItems: [PaletteItem] {
        if isCommandMode {
            return commandItems
        }

        var items: [PaletteItem] = []
        let query = effectiveQuery(from: searchText)

        // "Create new page" option at top in newTab mode
        if appState.commandPaletteMode == .newTab && !query.isEmpty {
            items.append(.createPage(query))
        }

        // File results
        let maxFiles = appState.commandPaletteMode == .newTab ? 15 : 8
        let files = filteredEntries.prefix(maxFiles)
        items.append(contentsOf: files.map { .file($0) })

        // Content results (search and newTab modes with query >= 2)
        if (appState.commandPaletteMode == .search || appState.commandPaletteMode == .newTab) && query.count >= 2 {
            items.append(contentsOf: contentResults.prefix(20).map { .contentMatch($0) })
        }

        // "Ask AI" option at bottom when query is non-empty and workspace is open
        if !query.isEmpty && appState.workspacePath != nil {
            items.append(.askAI(query))
        }

        return items
    }

    // MARK: - Sections

    private struct PaletteSection {
        let title: String
        let items: [PaletteItem]
    }

    private func groupedSections(_ items: [PaletteItem]) -> [PaletteSection] {
        if isCommandMode {
            return items.isEmpty ? [] : [PaletteSection(title: "Commands", items: items)]
        }

        var sections: [PaletteSection] = []

        let createItems = items.filter { if case .createPage = $0 { return true }; return false }
        if !createItems.isEmpty {
            sections.append(PaletteSection(title: "Create", items: createItems))
        }

        let fileItems = items.filter { if case .file = $0 { return true }; return false }
        if !fileItems.isEmpty {
            sections.append(PaletteSection(title: "Files", items: fileItems))
        }

        let contentItems = items.filter { if case .contentMatch = $0 { return true }; return false }
        if !contentItems.isEmpty {
            sections.append(PaletteSection(title: "In Content", items: contentItems))
        }

        let aiItems = items.filter { if case .askAI = $0 { return true }; return false }
        if !aiItems.isEmpty {
            sections.append(PaletteSection(title: "AI", items: aiItems))
        }

        return sections
    }

    // MARK: - Row Rendering

    @ViewBuilder
    private func paletteRow(item: PaletteItem, index: Int) -> some View {
        Button {
            selectedIndex = index
            executeItem(item)
        } label: {
            HStack(spacing: 8) {
                switch item {
                case .file(let entry):
                    fileIcon(for: entry)
                    Text(entry.name.replacingOccurrences(of: ".md", with: ""))
                        .font(.system(size: 15))
                    Spacer()
                    Text(relativePath(for: entry))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)

                case .contentMatch(let match):
                    Image(systemName: "text.magnifyingglass")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(match.fileName.replacingOccurrences(of: ".md", with: ""))
                            .font(.system(size: 14, weight: .medium))
                        highlightedLine(match)
                            .font(.system(size: 13))
                            .lineLimit(1)
                    }
                    Spacer()

                case .command(let cmd):
                    Image(systemName: cmd.icon)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .frame(width: 16)
                    Text(cmd.name)
                        .font(.system(size: 15))
                    Spacer()
                    if let shortcut = cmd.shortcut {
                        Text(shortcut)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.secondary.opacity(0.12))
                            .clipShape(.rect(cornerRadius: 3))
                    }

                case .createPage(let name):
                    Image(systemName: "plus.circle")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.accentColor)
                    Text("Create new page: ")
                        .font(.system(size: 15))
                        .foregroundStyle(.secondary)
                    + Text(name)
                        .font(.system(size: 15, weight: .medium))
                    Spacer()

                case .askAI(let query):
                    Image(systemName: "sparkles")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                    Text("Ask AI: ")
                        .font(.system(size: 15))
                        .foregroundStyle(.secondary)
                    + Text(query)
                        .font(.system(size: 15, weight: .medium))
                    Spacer()
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(index == selectedIndex ? Color.accentColor.opacity(0.15) : Color.clear)
            .clipShape(.rect(cornerRadius: 4))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Content Match Highlighting

    private func highlightedLine(_ match: ContentMatch) -> Text {
        let line = match.lineText
        let query = effectiveQuery(from: searchText).lowercased()

        guard let range = line.lowercased().range(of: query) else {
            return Text(line).foregroundStyle(.secondary)
        }

        let before = String(line[line.startIndex..<range.lowerBound])
        let matched = String(line[range])
        let after = String(line[range.upperBound..<line.endIndex])

        return Text(before).foregroundStyle(.secondary)
            + Text(matched).foregroundStyle(Color.accentColor).bold()
            + Text(after).foregroundStyle(.secondary)
    }

    // MARK: - Commands

    private var commandItems: [PaletteItem] {
        let query = effectiveQuery(from: searchText)
        let commands = availableCommands
        if query.isEmpty { return commands.map { .command($0) } }
        return commands
            .filter { $0.name.localizedStandardContains(query) }
            .map { .command($0) }
    }

    private var availableCommands: [PaletteCommand] {
        [
            PaletteCommand(id: "toggle_sidebar", name: "Toggle Sidebar", icon: "sidebar.left", shortcut: "Cmd+.") {
                NotificationCenter.default.post(name: .toggleSidebar, object: nil)
            },
            PaletteCommand(id: "new_note", name: "New Note", icon: "doc.badge.plus", shortcut: "Cmd+N") {
                NotificationCenter.default.post(name: .newNote, object: nil)
            },
            PaletteCommand(id: "new_database", name: "New Database", icon: "tablecells.badge.ellipsis", shortcut: nil) {
                NotificationCenter.default.post(name: .newDatabase, object: nil)
            },
            PaletteCommand(id: "new_canvas", name: "New Canvas", icon: "rectangle.on.rectangle.angled", shortcut: nil) {
                NotificationCenter.default.post(name: .newCanvas, object: nil)
            },
            PaletteCommand(id: "open_settings", name: "Open Settings", icon: "gear", shortcut: "Cmd+,") {
                NotificationCenter.default.post(name: .openSettings, object: nil)
            },
            PaletteCommand(id: "toggle_theme", name: "Toggle Theme", icon: "circle.lefthalf.filled", shortcut: nil) {
                NotificationCenter.default.post(name: .toggleTheme, object: nil)
            },
        ]
    }

    // MARK: - File Filtering

    private var filteredEntries: [FileEntry] {
        let allFiles = cachedFlatEntries
        let query = effectiveQuery(from: searchText)
        if query.isEmpty { return allFiles }
        return allFiles.filter { $0.name.localizedStandardContains(query) }
    }

    private func flattenFileTree(_ entries: [FileEntry]) -> [FileEntry] {
        var result: [FileEntry] = []
        for entry in entries {
            if (!entry.isDirectory || entry.isDatabase || entry.isCanvas) {
                result.append(entry)
            }
            if let children = entry.children {
                result.append(contentsOf: flattenFileTree(children))
            }
        }
        return result
    }

    // MARK: - Content Search

    private func scheduleContentSearch(query: String) {
        contentSearchTask?.cancel()

        guard query.count >= 2, !isCommandMode else {
            contentResults = []
            return
        }

        contentSearchTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 200_000_000)
            guard !Task.isCancelled else { return }

            let results = await searchFileContents(query: query)
            guard !Task.isCancelled else { return }
            contentResults = results
        }
    }

    @MainActor
    private func warmContentIndexIfNeeded() async {
        guard let workspace = appState.workspacePath else { return }
        _ = await ensureContentIndex(for: workspace)
    }

    @MainActor
    private func ensureContentIndex(for workspace: String) async -> [IndexedContentLine] {
        if contentIndexWorkspace == workspace, contentIndexTask == nil {
            return contentIndex
        }

        if contentIndexWorkspace == workspace, let pendingTask = contentIndexTask {
            let indexed = await pendingTask.value
            if appState.workspacePath == workspace {
                contentIndex = indexed
                contentIndexTask = nil
            }
            return indexed
        }

        contentIndexTask?.cancel()
        let buildTask = Task<[IndexedContentLine], Never> {
            await buildContentIndex(workspace: workspace)
        }
        contentIndexTask = buildTask

        let indexed = await buildTask.value
        guard !Task.isCancelled else { return [] }

        if appState.workspacePath == workspace {
            contentIndex = indexed
            contentIndexWorkspace = workspace
            contentIndexTask = nil
        }

        return indexed
    }

    private func buildContentIndex(workspace: String) async -> [IndexedContentLine] {
        await Task.detached(priority: .utility) {
            let fm = FileManager.default
            guard let enumerator = fm.enumerator(atPath: workspace) else { return [IndexedContentLine]() }

            var excludedDirs: Set<String> = []
            if let scanner = fm.enumerator(atPath: workspace) {
                while let rel = scanner.nextObject() as? String {
                    guard !Task.isCancelled else { return [] }
                    let filename = (rel as NSString).lastPathComponent
                    if filename == "_schema.json" || filename == "_canvas.json" {
                        let dir = (rel as NSString).deletingLastPathComponent
                        excludedDirs.insert(dir)
                    }
                }
            }

            var indexed: [IndexedContentLine] = []
            let maxLineLength = 160

            while let relativePath = enumerator.nextObject() as? String {
                guard !Task.isCancelled else { break }
                if WorkspacePathRules.shouldIgnoreRelativePath(relativePath) { continue }
                let components = relativePath.components(separatedBy: "/")
                if components.contains(where: { $0.hasPrefix(".") }) { continue }

                let filename = (relativePath as NSString).lastPathComponent
                guard filename.hasSuffix(".md") else { continue }

                let parentDir = (relativePath as NSString).deletingLastPathComponent
                if excludedDirs.contains(parentDir) { continue }

                let fullPath = (workspace as NSString).appendingPathComponent(relativePath)
                guard let content = try? String(contentsOfFile: fullPath, encoding: .utf8) else { continue }

                let lines = content.components(separatedBy: .newlines)
                for (lineIndex, line) in lines.enumerated() {
                    guard !Task.isCancelled else { break }
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    guard trimmed.count > 2 else { continue }

                    indexed.append(
                        IndexedContentLine(
                            filePath: fullPath,
                            fileName: filename,
                            lineNumber: lineIndex + 1,
                            lineText: String(trimmed.prefix(maxLineLength)),
                            lowercasedLine: trimmed.lowercased()
                        )
                    )
                }
            }

            // Index database row titles from _index.json files
            let indexManager = IndexManager()
            for dir in excludedDirs {
                guard !Task.isCancelled else { break }
                let dbPath = (workspace as NSString).appendingPathComponent(dir)
                guard let json = indexManager.loadIndex(at: dbPath),
                      let rows = json["rows"] as? [String: [String: Any]] else { continue }

                let dbName = (dir as NSString).lastPathComponent
                for (_, rowData) in rows {
                    guard let filename = rowData["filename"] as? String else { continue }
                    let title: String
                    if let parenRange = filename.range(of: " (", options: .backwards) {
                        title = String(filename[..<parenRange.lowerBound])
                    } else {
                        title = filename
                    }
                    guard !title.isEmpty else { continue }
                    indexed.append(IndexedContentLine(
                        filePath: dbPath,
                        fileName: dbName,
                        lineNumber: 0,
                        lineText: title,
                        lowercasedLine: title.lowercased()
                    ))
                }
            }

            return indexed
        }.value
    }

    @MainActor
    private func searchFileContents(query: String) async -> [ContentMatch] {
        guard let workspace = appState.workspacePath else { return [] }

        // Use qmd when available — faster and ranking-aware
        if let binary = qmdBinaryPath, !binary.isEmpty {
            if let results = await searchWithQmd(query: query, workspace: workspace, binary: binary) {
                return results
            }
        }

        // Fallback: in-memory substring search
        let indexed = await ensureContentIndex(for: workspace)
        let lowerQuery = query.lowercased()
        guard !indexed.isEmpty else { return [] }

        return await Task.detached(priority: .userInitiated) {
            var matches: [ContentMatch] = []
            var matchesPerFile: [String: Int] = [:]
            let maxPerFile = 3
            let maxTotal = 20

            for line in indexed {
                guard !Task.isCancelled else { break }
                guard line.lowercasedLine.contains(lowerQuery) else { continue }

                let current = matchesPerFile[line.filePath, default: 0]
                guard current < maxPerFile else { continue }

                matches.append(ContentMatch(
                    filePath: line.filePath,
                    fileName: line.fileName,
                    lineNumber: line.lineNumber,
                    lineText: line.lineText
                ))
                matchesPerFile[line.filePath] = current + 1
                if matches.count >= maxTotal { break }
            }

            return matches
        }.value
    }

    private func searchWithQmd(query: String, workspace: String, binary: String) async -> [ContentMatch]? {
        let collection = URL(fileURLWithPath: workspace).lastPathComponent
        let mode = appState.settings.qmdSearchMode.rawValue

        return await Task.detached(priority: .userInitiated) {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: binary)
            task.arguments = [mode == "bm25" ? "search" : mode == "semantic" ? "vsearch" : "query",
                               query, "--json", "-n", "20", "-c", collection]
            let pipe = Pipe()
            task.standardOutput = pipe
            task.standardError = FileHandle.nullDevice
            guard (try? task.run()) != nil else { return nil }
            task.waitUntilExit()
            guard task.terminationStatus == 0 else { return nil }

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            // qmd CLI returns a JSON array; MCP returns {"results":[...]}
            let parsed = try? JSONSerialization.jsonObject(with: data)
            let raw: [[String: Any]]
            if let arr = parsed as? [[String: Any]] {
                raw = arr
            } else if let obj = parsed as? [String: Any],
                      let arr = obj["results"] as? [[String: Any]] {
                raw = arr
            } else {
                return nil
            }

            return raw.compactMap { r -> ContentMatch? in
                guard let relPath = (r["file"] as? String) ?? (r["path"] as? String) else { return nil }
                // Strip qmd://CollectionName/ virtual path prefix
                var cleanPath = relPath
                if cleanPath.hasPrefix("qmd://") {
                    cleanPath = String(cleanPath.dropFirst(6))
                    if let slash = cleanPath.firstIndex(of: "/") {
                        cleanPath = String(cleanPath[cleanPath.index(after: slash)...])
                    }
                }
                let fullPath = (workspace as NSString).appendingPathComponent(cleanPath)
                let fileName = (cleanPath as NSString).lastPathComponent
                let lineNumber = r["line"] as? Int ?? 0

                // Extract first meaningful line from snippet, strip "42: " prefix if present
                var lineText = (r["snippet"] as? String ?? "")
                    .components(separatedBy: "\n")
                    .first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) ?? ""
                if let colon = lineText.firstIndex(of: ":") {
                    let prefix = String(lineText[lineText.startIndex..<colon])
                    if prefix.trimmingCharacters(in: .whitespaces).allSatisfy(\.isNumber) {
                        lineText = String(lineText[lineText.index(after: colon)...])
                            .trimmingCharacters(in: .whitespaces)
                    }
                }

                return ContentMatch(
                    filePath: fullPath,
                    fileName: fileName,
                    lineNumber: lineNumber,
                    lineText: lineText.isEmpty ? relPath : lineText
                )
            }
        }.value
    }

    // MARK: - Selection

    private func globalIndex(of item: PaletteItem, in items: [PaletteItem]) -> Int {
        items.firstIndex(where: { $0.id == item.id }) ?? 0
    }

    private func selectCurrent() {
        let items = allItems
        guard selectedIndex >= 0, selectedIndex < items.count else { return }
        executeItem(items[selectedIndex])
    }

    private func executeItem(_ item: PaletteItem) {
        switch item {
        case .file(let entry):
            if appState.commandPaletteMode == .newTab {
                onSelectFileNewTab?(entry)
            } else {
                onSelectFile(entry)
            }
        case .contentMatch(let match):
            let entry = FileEntry(
                id: match.filePath,
                name: match.fileName,
                path: match.filePath,
                isDirectory: false
            )
            let query = effectiveQuery(from: searchText)
            if let handler = onSelectContentMatch {
                handler(entry, query)
            } else if appState.commandPaletteMode == .newTab {
                onSelectFileNewTab?(entry)
            } else {
                onSelectFile(entry)
            }
        case .command(let cmd):
            cmd.action()
        case .createPage(let name):
            onCreateFile?(name)
        case .askAI(let query):
            NotificationCenter.default.post(
                name: .askAI,
                object: nil,
                userInfo: ["prompt": query]
            )
        }

        isPresented = false
    }

    // MARK: - Helpers

    private func relativePath(for entry: FileEntry) -> String {
        guard let workspace = appState.workspacePath else { return "" }
        return entry.path.replacingOccurrences(of: workspace + "/", with: "")
    }

    @ViewBuilder
    private func fileIcon(for entry: FileEntry) -> some View {
        if let icon = entry.icon, !icon.isEmpty {
            if icon.hasPrefix("custom:") {
                let path = String(icon.dropFirst(7))
                if let nsImage = NSImage(contentsOfFile: path) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 16, height: 16)
                } else {
                    defaultFileIcon(for: entry)
                }
            } else if icon.hasPrefix("sf:") {
                Image(systemName: String(icon.dropFirst(3)))
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            } else if icon.unicodeScalars.first?.properties.isEmoji == true {
                Text(icon).font(.system(size: 14))
            } else {
                defaultFileIcon(for: entry)
            }
        } else {
            defaultFileIcon(for: entry)
        }
    }

    @ViewBuilder
    private func defaultFileIcon(for entry: FileEntry) -> some View {
        if entry.isCanvas {
            Image(systemName: "rectangle.on.rectangle.angled")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        } else {
            Image(systemName: entry.isDatabase ? "tablecells" : "doc.text")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
    }
}
