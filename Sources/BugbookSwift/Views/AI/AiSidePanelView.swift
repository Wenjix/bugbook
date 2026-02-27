import SwiftUI

struct AiSidePanelView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var aiService: AiService
    @State private var messages: [ChatMessage] = []
    @State private var inputText: String = ""
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Ask AI")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Button(action: openFullChat) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Expand to full chat")

                Button(action: closePanel) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Close")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

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
                            HStack(spacing: 6) {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Thinking...")
                                    .font(.system(size: 13))
                                    .foregroundColor(.secondary)
                            }
                            .padding(.horizontal, 14)
                            .id("loading")
                        }
                    }
                    .padding(.vertical, 10)
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
            HStack(alignment: .bottom, spacing: 8) {
                TextField("Ask about your notes...", text: $inputText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .lineLimit(1...5)
                    .focused($inputFocused)
                    .onSubmit {
                        // Cmd+Enter sends (plain Enter creates newline in multiline)
                        sendMessage()
                    }

                Button(action: sendMessage) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 21))
                        .foregroundColor(inputText.trimmingCharacters(in: .whitespaces).isEmpty ? .secondary : .accentColor)
                }
                .buttonStyle(.borderless)
                .disabled(inputText.trimmingCharacters(in: .whitespaces).isEmpty || aiService.isRunning)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .frame(width: 320)
        .background(Color.fallbackEditorBg)
        .onAppear {
            inputFocused = true
            if let prompt = appState.aiInitialPrompt, !prompt.isEmpty {
                inputText = prompt
                appState.aiInitialPrompt = nil
            }
        }
    }

    // MARK: - Message Bubble

    @ViewBuilder
    private func messageBubble(_ message: ChatMessage) -> some View {
        VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
            HStack {
                if message.role == .user { Spacer(minLength: 40) }

                Text(message.content)
                    .font(.system(size: 14))
                    .foregroundColor(message.role == .error ? .red : .primary)
                    .textSelection(.enabled)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(bubbleBackground(for: message.role))
                    .cornerRadius(10)

                if message.role != .user { Spacer(minLength: 40) }
            }
        }
        .padding(.horizontal, 14)
    }

    private func bubbleBackground(for role: ChatMessage.Role) -> Color {
        switch role {
        case .user:
            return Color.fallbackAccent.opacity(0.15)
        case .assistant:
            return Color.primary.opacity(0.06)
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

        Task {
            do {
                let workspacePath = appState.workspacePath ?? ""
                let response = try await aiService.chatWithNotes(
                    engine: appState.settings.preferredAIEngine,
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

    private func closePanel() {
        appState.aiSidePanelOpen = false
    }

    private func openFullChat() {
        appState.openNotesChat()
    }
}
