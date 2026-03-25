import SwiftUI
import BugbookCore

struct MeetingsView: View {
    var appState: AppState
    var calendarService: CalendarService
    var aiService: AiService
    var onNavigateToFile: (String) -> Void

    @State private var vm = MeetingsViewModel()
    @State private var chatInput: String = ""
    @State private var chatResponse: String = ""
    @State private var isChatLoading = false
    @FocusState private var chatFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            searchBar
            meetingsList
            Divider()
            chatBar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.fallbackEditorBg)
        .onAppear { loadMeetings() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "person.2")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(.secondary)

            Text("Meetings")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Color.fallbackTextPrimary)

            Spacer()
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 14)
        .padding(.top, 36)
    }

    // MARK: - Search

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13))
                .foregroundStyle(.tertiary)
            TextField("Filter meetings...", text: $vm.searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color.primary.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .padding(.horizontal, 28)
        .padding(.bottom, 8)
    }

    // MARK: - Meetings List

    private var meetingsList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                let upcoming = vm.filteredUpcoming
                let past = vm.filteredPast

                if !upcoming.isEmpty {
                    sectionHeader("Coming Up")
                    ForEach(upcoming, id: \.date) { group in
                        dayHeader(vm.relativeLabel(for: group.date))
                        ForEach(group.items) { item in
                            meetingRow(item)
                        }
                    }
                }

                if !past.isEmpty {
                    sectionHeader("Past Meetings")
                    ForEach(past, id: \.date) { group in
                        dayHeader(vm.relativeLabel(for: group.date))
                        ForEach(group.items) { item in
                            meetingRow(item)
                        }
                    }
                }

                if upcoming.isEmpty && past.isEmpty {
                    emptyState
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 8)
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.top, 16)
            .padding(.bottom, 4)
    }

    private func dayHeader(_ label: String) -> some View {
        Text(label)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.tertiary)
            .padding(.top, 10)
            .padding(.bottom, 2)
    }

    private func meetingRow(_ item: MeetingItem) -> some View {
        Button(action: { handleTap(item) }) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.fallbackTextPrimary)
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        if !item.isAllDay, let end = item.endDate {
                            Text("\(vm.timeFormatter.string(from: item.date)) - \(vm.timeFormatter.string(from: end))")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        } else if item.isAllDay {
                            Text("All day")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }

                        if !item.attendeeSummary.isEmpty {
                            Text(item.attendeeSummary)
                                .font(.system(size: 11))
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }
                    }
                }

                Spacer()

                if item.pagePath != nil {
                    Image(systemName: "doc.text")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.primary.opacity(0.03))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, 1)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "person.2.slash")
                .font(.system(size: 28))
                .foregroundStyle(.quaternary)
            Text(vm.searchText.isEmpty ? "No meetings found" : "No matching meetings")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            if vm.searchText.isEmpty {
                Text("Sync your calendar in Settings to see upcoming meetings.")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    // MARK: - Chat Bar

    private var chatBar: some View {
        VStack(spacing: 6) {
            if !chatResponse.isEmpty {
                ScrollView {
                    Text(chatResponse)
                        .font(.system(size: 13))
                        .foregroundStyle(Color.fallbackTextPrimary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                }
                .frame(maxHeight: 160)

                Divider()
            }

            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)

                TextField("Ask about your meetings...", text: $chatInput)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .focused($chatFocused)
                    .onSubmit { sendChat() }

                if isChatLoading {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Button(action: sendChat) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(chatInput.isEmpty ? Color.secondary.opacity(0.4) : .accentColor)
                    }
                    .buttonStyle(.plain)
                    .disabled(chatInput.isEmpty)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
    }

    // MARK: - Actions

    private func loadMeetings() {
        guard let workspace = appState.workspacePath else { return }
        calendarService.loadCachedData(workspace: workspace)
        vm.load(workspace: workspace, calendarEvents: calendarService.events)
    }

    private func handleTap(_ item: MeetingItem) {
        if let path = item.pagePath {
            onNavigateToFile(path)
        }
    }

    private func sendChat() {
        let question = chatInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, let workspace = appState.workspacePath else { return }
        chatInput = ""
        isChatLoading = true

        Task {
            do {
                let response = try await aiService.chatWithNotes(
                    engine: appState.settings.preferredAIEngine,
                    workspacePath: workspace,
                    question: question,
                    apiKey: appState.settings.anthropicApiKey
                )
                chatResponse = response
            } catch {
                chatResponse = "Error: \(error.localizedDescription)"
            }
            isChatLoading = false
        }
    }
}
