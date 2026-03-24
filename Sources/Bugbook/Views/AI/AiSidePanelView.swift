import SwiftUI

struct AiSidePanelView: View {
    var appState: AppState
    var aiService: AiService
    var activeDocument: BlockDocument?
    @State private var messages: [ChatMessage] = []
    @State private var inputText: String = ""
    @State private var activeTask: Task<Void, Never>?
    @State private var statusPhase: String = "Thinking..."
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
                                Text(statusPhase)
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

            // Input area
            HStack(alignment: .bottom, spacing: 10) {
                TextField("Ask about your notes...", text: $inputText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
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
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .frame(width: 380)
        .background(Color.fallbackEditorBg)
        .task {
            inputFocused = true
            if let prompt = appState.aiInitialPrompt, !prompt.isEmpty {
                inputText = prompt
                appState.aiInitialPrompt = nil
                // Auto-send the prompt from inline AI trigger
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    sendMessage()
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
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.green)
                    Text("Done — what do you think?")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.fallbackTextPrimary)
                }
                if let summary = message.changeSummary {
                    Text(summary)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.fallbackTextSecondary)
                }
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

        // Phase 1: Reading context — always read current doc state for iterative editing
        statusPhase = "Reading page..."
        let pageContext: String
        if let selectionContext {
            pageContext = selectionContext
        } else if let doc = activeDocument {
            pageContext = MarkdownBlockParser.serialize(doc.blocks)
        } else {
            pageContext = ""
        }

        // Snapshot block count before AI edits for change summary
        let blockCountBefore = activeDocument?.blocks.count ?? 0

        let task = Task {
            do {
                // Phase 2: Generating
                statusPhase = "Generating..."
                let workspacePath = appState.workspacePath ?? ""
                var response: String
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

                // Post-process: strip empty blocks and excessive whitespace
                response = AiService.sanitizeResponse(response)

                // Phase 3: Applying changes
                if let pagePath, let doc = activeDocument {
                    statusPhase = "Applying changes..."
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

                    // Build change summary
                    let blockCountAfter = doc.blocks.count
                    let summary = buildChangeSummary(
                        blocksBefore: blockCountBefore,
                        blocksAfter: blockCountAfter,
                        responseLength: response.count
                    )

                    // Show clean confirmation instead of raw markdown
                    var appliedMessage = ChatMessage(role: .applied, content: response, timestamp: Date())
                    appliedMessage.changeSummary = summary
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

    /// Build a human-readable summary of what changed.
    private func buildChangeSummary(blocksBefore: Int, blocksAfter: Int, responseLength: Int) -> String {
        let diff = blocksAfter - blocksBefore
        var parts: [String] = []

        if diff > 0 {
            parts.append("added \(diff) block\(diff == 1 ? "" : "s")")
        } else if diff < 0 {
            let removed = abs(diff)
            parts.append("removed \(removed) block\(removed == 1 ? "" : "s")")
        }

        parts.append("edited \(blocksAfter) block\(blocksAfter == 1 ? "" : "s") total")

        return parts.joined(separator: ", ").prefix(1).uppercased() + parts.joined(separator: ", ").dropFirst()
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
