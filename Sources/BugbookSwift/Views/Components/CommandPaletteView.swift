import SwiftUI
import AppKit

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
            .foregroundColor(.secondary)
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 2)
    }
}

// MARK: - CommandPaletteView

struct CommandPaletteView: View {
    @ObservedObject var appState: AppState
    @State private var searchText = ""
    @State private var selectedIndex = 0
    @State private var contentResults: [ContentMatch] = []
    @State private var contentSearchTask: Task<Void, Never>?
    @FocusState private var isSearchFieldFocused: Bool
    @Binding var isPresented: Bool
    var onSelectFile: (FileEntry) -> Void
    var onSelectFileNewTab: ((FileEntry) -> Void)?
    var onCreateFile: ((String) -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            // Search field
            HStack {
                Image(systemName: searchIcon)
                    .foregroundColor(.secondary)
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

                        ForEach(sections, id: \.title) { section in
                            SectionHeader(title: section.title)
                            ForEach(Array(section.items.enumerated()), id: \.element.id) { _, item in
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
        .background(Color.fallbackBgPrimary)
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.3), radius: 20, y: 10)
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
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                isSearchFieldFocused = true
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
        return "Search pages..."
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

        // Content results (only in search mode with query >= 2)
        if appState.commandPaletteMode == .search && query.count >= 2 {
            items.append(contentsOf: contentResults.prefix(10).map { .contentMatch($0) })
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
        HStack(spacing: 8) {
            switch item {
            case .file(let entry):
                fileIcon(for: entry)
                Text(entry.name.replacingOccurrences(of: ".md", with: ""))
                    .font(.system(size: 15))
                Spacer()
                Text(relativePath(for: entry))
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)

            case .contentMatch(let match):
                Image(systemName: "text.magnifyingglass")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
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
                    .foregroundColor(.secondary)
                    .frame(width: 16)
                Text(cmd.name)
                    .font(.system(size: 15))
                Spacer()
                if let shortcut = cmd.shortcut {
                    Text(shortcut)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.secondary.opacity(0.12))
                        .cornerRadius(3)
                }

            case .createPage(let name):
                Image(systemName: "plus.circle")
                    .font(.system(size: 13))
                    .foregroundColor(.accentColor)
                Text("Create new page: ")
                    .font(.system(size: 15))
                    .foregroundColor(.secondary)
                + Text(name)
                    .font(.system(size: 15, weight: .medium))
                Spacer()

            case .askAI(let query):
                Image(systemName: "sparkles")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                Text("Ask AI: ")
                    .font(.system(size: 15))
                    .foregroundColor(.secondary)
                + Text(query)
                    .font(.system(size: 15, weight: .medium))
                Spacer()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(index == selectedIndex ? Color.accentColor.opacity(0.15) : Color.clear)
        .cornerRadius(4)
        .contentShape(Rectangle())
        .onTapGesture {
            selectedIndex = index
            selectCurrent()
        }
    }

    // MARK: - Content Match Highlighting

    private func highlightedLine(_ match: ContentMatch) -> Text {
        let line = match.lineText
        let query = effectiveQuery(from: searchText).lowercased()

        guard let range = line.lowercased().range(of: query) else {
            return Text(line).foregroundColor(.secondary)
        }

        let before = String(line[line.startIndex..<range.lowerBound])
        let matched = String(line[range])
        let after = String(line[range.upperBound..<line.endIndex])

        return Text(before).foregroundColor(.secondary)
            + Text(matched).foregroundColor(.accentColor).bold()
            + Text(after).foregroundColor(.secondary)
    }

    // MARK: - Commands

    private var commandItems: [PaletteItem] {
        let query = effectiveQuery(from: searchText)
        let commands = availableCommands
        if query.isEmpty { return commands.map { .command($0) } }
        return commands
            .filter { $0.name.localizedCaseInsensitiveContains(query) }
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
        let allFiles = flattenFileTree(appState.fileTree)
        let query = effectiveQuery(from: searchText)
        if query.isEmpty { return allFiles }
        return allFiles.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    private func flattenFileTree(_ entries: [FileEntry]) -> [FileEntry] {
        var result: [FileEntry] = []
        for entry in entries {
            if !entry.isDirectory || entry.isDatabase {
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

    private func searchFileContents(query: String) async -> [ContentMatch] {
        guard appState.workspacePath != nil else { return [] }
        let allFiles = flattenFileTree(appState.fileTree)
            .filter { !$0.isDatabase && $0.path.hasSuffix(".md") }
            .prefix(50)

        var matches: [ContentMatch] = []
        let lowerQuery = query.lowercased()

        for file in allFiles {
            guard !Task.isCancelled else { break }
            guard let content = try? String(contentsOfFile: file.path, encoding: .utf8) else { continue }

            let lines = content.components(separatedBy: .newlines)
            for (lineIndex, line) in lines.enumerated() {
                if line.lowercased().range(of: lowerQuery) != nil {
                    let trimmedLine = line.trimmingCharacters(in: .whitespaces)
                    guard trimmedLine.count > 2 else { continue }
                    if trimmedLine.lowercased().range(of: lowerQuery) != nil {
                        matches.append(ContentMatch(
                            filePath: file.path,
                            fileName: file.name,
                            lineNumber: lineIndex + 1,
                            lineText: String(trimmedLine.prefix(120))
                        ))
                    }
                    break // Only first match per file
                }
            }

            if matches.count >= 10 { break }
        }

        return matches
    }

    // MARK: - Selection

    private func globalIndex(of item: PaletteItem, in items: [PaletteItem]) -> Int {
        items.firstIndex(where: { $0.id == item.id }) ?? 0
    }

    private func selectCurrent() {
        let items = allItems
        guard selectedIndex >= 0, selectedIndex < items.count else { return }
        let item = items[selectedIndex]

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
                isDirectory: false,
                isDatabase: false
            )
            if appState.commandPaletteMode == .newTab {
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
                userInfo: ["query": query]
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
                    .foregroundColor(.secondary)
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
        Image(systemName: entry.isDatabase ? "tablecells" : "doc.text")
            .font(.system(size: 13))
            .foregroundColor(.secondary)
    }
}
