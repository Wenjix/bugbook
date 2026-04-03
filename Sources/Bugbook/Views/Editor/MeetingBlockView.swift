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
    @State private var processingStatus = ""
    @State private var showTranscriptSheet = false
    @State private var copiedTranscript = false
    @State private var isGenerating = false
    @FocusState private var searchFocused: Bool

    private let transcriptBottomAnchorID = "transcript-bottom"

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
        .frame(maxWidth: .infinity)
        .contentShape(RoundedRectangle(cornerRadius: Radius.lg))
        .padding(.vertical, 4)
        .overlay {
            if showTranscriptSheet {
                ZStack {
                    Rectangle()
                        .fill(Color.black.opacity(0.28))
                        .contentShape(Rectangle())
                        .onTapGesture { showTranscriptSheet = false }

                    TranscriptBubbleView(
                        transcript: block.meetingTranscript,
                        meetingNotes: block.meetingNotes,
                        onClose: { showTranscriptSheet = false }
                    )
                    .frame(maxWidth: 680, maxHeight: 600)
                    .background(Elevation.popoverBg)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                    .overlay {
                        RoundedRectangle(cornerRadius: 18)
                            .stroke(Elevation.popoverBorder, lineWidth: 0.5)
                            .allowsHitTesting(false)
                    }
                    .shadow(
                        color: Elevation.shadowColor.opacity(0.18),
                        radius: 24,
                        y: Elevation.shadowY * 2
                    )
                    .onTapGesture { }
                    .padding(32)
                }
                .transition(.opacity)
            }
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
                            .frame(width: 6, height: 6)
                        Text("Record")
                            .font(.system(size: Typography.bodySmall, weight: .medium))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.primary.opacity(Opacity.subtle))
                    .foregroundStyle(Color.fallbackTextPrimary)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
                    .contentShape(RoundedRectangle(cornerRadius: Radius.sm))
                }
                .buttonStyle(.borderless)
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 0)

            meetingNotesChildBlocks
                .padding(.horizontal, 14)
                .padding(.top, 4)
                .padding(.bottom, 12)
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

                Button(action: stopRecording) {
                    HStack(spacing: 5) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.red)
                            .frame(width: 6, height: 6)
                        Text("Stop")
                            .font(.system(size: Typography.bodySmall, weight: .medium))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.primary.opacity(Opacity.subtle))
                    .foregroundStyle(Color.fallbackTextPrimary)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
                    .contentShape(RoundedRectangle(cornerRadius: Radius.sm))
                }
                .buttonStyle(.borderless)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            meetingNotesChildBlocks
                .padding(.horizontal, 10)
                .padding(.vertical, 8)

            Divider()

            bottomBar(showWaveform: true)
                .zIndex(1)

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
        let sections = parseSections(block.language)
        return VStack(spacing: 0) {
            HStack(spacing: 10) {
                TextField("Meeting", text: $title, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: Typography.title3, weight: .semibold))
                    .foregroundStyle(Color.fallbackTextPrimary)
                    .lineLimit(1...)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .onChange(of: title) { _, newVal in
                        document.updateMeetingTitle(blockId: block.id, title: newVal)
                    }

                // Generate summary button (only when no summary exists and not already generating)
                let hasHeadingChild = block.children.contains(where: { $0.type == .heading })
                if sections.isEmpty && block.meetingActionItems.isEmpty && block.meetingSummary.isEmpty && !hasHeadingChild && (!block.meetingTranscript.isEmpty || !block.meetingNotes.isEmpty || !block.children.isEmpty) {
                    Button {
                        Task { await generateSummary() }
                    } label: {
                        HStack(spacing: 4) {
                            if isGenerating {
                                ProgressView()
                                    .controlSize(.mini)
                                    .frame(width: 11, height: 11)
                            } else {
                                Image(systemName: "ladybug")
                                    .font(.system(size: 11))
                            }
                            Text("Generate")
                                .font(.system(size: Typography.caption, weight: .medium))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.primary.opacity(Opacity.subtle))
                        .clipShape(RoundedRectangle(cornerRadius: Radius.xs))
                    }
                    .buttonStyle(.borderless)
                    .disabled(isGenerating)
                }

                Button(action: resumeRecording) {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 6, height: 6)
                        Text("Resume")
                            .font(.system(size: Typography.bodySmall, weight: .medium))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.primary.opacity(Opacity.subtle))
                    .foregroundStyle(Color.fallbackTextPrimary)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
                    .contentShape(RoundedRectangle(cornerRadius: Radius.sm))
                }
                .buttonStyle(.borderless)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            if !sections.isEmpty || !block.meetingActionItems.isEmpty || !block.meetingSummary.isEmpty {
                summaryView(sections)
            }
            notesView

            Divider()

            bottomBar(showWaveform: false)
                .zIndex(1)

            if isTranscriptOpen {
                transcriptDrawer
            }
        }
    }

    // MARK: - Summary View

    private func summaryView(_ sections: [MeetingSection]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
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
                                        .foregroundStyle(Color.fallbackTextSecondary)
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
                                        .foregroundStyle(Color.fallbackTextSecondary)
                                }
                            }
                        }
                    }
                }
            }

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
                                .foregroundStyle(Color.fallbackTextSecondary)
                        }
                    }
                }
            }
        }
        .padding(14)
    }

    // MARK: - Notes View

    private var notesView: some View {
        VStack(alignment: .leading, spacing: 0) {
            if block.children.isEmpty && !block.meetingNotes.isEmpty {
                // Legacy plain-text notes (backwards compat)
                Text(block.meetingNotes)
                    .font(.system(size: Typography.bodySmall))
                    .foregroundStyle(Color.fallbackTextPrimary)
                    .textSelection(.enabled)
                    .padding(14)
            }

            meetingNotesChildBlocks
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
        }
    }

    // MARK: - Bottom Bar

    private func bottomBar(showWaveform: Bool) -> some View {
        HStack(spacing: 8) {
            if showWaveform {
                WaveformView(isActive: block.meetingState == .recording, audioLevel: document.meetingAudioLevel)
                    .frame(width: 40, height: 16)
            } else {
                Text("Transcript")
                    .font(.system(size: Typography.caption, weight: .medium))
                    .foregroundStyle(Color.fallbackTextSecondary)
            }

            Spacer()

            if isTranscriptOpen {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isSearchingTranscript.toggle()
                        if isSearchingTranscript {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                                searchFocused = true
                            }
                        } else {
                            transcriptSearch = ""
                        }
                    }
                } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(isSearchingTranscript ? Color.accentColor : Color.fallbackTextSecondary)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Button {
                    let entries = !block.transcriptEntries.isEmpty
                        ? block.transcriptEntries
                        : block.meetingTranscript.components(separatedBy: "\n").filter { !$0.isEmpty }
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(entries.joined(separator: "\n\n"), forType: .string)
                    copiedTranscript = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        copiedTranscript = false
                    }
                } label: {
                    Image(systemName: copiedTranscript ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(copiedTranscript ? Color.accentColor : Color.fallbackTextSecondary)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
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
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.25)) {
                isTranscriptOpen.toggle()
            }
            if isTranscriptOpen {
                document.scrollToBlockId = block.id
            }
        }
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
                        .focused($searchFocused)
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

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 6) {
                        let rawEntries = !block.transcriptEntries.isEmpty
                            ? block.transcriptEntries
                            : block.meetingTranscript.components(separatedBy: "\n").filter { !$0.isEmpty }
                        let allEntries = rawEntries.flatMap { splitTranscriptEntry($0) }
                        let entries = transcriptSearch.isEmpty
                            ? allEntries
                            : allEntries.filter { $0.localizedCaseInsensitiveContains(transcriptSearch) }
                        let isLive = block.meetingState == .recording
                        let bubbleBg = isLive
                            ? Color(red: 0.694, green: 0.831, blue: 0.976) // #B1D4F9
                            : Color.primary.opacity(0.07)

                        ForEach(Array(entries.enumerated()), id: \.offset) { _, entry in
                            HStack {
                                Spacer(minLength: 40)
                                Text(entry)
                                    .font(.system(size: Typography.caption2))
                                    .foregroundStyle(Color.fallbackTextPrimary)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(bubbleBg)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                        }

                        if isLive {
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

                        Color.clear.frame(height: 1).id(transcriptBottomAnchorID)
                    }
                    .padding(10)
                }
                .frame(maxHeight: 400)
                .onAppear {
                    proxy.scrollTo(transcriptBottomAnchorID, anchor: .bottom)
                }
            }
        }
        .transition(.asymmetric(
            insertion: .push(from: .bottom).combined(with: .opacity),
            removal: .push(from: .top).combined(with: .opacity)
        ))
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
        document.onStartMeeting?(block.id)
    }

    private func stopRecording() {
        document.onStopMeeting?(block.id)
    }

    private func resumeRecording() {
        document.updateMeetingState(blockId: block.id, state: .recording)
        document.onStartMeeting?(block.id)
    }

    // MARK: - Helpers

    /// Splits a single transcript entry into sentence-sized bubbles.
    /// Splits on sentence-ending punctuation or every ~20 words if unpunctuated.
    private func splitTranscriptEntry(_ text: String) -> [String] {
        let words = text.components(separatedBy: " ").filter { !$0.isEmpty }
        guard words.count > 6 else { return [text] }
        var result: [String] = []
        var chunk: [String] = []
        for word in words {
            chunk.append(word)
            let ends = word.hasSuffix(".") || word.hasSuffix("?") || word.hasSuffix("!")
            if ends || chunk.count >= 20 {
                result.append(chunk.joined(separator: " "))
                chunk = []
            }
        }
        if !chunk.isEmpty { result.append(chunk.joined(separator: " ")) }
        return result.isEmpty ? [text] : result
    }

    private func markdownToBlocks(_ sections: String, actionItems: String) -> [Block] {
        var markdown = sections.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedItems = actionItems.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedItems.isEmpty {
            if !markdown.isEmpty { markdown += "\n\n" }
            markdown += "## Action Items\n" + trimmedItems
        }
        return MarkdownBlockParser.parse(markdown)
    }

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
        isGenerating = true
        defer { isGenerating = false }
        let transcript = block.meetingTranscript
        let userNotes = block.children.isEmpty
            ? block.meetingNotes
            : block.children.map { $0.text }.joined(separator: "\n")

        document.updateMeetingState(blockId: block.id, state: .processing)

        var cleanedTranscript = transcript

        if !transcript.isEmpty {
            processingStatus = "Cleaning transcript..."
            if let result = await cleanTranscript(transcript) {
                cleanedTranscript = result
                document.updateMeetingTranscript(blockId: block.id, transcript: cleanedTranscript)
            }
        }

        let hasContent = !cleanedTranscript.isEmpty || !userNotes.isEmpty
        if hasContent {
            processingStatus = "Extracting meeting sections..."
            if let structured = await extractStructuredSections(transcript: cleanedTranscript, notes: userNotes) {
                let parsed = parseAIResponse(structured)
                if !parsed.title.isEmpty {
                    document.updateMeetingTitle(blockId: block.id, title: parsed.title)
                }
                // Convert summary + action items into editable child blocks prepended before user notes
                let summaryBlocks = markdownToBlocks(parsed.sections, actionItems: parsed.actionItems)
                if !summaryBlocks.isEmpty {
                    let existingChildren = block.children
                    let combined = summaryBlocks + existingChildren
                    guard let idx = document.index(for: block.id) else { return }
                    document.blocks[idx].children = combined
                }
            }
        }

        processingStatus = ""
        document.updateMeetingState(blockId: block.id, state: .complete)
    }

    /// Parse the structured AI response into title, action items, and remaining sections.
    private func parseAIResponse(_ response: String) -> (title: String, actionItems: String, sections: String) {
        var title = ""
        var actionLines: [String] = []
        var sectionLines: [String] = []
        var inActionItems = false

        for line in response.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Extract title from "## Title" section
            if trimmed.hasPrefix("## Title") {
                // The title value is on the next non-empty line; handled below
                inActionItems = false
                continue
            }

            // Detect action items section
            if trimmed == "## Action Items" || trimmed == "### Action Items" {
                inActionItems = true
                continue
            }

            // Detect start of a new section (not Action Items)
            if (trimmed.hasPrefix("## ") || trimmed.hasPrefix("### ")) && !trimmed.contains("Action Items") {
                inActionItems = false
            }

            // If we just saw "## Title" and this is a non-empty line, capture it as the title
            if title.isEmpty && sectionLines.isEmpty && actionLines.isEmpty && !trimmed.isEmpty
                && !trimmed.hasPrefix("##") && !trimmed.hasPrefix("- ") {
                title = trimmed
                continue
            }

            if inActionItems {
                if !trimmed.isEmpty {
                    actionLines.append(trimmed)
                }
            } else {
                sectionLines.append(line)
            }
        }

        // Clean trailing empty lines from sections
        while sectionLines.last?.trimmingCharacters(in: .whitespaces).isEmpty == true {
            sectionLines.removeLast()
        }

        return (
            title: title,
            actionItems: actionLines.joined(separator: "\n"),
            sections: sectionLines.joined(separator: "\n")
        )
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

        IMPORTANT: Only include ## Action Items if there are real, concrete next steps. If there are no clear action items, omit the section entirely — do NOT write placeholder text like "No action items" or "---".
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
                process.arguments = ["-c", "PATH=\"$PATH:/usr/local/bin:/opt/homebrew/bin:$HOME/.local/bin:$HOME/.npm-global/bin\" claude --model haiku --print '\(escaped)'"]
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
    var audioLevel: Float

    private let barCount = 5
    private let maxHeight: CGFloat = 14
    private let minHeight: CGFloat = 3

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.1, paused: !isActive)) { timeline in
            HStack(spacing: 2) {
                ForEach(0..<barCount, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(isActive ? Color.fallbackTextSecondary : Color.fallbackTextMuted)
                        .frame(width: 3, height: barHeight(for: i, date: timeline.date))
                        .animation(.easeInOut(duration: 0.1), value: audioLevel)
                }
            }
        }
    }

    private func barHeight(for index: Int, date: Date) -> CGFloat {
        guard isActive else { return minHeight }
        let level = CGFloat(audioLevel)
        // Each bar gets a slightly different offset from the audio level for organic movement
        let t = date.timeIntervalSinceReferenceDate
        let freq = 2.5 + Double(index) * 1.3
        let jitter = CGFloat(sin(t * freq) * 0.15)
        let height = minHeight + (maxHeight - minHeight) * (level + jitter)
        return max(minHeight, min(maxHeight, height))
    }
}

// MARK: - Chat-Style Transcript Viewer (from dev)

struct TranscriptBubbleView: View {
    let transcript: String
    let meetingNotes: String
    var onClose: (() -> Void)?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Transcript")
                    .font(.system(size: 18, weight: .semibold))
                Spacer()
                Button {
                    if let onClose { onClose() } else { dismiss() }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
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
