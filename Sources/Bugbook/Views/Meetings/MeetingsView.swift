import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct MeetingsView: View {
    var appState: AppState
    @Bindable var viewModel: MeetingsViewModel
    var meetingNoteService: MeetingNoteService
    var transcriptionService: TranscriptionService
    var aiService: AiService
    var onNavigateToFile: (String) -> Void

    @State private var isImporting = false

    var body: some View {
        VStack(spacing: 0) {
            header
            meetingsList
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .ignoresSafeArea(.container, edges: .top)
        .background(Color.fallbackEditorBg)
        .onAppear {
            if let workspace = appState.workspacePath {
                viewModel.scan(workspace: workspace)
            }
        }
        .onDisappear {
            viewModel.stop()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Text("AI Meeting Notes")
                .font(.system(size: 16, weight: .semibold))
                .lineLimit(1)

            Spacer()

            if viewModel.isScanning {
                ProgressView()
                    .controlSize(.small)
            }

            Button(action: importRecording) {
                Image(systemName: "square.and.arrow.down")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .disabled(isImporting)
            .help("Import Recording")

            Button(action: { appState.openNotesChat() }) {
                HStack(spacing: 4) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 11))
                    Text("Chat with all my notes")
                        .font(.system(size: 12))
                }
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)

            Button(action: rescan) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isScanning)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }

    // MARK: - List

    @ViewBuilder
    private var meetingsList: some View {
        let groups = viewModel.groupedMeetings
        if groups.isEmpty && !viewModel.isScanning {
            emptyState
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(groups, id: \.bucket) { group in
                        sectionHeader(group.bucket.rawValue)
                        ForEach(group.meetings) { meeting in
                            meetingRow(meeting)
                        }
                    }
                }
                .padding(.vertical, 8)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.2.circle")
                .font(.system(size: 36))
                .foregroundStyle(.quaternary)
            Text("No meetings found")
                .font(.system(size: Typography.body))
                .foregroundStyle(.secondary)
            Text("Meetings are discovered from date-prefixed pages\nor pages containing <!-- meeting --> blocks.")
                .font(.system(size: Typography.caption))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Components

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: Typography.caption, weight: .semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 6)
    }

    private func meetingRow(_ meeting: DiscoveredMeeting) -> some View {
        Button(action: { onNavigateToFile(meeting.filePath) }) {
            HStack(spacing: 10) {
                Image(systemName: "doc.text")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 2) {
                    Text(meeting.title)
                        .font(.system(size: Typography.body))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        Text(meeting.parentPageName)
                            .font(.system(size: Typography.caption))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)

                        Text("\u{00B7}")
                            .font(.system(size: Typography.caption))
                            .foregroundStyle(.quaternary)

                        Text(formattedDate(meeting.timestamp))
                            .font(.system(size: Typography.caption))
                            .foregroundStyle(.tertiary)
                    }
                }

                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(HoverHighlight())
    }

    // MARK: - Helpers

    private func importRecording() {
        let panel = NSOpenPanel()
        panel.title = "Import Recording"
        panel.allowedContentTypes = [.audio]
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard TranscriptionService.isSupportedAudioFile(url) else { return }

        isImporting = true
        Task {
            defer { isImporting = false }
            guard let workspace = appState.workspacePath else { return }
            let apiKey = appState.settings.anthropicApiKey
            let model = appState.settings.anthropicModel

            if let path = await meetingNoteService.importRecording(
                fileURL: url,
                workspace: workspace,
                transcriptionService: transcriptionService,
                aiService: aiService,
                apiKey: apiKey,
                model: model
            ) {
                onNavigateToFile(path)
                rescan()
            }
        }
    }

    private func rescan() {
        guard let workspace = appState.workspacePath else { return }
        viewModel.scan(workspace: workspace)
    }

    private func formattedDate(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) {
            return Self.timeFormatter.string(from: date)
        } else if cal.isDateInYesterday(date) {
            return "Yesterday"
        } else {
            return Self.shortDateFormatter.string(from: date)
        }
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f
    }()

    private static let shortDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d, yyyy"
        return f
    }()
}

// MARK: - Hover Highlight

private struct HoverHighlight: View {
    @State private var isHovered = false

    var body: some View {
        Rectangle()
            .fill(isHovered ? Color.primary.opacity(0.04) : Color.clear)
            .onHover { isHovered = $0 }
    }
}
