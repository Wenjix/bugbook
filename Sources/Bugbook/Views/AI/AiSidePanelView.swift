import SwiftUI

struct AiSidePanelView: View {
    var appState: AppState
    var aiService: AiService
    var activeDocument: BlockDocument?
    @State private var inputText: String = ""
    @State private var activeTask: Task<Void, Never>?
    @State private var showThreadPicker = false
    @FocusState private var inputFocused: Bool

    private var threadStore: AiThreadStore { appState.aiThreadStore }

    private var messages: [ChatMessage] {
        threadStore.activeThread?.messages ?? []
    }

    var body: some View {
        VStack(spacing: 0) {
            header

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
                                Text(aiService.phase.label.isEmpty ? "Thinking..." : aiService.phase.label)
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
                                : Color.accentColor
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
            // Ensure there's an active thread
            ensureActiveThread()
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

            threadTitleButton

            Spacer()

            Button(action: { threadStore.createThread() }) {
                Label("New Thread", systemImage: "plus")
                    .labelStyle(.iconOnly)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help("New thread")

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
    }

    private var threadTitleButton: some View {
        Button {
            showThreadPicker.toggle()
        } label: {
            HStack(spacing: 4) {
                Text(threadStore.activeThread?.title ?? "Chat")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.fallbackTextPrimary)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.borderless)
        .floatingPopover(isPresented: $showThreadPicker, arrowEdge: .bottom) {
            threadPickerContent
                .popoverSurface()
        }
    }

    private var threadPickerContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            NewThreadButton {
                threadStore.createThread()
                showThreadPicker = false
            }

            Divider()
                .padding(.horizontal, 8)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(threadStore.sortedThreads) { thread in
                        threadRow(thread)
                    }
                }
            }
            .frame(maxHeight: 300)
        }
        .padding(.vertical, 6)
        .frame(width: 280)
    }

    private func threadRow(_ thread: AiThread) -> some View {
        ThreadRow(
            thread: thread,
            isActive: thread.id == threadStore.activeThreadId,
            timestamp: relativeTimestamp(thread.updatedAt),
            onSelect: {
                threadStore.switchTo(thread.id)
                showThreadPicker = false
            },
            onDelete: {
                threadStore.deleteThread(thread.id)
            }
        )
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
                        .font(.system(size: Typography.caption2))
                        .foregroundStyle(Color.fallbackTextSecondary)
                        .padding(.leading, 19) // align with text after icon
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.primary.opacity(Opacity.subtle))
            .clipShape(.rect(cornerRadius: Radius.lg))

            if activeDocument != nil {
                HStack(spacing: 8) {
                    Button {
                        handleRevert(message)
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

    private func ensureActiveThread() {
        if threadStore.activeThreadId == nil || threadStore.activeThread == nil {
            threadStore.createThread()
        }
    }

    private func handleRevert(_ message: ChatMessage) {
        if message.isReverted {
            activeDocument?.redo()
        } else {
            activeDocument?.undo()
        }
        guard let threadId = threadStore.activeThreadId else { return }
        threadStore.toggleMessageReverted(message.id, in: threadId)
    }

    private func sendMessage() {
        let trimmed = inputText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !aiService.isRunning else { return }

        ensureActiveThread()
        guard let threadId = threadStore.activeThreadId else { return }

        let userMessage = ChatMessage(role: .user, content: trimmed, timestamp: Date())
        threadStore.appendMessage(userMessage, to: threadId)
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
                    let beforeBlocks = doc.blocks
                    aiService.phase = .applyingChanges

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
                    let summary = Self.changeSummary(before: beforeBlocks, after: doc.blocks)
                    let appliedMessage = ChatMessage(role: .applied, content: response, timestamp: Date(), changeSummary: summary)
                    threadStore.appendMessage(appliedMessage, to: threadId)
                } else {
                    let assistantMessage = ChatMessage(role: .assistant, content: response, timestamp: Date())
                    threadStore.appendMessage(assistantMessage, to: threadId)
                }

                appState.aiSelectionContext = nil
            } catch {
                if !Task.isCancelled {
                    let errorMessage = ChatMessage(role: .error, content: error.localizedDescription, timestamp: Date())
                    threadStore.appendMessage(errorMessage, to: threadId)
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

    // MARK: - Helpers

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    private func relativeTimestamp(_ date: Date) -> String {
        Self.relativeFormatter.localizedString(for: date, relativeTo: Date())
    }

    /// Compute a human-readable summary of block-level changes.
    private static func changeSummary(before: [Block], after: [Block]) -> String? {
        let beforeIDs = Set(before.map { $0.id })
        let afterIDs = Set(after.map { $0.id })

        let added = afterIDs.subtracting(beforeIDs).count
        let removed = beforeIDs.subtracting(afterIDs).count

        let commonIDs = beforeIDs.intersection(afterIDs)
        let beforeMap = Dictionary(uniqueKeysWithValues: before.map { ($0.id, $0) })
        let afterMap = Dictionary(uniqueKeysWithValues: after.map { ($0.id, $0) })
        var modified = 0
        for id in commonIDs {
            if beforeMap[id] != afterMap[id] {
                modified += 1
            }
        }

        guard added > 0 || removed > 0 || modified > 0 else { return nil }

        var parts: [String] = []
        if added > 0 { parts.append("Added \(added) block\(added == 1 ? "" : "s")") }
        if modified > 0 { parts.append("modified \(modified)") }
        if removed > 0 { parts.append("removed \(removed)") }
        return parts.joined(separator: ", ")
    }
}
