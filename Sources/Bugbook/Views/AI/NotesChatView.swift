import SwiftUI
import Sentry

struct NotesChatView: View {
    var appState: AppState
    var aiService: AiService
    @State private var inputText: String = ""
    @State private var selectedEngine: PreferredAIEngine = .auto
    @State private var referencedFiles: [ChatReferencedFile] = []
    @State private var showFileReferencePicker = false
    @State private var fileReferenceSearch = ""
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

            messageArea

            Divider()

            composer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.fallbackEditorBg)
        .task {
            selectedEngine = appState.settings.preferredAIEngine
            inputFocused = true
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

    // MARK: - Sections

    private var header: some View {
        HStack(spacing: 12) {
            Image("BugbookLogo")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 32, height: 32)
                .clipShape(RoundedRectangle(cornerRadius: 7))

            VStack(alignment: .leading, spacing: 1) {
                Text("Bugbook")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)

                threadTitleButton
            }

            Spacer()

            enginePicker

            Button(action: { threadStore.createThread() }) {
                Label("New Thread", systemImage: "plus.message")
                    .labelStyle(.iconOnly)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help("New thread")

            Button(action: clearChat) {
                Label("Clear Chat", systemImage: "trash")
                    .labelStyle(.iconOnly)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help("Clear chat")
            .disabled(messages.isEmpty)

        }
        .padding(.horizontal, 28)
        .padding(.vertical, 14)
    }

    private var threadTitleButton: some View {
        Button {
            showThreadPicker.toggle()
        } label: {
            HStack(spacing: 4) {
                Text(threadStore.activeThread?.title ?? "Chat with Notes")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Color.fallbackTextPrimary)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
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
            .frame(maxHeight: 400)
        }
        .padding(.vertical, 6)
        .frame(width: 320)
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

    @ViewBuilder
    private var messageArea: some View {
        if messages.isEmpty && !aiService.isRunning {
            VStack(alignment: .leading, spacing: 12) {
                Text("Ask anything about your workspace")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)

                WrappingHStack(spacing: 6) {
                    suggestionChip("Summarize today's meetings")
                    suggestionChip("What changed this week?")
                    suggestionChip("Draft a follow-up email")
                    suggestionChip("Open tickets overview")
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        ForEach(messages) { message in
                            messageRow(message)
                                .id(message.id)
                        }

                        if aiService.isRunning {
                            HStack(spacing: 8) {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Thinking...")
                                    .font(.system(size: 14))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 24)
                            .id("loading")
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 20)
                    .frame(maxWidth: 980)
                    .frame(maxWidth: .infinity)
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
    }

    private var composer: some View {
        VStack(spacing: 8) {
            if !referencedFiles.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(referencedFiles) { file in
                            HStack(spacing: 6) {
                                Text("@\(displayName(for: file.name))")
                                    .font(.system(size: 12, weight: .medium))
                                    .lineLimit(1)
                                Button {
                                    removeReferencedFile(path: file.path)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 12))
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.fallbackBadgeBg)
                            .clipShape(.capsule)
                        }
                    }
                    .padding(.horizontal, 4)
                }
                .scrollIndicators(.hidden)
            }

            HStack(alignment: .bottom, spacing: 12) {
                Button {
                    showFileReferencePicker.toggle()
                } label: {
                    Image(systemName: "at")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 30, height: 30)
                        .background(Color.fallbackBadgeBg)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Reference files")
                .floatingPopover(isPresented: $showFileReferencePicker, arrowEdge: .top) {
                    fileReferencePicker
                }

                TextField("Ask about your notes...", text: $inputText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 16))
                    .lineLimit(1...8)
                    .focused($inputFocused)
                    .onChange(of: inputText) { _, value in
                        if value.last == "@" {
                            showFileReferencePicker = true
                        }
                    }
                    .onSubmit {
                        sendMessage()
                    }

                Button(action: sendMessage) {
                    Label("Send", systemImage: "arrow.up.circle.fill")
                        .labelStyle(.iconOnly)
                        .font(.system(size: 28))
                        .foregroundStyle(canSend ? Color.accentColor : Color.secondary)
                }
                .buttonStyle(.borderless)
                .disabled(!canSend)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.fallbackSurfaceSubtle)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.fallbackBorderColor, lineWidth: 1)
            )
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
    }

    private var fileReferencePicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Reference a file")
                .font(.system(size: 14, weight: .semibold))

            TextField("Search files...", text: $fileReferenceSearch)
                .textFieldStyle(.roundedBorder)

            if filteredReferenceFiles.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("No files found")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                    Text("Open a workspace first, or change your search.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.top, 8)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(filteredReferenceFiles.prefix(200), id: \.path) { entry in
                            Button {
                                addReferencedFile(entry)
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
        .frame(width: 420, height: 320)
        .popoverSurface()
    }

    // MARK: - Engine Picker

    private var enginePicker: some View {
        HStack(spacing: 6) {
            Picker("", selection: $selectedEngine) {
                ForEach(PreferredAIEngine.allCases, id: \.self) { engine in
                    HStack(spacing: 4) {
                        Circle()
                            .fill(engineAvailable(engine) ? Color.green : Color.red)
                            .frame(width: 6, height: 6)
                        Text(engine.rawValue)
                    }
                    .tag(engine)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 110)
        }
    }

    private func engineAvailable(_ engine: PreferredAIEngine) -> Bool {
        switch engine {
        case .auto:
            return aiService.engineStatus.claudeAvailable || aiService.engineStatus.codexAvailable
        case .claude:
            return aiService.engineStatus.claudeAvailable
        case .codex:
            return aiService.engineStatus.codexAvailable
        case .claudeAPI:
            return !appState.settings.anthropicApiKey.isEmpty
        }
    }

    // MARK: - Message Row

    @ViewBuilder
    private func messageRow(_ message: ChatMessage) -> some View {
        switch message.role {
        case .user:
            HStack {
                Spacer(minLength: 80)
                Text(message.content)
                    .font(.system(size: 16))
                    .lineSpacing(3)
                    .foregroundStyle(.white)
                    .textSelection(.enabled)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color.fallbackAccent)
                    )
                    .frame(maxWidth: 720, alignment: .leading)
            }

        case .assistant:
            HStack {
                Text(message.content)
                    .font(.system(size: 16))
                    .lineSpacing(4)
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.fallbackSurfaceSubtle)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.fallbackBorderColor.opacity(0.8), lineWidth: 1)
                    )
                    .frame(maxWidth: 760, alignment: .leading)
                Spacer(minLength: 80)
            }

        case .error:
            HStack {
                Text(message.content)
                    .font(.system(size: 15))
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.red.opacity(0.1))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.red.opacity(0.25), lineWidth: 1)
                    )
                Spacer(minLength: 80)
            }

        case .applied:
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Done — what do you think?")
                        .font(.system(size: 16))
                        .foregroundStyle(.primary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.fallbackSurfaceSubtle)
                )
                Spacer(minLength: 80)
            }
        }
    }

    // MARK: - Actions

    private func ensureActiveThread() {
        if threadStore.activeThreadId == nil || threadStore.activeThread == nil {
            threadStore.createThread()
        }
    }

    private var canSend: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !aiService.isRunning
    }

    private func sendMessage() {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !aiService.isRunning else { return }
        let selectedReferences = referencedFiles

        ensureActiveThread()
        guard let threadId = threadStore.activeThreadId else { return }

        let userMessage = ChatMessage(
            role: .user,
            content: displayUserMessage(question: trimmed, references: selectedReferences),
            timestamp: Date()
        )
        threadStore.appendMessage(userMessage, to: threadId)
        inputText = ""
        referencedFiles.removeAll()
        showFileReferencePicker = false
        fileReferenceSearch = ""
        SentrySDK.addBreadcrumb(Breadcrumb(level: .info, category: "ai.send"))

        Task {
            do {
                let workspacePath = appState.workspacePath ?? ""
                let prompt = buildPromptWithReferences(
                    question: trimmed,
                    references: selectedReferences,
                    workspacePath: workspacePath
                )
                let response = try await aiService.chatWithNotes(
                    engine: selectedEngine,
                    workspacePath: workspacePath,
                    question: prompt,
                    apiKey: appState.settings.anthropicApiKey
                )
                SentrySDK.addBreadcrumb(Breadcrumb(level: .info, category: "ai.receive"))
                let assistantMessage = ChatMessage(role: .assistant, content: response, timestamp: Date())
                threadStore.appendMessage(assistantMessage, to: threadId)
            } catch {
                SentrySDK.addBreadcrumb(Breadcrumb(level: .error, category: "ai.error"))
                let errorMessage = ChatMessage(role: .error, content: error.localizedDescription, timestamp: Date())
                threadStore.appendMessage(errorMessage, to: threadId)
            }
        }
    }

    private func clearChat() {
        guard let threadId = threadStore.activeThreadId else { return }
        threadStore.deleteThread(threadId)
        threadStore.createThread()
    }

    private var allReferenceFiles: [FileEntry] {
        var files: [FileEntry] = []
        flattenFiles(appState.fileTree, into: &files)
        let unique = Dictionary(uniqueKeysWithValues: files.map { ($0.path, $0) })
        return unique.values
            .filter { !$0.isDirectory && !$0.isDatabase }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var filteredReferenceFiles: [FileEntry] {
        let existing = Set(referencedFiles.map(\.path))
        let query = fileReferenceSearch.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return allReferenceFiles.filter { entry in
            guard !existing.contains(entry.path) else { return false }
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

    private func addReferencedFile(_ entry: FileEntry) {
        guard !referencedFiles.contains(where: { $0.path == entry.path }) else { return }
        referencedFiles.append(ChatReferencedFile(path: entry.path, name: entry.name))
        if inputText.hasSuffix("@") {
            inputText.removeLast()
        }
        inputFocused = true
    }

    private func removeReferencedFile(path: String) {
        referencedFiles.removeAll { $0.path == path }
    }

    private func relativePath(for path: String) -> String {
        guard let workspace = appState.workspacePath, path.hasPrefix(workspace) else { return path }
        let relative = path.dropFirst(workspace.count)
        return relative.hasPrefix("/") ? String(relative.dropFirst()) : String(relative)
    }

    private func displayName(for name: String) -> String {
        if name.hasSuffix(".md") {
            return String(name.dropLast(3))
        }
        return name
    }

    private func displayUserMessage(question: String, references: [ChatReferencedFile]) -> String {
        guard !references.isEmpty else { return question }
        let refs = references.map { "@\(displayName(for: $0.name))" }.joined(separator: " ")
        return "\(question)\n\n\(refs)"
    }

    private func buildPromptWithReferences(
        question: String,
        references: [ChatReferencedFile],
        workspacePath: String
    ) -> String {
        guard !references.isEmpty else { return question }
        var sections: [String] = []

        for reference in references.prefix(6) {
            let path = reference.path
            let relative = relativePath(for: path)
            guard !workspacePath.isEmpty, path.hasPrefix(workspacePath) else { continue }

            if let content = try? String(contentsOfFile: path, encoding: .utf8) {
                let maxCharacters = 8_000
                let snippet = String(content.prefix(maxCharacters))
                let truncated = content.count > snippet.count ? "\n...[truncated]" : ""
                sections.append(
                    """
                    File: \(relative)
                    ```text
                    \(snippet)\(truncated)
                    ```
                    """
                )
            } else {
                sections.append("File: \(relative)\n[Could not read file content]")
            }
        }

        if sections.isEmpty { return question }
        return """
        \(question)

        Referenced files (treat these as primary context):

        \(sections.joined(separator: "\n\n"))
        """
    }

    // MARK: - Suggestion Chips

    private func suggestionChip(_ text: String) -> some View {
        Button {
            inputText = text
            sendMessage()
        } label: {
            Text(text)
                .font(.system(size: Typography.caption))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.primary.opacity(Opacity.subtle))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.primary.opacity(Opacity.light), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
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
}

private struct WrappingHStack: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }

        return CGSize(width: maxWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX && x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

private struct ChatReferencedFile: Identifiable, Equatable {
    let path: String
    let name: String

    var id: String { path }
}
