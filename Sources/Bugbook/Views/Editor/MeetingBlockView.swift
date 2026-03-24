import SwiftUI

/// Meeting block view with three states: before (ready to record), during (recording),
/// and after (summary generated). Uses the same card shell across all states.
struct MeetingBlockView: View {
    var document: BlockDocument
    let block: Block

    @State private var title: String
    @State private var notes: String
    @State private var isTranscriptOpen = false
    @State private var isSummaryExpanded = false
    @State private var activeTab: MeetingTab = .summary
    @State private var isHovered = false
    @State private var waveformPhase: CGFloat = 0
    @State private var hasVoiceActivity = false

    enum MeetingTab {
        case summary
        case notes
    }

    init(document: BlockDocument, block: Block) {
        self.document = document
        self.block = block
        _title = State(initialValue: block.meetingTitle)
        _notes = State(initialValue: block.meetingNotes)
    }

    var body: some View {
        VStack(spacing: 0) {
            switch block.meetingState {
            case .before:
                beforeStateView
            case .during:
                duringStateView
            case .after:
                afterStateView
            }
        }
        .background(Color.fallbackCardBg)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg)
                .strokeBorder(Color.fallbackBorderColor, lineWidth: 1)
        )
        .onHover { isHovered = $0 }
        .padding(.vertical, 4)
    }

    // MARK: - Before State

    private var beforeStateView: some View {
        VStack(spacing: 0) {
            // Header: title + record button
            HStack(spacing: 10) {
                TextField("New Meeting", text: $title)
                    .textFieldStyle(.plain)
                    .font(.system(size: Typography.body, weight: .medium))
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

            Divider()

            // Empty notes area
            TextEditor(text: $notes)
                .font(.system(size: Typography.body))
                .foregroundStyle(Color.fallbackTextPrimary)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 80)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .overlay(alignment: .topLeading) {
                    if notes.isEmpty {
                        Text("Write notes...")
                            .font(.system(size: Typography.body))
                            .foregroundStyle(Color.fallbackTextMuted)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .allowsHitTesting(false)
                    }
                }
                .onChange(of: notes) { _, newVal in
                    document.updateMeetingNotes(blockId: block.id, notes: newVal)
                }
        }
    }

    // MARK: - During State

    private var duringStateView: some View {
        VStack(spacing: 0) {
            // Header: pulsing red dot, title, ladybug AI button, Stop
            HStack(spacing: 10) {
                PulsingDot()

                TextField("New Meeting", text: $title)
                    .textFieldStyle(.plain)
                    .font(.system(size: Typography.body, weight: .medium))
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

            Divider()

            // Wide notes area
            TextEditor(text: $notes)
                .font(.system(size: Typography.body))
                .foregroundStyle(Color.fallbackTextPrimary)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 160)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .overlay(alignment: .topLeading) {
                    if notes.isEmpty {
                        Text("Write notes...")
                            .font(.system(size: Typography.body))
                            .foregroundStyle(Color.fallbackTextMuted)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .allowsHitTesting(false)
                    }
                }
                .onChange(of: notes) { _, newVal in
                    document.updateMeetingNotes(blockId: block.id, notes: newVal)
                }

            Divider()

            // Bottom bar: waveform + chevron, entire bar clickable
            bottomBar(showWaveform: true)

            // Transcript drawer
            if isTranscriptOpen {
                transcriptDrawer
            }
        }
    }

    // MARK: - After State

    private var afterStateView: some View {
        VStack(spacing: 0) {
            // Header: title + date/duration, ladybug, expand, dropdown, Resume
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(block.meetingTitle.isEmpty ? "Meeting" : block.meetingTitle)
                        .font(.system(size: Typography.body, weight: .medium))
                        .foregroundStyle(Color.fallbackTextPrimary)

                    HStack(spacing: 6) {
                        if let date = block.meetingStartDate {
                            Text(date, style: .date)
                                .font(.system(size: Typography.caption))
                                .foregroundStyle(Color.fallbackTextSecondary)
                        }
                        if block.meetingDuration > 0 {
                            Text(formatDuration(block.meetingDuration))
                                .font(.system(size: Typography.caption))
                                .foregroundStyle(Color.fallbackTextSecondary)
                        }
                    }
                }

                Spacer()

                ladybugButton

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

                // Summary/Notes dropdown
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

            Divider()

            // Content area: Summary or Notes
            switch activeTab {
            case .summary:
                summaryView
            case .notes:
                notesView
            }

            Divider()

            // Bottom bar: "Transcript" label + chevron + duration
            bottomBar(showWaveform: false)

            // Transcript drawer
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
                    // Key decisions
                    if !block.meetingKeyDecisions.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Key Decisions")
                                .font(.system(size: Typography.bodySmall, weight: .semibold))
                                .foregroundStyle(Color.fallbackTextPrimary)

                            ForEach(block.meetingKeyDecisions, id: \.self) { decision in
                                HStack(alignment: .top, spacing: 6) {
                                    Image(systemName: "checkmark.diamond.fill")
                                        .font(.system(size: 10))
                                        .foregroundStyle(StatusColor.success)
                                        .padding(.top, 2)
                                    Text(decision)
                                        .font(.system(size: Typography.bodySmall))
                                        .foregroundStyle(Color.fallbackTextPrimary)
                                }
                            }
                        }
                    }

                    // Action items
                    if !block.meetingActionItems.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Action Items")
                                .font(.system(size: Typography.bodySmall, weight: .semibold))
                                .foregroundStyle(Color.fallbackTextPrimary)

                            ForEach(block.meetingActionItems) { item in
                                HStack(alignment: .top, spacing: 6) {
                                    Image(systemName: item.isChecked ? "checkmark.square.fill" : "square")
                                        .font(.system(size: 12))
                                        .foregroundStyle(item.isChecked ? StatusColor.success : Color.fallbackTextSecondary)
                                        .onTapGesture {
                                            document.toggleMeetingActionItem(blockId: block.id, itemId: item.id)
                                        }
                                    Text(item.text)
                                        .font(.system(size: Typography.bodySmall))
                                        .foregroundStyle(Color.fallbackTextPrimary)
                                        .strikethrough(item.isChecked, color: Color.fallbackTextMuted)
                                }
                            }
                        }
                    }

                    // Discussion notes
                    if !block.meetingDiscussionNotes.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Discussion Notes")
                                .font(.system(size: Typography.bodySmall, weight: .semibold))
                                .foregroundStyle(Color.fallbackTextPrimary)

                            Text(block.meetingDiscussionNotes)
                                .font(.system(size: Typography.bodySmall))
                                .foregroundStyle(Color.fallbackTextSecondary)
                        }
                    }

                    if block.meetingKeyDecisions.isEmpty && block.meetingActionItems.isEmpty && block.meetingDiscussionNotes.isEmpty {
                        Text("No summary generated yet.")
                            .font(.system(size: Typography.bodySmall))
                            .foregroundStyle(Color.fallbackTextMuted)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 20)
                    }
                }
                .padding(14)
            }
            .frame(maxHeight: isSummaryExpanded ? nil : 200)
            .clipped()

            // Fade gradient at bottom when collapsed
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
            if block.meetingNotes.isEmpty {
                Text("No notes recorded.")
                    .font(.system(size: Typography.bodySmall))
                    .foregroundStyle(Color.fallbackTextMuted)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            } else {
                Text(block.meetingNotes)
                    .font(.system(size: Typography.bodySmall))
                    .foregroundStyle(Color.fallbackTextPrimary)
                    .textSelection(.enabled)
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
        }) {
            HStack(spacing: 8) {
                if showWaveform {
                    WaveformView(isActive: hasVoiceActivity, phase: waveformPhase)
                        .frame(width: 40, height: 16)
                } else {
                    Text("Transcript")
                        .font(.system(size: Typography.caption, weight: .medium))
                        .foregroundStyle(Color.fallbackTextSecondary)
                }

                Spacer()

                if !showWaveform && block.meetingDuration > 0 {
                    Text(formatDuration(block.meetingDuration))
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
        .background(Color.primary.opacity(Opacity.subtle))
    }

    // MARK: - Transcript Drawer

    private var transcriptDrawer: some View {
        VStack(spacing: 0) {
            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(block.meetingTranscript) { entry in
                        transcriptBubble(entry)
                    }

                    if block.meetingState == .during {
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
            .frame(maxHeight: 200)
        }
        .transition(.asymmetric(
            insertion: .push(from: .bottom).combined(with: .opacity),
            removal: .push(from: .top).combined(with: .opacity)
        ))
    }

    private func transcriptBubble(_ entry: TranscriptEntry) -> some View {
        HStack {
            if entry.isUser { Spacer(minLength: 40) }

            VStack(alignment: entry.isUser ? .trailing : .leading, spacing: 1) {
                Text(entry.text)
                    .font(.system(size: Typography.caption2))
                    .foregroundStyle(entry.isUser ? .white : Color.fallbackTextPrimary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(entry.isUser
                        ? Color(light: Color(hex: "37352f"), dark: Color(hex: "d4d4d0"))
                        : Color.primary.opacity(Opacity.light))
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md))

                Text(entry.timestamp, style: .time)
                    .font(.system(size: 9))
                    .foregroundStyle(Color.fallbackTextMuted)
            }

            if !entry.isUser { Spacer(minLength: 40) }
        }
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

    // MARK: - Actions

    private func startRecording() {
        document.updateMeetingState(blockId: block.id, state: .during)
    }

    private func stopRecording() {
        document.updateMeetingState(blockId: block.id, state: .after)
    }

    private func resumeRecording() {
        document.updateMeetingState(blockId: block.id, state: .during)
    }

    private func openAiWithContext() {
        var context = ""
        if !block.meetingTitle.isEmpty {
            context += "# Meeting: \(block.meetingTitle)\n\n"
        }
        if !block.meetingNotes.isEmpty {
            context += "## Notes\n\(block.meetingNotes)\n\n"
        }
        if !block.meetingTranscript.isEmpty {
            context += "## Transcript\n"
            for entry in block.meetingTranscript {
                let speaker = entry.isUser ? "You" : "Other"
                context += "[\(speaker)] \(entry.text)\n"
            }
        }
        document.onOpenAiPanelWithContext?(context)
    }

    // MARK: - Helpers

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        }
        return "\(seconds)s"
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
