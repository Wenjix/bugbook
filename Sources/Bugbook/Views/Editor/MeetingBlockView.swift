import SwiftUI

struct MeetingBlockView: View {
    var document: BlockDocument
    let block: Block

    @State private var transcription = TranscriptionService()
    @State private var meetingNotes: String
    @State private var showTranscript = false

    init(document: BlockDocument, block: Block) {
        self.document = document
        self.block = block
        self._meetingNotes = State(initialValue: block.meetingNotes)
    }

    private var hasTranscript: Bool {
        !block.text.isEmpty || !transcription.currentTranscript.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "mic.fill")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(transcription.isRecording ? StatusColor.error : Color.fallbackTextSecondary)

                Text("Meeting Recording")
                    .font(.system(size: Typography.body, weight: .medium))
                    .foregroundStyle(Color.fallbackTextPrimary)

                Spacer()

                recordButton
            }

            if transcription.isRecording {
                AudioBarsView(audioLevel: transcription.audioLevel)
                    .frame(height: 32)
            }

            if let error = transcription.error {
                Text(error)
                    .font(.system(size: Typography.caption))
                    .foregroundStyle(StatusColor.error)
            }

            transcriptSection
            notesSection

            if hasTranscript || !meetingNotes.isEmpty {
                summaryButton
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: Radius.md)
                .fill(Color.fallbackBgTertiary.opacity(0.5))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md)
                .strokeBorder(transcription.isRecording ? StatusColor.error.opacity(0.3) : Color.fallbackBorderColor, lineWidth: 1)
        )
        .onChange(of: transcription.currentTranscript) { _, newVal in
            guard transcription.isRecording else { return }
            document.updateBlockProperty(id: block.id) { $0.text = newVal }
        }
        .onChange(of: meetingNotes) { _, newVal in
            document.updateBlockProperty(id: block.id) { $0.meetingNotes = newVal }
        }
        .sheet(isPresented: $showTranscript) {
            transcriptModal
        }
    }

    // MARK: - Record Button

    private var recordButton: some View {
        Button {
            Task {
                if transcription.isRecording {
                    let finalText = transcription.stopRecording()
                    document.updateBlockProperty(id: block.id) { $0.text = finalText }
                } else {
                    await transcription.startRecording()
                }
            }
        } label: {
            HStack(spacing: 6) {
                Circle()
                    .fill(transcription.isRecording ? StatusColor.error : StatusColor.neutral)
                    .frame(width: 8, height: 8)

                Text(transcription.isRecording ? "Stop" : "Record")
                    .font(.system(size: Typography.caption, weight: .medium))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: Radius.sm)
                    .fill(transcription.isRecording ? StatusColor.error.opacity(Opacity.medium) : Color.primary.opacity(Opacity.light))
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Transcript Section

    @ViewBuilder
    private var transcriptSection: some View {
        let displayText = transcription.isRecording ? transcription.currentTranscript : block.text

        if !displayText.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("Transcript")
                    .font(.system(size: Typography.caption, weight: .medium))
                    .foregroundStyle(Color.fallbackTextSecondary)

                if transcription.isRecording {
                    Text(displayText)
                        .font(.system(size: Typography.body))
                        .foregroundStyle(Color.fallbackTextPrimary)
                        .lineLimit(6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Button { showTranscript = true } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "doc.text")
                                .font(.system(size: Typography.caption))
                            Text("View Transcript")
                                .font(.system(size: Typography.caption, weight: .medium))
                        }
                        .foregroundStyle(Color.fallbackTextSecondary)
                    }
                    .buttonStyle(.plain)
                }
            }
        } else if !transcription.isRecording {
            Text("Click Record to start capturing audio and live transcription.")
                .font(.system(size: Typography.body))
                .foregroundStyle(Color.fallbackTextSecondary)
                .italic()
        }
    }

    // MARK: - Transcript Modal

    private var transcriptModal: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Transcript")
                    .font(.system(size: Typography.title2, weight: .semibold))
                    .foregroundStyle(Color.fallbackTextPrimary)

                Spacer()

                Button { showTranscript = false } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.fallbackTextSecondary)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)

            Divider()

            ScrollView {
                Text(block.text)
                    .font(.system(size: Typography.body))
                    .foregroundStyle(Color.fallbackTextPrimary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
            }
            .frame(maxHeight: .infinity)
        }
        .frame(width: 560, height: 480)
    }

    // MARK: - Notes Section

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Notes")
                .font(.system(size: Typography.caption, weight: .medium))
                .foregroundStyle(Color.fallbackTextSecondary)

            TextEditor(text: $meetingNotes)
                .font(.system(size: Typography.body))
                .scrollContentBackground(.hidden)
                .frame(minHeight: 60)
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: Radius.xs)
                        .fill(Color.fallbackBgPrimary)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.xs)
                        .strokeBorder(Color.fallbackBorderColor, lineWidth: 1)
                )
        }
    }

    // MARK: - Summary Button

    private var summaryButton: some View {
        Button {
            generateSummary()
        } label: {
            HStack(spacing: 6) {
                if document.isAiGenerating {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "sparkles")
                        .font(.system(size: 12))
                }
                Text(document.isAiGenerating ? "Generating..." : "Generate Summary")
                    .font(.system(size: Typography.caption, weight: .medium))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: Radius.sm)
                    .fill(Brand.subtle)
            )
        }
        .buttonStyle(.plain)
        .disabled(document.isAiGenerating || (!hasTranscript && meetingNotes.isEmpty))
    }

    // MARK: - Summary Generation

    private func generateSummary() {
        var prompt = "Summarize this meeting into key points, decisions, and action items.\n\n"
        if !block.text.isEmpty {
            prompt += "## Transcript\n\(block.text)\n\n"
        }
        if !meetingNotes.isEmpty {
            prompt += "## Notes\n\(meetingNotes)\n\n"
        }

        document.aiPromptText = prompt
        document.submitAiPrompt()
    }
}

// MARK: - Audio Bars View

struct AudioBarsView: View {
    var audioLevel: Float
    private let barCount = 12

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.05)) { timeline in
            HStack(spacing: 3) {
                ForEach(0..<barCount, id: \.self) { index in
                    barView(index: index, date: timeline.date)
                }
            }
        }
    }

    private func barView(index: Int, date: Date) -> some View {
        let seed = sin(date.timeIntervalSinceReferenceDate * 6 + Double(index) * 1.3)
        let jitter = Float(seed + 1) / 2 // 0...1
        let level = max(0.08, min(1.0, audioLevel * (0.5 + jitter)))
        let height: CGFloat = CGFloat(level) * 28 + 4

        return RoundedRectangle(cornerRadius: 2)
            .fill(StatusColor.error.opacity(0.6 + Double(audioLevel) * 0.4))
            .frame(width: 4, height: height)
            .animation(.easeInOut(duration: 0.08), value: height)
    }
}
