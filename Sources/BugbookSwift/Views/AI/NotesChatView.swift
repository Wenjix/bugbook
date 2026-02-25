import SwiftUI

struct NotesChatView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var aiService: AiService
    @State private var messages: [ChatMessage] = []
    @State private var inputText: String = ""
    @State private var selectedEngine: PreferredAIEngine = .auto
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Chat with Notes")
                    .font(.system(size: 19, weight: .semibold))

                Spacer()

                // Engine selector
                enginePicker

                Button(action: clearChat) {
                    Image(systemName: "trash")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Clear chat")
                .disabled(messages.isEmpty)

                Button(action: { appState.currentView = .editor }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Back to editor")
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)

            Divider()

            // Messages
            if messages.isEmpty && !aiService.isRunning {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "bubble.left.and.text.bubble.right")
                        .font(.system(size: 36))
                        .foregroundColor(.secondary.opacity(0.5))
                    Text("Ask a question about your notes")
                        .font(.system(size: 16))
                        .foregroundColor(.secondary)
                }
                Spacer()
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 16) {
                            ForEach(messages) { message in
                                fullMessageRow(message)
                                    .id(message.id)
                            }

                            if aiService.isRunning {
                                HStack(spacing: 8) {
                                    ProgressView()
                                        .controlSize(.small)
                                    Text("Thinking...")
                                        .font(.system(size: 14))
                                        .foregroundColor(.secondary)
                                }
                                .padding(.horizontal, 24)
                                .id("loading")
                            }
                        }
                        .padding(.vertical, 16)
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

            Divider()

            // Input area
            HStack(alignment: .bottom, spacing: 10) {
                TextField("Ask about your notes...", text: $inputText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15))
                    .lineLimit(1...8)
                    .focused($inputFocused)
                    .onSubmit {
                        sendMessage()
                    }

                Button(action: sendMessage) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(inputText.trimmingCharacters(in: .whitespaces).isEmpty ? .secondary : .accentColor)
                }
                .buttonStyle(.borderless)
                .disabled(inputText.trimmingCharacters(in: .whitespaces).isEmpty || aiService.isRunning)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.fallbackEditorBg)
        .onAppear {
            selectedEngine = appState.settings.preferredAIEngine
            inputFocused = true
        }
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
        }
    }

    // MARK: - Message Row

    @ViewBuilder
    private func fullMessageRow(_ message: ChatMessage) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // Role label
            HStack(spacing: 6) {
                Image(systemName: roleIcon(message.role))
                    .font(.system(size: 12))
                    .foregroundColor(roleColor(message.role))
                Text(roleLabel(message.role))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.secondary)
            }

            Text(message.content)
                .font(.system(size: 15))
                .foregroundColor(message.role == .error ? .red : .primary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 24)
    }

    private func roleIcon(_ role: ChatMessage.Role) -> String {
        switch role {
        case .user: return "person.fill"
        case .assistant: return "cpu"
        case .error: return "exclamationmark.triangle.fill"
        }
    }

    private func roleLabel(_ role: ChatMessage.Role) -> String {
        switch role {
        case .user: return "You"
        case .assistant: return "AI"
        case .error: return "Error"
        }
    }

    private func roleColor(_ role: ChatMessage.Role) -> Color {
        switch role {
        case .user: return .secondary
        case .assistant: return .accentColor
        case .error: return .red
        }
    }

    // MARK: - Actions

    private func sendMessage() {
        let trimmed = inputText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !aiService.isRunning else { return }

        let userMessage = ChatMessage(role: .user, content: trimmed, timestamp: Date())
        messages.append(userMessage)
        inputText = ""

        Task {
            do {
                let workspacePath = appState.workspacePath ?? ""
                let response = try await aiService.chatWithNotes(
                    engine: selectedEngine,
                    workspacePath: workspacePath,
                    question: trimmed
                )
                let assistantMessage = ChatMessage(role: .assistant, content: response, timestamp: Date())
                messages.append(assistantMessage)
            } catch {
                let errorMessage = ChatMessage(role: .error, content: error.localizedDescription, timestamp: Date())
                messages.append(errorMessage)
            }
        }
    }

    private func clearChat() {
        messages.removeAll()
    }
}
