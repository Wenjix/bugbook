import SwiftUI
import Sentry

struct NotesChatView: View {
    var appState: AppState
    var aiService: AiService
    @State private var messages: [ChatMessage] = []
    @State private var inputText: String = ""
    @State private var selectedEngine: PreferredAIEngine = .auto
    @State private var referencedFiles: [ChatReferencedFile] = []
    @State private var showFileReferencePicker = false
    @State private var fileReferenceSearch = ""
    @FocusState private var inputFocused: Bool

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
        }
    }

    // MARK: - Sections

    private var header: some View {
        HStack(spacing: 8) {
            Image("BugbookAI")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 22, height: 22)
                .clipShape(RoundedRectangle(cornerRadius: 5))

            Text("Chat with Notes")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.fallbackTextPrimary)

            Spacer()

            enginePicker

            Button(action: clearChat) {
                Label("Clear Chat", systemImage: "trash")
                    .labelStyle(.iconOnly)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help("Clear chat")
            .disabled(messages.isEmpty)

            Button(action: closeChat) {
                Label("Close", systemImage: "xmark")
                    .labelStyle(.iconOnly)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help("Close chat")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var messageArea: some View {
        if messages.isEmpty && !aiService.isRunning {
            Spacer()
            VStack(spacing: 16) {
                Image("BugbookAI")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .opacity(0.85)
                VStack(spacing: 6) {
                    Text("Chat with your notes")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color.fallbackTextPrimary)
                    Text("Ask anything about your workspace")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        } else {
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
                            }
                            .padding(.horizontal, 16)
                            .id("loading")
                        }
                    }
                    .padding(.vertical, 12)
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

            HStack(alignment: .bottom, spacing: 10) {
                Button {
                    showFileReferencePicker.toggle()
                } label: {
                    Image(systemName: "at")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 26, height: 26)
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
                    .font(.system(size: 14))
                    .lineLimit(1...20)
                    .frame(minHeight: 24)
                    .fixedSize(horizontal: false, vertical: true)
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
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(
                            canSend
                                ? Color.accentColor
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

    // MARK: - Message Bubble

    @ViewBuilder
    private func messageBubble(_ message: ChatMessage) -> some View {
        VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
            HStack {
                if message.role == .user { Spacer(minLength: 40) }

                if message.role == .applied {
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
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !aiService.isRunning
    }

    private func sendMessage() {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !aiService.isRunning else { return }
        let selectedReferences = referencedFiles

        let userMessage = ChatMessage(
            role: .user,
            content: displayUserMessage(question: trimmed, references: selectedReferences),
            timestamp: Date()
        )
        messages.append(userMessage)
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
                messages.append(assistantMessage)
            } catch {
                SentrySDK.addBreadcrumb(Breadcrumb(level: .error, category: "ai.error"))
                let errorMessage = ChatMessage(role: .error, content: error.localizedDescription, timestamp: Date())
                messages.append(errorMessage)
            }
        }
    }

    private func clearChat() {
        messages.removeAll()
    }

    private func closeChat() {
        appState.closeNotesChat()
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
}

private struct ChatReferencedFile: Identifiable, Equatable {
    let path: String
    let name: String

    var id: String { path }
}
