import SwiftUI
import BugbookCore

struct MeetingsView: View {
    var appState: AppState
    @Bindable var viewModel: MeetingsViewModel
    var transcriptionService: TranscriptionService
    var meetingNoteService: MeetingNoteService
    var aiService: AiService
    var onNavigateToFile: (String) -> Void

    @State private var meetingTitle = ""
    @State private var isRecording = false
    @State private var liveTranscript: [String] = []
    @State private var volatileText = ""
    @State private var audioLevel: Float = 0
    @State private var pollingTask: Task<Void, Never>?
    @State private var isSaving = false
    @State private var showTranscript = false
    @State private var notesText = ""

    var body: some View {
        VStack(spacing: 0) {
            header

            if isRecording {
                recordingView
            } else if isSaving {
                savingView
            } else {
                recorderPrompt
                recentRecordings
            }
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
            Text("Meetings")
                .font(.system(size: 16, weight: .semibold))
                .lineLimit(1)

            Spacer()

            if isRecording {
                PulsingRecordDot()
                Text("Recording")
                    .font(.system(size: Typography.caption, weight: .medium))
                    .foregroundStyle(StatusColor.error)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    // MARK: - Recorder Prompt (idle state)

    private var recorderPrompt: some View {
        VStack(spacing: 16) {
            Spacer()

            // Title field
            TextField("Meeting title (optional)", text: $meetingTitle)
                .textFieldStyle(.plain)
                .font(.system(size: Typography.body))
                .foregroundStyle(.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.primary.opacity(Opacity.subtle))
                .clipShape(.rect(cornerRadius: Radius.sm))
                .padding(.horizontal, 24)

            // Big record button
            Button(action: startRecording) {
                HStack(spacing: 10) {
                    Circle()
                        .fill(StatusColor.error)
                        .frame(width: 14, height: 14)
                    Text("Start recording")
                        .font(.system(size: Typography.body, weight: .medium))
                }
                .foregroundStyle(.primary)
                .padding(.horizontal, 24)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity)
                .background(Color.primary.opacity(Opacity.light))
                .clipShape(.rect(cornerRadius: Radius.md))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.md)
                        .strokeBorder(Color.primary.opacity(Opacity.medium), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 24)

            Spacer()
        }
    }

    // MARK: - Recording View (active state)

    private var recordingView: some View {
        VStack(spacing: 0) {
            // Title (editable during recording)
            TextField("Meeting title", text: $meetingTitle)
                .textFieldStyle(.plain)
                .font(.system(size: Typography.body, weight: .medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

            // Notes / Transcript toggle
            HStack(spacing: 0) {
                toggleTab("Notes", isActive: !showTranscript) { showTranscript = false }
                toggleTab("Transcript", isActive: showTranscript) { showTranscript = true }
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 4)

            Divider()

            // Content area — either notes or transcript
            if showTranscript {
                transcriptView
            } else {
                notesView
            }

            Divider()

            // Waveform + stop button
            HStack(spacing: 12) {
                HStack(spacing: 2) {
                    ForEach(0..<5, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 1)
                            .fill(StatusColor.error.opacity(0.7))
                            .frame(width: 3, height: barHeight(index: i))
                    }
                }
                .frame(height: 20)

                Spacer()

                Button(action: stopRecording) {
                    HStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(.primary)
                            .frame(width: 10, height: 10)
                        Text("Stop")
                            .font(.system(size: Typography.bodySmall, weight: .medium))
                    }
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.primary.opacity(Opacity.light))
                    .clipShape(.rect(cornerRadius: Radius.sm))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
    }

    // MARK: - Notes / Transcript Views

    private func toggleTab(_ label: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: Typography.caption, weight: .medium))
                .foregroundStyle(isActive ? .primary : .tertiary)
                .padding(.vertical, 3)
                .padding(.horizontal, 8)
                .background(isActive ? Color.primary.opacity(Opacity.light) : Color.clear)
                .clipShape(.rect(cornerRadius: Radius.xs))
        }
        .buttonStyle(.plain)
    }

    private var notesView: some View {
        TextEditor(text: $notesText)
            .font(.system(size: Typography.body))
            .scrollContentBackground(.hidden)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var transcriptView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(liveTranscript.enumerated()), id: \.offset) { idx, segment in
                        Text(segment)
                            .font(.system(size: Typography.bodySmall))
                            .foregroundStyle(.primary)
                            .id(idx)
                    }

                    if !volatileText.isEmpty {
                        Text(volatileText)
                            .font(.system(size: Typography.bodySmall))
                            .foregroundStyle(.tertiary)
                            .id("volatile")
                    }

                    if liveTranscript.isEmpty && volatileText.isEmpty {
                        Text("Listening...")
                            .font(.system(size: Typography.bodySmall))
                            .foregroundStyle(.quaternary)
                    }
                }
                .padding(12)
            }
            .onChange(of: liveTranscript.count) { _, _ in
                if let last = liveTranscript.indices.last {
                    proxy.scrollTo(last, anchor: .bottom)
                }
            }
        }
    }

    // MARK: - Saving View

    private var savingView: some View {
        VStack(spacing: 12) {
            Spacer()
            ProgressView()
                .controlSize(.regular)
            Text("Saving meeting note...")
                .font(.system(size: Typography.bodySmall))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Recent Recordings (compact list below prompt)

    @ViewBuilder
    private var recentRecordings: some View {
        let groups = viewModel.groupedMeetings
        if !groups.isEmpty {
            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    sectionDivider("Recent")
                    ForEach(groups.flatMap(\.meetings).prefix(8)) { meeting in
                        meetingRow(meeting)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    // MARK: - Actions

    private func startRecording() {
        isRecording = true
        appState.isRecording = true
        liveTranscript = []
        volatileText = ""

        pollingTask = Task {
            await transcriptionService.startRecording()

            var lastSegmentCount = 0
            var lastVolatile = ""

            while transcriptionService.isRecording {
                let segments = transcriptionService.confirmedSegments
                let vol = transcriptionService.volatileText
                let level = transcriptionService.audioLevel

                if segments.count != lastSegmentCount {
                    lastSegmentCount = segments.count
                    liveTranscript = segments
                }
                if vol != lastVolatile {
                    lastVolatile = vol
                    volatileText = vol
                }
                audioLevel = level

                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }

    private func stopRecording() {
        let transcript = transcriptionService.stopRecording()
        pollingTask?.cancel()
        pollingTask = nil
        isRecording = false
        appState.isRecording = false
        audioLevel = 0

        guard !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let workspace = appState.workspacePath else {
            return
        }

        isSaving = true
        let title = meetingTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let effectiveTitle = title.isEmpty ? "Meeting \(Self.dateFormatter.string(from: Date()))" : title

        Task {
            // Create a lightweight event placeholder to carry the title
            let placeholderEvent = CalendarEvent(
                id: UUID().uuidString,
                title: effectiveTitle,
                startDate: Date(),
                endDate: Date().addingTimeInterval(3600),
                isAllDay: false,
                calendarId: ""
            )
            let path = await meetingNoteService.createMeetingNoteWithTranscript(
                transcription: TranscriptionResult(fullText: transcript, timestampedText: transcript),
                event: placeholderEvent,
                workspace: workspace,
                aiService: aiService,
                apiKey: appState.settings.anthropicApiKey
            )
            isSaving = false
            meetingTitle = ""
            liveTranscript = []

            if let path {
                onNavigateToFile(path)
            }

            // Refresh the list
            viewModel.scan(workspace: workspace)
        }
    }

    // MARK: - Waveform

    private func barHeight(index: Int) -> CGFloat {
        let base: CGFloat = 4
        let scale = CGFloat(audioLevel) * 16
        let offset = sin(Double(index) * 1.3 + Date().timeIntervalSinceReferenceDate * 3) * 0.5 + 0.5
        return base + scale * CGFloat(offset)
    }

    // MARK: - Components

    private func sectionDivider(_ title: String) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: Typography.caption2, weight: .medium))
                .foregroundStyle(.tertiary)
                .textCase(.uppercase)
                .fixedSize()

            Rectangle()
                .fill(Color.primary.opacity(Opacity.subtle))
                .frame(height: 1)
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 4)
    }

    private func meetingRow(_ meeting: DiscoveredMeeting) -> some View {
        Button(action: { onNavigateToFile(meeting.filePath) }) {
            HStack(spacing: 8) {
                Text(formattedTime(meeting.timestamp))
                    .font(.system(size: Typography.caption, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .frame(width: 48, alignment: .trailing)

                Text(meeting.title)
                    .font(.system(size: Typography.body))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer(minLength: 4)

                Text(meeting.parentPageName)
                    .font(.system(size: Typography.caption))
                    .foregroundStyle(.quaternary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(HoverHighlight())
    }

    // MARK: - Helpers

    private func formattedTime(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) {
            return Self.timeFormatter.string(from: date)
        } else if cal.isDateInYesterday(date) {
            return "Yest"
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
        f.dateFormat = "MMM d"
        return f
    }()

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f
    }()
}

// MARK: - Pulsing Record Dot

private struct PulsingRecordDot: View {
    @State private var pulse = false

    var body: some View {
        Circle()
            .fill(StatusColor.error)
            .frame(width: 8, height: 8)
            .scaleEffect(pulse ? 1.3 : 1.0)
            .opacity(pulse ? 0.6 : 1.0)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            }
    }
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
