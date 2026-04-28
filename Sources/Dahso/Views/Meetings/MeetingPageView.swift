import SwiftUI

private enum MeetingSummaryGenerationError: LocalizedError {
    case commandFailed(String)
    case emptyOutput
    case missingSummary

    var errorDescription: String? {
        switch self {
        case .commandFailed(let message):
            return message.isEmpty ? "Summary generation failed." : message
        case .emptyOutput:
            return "Summary generation returned no text."
        case .missingSummary:
            return "Summary generation did not return a usable summary."
        }
    }
}

/// Dedicated meeting page layout.
/// Standard page header + title + database-style property pills + block editor body.
/// Recording controls live in the property pill row.
struct MeetingPageView: View {
    var appState: AppState
    var document: BlockDocument
    var transcriptionService: TranscriptionService
    var meetingNoteService: MeetingNoteService
    var transcriptStore: MeetingTranscriptStore
    var onTextChange: () -> Void
    var onTyping: () -> Void
    var onNavigateToFile: (String) -> Void

    @State private var transcript: MeetingTranscript = MeetingTranscript()
    @State private var isTranscriptExpanded = false
    @State private var transcriptSearch = ""
    @State private var copyConfirmation = false
    @State private var isGeneratingSummary = false
    @State private var summaryError: String?
    @State private var recordingNotice: String?
    @State private var recordingNoticeTask: Task<Void, Never>?

    /// Cached YAML-derived values, refreshed only when frontmatter changes.
    /// Avoids re-parsing on every view body invalidation (which fires 10x/sec during recording).
    @State private var cachedParticipants: [String] = []
    @State private var cachedMeetingId: String?
    @State private var cachedMeetingDate: Date?

    private static let columnHorizontalPadding: CGFloat = 76

    private var isRecordingThisPage: Bool {
        guard let session = appState.activeMeetingSession else { return false }
        return session.meetingPagePath == document.filePath
    }

    // MARK: - YAML Parsing

    private static func parseParticipants(from yaml: String) -> [String] {
        let lines = yaml.split(separator: "\n", omittingEmptySubsequences: false)
        var inParticipants = false
        var result: [String] = []
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("participants:") {
                inParticipants = true
                continue
            }
            if inParticipants {
                if trimmed.hasPrefix("- ") {
                    result.append(String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces))
                } else {
                    break
                }
            }
        }
        return result
    }

    private func refreshCachedFrontmatter() {
        let yaml = document.yamlFrontmatter
        cachedParticipants = Self.parseParticipants(from: yaml)
        cachedMeetingId = MarkdownBlockParser.yamlValue(for: "meeting_id", in: yaml)
        if let raw = MarkdownBlockParser.yamlValue(for: "date", in: yaml) {
            cachedMeetingDate = MeetingNoteService.isoDateFormatter.date(from: raw)
        } else {
            cachedMeetingDate = nil
        }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    PageHeaderView(
                        icon: Binding(get: { document.icon }, set: { document.icon = $0; onTextChange() }),
                        coverUrl: Binding(get: { document.coverUrl }, set: { document.coverUrl = $0; onTextChange() }),
                        coverPosition: Binding(get: { document.coverPosition }, set: { document.coverPosition = $0; onTextChange() }),
                        fullWidth: false,
                        contentColumnMaxWidth: 860
                    )

                    columnAligned {
                        VStack(alignment: .leading, spacing: 8) {
                            if let titleBlock = document.titleBlock {
                                TextBlockView(document: document, block: titleBlock, onTyping: onTyping)
                            }

                            propertyPills
                            summaryGenerationPanel
                        }
                        .padding(.horizontal, Self.columnHorizontalPadding)
                        .padding(.top, 8)
                        .padding(.bottom, 12)
                    }

                    BlockEditorView(
                        document: document,
                        onTextChange: onTextChange,
                        onTyping: onTyping,
                        onPagePathDrop: { _, _ in },
                        contentColumnMaxWidth: 860
                    )

                    // Bottom spacer so the user can scroll past the last note
                    // without it being hidden behind the floating transcript header.
                    if isRecordingThisPage || !transcript.entries.isEmpty {
                        Color.clear.frame(height: 80)
                    }
                }
            }

            // Floating transcript widget — fixed to the bottom of the meeting page.
            // Header is always visible; tap to expand the body upward as an overlay.
            if isRecordingThisPage || !transcript.entries.isEmpty {
                columnAligned {
                    VStack(alignment: .trailing, spacing: 8) {
                        if let recordingNotice {
                            recordingNoticeToast(recordingNotice)
                        }
                        transcriptWidget
                    }
                        .padding(.horizontal, Self.columnHorizontalPadding)
                        .padding(.bottom, 16)
                }
            }
        }
        .background(Color.fallbackEditorBg)
        .onAppear {
            refreshCachedFrontmatter()
            loadTranscriptIfNeeded()

            // Auto-start recording if this page was just created via "New Meeting"
            if let pending = appState.pendingAutoRecordPath, pending == document.filePath {
                appState.pendingAutoRecordPath = nil
                if appState.activeMeetingSession == nil {
                    startRecording()
                }
            }
        }
        .onChange(of: document.yamlFrontmatter) { _, _ in
            refreshCachedFrontmatter()
        }
        .onReceive(NotificationCenter.default.publisher(for: .stopMeetingRecording)) { _ in
            if isRecordingThisPage {
                stopRecording()
            }
        }
        .onDisappear {
            recordingNoticeTask?.cancel()
            recordingNoticeTask = nil
        }
    }

    private func loadTranscriptIfNeeded() {
        // Skip if already loaded (in-memory transcript has data) or no meeting id
        guard transcript.entries.isEmpty, transcript.summary.isEmpty,
              let id = cachedMeetingId,
              let workspace = appState.workspacePath else { return }

        // Background read so a large transcript JSON doesn't block the main thread.
        // Store is nonisolated so the load runs on a background thread.
        let store = transcriptStore
        Task.detached(priority: .userInitiated) {
            let loaded = store.load(meetingId: id, workspace: workspace)
            await MainActor.run {
                self.transcript = loaded
            }
        }
    }

    /// Center a block of content in the page column, matching the block editor layout.
    @ViewBuilder
    private func columnAligned<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 0) {
                content()
            }
            .frame(maxWidth: 860)
            Spacer(minLength: 0)
        }
    }

    // MARK: - Transcript Widget

    /// Combined live + persisted transcript entries for display.
    private var displayedEntries: [MeetingTranscriptEntry] {
        if let session = appState.activeMeetingSession, isRecordingThisPage {
            // During recording, show the live polled segments from the session
            return session.confirmedSegments.map { MeetingTranscriptEntry(text: $0) }
        }
        return transcript.entries
    }

    private var filteredEntries: [MeetingTranscriptEntry] {
        let query = transcriptSearch.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return displayedEntries }
        return displayedEntries.filter { $0.text.lowercased().contains(query) }
    }

    private var transcriptWidget: some View {
        // Header is anchored at the bottom; body grows upward when expanded.
        // Floats over the notes — needs an opaque background.
        VStack(alignment: .leading, spacing: 0) {
            if isTranscriptExpanded {
                transcriptBody
                Divider()
                transcriptControls
                Divider()
            }
            transcriptHeader
        }
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.fallbackCardBg)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.primary.opacity(Opacity.medium), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
    }

    private var transcriptHeader: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                isTranscriptExpanded.toggle()
            }
        } label: {
            HStack(spacing: 8) {
                // Chevron points up when collapsed (will open upward), down when expanded.
                Image(systemName: "chevron.up")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(isTranscriptExpanded ? 180 : 0))

                Image(systemName: isRecordingThisPage ? "waveform" : "text.bubble")
                    .font(.system(size: 12))
                    .foregroundStyle(isRecordingThisPage ? StatusColor.error : .secondary)

                Text("Transcript")
                    .font(.system(size: Typography.bodySmall, weight: .medium))
                    .foregroundStyle(.primary)

                Spacer()

                if isRecordingThisPage {
                    PulsingRecordDot()
                        .scaleEffect(0.8)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func recordingNoticeToast(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(StatusColor.warning)
            Text(message)
                .font(.system(size: Typography.caption))
                .foregroundStyle(.primary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: 520, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.fallbackCardBg)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(StatusColor.warning.opacity(0.45), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
    }

    private var transcriptControls: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                TextField("Search transcript", text: $transcriptSearch)
                    .textFieldStyle(.plain)
                    .font(.system(size: Typography.caption))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color.primary.opacity(Opacity.subtle))
            .clipShape(.rect(cornerRadius: Radius.xs))

            Spacer()

            Button(action: copyTranscript) {
                HStack(spacing: 4) {
                    Image(systemName: copyConfirmation ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 10))
                    Text(copyConfirmation ? "Copied" : "Copy")
                        .font(.system(size: Typography.caption, weight: .medium))
                }
                .foregroundStyle(.primary)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color.primary.opacity(Opacity.light))
                .clipShape(.rect(cornerRadius: Radius.xs))
            }
            .buttonStyle(.plain)
            .disabled(displayedEntries.isEmpty)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var transcriptBody: some View {
        Group {
            if filteredEntries.isEmpty && displayedEntries.isEmpty {
                Text(isRecordingThisPage ? "Listening..." : "No transcript")
                    .font(.system(size: Typography.bodySmall))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            } else if filteredEntries.isEmpty {
                Text("No matches")
                    .font(.system(size: Typography.bodySmall))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(filteredEntries) { entry in
                            transcriptBubble(entry: entry)
                        }
                        if isRecordingThisPage,
                           let session = appState.activeMeetingSession,
                           !session.volatileText.isEmpty {
                            transcriptBubble(entry: MeetingTranscriptEntry(text: session.volatileText), isVolatile: true)
                        }
                    }
                    .padding(12)
                }
                .frame(maxHeight: 300)
            }
        }
    }

    private func transcriptBubble(entry: MeetingTranscriptEntry, isVolatile: Bool = false) -> some View {
        let isSelf = entry.speaker == "self"
        return HStack {
            if isSelf { Spacer(minLength: 40) }
            Text(entry.text)
                .font(.system(size: Typography.bodySmall))
                .foregroundStyle(isVolatile ? .tertiary : .primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(isSelf ? Color.accentColor.opacity(0.18) : Color.primary.opacity(Opacity.light))
                )
                .frame(maxWidth: .infinity, alignment: isSelf ? .trailing : .leading)
            if !isSelf { Spacer(minLength: 40) }
        }
    }

    private func copyTranscript() {
        let text = displayedEntries.map(\.text).joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copyConfirmation = true
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            copyConfirmation = false
        }
    }

    // MARK: - Property Pills

    private var propertyPills: some View {
        HStack(spacing: 8) {
            datePill
            recordingPill
            if !cachedParticipants.isEmpty {
                participantsPill
            }
            if shouldShowManualSummaryButton {
                manualSummaryButton
            }
        }
    }

    @ViewBuilder
    private var summaryGenerationPanel: some View {
        if isGeneratingSummary {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Generating summary...")
                    .font(.system(size: Typography.caption))
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 4)
        } else if let summaryError {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(StatusColor.warning)
                Text(summaryError)
                    .font(.system(size: Typography.caption))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                Button(action: retrySummaryGeneration) {
                    Text("Retry")
                        .font(.system(size: Typography.caption, weight: .medium))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.primary.opacity(Opacity.subtle))
                        .clipShape(RoundedRectangle(cornerRadius: Radius.xs))
                }
                .buttonStyle(.borderless)
            }
            .padding(.top, 4)
        }
    }

    private var manualSummaryButton: some View {
        Button(action: retrySummaryGeneration) {
            HStack(spacing: 4) {
                Image(systemName: "sparkles")
                    .font(.system(size: 11))
                Text(hasSummaryContent ? "Regenerate Summary" : "Generate Summary")
                    .font(.system(size: Typography.caption, weight: .medium))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.primary.opacity(Opacity.subtle))
            .clipShape(RoundedRectangle(cornerRadius: Radius.xs))
        }
        .buttonStyle(.borderless)
    }

    private var shouldShowManualSummaryButton: Bool {
        !isRecordingThisPage && !isGeneratingSummary && summaryError == nil
    }

    private var hasSummaryContent: Bool {
        if !transcript.summary.isEmpty || !transcript.actionItems.isEmpty {
            return true
        }
        let generatedIds = Set(transcript.generatedBlockIds)
        if document.blocks.contains(where: { generatedIds.contains($0.id) }) {
            return true
        }
        return document.blocks.contains { block in
            guard block.type == .heading else { return false }
            let text = block.text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return text == "summary" || text == "action items"
        }
    }

    private var datePill: some View {
        let date = cachedMeetingDate ?? Date()
        return propertyChip(icon: "calendar", text: Self.pillDateFormatter.string(from: date))
    }

    @ViewBuilder
    private var recordingPill: some View {
        if isRecordingThisPage, let session = appState.activeMeetingSession {
            Button(action: stopRecording) {
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.white)
                        .frame(width: 9, height: 9)
                    TimelineView(.periodic(from: session.startDate, by: 1)) { context in
                        let elapsed = Int(context.date.timeIntervalSince(session.startDate))
                        Text(String(format: "%d:%02d", elapsed / 60, elapsed % 60))
                            .font(.system(size: Typography.bodySmall, weight: .semibold).monospacedDigit())
                            .foregroundStyle(.white)
                    }
                    Text("Stop Recording")
                        .font(.system(size: Typography.bodySmall, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Capsule().fill(StatusColor.error))
            }
            .buttonStyle(.plain)
        } else if appState.activeMeetingSession == nil {
            Button(action: startRecording) {
                HStack(spacing: 5) {
                    Circle().fill(StatusColor.error).frame(width: 7, height: 7)
                    Text("Record")
                        .font(.system(size: Typography.caption, weight: .medium))
                        .foregroundStyle(.primary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .overlay(
                    Capsule().strokeBorder(Color.primary.opacity(Opacity.medium), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
        }
    }

    private var participantsPill: some View {
        propertyChip(icon: "person.2", text: cachedParticipants.joined(separator: ", "))
    }

    private func propertyChip(icon: String, text: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Text(text)
                .font(.system(size: Typography.caption, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .overlay(
            Capsule().strokeBorder(Color.primary.opacity(Opacity.medium), lineWidth: 1)
        )
    }

    // MARK: - Formatters

    private static let pillDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d, h:mm a"
        f.timeZone = .current
        return f
    }()

    // MARK: - Actions

    private func startRecording() {
        guard let filePath = document.filePath else { return }
        let session = ActiveMeetingSession(meetingPagePath: filePath)
        appState.activeMeetingSession = session
        appState.isRecording = true

        Task {
            await transcriptionService.startRecording()

            // Poll transcript and audio level. Each property write goes through an
            // @Observable session, so we guard each one to avoid spurious 10Hz invalidations.
            var lastSegmentCount = 0
            var lastVolatile = ""
            var lastLevel: Float = -1
            var lastNotice = ""
            while transcriptionService.isRecording {
                let level = transcriptionService.audioLevel
                if level != lastLevel {
                    lastLevel = level
                    session.audioLevel = level
                }

                let segmentCount = transcriptionService.confirmedSegments.count
                if segmentCount != lastSegmentCount {
                    lastSegmentCount = segmentCount
                    session.confirmedSegments = transcriptionService.confirmedSegments
                }

                let volatile = transcriptionService.volatileText
                if volatile != lastVolatile {
                    lastVolatile = volatile
                    session.volatileText = volatile
                }

                let notice = transcriptionService.error ?? ""
                if !notice.isEmpty, notice != lastNotice {
                    lastNotice = notice
                    showRecordingNotice(notice)
                }

                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }

    private func stopRecording() {
        recordingNoticeTask?.cancel()
        recordingNoticeTask = nil
        recordingNotice = nil

        let fullText = transcriptionService.stopRecording()
        appState.isRecording = false

        guard let session = appState.activeMeetingSession else {
            appState.activeMeetingSession = nil
            return
        }

        // Read directly from the transcription service to capture any segments
        // that were flushed synchronously by stopRecording() after the last poll tick.
        let finalSegments = transcriptionService.confirmedSegments

        // Save the transcript entries to the sidecar store
        if !finalSegments.isEmpty,
           let id = cachedMeetingId,
           let workspace = appState.workspacePath {
            let entries = finalSegments.map { MeetingTranscriptEntry(text: $0) }
            transcript = MeetingTranscript(
                entries: entries,
                summary: transcript.summary,
                actionItems: transcript.actionItems,
                createdAt: session.startDate
            )
            transcriptStore.save(transcript, meetingId: id, workspace: workspace)
        }

        // Update frontmatter with duration
        let duration = Int(Date().timeIntervalSince(session.startDate))
        updateFrontmatterDuration(duration)
        onTextChange()

        // Clear the session so isRecording and pill state are consistent
        appState.activeMeetingSession = nil

        // Auto-generate summary in the background
        if !fullText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            startSummaryGeneration(with: fullText)
        }
    }

    private func showRecordingNotice(_ message: String) {
        recordingNotice = message
        recordingNoticeTask?.cancel()
        recordingNoticeTask = Task {
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled else { return }
            recordingNotice = nil
        }
    }

    private func retrySummaryGeneration() {
        startSummaryGeneration(with: summaryInputText)
    }

    private func startSummaryGeneration(with input: String) {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            summaryError = "Add a transcript or notes before generating a summary."
            return
        }

        summaryError = nil
        isGeneratingSummary = true
        Task {
            do {
                try await generateSummary(transcript: trimmed)
                summaryError = nil
            } catch {
                summaryError = error.localizedDescription
            }
            isGeneratingSummary = false
        }
    }

    private var summaryInputText: String {
        let transcriptText = transcript.fullText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !transcriptText.isEmpty {
            return transcriptText
        }

        let titleID = document.titleBlock?.id
        let generatedIDs = Set(transcript.generatedBlockIds)
        return document.blocks
            .filter { block in
                block.id != titleID && !generatedIDs.contains(block.id)
            }
            .map(\.text)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    private func updateFrontmatterDuration(_ seconds: Int) {
        let minutes = seconds / 60
        var yaml = document.yamlFrontmatter
        if yaml.contains("duration:") {
            yaml = yaml.replacingOccurrences(
                of: #"duration:.*"#,
                with: "duration: \(minutes)m",
                options: .regularExpression
            )
        } else {
            yaml += "\nduration: \(minutes)m"
        }
        document.yamlFrontmatter = yaml
    }

    private func generateSummary(transcript: String) async throws {
        let prompt = """
        Summarize this meeting transcript. Output in this exact format with no preamble:

        TITLE: <a short, descriptive meeting title (max 8 words)>

        SUMMARY:
        - <key bullet 1>
        - <key bullet 2>
        - <key bullet 3>

        ACTION ITEMS:
        - <action item 1>
        - <action item 2>

        Rules:
        - Title is one line, no quotes, no trailing punctuation.
        - Summary bullets are short (one sentence each), capturing the main points discussed.
        - Action items are concrete tasks or follow-ups. Omit the section if there are none.
        - Do not include any text outside these three sections.

        Transcript:
        \(transcript)
        """

        // Run the CLI process off the main thread to avoid blocking the UI.
        // Use a login shell so the user's PATH (including ~/.local/bin) is loaded.
        let output: String = try await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-l", "-c", "claude --model haiku -p"]

            let inputPipe = Pipe()
            let outputPipe = Pipe()
            let errorPipe = Pipe()
            process.standardInput = inputPipe
            process.standardOutput = outputPipe
            process.standardError = errorPipe

            try process.run()

            if let data = prompt.data(using: .utf8) {
                inputPipe.fileHandleForWriting.write(data)
            }
            try? inputPipe.fileHandleForWriting.close()

            process.waitUntilExit()

            let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            if process.terminationStatus != 0 {
                let message = String(data: errorData, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                throw MeetingSummaryGenerationError.commandFailed(message)
            }

            guard let output = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                  !output.isEmpty else {
                throw MeetingSummaryGenerationError.emptyOutput
            }
            return output
        }.value

        let parsed = parseSummaryOutput(output)
        guard parsed.sawSummarySection, !parsed.summary.isEmpty else {
            throw MeetingSummaryGenerationError.missingSummary
        }

        // Persist on the transcript sidecar for future reference
        self.transcript.summary = parsed.summary
        self.transcript.actionItems = parsed.actionItems

        // Apply title to the empty H1 title block, and inject summary + action items as document blocks
        applyGeneratedTitle(parsed.title)
        injectSummaryAndActionsBlocks(summary: parsed.summary, actionItems: parsed.actionItems)

        if let id = cachedMeetingId, let workspace = appState.workspacePath {
            transcriptStore.save(self.transcript, meetingId: id, workspace: workspace)
        }

        onTextChange()
    }

    private func parseSummaryOutput(_ output: String) -> (title: String?, summary: [String], actionItems: [String], sawSummarySection: Bool) {
        var title: String?
        var summary: [String] = []
        var actionItems: [String] = []
        var inSummary = false
        var inActions = false
        var sawSummarySection = false

        for line in output.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("TITLE:") {
                let value = String(trimmed.dropFirst(6))
                    .trimmingCharacters(in: CharacterSet(charactersIn: " \"'"))
                if !value.isEmpty { title = value }
                inSummary = false
                inActions = false
                continue
            }
            if trimmed.hasPrefix("SUMMARY:") {
                inSummary = true
                inActions = false
                sawSummarySection = true
                continue
            }
            if trimmed.hasPrefix("ACTION ITEMS:") {
                inSummary = false
                inActions = true
                continue
            }
            if trimmed.hasPrefix("- ") {
                let item = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                guard !item.isEmpty else { continue }
                if inSummary {
                    summary.append(item)
                } else if inActions {
                    actionItems.append(item)
                }
            }
        }

        return (title, summary, actionItems, sawSummarySection)
    }

    // MARK: - Document Mutation

    /// Set the H1 title block to the AI-generated title if it's currently empty.
    private func applyGeneratedTitle(_ title: String?) {
        guard let title, !title.isEmpty,
              let titleBlock = document.titleBlock,
              titleBlock.text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        document.updateBlockProperty(id: titleBlock.id) { block in
            block.text = title
        }
    }

    /// Insert (or replace) the Summary and Action Items sections in the document body.
    /// Idempotent: previously-generated blocks are tracked by ID in the transcript sidecar
    /// and removed before fresh ones are inserted. This is robust to the user renaming the
    /// section headings.
    private func injectSummaryAndActionsBlocks(summary: [String], actionItems: [String]) {
        // Remove blocks from any previous generation by ID
        let staleIds = Set(transcript.generatedBlockIds)
        if !staleIds.isEmpty {
            document.blocks.removeAll { staleIds.contains($0.id) }
        }

        // Build the new blocks and capture their IDs
        var newBlocks: [Block] = []
        if !summary.isEmpty {
            newBlocks.append(Block(type: .heading, text: "Summary", headingLevel: 2))
            for bullet in summary {
                newBlocks.append(Block(type: .bulletListItem, text: bullet))
            }
        }
        if !actionItems.isEmpty {
            newBlocks.append(Block(type: .heading, text: "Action Items", headingLevel: 2))
            for item in actionItems {
                newBlocks.append(Block(type: .taskItem, text: item))
            }
        }

        transcript.generatedBlockIds = newBlocks.map(\.id)
        guard !newBlocks.isEmpty else { return }
        document.blocks.append(contentsOf: newBlocks)
    }
}

// MARK: - Pulsing Record Dot (reused from MeetingsView)

struct PulsingRecordDot: View {
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
