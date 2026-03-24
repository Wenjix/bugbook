import SwiftUI

struct AiSidePanelView: View {
    var appState: AppState
    var aiService: AiService
    var activeDocument: BlockDocument?
    @State private var messages: [ChatMessage] = []
    @State private var inputText: String = ""
    @State private var activeTask: Task<Void, Never>?
    @State private var referencedItems: [AiContextItem] = []
    @State private var showPagePicker = false
    @State private var pagePickerSearch = ""
    @FocusState private var inputFocused: Bool
    @FocusState private var pickerSearchFocused: Bool
    @State private var pickerSelectedIndex: Int = 0
    @State private var hoveredMessageId: UUID?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if messages.isEmpty {
                welcomeState
            } else {
                messageList
            }

            Divider()
            inputArea
        }
        .frame(width: 380)
        .background(Color.fallbackEditorBg)
        .task {
            inputFocused = true
            // Ingest any referenced items passed via appState
            let incoming = appState.aiReferencedItems
            if !incoming.isEmpty {
                let existing = Set(referencedItems.map(\.id))
                referencedItems += incoming.filter { !existing.contains($0.id) }
                appState.aiReferencedItems.removeAll()
            }
            if let prompt = appState.aiInitialPrompt, !prompt.isEmpty {
                inputText = prompt
                appState.aiInitialPrompt = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    sendMessage()
                }
            }
        }
        .onChange(of: appState.aiReferencedItems) { _, newItems in
            guard !newItems.isEmpty else { return }
            let existing = Set(referencedItems.map(\.id))
            referencedItems += newItems.filter { !existing.contains($0.id) }
            appState.aiReferencedItems.removeAll()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Image("BugbookAI")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 22, height: 22)
                .clipShape(RoundedRectangle(cornerRadius: 5))

            Text("New AI Chat")
                .font(.system(size: Typography.body, weight: .semibold))
                .foregroundStyle(Color.fallbackTextPrimary)

            Spacer()

            Button(action: openFullChat) {
                Label("Expand", systemImage: "arrow.up.left.and.arrow.down.right")
                    .labelStyle(.iconOnly)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help("Expand to full chat")

            Button(action: closePanel) {
                Label("Collapse", systemImage: "chevron.right.2")
                    .labelStyle(.iconOnly)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help("Collapse sidebar")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Welcome State

    private var welcomeState: some View {
        ScrollView {
            VStack(spacing: 20) {
                Spacer(minLength: 40)

                // Icon + heading
                VStack(spacing: 8) {
                    Image("BugbookAI")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 40, height: 40)
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                    Text("Bugbook AI")
                        .font(.system(size: Typography.title3, weight: .semibold))
                        .foregroundStyle(Color.fallbackTextPrimary)

                    Text("Ask questions, generate content, or get help with your notes.")
                        .font(.system(size: Typography.bodySmall))
                        .foregroundStyle(Color.fallbackTextSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }

                // Shortcut cards
                VStack(spacing: 8) {
                    shortcutCard(
                        icon: "text.justify.leading",
                        label: "Summarize this page",
                        description: "Get a concise summary of the current page",
                        prompt: "Summarize this page"
                    )
                    shortcutCard(
                        icon: "rectangle.on.rectangle.angled",
                        label: "Generate flashcards",
                        description: "Create study cards from your notes",
                        prompt: "Generate flashcards from this page"
                    )
                    shortcutCard(
                        icon: "arrow.triangle.2.circlepath",
                        label: "Rewrite for clarity",
                        description: "Improve readability and flow",
                        prompt: "Rewrite this page for clarity"
                    )
                    shortcutCard(
                        icon: "link",
                        label: "Find connections",
                        description: "Discover links to other notes",
                        prompt: "Find connections between this page and my other notes"
                    )
                }
                .padding(.horizontal, 16)

                Spacer(minLength: 20)
            }
        }
    }

    private func shortcutCard(icon: String, label: String, description: String, prompt: String) -> some View {
        Button {
            inputText = prompt
            sendMessage()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundStyle(Color.fallbackTextSecondary)
                    .frame(width: 32, height: 32)
                    .background(Color.primary.opacity(Opacity.subtle))
                    .clipShape(RoundedRectangle(cornerRadius: Radius.sm))

                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(.system(size: Typography.body, weight: .medium))
                        .foregroundStyle(Color.fallbackTextPrimary)
                    Text(description)
                        .font(.system(size: Typography.caption2))
                        .foregroundStyle(Color.fallbackTextSecondary)
                }

                Spacer()
            }
            .padding(10)
            .background(Color.primary.opacity(Opacity.subtle))
            .clipShape(RoundedRectangle(cornerRadius: Radius.md))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Message List

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(messages) { message in
                        messageBubble(message)
                            .id(message.id)
                    }

                    if aiService.isRunning {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Thinking...")
                                .font(.system(size: Typography.bodySmall))
                                .foregroundStyle(Color.fallbackTextSecondary)
                            Spacer()
                            Button("Cancel") {
                                cancelGeneration()
                            }
                            .font(.system(size: Typography.caption))
                            .foregroundStyle(Color.fallbackTextSecondary)
                            .buttonStyle(.borderless)
                        }
                        .padding(.horizontal, 16)
                        .id("loading")
                    }
                }
                .padding(.vertical, 12)
            }
            .onChange(of: messages.count) { _, _ in
                if let last = messages.last {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
            .onChange(of: aiService.isRunning) { _, running in
                if running {
                    proxy.scrollTo("loading", anchor: .bottom)
                }
            }
        }
    }

    // MARK: - Context Chips

    private var contextChipsView: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                ForEach(referencedItems) { item in
                    HStack(spacing: 5) {
                        Image(systemName: item.iconName)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)

                        Text(item.displayLabel)
                            .font(.system(size: 12, weight: .medium))
                            .lineLimit(1)

                        Button {
                            referencedItems.removeAll { $0.id == item.id }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color.fallbackBadgeBg)
                    .clipShape(.capsule)
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    // MARK: - Page Reference Picker

    private var pickerVisiblePages: [FileEntry] {
        Array(filteredPages.prefix(50))
    }

    private var pageReferencePickerView: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)

                TextField("Search pages...", text: $pagePickerSearch)
                    .textFieldStyle(.plain)
                    .font(.system(size: Typography.bodySmall))
                    .focused($pickerSearchFocused)
                    .onSubmit {
                        let pages = pickerVisiblePages
                        if !pages.isEmpty, pickerSelectedIndex < pages.count {
                            addPageReference(pages[pickerSelectedIndex])
                        }
                    }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Divider()

            if filteredPages.isEmpty {
                Text("No pages found")
                    .font(.system(size: Typography.caption))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 12)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(pickerVisiblePages.enumerated()), id: \.element.path) { index, entry in
                                PageReferenceRow(
                                    entry: entry,
                                    displayName: displayName(for: entry.name),
                                    index: index,
                                    isSelected: index == pickerSelectedIndex,
                                    onHoverIndex: { pickerSelectedIndex = $0 }
                                ) {
                                    addPageReference(entry)
                                }
                                .id(entry.path)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .onChange(of: pickerSelectedIndex) { _, newIndex in
                        let pages = pickerVisiblePages
                        if newIndex < pages.count {
                            proxy.scrollTo(pages[newIndex].path, anchor: .center)
                        }
                    }
                }
            }
        }
        .frame(width: 280)
        .frame(maxHeight: 300)
        .popoverSurface()
        .onAppear {
            pickerSearchFocused = true
            pickerSelectedIndex = 0
        }
        .onDisappear { pagePickerSearch = "" }
        .onChange(of: pagePickerSearch) { _, _ in
            pickerSelectedIndex = 0
        }
        .onKeyPress(.upArrow) {
            if pickerSelectedIndex > 0 { pickerSelectedIndex -= 1 }
            return .handled
        }
        .onKeyPress(.downArrow) {
            let count = pickerVisiblePages.count
            if pickerSelectedIndex < count - 1 { pickerSelectedIndex += 1 }
            return .handled
        }
    }

    // MARK: - Message Bubble

    @ViewBuilder
    private func messageBubble(_ message: ChatMessage) -> some View {
        VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
            HStack {
                if message.role == .user { Spacer(minLength: 40) }

                if message.role == .applied {
                    appliedBubble(message)
                } else if message.role == .user {
                    // User: dark rounded bubble with white text
                    Text(message.content)
                        .font(.system(size: Typography.body))
                        .foregroundStyle(.white)
                        .textSelection(.enabled)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color(light: Color(hex: "1f1f1f"), dark: Color(hex: "e0e0e0")))
                        .clipShape(.rect(cornerRadius: Radius.xl))
                } else {
                    // Assistant / error: plain text, no bubble
                    Text(message.content)
                        .font(.system(size: Typography.body))
                        .foregroundStyle(message.role == .error ? .red : Color.fallbackTextPrimary)
                        .textSelection(.enabled)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 4)
                        .overlay(alignment: .topTrailing) {
                            if message.role == .assistant && hoveredMessageId == message.id {
                                Button {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(message.content, forType: .string)
                                } label: {
                                    Image(systemName: "doc.on.doc")
                                        .font(.system(size: 11))
                                        .foregroundStyle(Color.fallbackTextSecondary)
                                        .padding(4)
                                        .background(Color.fallbackBgTertiary)
                                        .clipShape(RoundedRectangle(cornerRadius: Radius.xs))
                                }
                                .buttonStyle(.borderless)
                                .offset(x: 4, y: -4)
                            }
                        }
                        .onHover { hovering in
                            hoveredMessageId = hovering ? message.id : nil
                        }
                }

                if message.role != .user { Spacer(minLength: 40) }
            }
        }
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private func appliedBubble(_ message: ChatMessage) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(.green)
                Text("Done — what do you think?")
                    .font(.system(size: Typography.body))
                    .foregroundStyle(Color.fallbackTextPrimary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.green.opacity(Opacity.light))
            .clipShape(.rect(cornerRadius: Radius.lg))

            if activeDocument != nil {
                HStack(spacing: 8) {
                    Button {
                        if message.isReverted {
                            activeDocument?.redo()
                        } else {
                            activeDocument?.undo()
                        }
                        if let idx = messages.firstIndex(where: { $0.id == message.id }) {
                            messages[idx].isReverted.toggle()
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: message.isReverted ? "arrow.uturn.forward" : "arrow.uturn.backward")
                                .font(.system(size: 10))
                            Text(message.isReverted ? "Reapply" : "Revert")
                                .font(.system(size: Typography.caption2, weight: .medium))
                        }
                        .foregroundStyle(Color.fallbackTextSecondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.primary.opacity(Opacity.subtle))
                        .clipShape(RoundedRectangle(cornerRadius: Radius.xs))
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
    }

    // MARK: - Input Area

    private var inputArea: some View {
        VStack(spacing: 0) {
            if !referencedItems.isEmpty {
                contextChipsView
                    .padding(.horizontal, 12)
                    .padding(.top, 10)
                    .padding(.bottom, 4)
            }

            // Context chips (page context)
            if let doc = activeDocument, let path = doc.filePath {
                let pageName = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
                HStack(spacing: 6) {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 10))
                        Text(pageName)
                            .font(.system(size: Typography.caption2))
                            .lineLimit(1)
                    }
                    .foregroundStyle(Color.fallbackTextSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.primary.opacity(Opacity.subtle))
                    .clipShape(RoundedRectangle(cornerRadius: Radius.xs))

                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 4)
            }

            // Text field + buttons
            HStack(alignment: .bottom, spacing: 8) {
                Button {
                    showPagePicker.toggle()
                } label: {
                    Image(systemName: "paperclip")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.fallbackTextSecondary)
                }
                .buttonStyle(.borderless)
                .help("Reference a page")
                .floatingPopover(isPresented: $showPagePicker, arrowEdge: .top, becomesKey: true) {
                    pageReferencePickerView
                }

                TextField("Ask about your notes...", text: $inputText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: Typography.body))
                    .lineLimit(1...20)
                    .frame(minHeight: 24)
                    .fixedSize(horizontal: false, vertical: true)
                    .focused($inputFocused)
                    .onChange(of: inputText) { _, value in
                        if value.hasSuffix("@") {
                            showPagePicker = true
                        }
                    }
                    .onSubmit {
                        sendMessage()
                    }

                Button(action: sendMessage) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(
                            canSend
                                ? Color.fallbackTextPrimary
                                : Color.fallbackTextMuted
                        )
                }
                .buttonStyle(.borderless)
                .disabled(!canSend)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .background(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    inputFocused ? Color(hex: "6366f1") : Color.fallbackBorderColor,
                    lineWidth: inputFocused ? 2 : 1
                )
        )
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    // MARK: - Actions

    private var canSend: Bool {
        !inputText.trimmingCharacters(in: .whitespaces).isEmpty && !aiService.isRunning
    }

    private func buildContext(
        references: [AiContextItem],
        selectionContext: String?
    ) -> String {
        if !references.isEmpty {
            var sections: [String] = []
            if let selectionContext {
                sections.append("Selected text:\n\(selectionContext)")
            } else if let doc = activeDocument {
                sections.append("Current page:\n\(MarkdownBlockParser.serialize(doc.blocks))")
            }
            for ref in references {
                sections.append("\(ref.contextHeading):\n\(ref.contextMarkdown)")
            }
            return sections.joined(separator: "\n\n---\n\n")
        }
        if let selectionContext {
            return selectionContext
        }
        if let doc = activeDocument {
            return MarkdownBlockParser.serialize(doc.blocks)
        }
        return ""
    }

    private func sendMessage() {
        let trimmed = inputText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !aiService.isRunning else { return }

        let userMessage = ChatMessage(role: .user, content: trimmed, timestamp: Date())
        messages.append(userMessage)
        inputText = ""

        // Snapshot referenced items for this message and clear them
        let currentReferences = referencedItems
        referencedItems.removeAll()

        // Capture selection context and block range before it gets cleared
        let selectionContext = appState.aiSelectionContext
        let hasSelection = selectionContext != nil
        let blockRange = activeDocument?.selectedBlockPathRange()
        let pagePath = activeDocument?.filePath

        let task = Task {
            // Build context off main thread (contextMarkdown may read files)
            let pageContext = buildContext(
                references: currentReferences,
                selectionContext: selectionContext
            )
            do {
                let workspacePath = appState.workspacePath ?? ""
                let response: String
                if activeDocument != nil {
                    response = try await aiService.generateContent(
                        engine: appState.settings.preferredAIEngine,
                        workspacePath: workspacePath,
                        prompt: trimmed,
                        pageContext: pageContext,
                        apiKey: appState.settings.anthropicApiKey
                    )
                } else {
                    response = try await aiService.chatWithNotes(
                        engine: appState.settings.preferredAIEngine,
                        workspacePath: workspacePath,
                        question: trimmed,
                        apiKey: appState.settings.anthropicApiKey
                    )
                }

                guard !Task.isCancelled else { return }

                // Apply changes via CLI for precision, fallback to in-memory
                if let pagePath, let doc = activeDocument {
                    let pageName = ((pagePath as NSString).lastPathComponent as NSString).deletingPathExtension
                    let applied = await applyViaCLI(
                        pageName: pageName,
                        response: response,
                        hasSelection: hasSelection,
                        blockRange: blockRange
                    )
                    if applied {
                        doc.reloadFromDisk()
                    } else {
                        if hasSelection {
                            doc.replaceSelectedBlocks(markdown: response)
                        } else {
                            doc.applyAiResponse(markdown: response)
                        }
                    }
                    // Show clean confirmation instead of raw markdown
                    let appliedMessage = ChatMessage(role: .applied, content: response, timestamp: Date())
                    messages.append(appliedMessage)
                } else {
                    // No active doc — show the response as plain chat
                    let assistantMessage = ChatMessage(role: .assistant, content: response, timestamp: Date())
                    messages.append(assistantMessage)
                }

                appState.aiSelectionContext = nil
            } catch {
                if !Task.isCancelled {
                    let errorMessage = ChatMessage(role: .error, content: error.localizedDescription, timestamp: Date())
                    messages.append(errorMessage)
                }
            }
        }
        activeTask = task
    }

    /// Apply AI response to page via bugbook CLI commands.
    private func applyViaCLI(pageName: String, response: String, hasSelection: Bool, blockRange: (first: String, last: String)?) async -> Bool {
        let escapedPage = pageName.replacingOccurrences(of: "'", with: "'\"'\"'")

        if hasSelection, let range = blockRange {
            let tempFile = NSTemporaryDirectory() + "bugbook-ai-\(UUID().uuidString).md"
            do {
                try response.write(toFile: tempFile, atomically: true, encoding: .utf8)
                defer { try? FileManager.default.removeItem(atPath: tempFile) }

                _ = try await aiService.executeBugbookCommand(
                    "block replace '\(escapedPage)' \(range.first) --content-file '\(tempFile)'"
                )

                if range.first != range.last {
                    let firstIdx = Int(range.first.replacingOccurrences(of: "path:", with: "")) ?? 0
                    let lastIdx = Int(range.last.replacingOccurrences(of: "path:", with: "")) ?? 0
                    if lastIdx > firstIdx {
                        let newBlockCount = MarkdownBlockParser.parse(response).count
                        let deleteStart = firstIdx + newBlockCount
                        let deleteEnd = lastIdx + newBlockCount - 1
                        for i in stride(from: deleteEnd, through: deleteStart, by: -1) {
                            _ = try? await aiService.executeBugbookCommand(
                                "block delete '\(escapedPage)' path:\(i)"
                            )
                        }
                    }
                }
                return true
            } catch {
                Log.ai.error("CLI block replace failed: \(error.localizedDescription)")
                return false
            }
        } else {
            let tempFile = NSTemporaryDirectory() + "bugbook-ai-\(UUID().uuidString).md"
            do {
                try response.write(toFile: tempFile, atomically: true, encoding: .utf8)
                defer { try? FileManager.default.removeItem(atPath: tempFile) }
                _ = try await aiService.executeBugbookCommand(
                    "page update '\(escapedPage)' --content-file '\(tempFile)'"
                )
                return true
            } catch {
                Log.ai.error("CLI page update failed: \(error.localizedDescription)")
                return false
            }
        }
    }

    private func cancelGeneration() {
        activeTask?.cancel()
        activeTask = nil
        aiService.isRunning = false
    }

    private func closePanel() {
        appState.aiSidePanelOpen = false
    }

    private func openFullChat() {
        appState.openNotesChat()
    }

    // MARK: - Page Reference Helpers

    private var allPages: [FileEntry] {
        var files: [FileEntry] = []
        flattenFiles(appState.fileTree, into: &files)
        let unique = Dictionary(files.map { ($0.path, $0) }, uniquingKeysWith: { first, _ in first })
        return unique.values
            .filter { !$0.isDirectory && !$0.isDatabase }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var filteredPages: [FileEntry] {
        let existingPaths = Set(referencedItems.compactMap { item -> String? in
            if case .page(let path, _) = item { return path }
            return nil
        })
        let query = pagePickerSearch.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return allPages.filter { entry in
            guard !existingPaths.contains(entry.path) else { return false }
            if query.isEmpty { return true }
            return entry.name.lowercased().contains(query) || relativePath(for: entry.path).lowercased().contains(query)
        }
    }

    private func flattenFiles(_ entries: [FileEntry], into result: inout [FileEntry]) {
        for entry in entries {
            result.append(entry)
            if let children = entry.children {
                flattenFiles(children, into: &result)
            }
        }
    }

    private func addPageReference(_ entry: FileEntry) {
        let item = AiContextItem.page(path: entry.path, name: entry.name)
        guard !referencedItems.contains(where: { $0.id == item.id }) else { return }
        referencedItems.append(item)
        if inputText.hasSuffix("@") {
            inputText.removeLast()
        }
        showPagePicker = false
        pagePickerSearch = ""
        inputFocused = true
    }

    private func relativePath(for path: String) -> String {
        guard let workspace = appState.workspacePath, path.hasPrefix(workspace) else { return path }
        let relative = path.dropFirst(workspace.count)
        return relative.hasPrefix("/") ? String(relative.dropFirst()) : String(relative)
    }

    private func displayName(for name: String) -> String {
        name.hasSuffix(".md") ? String(name.dropLast(3)) : name
    }
}

// MARK: - Page Reference Row

private struct PageReferenceRow: View {
    let entry: FileEntry
    let displayName: String
    let index: Int
    var isSelected: Bool = false
    let onHoverIndex: (Int) -> Void
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                pageIcon
                Text(displayName)
                    .font(.system(size: Typography.bodySmall))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isSelected || isHovered ? Color.primary.opacity(Opacity.light) : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
            if hovering { onHoverIndex(index) }
        }
    }

    @ViewBuilder
    private var pageIcon: some View {
        if let icon = entry.icon, !icon.isEmpty {
            if icon.unicodeScalars.first?.properties.isEmoji == true {
                Text(icon).font(.system(size: 13))
            } else {
                Image(systemName: entry.isDatabase ? "tablecells" : "doc.text")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        } else {
            Image(systemName: entry.isDatabase ? "tablecells" : "doc.text")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }
}
