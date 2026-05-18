import SwiftUI

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
    var onMeetingFinalized: () -> Void = {}

    private let summaryService = MeetingSummaryService()

    @State private var transcript: MeetingTranscript = MeetingTranscript()
    @State private var isTranscriptExpanded = false
    @State private var transcriptSearch = ""
    @State private var copyConfirmation = false
    @State private var isGeneratingSummary = false
    @State private var isStartingRecording = false
    @State private var isStoppingRecording = false
    @State private var summaryError: String?
    @State private var recordingNotice: String?
    @State private var recordingNoticeTask: Task<Void, Never>?
    @State private var profileAutoStopTask: Task<Void, Never>?

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

    private func refreshCachedFrontmatter() {
        let yaml = document.yamlFrontmatter
        cachedParticipants = MeetingFrontmatter.parseParticipants(from: yaml)
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
                            MeetingRecordingNoticeToast(message: recordingNotice)
                        }
                        MeetingTranscriptWidget(
                            entries: displayedTranscriptEntries,
                            volatileText: activeVolatileTranscript,
                            isRecording: isRecordingThisPage,
                            isExpanded: $isTranscriptExpanded,
                            searchText: $transcriptSearch,
                            copyConfirmation: $copyConfirmation
                        )
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
            stopPendingRecordingIfNeeded()
        }
        .onChange(of: document.yamlFrontmatter) { _, _ in
            refreshCachedFrontmatter()
        }
        .onChange(of: appState.activeMeetingSession?.stopRequested) { _, _ in
            stopPendingRecordingIfNeeded()
        }
        .onReceive(NotificationCenter.default.publisher(for: .stopMeetingRecording)) { _ in
            if isRecordingThisPage {
                stopRecording()
            }
        }
        .onDisappear {
            recordingNoticeTask?.cancel()
            recordingNoticeTask = nil
            profileAutoStopTask?.cancel()
            profileAutoStopTask = nil
        }
    }

    private func loadTranscriptIfNeeded() {
        // Skip if already loaded (in-memory transcript has data) or no meeting id
        guard transcript.entries.isEmpty, transcript.summary.isEmpty,
              let id = cachedMeetingId,
              let workspace = appState.workspacePath else { return }

        let store = transcriptStore
        Task {
            let loaded = await store.loadAsync(meetingId: id, workspace: workspace)
            guard !Task.isCancelled else { return }
            self.transcript = loaded
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

    private var displayedTranscriptEntries: [MeetingTranscriptEntry] {
        if let session = appState.activeMeetingSession, isRecordingThisPage {
            return session.confirmedSegments.map { MeetingTranscriptEntry(text: $0) }
        }
        return transcript.entries
    }

    private var activeVolatileTranscript: String {
        guard isRecordingThisPage, let session = appState.activeMeetingSession else { return "" }
        return session.volatileText
    }

    private var propertyPills: some View {
        MeetingPagePropertyPills(
            date: cachedMeetingDate ?? Date(),
            participants: cachedParticipants,
            activeSession: isRecordingThisPage ? appState.activeMeetingSession : nil,
            canStartRecording: appState.activeMeetingSession == nil && !isStartingRecording,
            isStartingRecording: isStartingRecording,
            isStoppingRecording: isStoppingRecording,
            showsManualSummaryButton: shouldShowManualSummaryButton,
            hasSummaryContent: hasSummaryContent,
            onStartRecording: startRecording,
            onStopRecording: stopRecording,
            onGenerateSummary: retrySummaryGeneration
        )
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

    private var shouldShowManualSummaryButton: Bool {
        appState.settings.meetingSummaryEnabled && !isRecordingThisPage && !isGeneratingSummary && summaryError == nil
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

    // MARK: - Actions

    private func stopPendingRecordingIfNeeded() {
        guard let session = appState.activeMeetingSession,
              session.meetingPagePath == document.filePath,
              session.stopRequested else { return }
        session.stopRequested = false
        if isRecordingThisPage {
            stopRecording()
        }
    }

    private func startRecording() {
        guard !isStartingRecording else { return }
        guard !isStoppingRecording else { return }
        guard let filePath = document.filePath else { return }
        isStartingRecording = true

        Task {
            let signpostState = Log.signpost.beginInterval("meetingRecordingStart")
            await transcriptionService.startRecording()
            Log.signpost.endInterval("meetingRecordingStart", signpostState)

            guard transcriptionService.isRecording else {
                isStartingRecording = false
                appState.isRecording = false
                appState.activeMeetingSession = nil
                let message = transcriptionService.error ?? "Recording did not start."
                showRecordingNotice(message)
                return
            }

            let session = ActiveMeetingSession(meetingPagePath: filePath)
            appState.activeMeetingSession = session
            appState.isRecording = true
            isStartingRecording = false
            Log.profileMarker("meetingRecordingStart")
            Log.profileMarker("meetingRecordingActive")
            scheduleProfileAutoStopIfNeeded(for: filePath)

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
        guard !isStoppingRecording else { return }
        profileAutoStopTask?.cancel()
        profileAutoStopTask = nil
        recordingNoticeTask?.cancel()
        recordingNoticeTask = nil
        recordingNotice = nil

        guard let session = appState.activeMeetingSession else {
            appState.isRecording = false
            appState.activeMeetingSession = nil
            return
        }

        isStoppingRecording = true
        Task {
            Log.profileMarker("meetingRecordingStopFinalize")
            let signpostState = Log.signpost.beginInterval("meetingRecordingStopFinalize")
            defer { Log.signpost.endInterval("meetingRecordingStopFinalize", signpostState) }
            let result = await transcriptionService.stopRecordingAndWaitForFinalTranscript()
            await finalizeStoppedRecording(result, session: session)
            isStoppingRecording = false
        }
    }

    private func scheduleProfileAutoStopIfNeeded(for filePath: String) {
        let rawValue = ProcessInfo.processInfo.environment["BUGBOOK_PROFILE_AUTO_STOP_RECORDING_AFTER_SECONDS"] ?? ""
        guard let seconds = Double(rawValue), seconds > 0 else { return }

        profileAutoStopTask?.cancel()
        profileAutoStopTask = Task {
            let milliseconds = Int((seconds * 1_000).rounded())
            try? await Task.sleep(for: .milliseconds(milliseconds))
            guard !Task.isCancelled,
                  appState.activeMeetingSession?.meetingPagePath == filePath,
                  !isStoppingRecording else { return }
            stopRecording()
        }
    }

    private func finalizeStoppedRecording(_ result: LiveRecordingStopResult, session: ActiveMeetingSession) async {
        // Read directly from the transcription service to capture any segments
        // that were flushed synchronously by stopRecording() after the last poll tick.
        let recordedAt = Date()
        let transcriptLines = MeetingRecordingDocumentFinalizer.finalize(
            document: document,
            finalSegments: result.confirmedSegments,
            fallbackText: result.fullText,
            startDate: session.startDate,
            recordedAt: recordedAt
        )

        // Save the transcript entries to the sidecar store and keep the post-meeting
        // transcript widget copyable even when the ASR backend only returns fallback text.
        if !transcriptLines.isEmpty {
            let entries = transcriptLines.map { MeetingTranscriptEntry(text: $0) }
            transcript = MeetingTranscript(
                entries: entries,
                summary: transcript.summary,
                actionItems: transcript.actionItems,
                createdAt: session.startDate
            )
            if let id = cachedMeetingId,
               let workspace = appState.workspacePath {
                let transcriptSnapshot = transcript
                let store = transcriptStore
                let signpostState = Log.signpost.beginInterval("meetingTranscriptPersist")
                await store.saveAsync(transcriptSnapshot, meetingId: id, workspace: workspace)
                Log.signpost.endInterval("meetingTranscriptPersist", signpostState)
                Log.profileMarker("meetingTranscriptPersist")
            }
        }

        onTextChange()

        // Clear the session so isRecording and pill state are consistent
        appState.isRecording = false
        appState.activeMeetingSession = nil

        // Auto-generate summary in the background
        if appState.settings.meetingSummaryEnabled,
           !result.fullText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            startSummaryGeneration(with: result.fullText)
        }

        onMeetingFinalized()
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

    private var summaryCommand: String {
        let command = appState.settings.meetingSummaryCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        return command.isEmpty ? AppSettings.default.meetingSummaryCommand : command
    }

    private func generateSummary(transcript: String) async throws {
        let signpostState = Log.signpost.beginInterval("meetingSummaryGenerate")
        defer { Log.signpost.endInterval("meetingSummaryGenerate", signpostState) }

        let command = summaryCommand
        let result = try await summaryService.generateSummary(transcript: transcript, command: command)

        // Persist on the transcript sidecar for future reference
        self.transcript.summary = result.summary
        self.transcript.actionItems = result.actionItems

        // Apply title to the empty H1 title block, and inject summary + action items as document blocks
        applyGeneratedTitle(result.title)
        injectSummaryAndActionsBlocks(summary: result.summary, actionItems: result.actionItems)

        if let id = cachedMeetingId, let workspace = appState.workspacePath {
            await transcriptStore.saveAsync(self.transcript, meetingId: id, workspace: workspace)
        }

        onTextChange()
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
