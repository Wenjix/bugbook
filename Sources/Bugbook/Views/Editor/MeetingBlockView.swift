import SwiftUI

/// Meeting block — notes-first recording UI with post-meeting AI processing.
struct MeetingBlockView: View {
    var document: BlockDocument
    let block: Block
    @State private var transcriptionService = TranscriptionService()
    @State private var isRecording = false
    @State private var meetingNotes = ""
    @State private var isProcessing = false
    @State private var processingStatus = ""
    @State private var showTranscript = false
    @State private var elapsedSeconds = 0
    @State private var timer: Timer?

    /// Parsed structured output stored after AI processing
    @State private var generatedTitle = ""
    @State private var structuredSections = ""
    @State private var actionItems: [String] = []

    private var hasTranscript: Bool {
        !block.text.isEmpty
    }

    private var hasBeenProcessed: Bool {
        !block.language.isEmpty // repurpose `language` field for structured summary storage
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerBar
            notesEditor
            if isProcessing {
                processingIndicator
            }
            if hasBeenProcessed {
                structuredOutput
            }
            if hasTranscript {
                transcriptButton
            }
        }
        .padding(16)
        .background(Color.fallbackBgTertiary.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
        .onAppear {
            meetingNotes = block.meetingNotes
        }
        .sheet(isPresented: $showTranscript) {
            TranscriptBubbleView(
                transcript: block.text,
                meetingNotes: block.meetingNotes
            )
        }
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack(spacing: 10) {
            // Recording indicator
            if isRecording {
                Circle()
                    .fill(Color.red)
                    .frame(width: 8, height: 8)

                Text(formatElapsed(elapsedSeconds))
                    .font(.system(size: Typography.caption, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.fallbackTextSecondary)
            } else {
                Image(systemName: "mic.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.fallbackTextSecondary)
            }

            Text(isRecording ? "Recording..." : (hasBeenProcessed ? "Meeting Complete" : "Meeting"))
                .font(.system(size: Typography.body, weight: .semibold))
                .foregroundStyle(Color.fallbackTextPrimary)

            Spacer()

            recordButton
        }
    }

    private var recordButton: some View {
        Button {
            if isRecording {
                stopMeeting()
            } else {
                startMeeting()
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: isRecording ? "stop.fill" : "record.circle")
                    .font(.system(size: 12))
                Text(isRecording ? "Stop" : "Record")
                    .font(.system(size: Typography.caption, weight: .medium))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(isRecording ? Color.red.opacity(0.15) : Color.fallbackAccent.opacity(0.15))
            .foregroundStyle(isRecording ? .red : Color.fallbackAccent)
            .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
        }
        .buttonStyle(.borderless)
        .disabled(isProcessing)
    }

    // MARK: - Notes Editor

    private var notesEditor: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Notes")
                .font(.system(size: Typography.caption, weight: .medium))
                .foregroundStyle(Color.fallbackTextSecondary)

            TextEditor(text: $meetingNotes)
                .font(.system(size: Typography.content))
                .scrollContentBackground(.hidden)
                .frame(minHeight: 80, maxHeight: 200)
                .padding(8)
                .background(Color.fallbackBgPrimary)
                .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
                .onChange(of: meetingNotes) { _, newVal in
                    document.updateMeetingNotes(blockId: block.id, notes: newVal)
                }
        }
    }

    // MARK: - Processing Indicator

    private var processingIndicator: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text(processingStatus)
                .font(.system(size: Typography.caption))
                .foregroundStyle(Color.fallbackTextSecondary)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Structured Output (post-processing)

    private var structuredOutput: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Parse the stored structured content and render it
            let sections = parseSections(block.language)

            ForEach(Array(sections.enumerated()), id: \.offset) { _, section in
                VStack(alignment: .leading, spacing: 4) {
                    if !section.heading.isEmpty {
                        Text(section.heading)
                            .font(.system(size: Typography.body, weight: .semibold))
                            .foregroundStyle(Color.fallbackTextPrimary)
                    }
                    ForEach(Array(section.items.enumerated()), id: \.offset) { _, item in
                        if item.isUserNote {
                            // User notes displayed in italic with accent color
                            Text(item.text)
                                .font(.system(size: Typography.body).italic())
                                .foregroundStyle(Color.fallbackAccent)
                                .padding(.leading, 8)
                        } else if item.isActionItem {
                            HStack(alignment: .top, spacing: 6) {
                                Image(systemName: "square")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Color.fallbackTextSecondary)
                                    .padding(.top, 2)
                                Text(item.text)
                                    .font(.system(size: Typography.body))
                                    .foregroundStyle(Color.fallbackTextPrimary)
                            }
                        } else {
                            HStack(alignment: .top, spacing: 6) {
                                Text("\u{2022}")
                                    .foregroundStyle(Color.fallbackTextSecondary)
                                Text(item.text)
                                    .font(.system(size: Typography.body))
                                    .foregroundStyle(Color.fallbackTextPrimary)
                            }
                        }
                    }
                }
            }
        }
        .padding(12)
        .background(Color.fallbackBgPrimary)
        .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
    }

    // MARK: - Transcript Button

    private var transcriptButton: some View {
        Button {
            showTranscript = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "text.bubble")
                    .font(.system(size: 12))
                Text("View Transcript")
                    .font(.system(size: Typography.caption, weight: .medium))
            }
            .foregroundStyle(Color.fallbackAccent)
        }
        .buttonStyle(.borderless)
    }

    // MARK: - Recording Control

    private func startMeeting() {
        Task {
            let authorized = await transcriptionService.requestAuthorization()
            guard authorized else {
                transcriptionService.error = "Speech recognition permission denied"
                return
            }
            transcriptionService.startRecording()
            isRecording = true
            elapsedSeconds = 0
            startTimer()
        }
    }

    private func stopMeeting() {
        stopTimer()
        let rawTranscript = transcriptionService.stopRecording()
        isRecording = false

        // Store raw transcript
        document.updateBlockText(blockId: block.id, text: rawTranscript)

        // Begin post-meeting AI processing
        guard !rawTranscript.isEmpty else { return }
        Task {
            await processTranscript(rawTranscript)
        }
    }

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            Task { @MainActor in
                elapsedSeconds += 1
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func formatElapsed(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%02d:%02d", m, s)
    }

    // MARK: - Post-Meeting AI Processing

    private func processTranscript(_ rawTranscript: String) async {
        isProcessing = true

        // Step 1: Clean transcript via claude CLI
        processingStatus = "Cleaning transcript..."
        let cleanedTranscript = await cleanTranscript(rawTranscript)
        let transcript = cleanedTranscript ?? rawTranscript

        // Update block with cleaned transcript
        document.updateBlockText(blockId: block.id, text: transcript)

        // Step 2: Extract structured sections
        processingStatus = "Extracting meeting sections..."
        let userNotes = block.meetingNotes
        let structured = await extractStructuredSections(transcript: transcript, notes: userNotes)

        if let structured {
            // Store structured output in the language field (repurposed for meeting blocks)
            document.updateMeetingSummary(blockId: block.id, summary: structured)
        }

        isProcessing = false
        processingStatus = ""
    }

    private func cleanTranscript(_ raw: String) async -> String? {
        let prompt = "Clean up this transcript: remove filler words (uh, um, like, you know), fix punctuation, add sentence breaks. Output only cleaned text:\n\n\(raw)"
        return await runClaude(prompt: prompt)
    }

    private func extractStructuredSections(transcript: String, notes: String) async -> String? {
        var prompt = """
        Given this meeting transcript, extract a structured meeting summary. Format your response EXACTLY like this:

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

            The user also took these notes during the meeting. Integrate them inline under the relevant topics, prefixed with [NOTE]:

            \(notes)
            """
        }

        prompt += """

        Transcript:
        \(transcript)
        """

        return await runClaude(prompt: prompt)
    }

    /// Shells out to `claude --model haiku --print` matching the AiService pattern.
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

    // MARK: - Section Parsing

    private struct MeetingSection {
        var heading: String
        var items: [MeetingItem]
    }

    private struct MeetingItem {
        var text: String
        var isActionItem: Bool
        var isUserNote: Bool
    }

    private func parseSections(_ raw: String) -> [MeetingSection] {
        guard !raw.isEmpty else { return [] }
        var sections: [MeetingSection] = []
        var currentHeading = ""
        var currentItems: [MeetingItem] = []

        for line in raw.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
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
                currentItems.append(MeetingItem(text: text, isActionItem: true, isUserNote: false))
            } else if trimmed.hasPrefix("[NOTE]") {
                let text = trimmed.replacingOccurrences(of: "[NOTE] ", with: "")
                    .replacingOccurrences(of: "[NOTE]", with: "")
                currentItems.append(MeetingItem(text: text, isActionItem: false, isUserNote: true))
            } else if trimmed.hasPrefix("- ") {
                let text = String(trimmed.dropFirst(2))
                let isNote = text.hasPrefix("[NOTE]")
                let cleanText = isNote
                    ? text.replacingOccurrences(of: "[NOTE] ", with: "").replacingOccurrences(of: "[NOTE]", with: "")
                    : text
                currentItems.append(MeetingItem(text: cleanText, isActionItem: false, isUserNote: isNote))
            } else if !trimmed.isEmpty {
                currentItems.append(MeetingItem(text: trimmed, isActionItem: false, isUserNote: false))
            }
        }
        if !currentHeading.isEmpty || !currentItems.isEmpty {
            sections.append(MeetingSection(heading: currentHeading, items: currentItems))
        }
        return sections
    }
}

// MARK: - Chat-Style Transcript Viewer

struct TranscriptBubbleView: View {
    let transcript: String
    let meetingNotes: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Transcript")
                    .font(.system(size: Typography.title3, weight: .semibold))
                    .foregroundStyle(Color.fallbackTextPrimary)
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

            // Bubbles
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    let utterances = splitIntoUtterances(transcript)
                    let noteBubbles = splitIntoNoteBubbles(meetingNotes)
                    let merged = mergeUtterancesAndNotes(utterances: utterances, notes: noteBubbles)

                    ForEach(Array(merged.enumerated()), id: \.offset) { _, bubble in
                        if bubble.isNote {
                            // User note bubble — right-aligned, accent tint
                            HStack {
                                Spacer(minLength: 60)
                                Text(bubble.text)
                                    .font(.system(size: Typography.body))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(Color.fallbackAccent)
                                    .clipShape(RoundedRectangle(cornerRadius: Radius.xl))
                            }
                        } else {
                            // Transcript utterance — left-aligned, subtle bg
                            HStack {
                                Text(bubble.text)
                                    .font(.system(size: Typography.body))
                                    .foregroundStyle(Color.fallbackTextPrimary)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(Color.fallbackBgTertiary)
                                    .clipShape(RoundedRectangle(cornerRadius: Radius.xl))
                                Spacer(minLength: 60)
                            }
                        }
                    }
                }
                .padding(20)
            }
        }
        .frame(minWidth: 500, minHeight: 400)
        .background(Color.fallbackEditorBg)
    }

    // MARK: - Utterance Splitting

    private struct Bubble {
        var text: String
        var isNote: Bool
    }

    /// Split transcript into sentence-level utterances for chat bubbles.
    private func splitIntoUtterances(_ text: String) -> [String] {
        guard !text.isEmpty else { return [] }
        // Split on sentence-ending punctuation followed by space
        var utterances: [String] = []
        var current = ""
        for char in text {
            current.append(char)
            if (char == "." || char == "?" || char == "!") {
                let trimmed = current.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty {
                    utterances.append(trimmed)
                }
                current = ""
            }
        }
        let remainder = current.trimmingCharacters(in: .whitespaces)
        if !remainder.isEmpty {
            utterances.append(remainder)
        }
        return utterances
    }

    /// Split user notes into individual lines for interleaving.
    private func splitIntoNoteBubbles(_ notes: String) -> [String] {
        guard !notes.isEmpty else { return [] }
        return notes.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// Interleave utterances and notes. Notes are spread evenly among utterances.
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
        // Append any remaining notes
        while noteIndex < notes.count {
            result.append(Bubble(text: notes[noteIndex], isNote: true))
            noteIndex += 1
        }
        return result
    }
}
