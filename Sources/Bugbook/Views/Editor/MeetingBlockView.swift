import SwiftUI
import AppKit

/// Notes-first meeting recording block. Shows a prominent notes area with
/// the live transcript hidden behind a disclosure toggle, an "Ask anything"
/// AI query bar for meeting Q&A, and post-meeting AI processing that produces
/// a structured summary with action items.
struct MeetingBlockView: View {
    var document: BlockDocument
    let block: Block
    @State private var isRecording = false
    @State private var hasRecorded = false
    @State private var audioLevel: CGFloat = 0.3
    // Post-meeting processing state
    @State private var isProcessing = false
    @State private var processingStatus = ""
    @State private var showTranscriptSheet = false

    // Tab toggle for merged notes + summary
    @State private var selectedTab: MeetingTab = .aiSummary
    @State private var isExpanded = false
    @State private var showViewPicker = false
    @State private var isHovering = false
    @State private var editingTitle: String = ""
    @State private var isEditingTitle = false

    private enum MeetingTab {
        case aiSummary
        case myNotes
    }

    private var hasBeenProcessed: Bool {
        !block.language.isEmpty // language field repurposed for structured summary storage
    }

    /// Whether we have prior recording content (transcript or notes) but are not currently recording
    private var hasRecordingContent: Bool {
        !isRecording && (!block.text.isEmpty || !block.meetingNotes.isEmpty)
    }

    private var showsStructuredOutput: Bool {
        !isRecording && selectedTab == .aiSummary && hasBeenProcessed
    }

    private var shouldUseExpandedLayout: Bool {
        !isRecording && isExpanded
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Top row: title left, controls right
            meetingHeaderRow

            if isRecording {
                waveformIndicator
                notesArea
            } else {
                // Show content based on selected tab
                if showsStructuredOutput {
                    structuredOutputContent
                } else {
                    notesArea
                        .frame(minHeight: isExpanded ? 200 : 120, maxHeight: isExpanded ? .infinity : 200)
                }

                if isProcessing {
                    processingIndicator
                }

                // Post-recording actions — only show when there's no summary yet
                // and the meeting isn't already content-rich (transcript + notes)
                if hasRecorded && !hasBeenProcessed && !isProcessing && block.meetingNotes.isEmpty {
                    generateButton
                }
                if !block.text.isEmpty {
                    transcriptButton
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .fixedSize(horizontal: false, vertical: shouldUseExpandedLayout)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.secondary.opacity(0.2), lineWidth: 1)
                .allowsHitTesting(false)
        )
        .onHover { hovering in
            isHovering = hovering
        }
        .sheet(isPresented: $showTranscriptSheet) {
            TranscriptBubbleView(
                transcript: block.text,
                meetingNotes: block.meetingNotes
            )
        }
    }

    @ViewBuilder
    private var structuredOutputContent: some View {
        if isExpanded {
            structuredOutput
                .fixedSize(horizontal: false, vertical: true)
                .layoutPriority(1)
                .id("expanded")
        } else {
            structuredOutput
                .frame(maxHeight: 200, alignment: .top)
                .clipped()
                .id("collapsed")
        }
    }

    // MARK: - Header Row (title + controls)

    private var meetingHeaderRow: some View {
        HStack(spacing: 8) {
            // Pulsing dot during recording
            if isRecording {
                PulsingDotView()
            }

            // Editable title — local state to avoid per-keystroke document updates
            TextField("New Meeting", text: $editingTitle, onEditingChanged: { editing in
                if editing {
                    editingTitle = extractTitle(from: block.language)
                } else {
                    let current = extractTitle(from: block.language)
                    if editingTitle != current {
                        let updated = replaceTitle(in: block.language, with: editingTitle)
                        document.updateMeetingSummary(blockId: block.id, summary: updated)
                    }
                }
            })
            .textFieldStyle(.plain)
            .font(.system(size: EditorTypography.scaled(21), weight: .semibold))
            .foregroundStyle(.primary)
            .onAppear { editingTitle = extractTitle(from: block.language) }
            .onChange(of: block.language) { _, newValue in
                if !isEditingTitle {
                    editingTitle = extractTitle(from: newValue)
                }
            }

            Spacer()

            if hasRecordingContent || hasBeenProcessed {
                // Expand / collapse — hover-only, left of dropdown
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        isExpanded.toggle()
                    }
                } label: {
                    Image(systemName: isExpanded ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help(isExpanded ? "Collapse" : "Expand")
                .opacity(isHovering ? 1 : 0)

                // View picker dropdown (AI Summary / My Notes)
                viewPickerDropdown

                // Ladybug → open AI sidebar
                Button {
                    NotificationCenter.default.post(name: .openAIPanel, object: nil)
                } label: {
                    Image(systemName: "ladybug.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Open AI sidebar")
            }

            // Record / Stop / Resume button
            Button {
                if isRecording {
                    stopRecordingAndProcess()
                } else {
                    isRecording = true
                }
            } label: {
                Text(isRecording ? "Stop" : ((hasRecordingContent || hasRecorded) ? "Resume" : "Record"))
                    .font(.system(size: 12, weight: .medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(isRecording ? Color.red.opacity(0.15) : Color.accentColor.opacity(0.15))
                    )
                    .foregroundStyle(isRecording ? .red : .accentColor)
            }
            .buttonStyle(.plain)
            .disabled(isProcessing)
        }
    }

    /// Build context string for the AI sidebar from this meeting's content
    private func buildAIContext() -> String {
        var parts: [String] = ["Here is the meeting content:\n"]
        if !block.meetingNotes.isEmpty {
            parts.append("Notes:\n\(block.meetingNotes)")
        }
        if !block.text.isEmpty {
            parts.append("Transcript:\n\(block.text)")
        }
        if !block.language.isEmpty {
            parts.append("Summary:\n\(block.language)")
        }
        return parts.joined(separator: "\n\n")
    }

    // MARK: - Waveform

    private var waveformIndicator: some View {
        HStack(spacing: 3) {
            ForEach(0..<16, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.red.opacity(0.5))
                    .frame(width: 4, height: barHeight(for: index))
            }
        }
        .frame(height: 24)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private func barHeight(for index: Int) -> CGFloat {
        let base = sin(Double(index) * 0.8 + 0.5) * 0.5 + 0.5
        return max(4, CGFloat(base) * 22 * audioLevel)
    }

    /// Pull the title out of the structured summary's "## Title" section, or return empty string.
    private func extractTitle(from raw: String) -> String {
        guard !raw.isEmpty else { return "" }
        let lines = raw.components(separatedBy: "\n")
        for (i, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == "## Title" || trimmed == "## Title:" {
                // The title text is the next non-empty line
                for j in (i + 1)..<lines.count {
                    let candidate = lines[j].trimmingCharacters(in: .whitespaces)
                    if candidate.hasPrefix("## ") || candidate.hasPrefix("### ") { break }
                    if !candidate.isEmpty { return candidate }
                }
            }
        }
        return ""
    }

    /// Replace (or insert) the title in the structured summary.
    private func replaceTitle(in raw: String, with newTitle: String) -> String {
        guard !raw.isEmpty else {
            return "## Title\n\(newTitle)"
        }
        var lines = raw.components(separatedBy: "\n")
        for (i, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == "## Title" || trimmed == "## Title:" {
                // Find and replace the title content line
                for j in (i + 1)..<lines.count {
                    let candidate = lines[j].trimmingCharacters(in: .whitespaces)
                    if candidate.hasPrefix("## ") || candidate.hasPrefix("### ") { break }
                    if !candidate.isEmpty {
                        lines[j] = newTitle
                        return lines.joined(separator: "\n")
                    }
                }
                // No content line found — insert after heading
                lines.insert(newTitle, at: i + 1)
                return lines.joined(separator: "\n")
            }
        }
        // No "## Title" heading — prepend it
        return "## Title\n\(newTitle)\n\n\(raw)"
    }

    // MARK: - View Picker Dropdown

    private var viewPickerDropdown: some View {
        Button(action: { showViewPicker.toggle() }) {
            HStack(spacing: 3) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 7, weight: .bold))
                Image(systemName: selectedTab == .aiSummary ? "sparkles" : "note.text")
                    .font(.system(size: 11))
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: Radius.sm)
                    .stroke(Color.primary.opacity(0.15), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .floatingPopover(isPresented: $showViewPicker, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 0) {
                viewPickerRow("AI Summary", icon: "sparkles", tab: .aiSummary)
                viewPickerRow("My Notes", icon: "note.text", tab: .myNotes)
            }
            .padding(.vertical, 4)
            .frame(width: 160)
            .popoverSurface()
        }
    }

    private func viewPickerRow(_ title: String, icon: String, tab: MeetingTab) -> some View {
        Button(action: {
            withAnimation(.easeInOut(duration: 0.12)) {
                selectedTab = tab
            }
            showViewPicker = false
        }) {
            HStack {
                if selectedTab == tab {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.primary)
                        .frame(width: 16)
                } else {
                    Color.clear.frame(width: 16, height: 1)
                }
                Image(systemName: icon)
                    .font(.system(size: 11))
                Text(title)
                    .font(.system(size: 13))
                    .foregroundStyle(.primary)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Notes Area

    private var notesArea: some View {
        ZStack(alignment: .topLeading) {
            MeetingNotesEditor(
                notes: Binding(
                    get: { block.meetingNotes },
                    set: { newValue in
                        document.updateBlockProperty(id: block.id) { b in
                            b.meetingNotes = newValue
                        }
                    }
                )
            )

            if block.meetingNotes.isEmpty {
                Text("Write notes...")
                    .font(.system(size: EditorTypography.bodyFontSize))
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 8)
                    .padding(.top, 8)
                    .allowsHitTesting(false)
            }
        }
    }

    // MARK: - Processing Indicator

    private var processingIndicator: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text(processingStatus)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Structured Output (post-processing)

    private var structuredOutput: some View {
        VStack(alignment: .leading, spacing: 10) {
            let sections = parseSections(block.language)

            ForEach(Array(sections.enumerated()), id: \.offset) { _, section in
                VStack(alignment: .leading, spacing: 4) {
                    if !section.heading.isEmpty {
                        Text(section.heading)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.primary)
                    }
                    ForEach(Array(section.items.enumerated()), id: \.offset) { _, item in
                        if item.isUserNote {
                            Text(item.text)
                                .font(.system(size: EditorTypography.bodyFontSize).italic())
                                .foregroundStyle(Color.accentColor)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.leading, 8)
                        } else if item.isActionItem {
                            HStack(alignment: .top, spacing: 6) {
                                Image(systemName: "square")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                                    .padding(.top, 2)
                                Text(item.text)
                                    .font(.system(size: EditorTypography.bodyFontSize))
                                    .foregroundStyle(.primary)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        } else if item.isSummaryText {
                            // AI summary text rendered as secondary (#1)
                            Text(item.text)
                                .font(.system(size: EditorTypography.bodyFontSize))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            HStack(alignment: .top, spacing: 6) {
                                Text("\u{2022}")
                                    .foregroundStyle(.secondary)
                                Text(item.text)
                                    .font(.system(size: EditorTypography.bodyFontSize))
                                    .foregroundStyle(.primary)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(nsColor: .textBackgroundColor).opacity(0.5))
        )
    }

    // MARK: - Generate Button

    private var generateButton: some View {
        Button {
            Task {
                await generateSummary()
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "ladybug.fill")
                    .font(.system(size: 12))
                Text("Generate Summary")
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.accentColor)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Transcript Button (#2)

    private var transcriptButton: some View {
        Button {
            showTranscriptSheet = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "text.bubble")
                    .font(.system(size: 12))
                Text("Transcript")
                    .font(.system(size: 12, weight: .medium))
                if !block.text.isEmpty {
                    Text("(\(block.text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.count) words)")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
            }
            .foregroundStyle(Color.accentColor)
        }
        .buttonStyle(.plain)
    }


    // MARK: - Recording Stop + Post-Meeting Processing

    private func stopRecordingAndProcess() {
        isRecording = false
        hasRecorded = true
    }

    private func generateSummary() async {
        let transcript = block.text
        let notes = block.meetingNotes

        if !transcript.isEmpty {
            // Has transcript — clean it and generate from both
            await processTranscript(transcript)
        } else if !notes.isEmpty {
            // Notes only, no transcript — generate from notes alone
            isProcessing = true
            processingStatus = "Generating summary from notes..."
            let structured = await extractStructuredSections(transcript: "", notes: notes)
            if let structured {
                document.updateMeetingSummary(blockId: block.id, summary: structured)
            }
            isProcessing = false
            processingStatus = ""
        }
    }

    private func processTranscript(_ rawTranscript: String) async {
        isProcessing = true

        // Step 1: Clean transcript
        processingStatus = "Cleaning transcript..."
        let cleanedTranscript = await cleanTranscript(rawTranscript)
        let transcript = cleanedTranscript ?? rawTranscript

        // Update block with cleaned transcript
        document.updateBlockText(id: block.id, text: transcript)

        // Step 2: Extract structured sections
        processingStatus = "Extracting meeting sections..."
        let userNotes = block.meetingNotes
        let structured = await extractStructuredSections(transcript: transcript, notes: userNotes)

        if let structured {
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

    /// Shells out to `claude --model haiku --print` for post-meeting AI processing.
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
        var isSummaryText: Bool
    }

    private func parseSections(_ raw: String) -> [MeetingSection] {
        guard !raw.isEmpty else { return [] }
        var sections: [MeetingSection] = []
        var currentHeading = ""
        var currentItems: [MeetingItem] = []

        for line in raw.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Strip HTML comment lines (#7)
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
        // Skip the "Title" section from structured output since it's shown in the title area (#7)
        return sections.filter { $0.heading != "Title" && $0.heading != "Title:" }
    }

}

// MARK: - Pulsing Dot

private struct PulsingDotView: View {
    @State private var isPulsing = false

    var body: some View {
        Circle()
            .fill(Color.red)
            .frame(width: 8, height: 8)
            .opacity(isPulsing ? 0.4 : 1.0)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                    isPulsing = true
                }
            }
    }
}

// MARK: - Notes Editor

/// A simple text editor that prepends `[HH:MM]` timestamps on new lines.
private struct MeetingNotesEditor: NSViewRepresentable {
    @Binding var notes: String

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        let textView = scrollView.documentView as! NSTextView
        textView.delegate = context.coordinator
        textView.font = .systemFont(ofSize: EditorTypography.bodyFontSize)
        textView.textColor = .labelColor
        textView.backgroundColor = .clear
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.textContainerInset = NSSize(width: 4, height: 6)
        textView.string = notes

        scrollView.hasVerticalScroller = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let textView = scrollView.documentView as! NSTextView
        if textView.string != notes {
            let selectedRange = textView.selectedRange()
            textView.string = notes
            if selectedRange.location + selectedRange.length <= notes.utf16.count {
                textView.setSelectedRange(selectedRange)
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(notes: $notes)
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        @Binding var notes: String
        private var isInserting = false

        init(notes: Binding<String>) {
            _notes = notes
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            guard !isInserting else { return }
            notes = textView.string
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                isInserting = true
                defer { isInserting = false }

                let timestamp = Self.currentTimestamp()
                let insertion = "\n\(timestamp) "
                textView.insertText(insertion, replacementRange: textView.selectedRange())
                notes = textView.string
                return true
            }
            return false
        }

        private static let timestampFormatter: DateFormatter = {
            let df = DateFormatter()
            df.dateFormat = "HH:mm"
            return df
        }()

        static func currentTimestamp() -> String {
            "[\(timestampFormatter.string(from: Date()))]"
        }
    }
}

// MARK: - Chat-Style Transcript Viewer

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

    // MARK: - Utterance Splitting (#3)

    private struct Bubble {
        var text: String
        var isNote: Bool
    }

    /// Split transcript into paragraph-level chunks first, then sentences within each paragraph.
    /// This gives better visual separation than splitting purely by punctuation.
    private func splitIntoUtterances(_ text: String) -> [String] {
        guard !text.isEmpty else { return [] }

        // First split by paragraph breaks (double newlines)
        let paragraphs = text.components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        // If we got multiple paragraphs, group sentences within each paragraph into one bubble
        if paragraphs.count > 1 {
            return paragraphs.flatMap { paragraph -> [String] in
                splitParagraphIntoSentenceGroups(paragraph)
            }
        }

        // Single block of text — fall back to splitting by sentences, grouping 2-3 together
        return splitParagraphIntoSentenceGroups(text)
    }

    /// Split a paragraph into groups of 2-3 sentences for better visual chunks.
    private func splitParagraphIntoSentenceGroups(_ paragraph: String) -> [String] {
        var sentences: [String] = []
        var current = ""
        for char in paragraph {
            current.append(char)
            if char == "." || char == "?" || char == "!" {
                let trimmed = current.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty {
                    sentences.append(trimmed)
                }
                current = ""
            }
        }
        let remainder = current.trimmingCharacters(in: .whitespaces)
        if !remainder.isEmpty {
            sentences.append(remainder)
        }

        // Group sentences into chunks of 2-3 for readability
        var groups: [String] = []
        let chunkSize = 3
        for i in stride(from: 0, to: sentences.count, by: chunkSize) {
            let end = min(i + chunkSize, sentences.count)
            let chunk = sentences[i..<end].joined(separator: " ")
            groups.append(chunk)
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
