import SwiftUI
import AppKit

/// Meeting block view with three states: ready (before recording), recording (during),
/// and complete (after). Uses the same card shell across all states. Preserves dev's
/// AI summary generation, transcript sheet, and structured output parsing.
struct MeetingBlockView: View {
    var document: BlockDocument
    let block: Block

    @State private var title: String
    @State private var isTranscriptOpen = false
    @State private var transcriptSearch = ""
    @State private var isSearchingTranscript = false
    @State private var isSummaryExpanded = false
    @State private var activeTab: MeetingTab = .summary
    @State private var isHovered = false
    private var hasVoiceActivity: Bool { document.meetingAudioLevel > 0.01 }

    // Dev's AI processing state
    @State private var isProcessing = false
    @State private var processingStatus = ""
    @State private var showTranscriptSheet = false

    enum MeetingTab {
        case summary
        case notes
    }

    init(document: BlockDocument, block: Block) {
        self.document = document
        self.block = block
        _title = State(initialValue: block.meetingTitle)
    }

    var body: some View {
        VStack(spacing: 0) {
            switch block.meetingState {
            case .ready:
                beforeStateView
            case .recording:
                duringStateView
            case .processing:
                processingStateView
            case .complete:
                afterStateView
            }
        }
        .background(
            RoundedRectangle(cornerRadius: Radius.lg)
                .fill(Color.fallbackCardBg)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg)
                .strokeBorder(Color.fallbackBorderColor, lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: Radius.lg))
        .onHover { isHovered = $0 }
        .padding(.vertical, 4)
        .sheet(isPresented: $showTranscriptSheet) {
            TranscriptBubbleView(
                transcript: block.meetingTranscript,
                meetingNotes: block.meetingNotes
            )
        }
    }

    // MARK: - Before State (Ready)

    private var beforeStateView: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                TextField("New Meeting", text: $title)
                    .textFieldStyle(.plain)
                    .font(.system(size: Typography.title3, weight: .semibold))
                    .foregroundStyle(Color.fallbackTextPrimary)
                    .onChange(of: title) { _, newVal in
                        document.updateMeetingTitle(blockId: block.id, title: newVal)
                    }

                Spacer()

                Button(action: startRecording) {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 8, height: 8)
                        Text("Record")
                            .font(.system(size: Typography.bodySmall, weight: .medium))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.red.opacity(Opacity.medium))
                    .foregroundStyle(Color.red)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
                }
                .buttonStyle(.borderless)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            meetingNotesChildBlocks
                .frame(minHeight: 80)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
        }
    }

    // MARK: - During State (Recording)

    private var duringStateView: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                PulsingDot()

                TextField("New Meeting", text: $title)
                    .textFieldStyle(.plain)
                    .font(.system(size: Typography.title3, weight: .semibold))
                    .foregroundStyle(Color.fallbackTextPrimary)
                    .onChange(of: title) { _, newVal in
                        document.updateMeetingTitle(blockId: block.id, title: newVal)
                    }

                Spacer()

                ladybugButton

                Button(action: stopRecording) {
                    HStack(spacing: 5) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.white)
                            .frame(width: 8, height: 8)
                        Text("Stop")
                            .font(.system(size: Typography.bodySmall, weight: .medium))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.red)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
                }
                .buttonStyle(.borderless)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            meetingNotesChildBlocks
                .frame(minHeight: 160)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)

            Divider()

            bottomBar(showWaveform: true)

            if isTranscriptOpen {
                transcriptDrawer
            }
        }
    }

    // MARK: - Processing State

    private var processingStateView: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text(block.meetingTitle.isEmpty ? "Meeting" : block.meetingTitle)
                    .font(.system(size: Typography.title3, weight: .semibold))
                    .foregroundStyle(Color.fallbackTextPrimary)

                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text(processingStatus.isEmpty ? "Processing..." : processingStatus)
                    .font(.system(size: Typography.bodySmall))
                    .foregroundStyle(Color.fallbackTextSecondary)
            }
            .padding(.vertical, 20)
        }
    }

    // MARK: - After State (Complete)

    private var afterStateView: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(block.meetingTitle.isEmpty ? "Meeting" : block.meetingTitle)
                        .font(.system(size: Typography.title3, weight: .semibold))
                        .foregroundStyle(Color.fallbackTextPrimary)
                }

                Spacer()

                ladybugButton

                // Generate summary button (only when no summary exists)
                if parseSections(block.language).isEmpty && block.meetingActionItems.isEmpty && block.meetingSummary.isEmpty && (!block.meetingTranscript.isEmpty || !block.meetingNotes.isEmpty || !block.children.isEmpty) {
                    Button {
                        Task { await generateSummary() }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 10))
                            Text("Generate")
                                .font(.system(size: Typography.caption, weight: .medium))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.primary.opacity(Opacity.subtle))
                        .clipShape(RoundedRectangle(cornerRadius: Radius.xs))
                    }
                    .buttonStyle(.borderless)
                }

                // Expand button (hover only)
                if isHovered {
                    Button(action: { withAnimation(.easeInOut(duration: 0.25)) { isSummaryExpanded.toggle() } }) {
                        Image(systemName: isSummaryExpanded ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.fallbackTextSecondary)
                            .frame(width: 24, height: 24)
                            .background(Color.primary.opacity(Opacity.subtle))
                            .clipShape(RoundedRectangle(cornerRadius: Radius.xs))
                    }
                    .buttonStyle(.borderless)
                    .transition(.opacity)
                }

                // Summary/Notes tab picker
                Picker("", selection: $activeTab) {
                    Text("Summary").tag(MeetingTab.summary)
                    Text("Notes").tag(MeetingTab.notes)
                }
                .pickerStyle(.segmented)
                .frame(width: 140)

                Button(action: resumeRecording) {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 8, height: 8)
                        Text("Resume")
                            .font(.system(size: Typography.bodySmall, weight: .medium))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.red.opacity(Opacity.medium))
                    .foregroundStyle(Color.red)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
                }
                .buttonStyle(.borderless)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            // Content area: Summary or Notes
            switch activeTab {
            case .summary:
                summaryView
            case .notes:
                notesView
            }

            Divider()

            bottomBar(showWaveform: false)

            if isTranscriptOpen {
                transcriptDrawer
            }
        }
    }

    // MARK: - Summary View

    private var summaryView: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    // Parse structured summary from the language field (dev convention)
                    let sections = parseSections(block.language)

                    if !sections.isEmpty {
                        ForEach(Array(sections.enumerated()), id: \.offset) { _, section in
                            VStack(alignment: .leading, spacing: 4) {
                                if !section.heading.isEmpty {
                                    Text(section.heading)
                                        .font(.system(size: Typography.bodySmall, weight: .semibold))
                                        .foregroundStyle(Color.fallbackTextPrimary)
                                }
                                ForEach(Array(section.items.enumerated()), id: \.offset) { _, item in
                                    if item.isActionItem {
                                        HStack(alignment: .top, spacing: 6) {
                                            Image(systemName: "square")
                                                .font(.system(size: 12))
                                                .foregroundStyle(Color.fallbackTextSecondary)
                                                .padding(.top, 2)
                                            Text(item.text)
                                                .font(.system(size: Typography.bodySmall))
                                                .foregroundStyle(Color.fallbackTextPrimary)
                                        }
                                    } else if item.isUserNote {
                                        Text(item.text)
                                            .font(.system(size: Typography.bodySmall).italic())
                                            .foregroundStyle(Color.accentColor)
                                            .padding(.leading, 8)
                                    } else if item.isSummaryText {
                                        Text(item.text)
                                            .font(.system(size: Typography.bodySmall))
                                            .foregroundStyle(Color.fallbackTextSecondary)
                                    } else {
                                        HStack(alignment: .top, spacing: 6) {
                                            Text("\u{2022}")
                                                .foregroundStyle(Color.fallbackTextSecondary)
                                            Text(item.text)
                                                .font(.system(size: Typography.bodySmall))
                                                .foregroundStyle(Color.fallbackTextPrimary)
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Action items from dedicated field
                    if !block.meetingActionItems.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Action Items")
                                .font(.system(size: Typography.bodySmall, weight: .semibold))
                                .foregroundStyle(Color.fallbackTextPrimary)

                            ForEach(parseActionItems(block.meetingActionItems), id: \.self) { item in
                                HStack(alignment: .top, spacing: 6) {
                                    Image(systemName: "square")
                                        .font(.system(size: 12))
                                        .foregroundStyle(Color.fallbackTextSecondary)
                                        .padding(.top, 2)
                                    Text(item)
                                        .font(.system(size: Typography.bodySmall))
                                        .foregroundStyle(Color.fallbackTextPrimary)
                                }
                            }
                        }
                    }

                    if sections.isEmpty && block.meetingActionItems.isEmpty && block.meetingSummary.isEmpty {
                        // Generate button when no summary exists yet
                        if !block.meetingTranscript.isEmpty || !block.meetingNotes.isEmpty {
                            Button {
                                Task { await generateSummary() }
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "ladybug.fill")
                                        .font(.system(size: 12))
                                    Text("Generate Summary")
                                        .font(.system(size: Typography.bodySmall, weight: .medium))
                                }
                                .foregroundStyle(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(RoundedRectangle(cornerRadius: 6).fill(Color.accentColor))
                            }
                            .buttonStyle(.plain)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 12)
                        } else {
                            Text("No summary generated yet.")
                                .font(.system(size: Typography.bodySmall))
                                .foregroundStyle(Color.fallbackTextMuted)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.vertical, 20)
                        }
                    }
                }
                .padding(14)
            }
            .frame(maxHeight: isSummaryExpanded ? nil : 200)
            .clipped()

            if !isSummaryExpanded {
                LinearGradient(
                    colors: [Color.fallbackCardBg.opacity(0), Color.fallbackCardBg],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 40)
                .allowsHitTesting(false)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: isSummaryExpanded)
    }

    // MARK: - Notes View

    private var notesView: some View {
        VStack(alignment: .leading, spacing: 0) {
            if block.children.isEmpty && block.meetingNotes.isEmpty {
                Text("No notes recorded.")
                    .font(.system(size: Typography.bodySmall))
                    .foregroundStyle(Color.fallbackTextMuted)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            } else if block.children.isEmpty {
                // Legacy plain-text notes (backwards compat)
                Text(block.meetingNotes)
                    .font(.system(size: Typography.bodySmall))
                    .foregroundStyle(Color.fallbackTextPrimary)
                    .textSelection(.enabled)
                    .padding(14)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(block.children) { child in
                        BlockCellView(document: document, block: child)
                            .padding(.vertical, 1)
                    }
                }
                .padding(14)
            }
        }
    }

    // MARK: - Bottom Bar

    private func bottomBar(showWaveform: Bool) -> some View {
        Button(action: {
            withAnimation(.easeInOut(duration: 0.25)) {
                isTranscriptOpen.toggle()
            }
            if isTranscriptOpen {
                document.scrollToBlockId = block.id
            }
        }) {
            HStack(spacing: 8) {
                if showWaveform {
                    WaveformView(isActive: block.meetingState == .recording, phase: 0)
                        .frame(width: 40, height: 16)
                } else {
                    Text("Transcript")
                        .font(.system(size: Typography.caption, weight: .medium))
                        .foregroundStyle(Color.fallbackTextSecondary)
                }

                Spacer()

                if isTranscriptOpen {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(isSearchingTranscript ? Color.accentColor : Color.fallbackTextSecondary)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                        .highPriorityGesture(TapGesture().onEnded {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isSearchingTranscript.toggle()
                                if !isSearchingTranscript { transcriptSearch = "" }
                            }
                        })

                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.fallbackTextSecondary)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                        .highPriorityGesture(TapGesture().onEnded {
                            let entries = !block.transcriptEntries.isEmpty
                                ? block.transcriptEntries
                                : block.meetingTranscript.components(separatedBy: "\n").filter { !$0.isEmpty }
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(entries.joined(separator: "\n\n"), forType: .string)
                        })
                        .help("Copy transcript")
                } else if !showWaveform && !block.meetingTranscript.isEmpty {
                    Text("\(block.meetingTranscript.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.count) words")
                        .font(.system(size: Typography.caption))
                        .foregroundStyle(Color.fallbackTextMuted)
                }

                Image(systemName: isTranscriptOpen ? "chevron.down" : "chevron.up")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.fallbackTextSecondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            Color.primary.opacity(Opacity.subtle),
            in: UnevenRoundedRectangle(
                bottomLeadingRadius: isTranscriptOpen ? 0 : Radius.lg,
                bottomTrailingRadius: isTranscriptOpen ? 0 : Radius.lg
            )
        )
    }

    // MARK: - Transcript Drawer

    private var transcriptDrawer: some View {
        VStack(spacing: 0) {
            Divider()

            if isSearchingTranscript {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    TextField("Search transcript...", text: $transcriptSearch)
                        .textFieldStyle(.plain)
                        .font(.system(size: Typography.bodySmall))
                    if !transcriptSearch.isEmpty {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                            .onTapGesture { transcriptSearch = "" }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.primary.opacity(Opacity.subtle))
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    let allEntries = !block.transcriptEntries.isEmpty
                        ? block.transcriptEntries
                        : block.meetingTranscript.components(separatedBy: "\n").filter { !$0.isEmpty }
                    let entries = transcriptSearch.isEmpty
                        ? allEntries
                        : allEntries.filter { $0.localizedCaseInsensitiveContains(transcriptSearch) }

                    ForEach(Array(entries.enumerated()), id: \.offset) { _, entry in
                        Text(entry)
                            .font(.system(size: Typography.caption2))
                            .foregroundStyle(Color.fallbackTextPrimary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.primary.opacity(Opacity.light))
                            .clipShape(RoundedRectangle(cornerRadius: Radius.md))
                    }

                    if block.meetingState == .recording {
                        HStack(spacing: 4) {
                            ProgressView()
                                .controlSize(.mini)
                            Text("Listening...")
                                .font(.system(size: Typography.caption2))
                                .foregroundStyle(Color.fallbackTextMuted)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                    }
                }
                .padding(10)
            }
            .frame(maxHeight: 400)
        }
        .transition(.asymmetric(
            insertion: .push(from: .bottom).combined(with: .opacity),
            removal: .push(from: .top).combined(with: .opacity)
        ))
    }

    // MARK: - Ladybug AI Button

    private var ladybugButton: some View {
        Button(action: openAiWithContext) {
            Image("BugbookAI")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 20, height: 20)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.borderless)
        .help("Ask AI about this meeting")
    }

    // MARK: - Meeting Notes (Child Blocks)

    private var meetingNotesChildBlocks: some View {
        VStack(alignment: .leading, spacing: 0) {
            if block.children.isEmpty {
                Text("Write notes...")
                    .font(.system(size: Typography.body))
                    .foregroundStyle(Color.fallbackTextMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture { addChild() }
            } else {
                ForEach(block.children) { child in
                    BlockCellView(document: document, block: child)
                        .padding(.vertical, 1)
                }
            }
        }
    }

    private func addChild() {
        guard let idx = document.index(for: block.id) else { return }
        let newChild = Block(type: .paragraph)
        document.blocks[idx].children.append(newChild)
        document.focusedBlockId = newChild.id
        document.cursorPosition = 0
    }

    // MARK: - Actions

    private func startRecording() {
        document.updateMeetingState(blockId: block.id, state: .recording)
    }

    private func stopRecording() {
        document.updateMeetingState(blockId: block.id, state: .complete)
    }

    private func resumeRecording() {
        document.updateMeetingState(blockId: block.id, state: .recording)
    }

    private func openAiWithContext() {
        NotificationCenter.default.post(name: .openAIPanel, object: nil)
    }

    // MARK: - Helpers

    private func parseActionItems(_ raw: String) -> [String] {
        raw.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .map { line in
                // Strip common prefixes like "- [ ] ", "- ", "[] "
                var s = line
                if s.hasPrefix("- [ ] ") { s = String(s.dropFirst(6)) }
                else if s.hasPrefix("- ") { s = String(s.dropFirst(2)) }
                return s
            }
            .filter { !$0.isEmpty }
    }

    // MARK: - AI Summary Generation (from dev)

    private func generateSummary() async {
        let transcript = block.meetingTranscript
        let userNotes = block.children.isEmpty
            ? block.meetingNotes
            : block.children.map { $0.text }.joined(separator: "\n")

        document.updateMeetingState(blockId: block.id, state: .processing)
        isProcessing = true

        if !transcript.isEmpty {
            processingStatus = "Cleaning transcript..."
            let cleanedTranscript = await cleanTranscript(transcript)
            let cleaned = cleanedTranscript ?? transcript
            document.updateBlockText(id: block.id, text: cleaned)

            processingStatus = "Extracting meeting sections..."
            let structured = await extractStructuredSections(transcript: cleaned, notes: userNotes)
            if let structured {
                document.updateMeetingSummary(blockId: block.id, summary: structured)
            }
        } else if !userNotes.isEmpty {
            processingStatus = "Generating summary from notes..."
            let structured = await extractStructuredSections(transcript: "", notes: userNotes)
            if let structured {
                document.updateMeetingSummary(blockId: block.id, summary: structured)
            }
        }

        isProcessing = false
        processingStatus = ""
        document.updateMeetingState(blockId: block.id, state: .complete)
    }

    private func cleanTranscript(_ raw: String) async -> String? {
        let prompt = "Clean up this transcript: remove filler words (uh, um, like, you know), fix punctuation, add sentence breaks. Output only cleaned text:\n\n\(raw)"
        return await runClaude(prompt: prompt)
    }

    private func extractStructuredSections(transcript: String, notes: String) async -> String? {
        var prompt = """
        Given this meeting content, extract a structured meeting summary. Format your response EXACTLY like this:

        ## Title
        <auto-generated title from content>

        ## Key Topics
        ### <topic name>
        - bullet point
        - bullet point

        ## Action Items
        - [ ] action item 1
        - [ ] action item 2
        """

        if !notes.isEmpty {
            prompt += """

            The user took these notes during the meeting. Integrate them inline under the relevant topics, prefixed with [NOTE]:

            \(notes)
            """
        }

        if !transcript.isEmpty {
            prompt += """

        Transcript:
        \(transcript)
        """
        }

        return await runClaude(prompt: prompt)
    }

    private func runClaude(prompt: String) async -> String? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/bin/zsh")
                let escaped = prompt.replacingOccurrences(of: "'", with: "'\"'\"'")
                process.arguments = ["-l", "-c", "claude --model haiku --print '\(escaped)'"]
                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = pipe
                do {
                    try process.run()
                    process.waitUntilExit()
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    let output = String(data: data, encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    continuation.resume(returning: process.terminationStatus == 0 ? output : nil)
                } catch {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    // MARK: - Section Parsing (from dev)

    private struct MeetingSection {
        var heading: String
        var items: [MeetingItem]
    }

    private struct MeetingItem {
        var text: String
        var isActionItem: Bool
        var isUserNote: Bool
        var isSummaryText: Bool
    }

    private func parseSections(_ raw: String) -> [MeetingSection] {
        guard !raw.isEmpty else { return [] }
        var sections: [MeetingSection] = []
        var currentHeading = ""
        var currentItems: [MeetingItem] = []

        for line in raw.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("<!--") && trimmed.hasSuffix("-->") {
                continue
            }

            if trimmed.hasPrefix("## ") || trimmed.hasPrefix("### ") {
                if !currentHeading.isEmpty || !currentItems.isEmpty {
                    sections.append(MeetingSection(heading: currentHeading, items: currentItems))
                    currentItems = []
                }
                currentHeading = trimmed
                    .replacingOccurrences(of: "### ", with: "")
                    .replacingOccurrences(of: "## ", with: "")
            } else if trimmed.hasPrefix("- [ ] ") {
                let text = String(trimmed.dropFirst(6))
                currentItems.append(MeetingItem(text: text, isActionItem: true, isUserNote: false, isSummaryText: false))
            } else if trimmed.hasPrefix("[NOTE]") {
                let text = trimmed.replacingOccurrences(of: "[NOTE] ", with: "")
                    .replacingOccurrences(of: "[NOTE]", with: "")
                currentItems.append(MeetingItem(text: text, isActionItem: false, isUserNote: true, isSummaryText: false))
            } else if trimmed.hasPrefix("- ") {
                let text = String(trimmed.dropFirst(2))
                let isNote = text.hasPrefix("[NOTE]")
                let cleanText = isNote
                    ? text.replacingOccurrences(of: "[NOTE] ", with: "").replacingOccurrences(of: "[NOTE]", with: "")
                    : text
                currentItems.append(MeetingItem(text: cleanText, isActionItem: false, isUserNote: isNote, isSummaryText: false))
            } else if !trimmed.isEmpty {
                currentItems.append(MeetingItem(text: trimmed, isActionItem: false, isUserNote: false, isSummaryText: true))
            }
        }
        if !currentHeading.isEmpty || !currentItems.isEmpty {
            sections.append(MeetingSection(heading: currentHeading, items: currentItems))
        }
        return sections.filter { $0.heading != "Title" && $0.heading != "Title:" }
    }
}

// MARK: - Pulsing Red Dot

private struct PulsingDot: View {
    @State private var isPulsing = false

    var body: some View {
        Circle()
            .fill(Color.red)
            .frame(width: 8, height: 8)
            .opacity(isPulsing ? 0.4 : 1.0)
            .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isPulsing)
            .onAppear { isPulsing = true }
    }
}

// MARK: - Waveform Animation

private struct WaveformView: View {
    var isActive: Bool
    var phase: CGFloat

    @State private var animating = false
    private let barCount = 5

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<barCount, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1)
                    .fill(isActive ? Color.red : Color.fallbackTextMuted)
                    .frame(width: 3, height: barHeight(for: i))
                    .animation(
                        isActive
                            ? .easeInOut(duration: 0.4 + Double(i) * 0.1)
                                .repeatForever(autoreverses: true)
                                .delay(Double(i) * 0.08)
                            : .easeOut(duration: 0.3),
                        value: animating
                    )
            }
        }
        .onAppear {
            if isActive { animating = true }
        }
        .onChange(of: isActive) { _, active in
            animating = active
        }
    }

    private func barHeight(for index: Int) -> CGFloat {
        if !isActive { return 3 }
        let base: CGFloat = animating ? 14 : 3
        let variance: CGFloat = animating ? CGFloat(index % 3) * 3 : 0
        return max(3, base - variance)
    }
}

// MARK: - Chat-Style Transcript Viewer (from dev)

struct TranscriptBubbleView: View {
    let transcript: String
    let meetingNotes: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Transcript")
                    .font(.system(size: 18, weight: .semibold))
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.borderless)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)

            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    let utterances = splitIntoUtterances(transcript)
                    let noteBubbles = splitIntoNoteBubbles(meetingNotes)
                    let merged = mergeUtterancesAndNotes(utterances: utterances, notes: noteBubbles)

                    ForEach(Array(merged.enumerated()), id: \.offset) { _, bubble in
                        if bubble.isNote {
                            HStack {
                                Spacer(minLength: 60)
                                Text(bubble.text)
                                    .font(.system(size: EditorTypography.bodyFontSize))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(Color.accentColor)
                                    .clipShape(RoundedRectangle(cornerRadius: 16))
                            }
                        } else {
                            HStack {
                                Text(bubble.text)
                                    .font(.system(size: EditorTypography.bodyFontSize))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(Color(nsColor: .controlBackgroundColor))
                                    .clipShape(RoundedRectangle(cornerRadius: 16))
                                Spacer(minLength: 60)
                            }
                        }
                    }
                }
                .padding(20)
            }
        }
        .frame(minWidth: 500, minHeight: 400)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private struct Bubble {
        var text: String
        var isNote: Bool
    }

    private func splitIntoUtterances(_ text: String) -> [String] {
        guard !text.isEmpty else { return [] }
        let paragraphs = text.components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if paragraphs.count > 1 {
            return paragraphs.flatMap { splitParagraphIntoSentenceGroups($0) }
        }
        return splitParagraphIntoSentenceGroups(text)
    }

    private func splitParagraphIntoSentenceGroups(_ paragraph: String) -> [String] {
        var sentences: [String] = []
        var current = ""
        for char in paragraph {
            current.append(char)
            if char == "." || char == "?" || char == "!" {
                let trimmed = current.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty { sentences.append(trimmed) }
                current = ""
            }
        }
        let remainder = current.trimmingCharacters(in: .whitespaces)
        if !remainder.isEmpty { sentences.append(remainder) }

        var groups: [String] = []
        let chunkSize = 3
        for i in stride(from: 0, to: sentences.count, by: chunkSize) {
            let end = min(i + chunkSize, sentences.count)
            groups.append(sentences[i..<end].joined(separator: " "))
        }
        return groups.isEmpty ? [paragraph] : groups
    }

    private func splitIntoNoteBubbles(_ notes: String) -> [String] {
        guard !notes.isEmpty else { return [] }
        return notes.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private func mergeUtterancesAndNotes(utterances: [String], notes: [String]) -> [Bubble] {
        guard !notes.isEmpty, !utterances.isEmpty else {
            return utterances.map { Bubble(text: $0, isNote: false) }
                + notes.map { Bubble(text: $0, isNote: true) }
        }
        var result: [Bubble] = []
        let interval = max(1, utterances.count / (notes.count + 1))
        var noteIndex = 0
        for (i, utterance) in utterances.enumerated() {
            result.append(Bubble(text: utterance, isNote: false))
            if noteIndex < notes.count && (i + 1) % interval == 0 {
                result.append(Bubble(text: notes[noteIndex], isNote: true))
                noteIndex += 1
            }
        }
        while noteIndex < notes.count {
            result.append(Bubble(text: notes[noteIndex], isNote: true))
            noteIndex += 1
        }
        return result
    }
}
