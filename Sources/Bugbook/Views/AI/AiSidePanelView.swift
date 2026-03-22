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

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 8) {
                Image("BugbookAI")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 22, height: 22)
                    .clipShape(RoundedRectangle(cornerRadius: 5))

                Text("Ask AI")
                    .font(.system(size: 14, weight: .semibold))
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
                    Label("Close", systemImage: "xmark")
                        .labelStyle(.iconOnly)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Close")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            // Messages
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
                                    .font(.system(size: 13))
                                    .foregroundStyle(Color.fallbackTextSecondary)
                                Spacer()
                                Button("Cancel") {
                                    cancelGeneration()
                                }
                                .font(.system(size: 12))
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

            Divider()

            // Context chips + input area
            VStack(spacing: 6) {
                if !referencedItems.isEmpty {
                    contextChipsView
                }

                HStack(alignment: .bottom, spacing: 8) {
                    Button {
                        showPagePicker.toggle()
                    } label: {
                        Image(systemName: "at")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 24, height: 24)
                            .background(Color.fallbackBadgeBg)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help("Reference a page")
                    .floatingPopover(isPresented: $showPagePicker, arrowEdge: .top) {
                        pageReferencePickerView
                    }

                    TextField("Ask about your notes...", text: $inputText, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14))
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
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
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
                // Auto-send the prompt from inline AI trigger
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

    private var pageReferencePickerView: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Reference a page")
                .font(.system(size: 14, weight: .semibold))

            TextField("Search pages...", text: $pagePickerSearch)
                .textFieldStyle(.roundedBorder)

            if filteredPages.isEmpty {
                Text("No pages found")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(.top, 8)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(filteredPages.prefix(100), id: \.path) { entry in
                            Button {
                                addPageReference(entry)
                            } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(displayName(for: entry.name))
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                    Text(relativePath(for: entry.path))
                                        .font(.system(size: 12))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .padding(12)
        .frame(width: 340, height: 280)
        .popoverSurface()
    }

    // MARK: - Message Bubble

    @ViewBuilder
    private func messageBubble(_ message: ChatMessage) -> some View {
        VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
            HStack {
                if message.role == .user { Spacer(minLength: 40) }

                if message.role == .applied {
                    appliedBubble(message)
                } else {
                    Text(message.content)
                        .font(.system(size: 14))
                        .foregroundStyle(message.role == .error ? .red : Color.fallbackTextPrimary)
                        .textSelection(.enabled)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(bubbleBackground(for: message.role))
                        .clipShape(.rect(cornerRadius: Radius.lg))
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
                    .font(.system(size: 14))
                    .foregroundStyle(Color.fallbackTextPrimary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.primary.opacity(Opacity.subtle))
            .clipShape(.rect(cornerRadius: Radius.lg))

            if activeDocument != nil {
                HStack(spacing: 8) {
                    Button {
                        if message.isReverted {
                            activeDocument?.redo()
                        } else {
                            activeDocument?.undo()
                        }
                        // Toggle the reverted state
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

    private func bubbleBackground(for role: ChatMessage.Role) -> Color {
        switch role {
        case .user:
            return Color.fallbackAccent.opacity(Opacity.medium)
        case .assistant, .applied:
            return Color.primary.opacity(Opacity.subtle)
        case .error:
            return Color.red.opacity(0.1)
        }
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
            // Replace the first selected block with the AI response,
            // then delete the remaining selected blocks
            let tempFile = NSTemporaryDirectory() + "bugbook-ai-\(UUID().uuidString).md"
            do {
                try response.write(toFile: tempFile, atomically: true, encoding: .utf8)
                defer { try? FileManager.default.removeItem(atPath: tempFile) }

                // Replace the first block with the full AI response
                _ = try await aiService.executeBugbookCommand(
                    "block replace '\(escapedPage)' \(range.first) --content-file '\(tempFile)'"
                )

                // Delete remaining original blocks (they're now shifted, delete from last to first+1)
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
            // Full page update via CLI
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
