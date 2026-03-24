import SwiftUI

struct AiSidePanelView: View {
    var appState: AppState
    var aiService: AiService
    var activeDocument: BlockDocument?
    @State private var messages: [ChatMessage] = []
    @State private var inputText: String = ""
    @State private var activeTask: Task<Void, Never>?
    @FocusState private var inputFocused: Bool
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
            if let prompt = appState.aiInitialPrompt, !prompt.isEmpty {
                inputText = prompt
                appState.aiInitialPrompt = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    sendMessage()
                }
            }
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
                Button(action: {}) {
                    Image(systemName: "paperclip")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.fallbackTextSecondary)
                }
                .buttonStyle(.borderless)
                .help("Attach file")

                TextField("Ask about your notes...", text: $inputText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: Typography.body))
                    .lineLimit(1...20)
                    .frame(minHeight: 24)
                    .fixedSize(horizontal: false, vertical: true)
                    .focused($inputFocused)
                    .onSubmit {
                        sendMessage()
                    }

                Button(action: sendMessage) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(
                            inputText.trimmingCharacters(in: .whitespaces).isEmpty
                                ? Color.fallbackTextMuted
                                : Brand.primary
                        )
                }
                .buttonStyle(.borderless)
                .disabled(inputText.trimmingCharacters(in: .whitespaces).isEmpty || aiService.isRunning)
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

    private func sendMessage() {
        let trimmed = inputText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !aiService.isRunning else { return }

        let userMessage = ChatMessage(role: .user, content: trimmed, timestamp: Date())
        messages.append(userMessage)
        inputText = ""

        // Capture selection context and block range before it gets cleared
        let selectionContext = appState.aiSelectionContext
        let hasSelection = selectionContext != nil
        let blockRange = activeDocument?.selectedBlockPathRange()
        let pagePath = activeDocument?.filePath

        // Build context
        let pageContext: String
        if let selectionContext {
            pageContext = selectionContext
        } else if let doc = activeDocument {
            pageContext = MarkdownBlockParser.serialize(doc.blocks)
        } else {
            pageContext = ""
        }

        let task = Task {
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
                    // After replacing the first block, the indices shift.
                    // The safest approach: get fresh block count, delete by original range
                    let firstIdx = Int(range.first.replacingOccurrences(of: "path:", with: "")) ?? 0
                    let lastIdx = Int(range.last.replacingOccurrences(of: "path:", with: "")) ?? 0
                    if lastIdx > firstIdx {
                        // Delete from last to first+1 (reverse order to keep indices stable)
                        // But after replace, the new content may span multiple blocks.
                        // Count how many blocks the AI response creates
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
}
