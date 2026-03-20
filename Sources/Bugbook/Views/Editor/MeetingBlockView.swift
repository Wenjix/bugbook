import SwiftUI

/// Inline meeting recording block with three states: recording, processing, complete.
struct MeetingBlockView: View {
    var document: BlockDocument
    let block: Block
    var transcriptionService: TranscriptionService
    var onStop: () -> Void
    @State private var editingSummary: String = ""
    @State private var isSummaryFocused: Bool = false
    @State private var showTranscript: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch block.meetingState {
            case .recording:
                recordingView
            case .processing:
                processingView
            case .complete:
                completeView
            }
        }
        .padding(12)
        .background(Color.fallbackSurfaceSubtle)
        .clipShape(.rect(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(borderColor, lineWidth: 1)
        )
    }

    private var borderColor: Color {
        switch block.meetingState {
        case .recording: return .red.opacity(0.4)
        case .processing: return .orange.opacity(0.3)
        case .complete: return Color.fallbackDividerColor
        }
    }

    // MARK: - Recording State

    private var recordingView: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                // Pulsing red dot
                Circle()
                    .fill(.red)
                    .frame(width: 8, height: 8)
                    .modifier(PulseModifier())

                Text("Recording...")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)

                Spacer()

                Button {
                    onStop()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "stop.fill")
                            .font(.caption2)
                        Text("Stop")
                            .font(.caption)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.red.opacity(0.12))
                    .foregroundStyle(.red)
                    .clipShape(.capsule)
                }
                .buttonStyle(.plain)
            }

            // Waveform indicator
            waveformView

            // Live transcript
            if !transcriptionService.currentTranscript.isEmpty {
                Text(transcriptionService.currentTranscript)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var waveformView: some View {
        HStack(spacing: 2) {
            ForEach(0..<20, id: \.self) { i in
                WaveformBar(index: i, isActive: transcriptionService.isRecording)
            }
        }
        .frame(height: 24)
    }

    // MARK: - Processing State

    private var processingView: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text("Generating summary...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Complete State

    private var completeView: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Title
            HStack(spacing: 6) {
                Image(systemName: "mic.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(block.meetingTitle.isEmpty ? "Meeting Notes" : block.meetingTitle)
                    .font(.subheadline.weight(.semibold))
            }

            // Summary — editable
            if !block.meetingSummary.isEmpty || isSummaryFocused {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Summary")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    TextEditor(text: $editingSummary)
                        .font(.caption)
                        .foregroundStyle(.primary)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 40, maxHeight: 120)
                        .fixedSize(horizontal: false, vertical: true)
                        .onAppear { editingSummary = block.meetingSummary }
                        .onChange(of: editingSummary) { _, newValue in
                            document.updateBlockProperty(id: block.id) { b in
                                b.meetingSummary = newValue
                            }
                        }
                }
            }

            // Action items
            if !block.meetingActionItems.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Action Items")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    Text(block.meetingActionItems)
                        .font(.caption)
                        .foregroundStyle(.primary)
                }
            }

            // View transcript
            if !block.meetingTranscript.isEmpty {
                Button { showTranscript = true } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.text")
                            .font(.caption2)
                        Text("View Transcript")
                            .font(.caption.weight(.medium))
                    }
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .sheet(isPresented: $showTranscript) {
                    transcriptSheet
                }
            }
        }
    }
    private var transcriptSheet: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(block.meetingTitle.isEmpty ? "Meeting Transcript" : block.meetingTitle)
                    .font(.headline)
                Spacer()
                Button("Done") { showTranscript = false }
                    .keyboardShortcut(.cancelAction)
            }
            .padding()

            Divider()

            ScrollView {
                Text(block.meetingTranscript)
                    .font(.body)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
        }
        .frame(minWidth: 500, minHeight: 400)
    }
}

// MARK: - Waveform Bar

private struct WaveformBar: View {
    let index: Int
    let isActive: Bool

    @State private var height: CGFloat = 4

    var body: some View {
        RoundedRectangle(cornerRadius: 1)
            .fill(isActive ? Color.red.opacity(0.6) : Color.secondary.opacity(0.2))
            .frame(width: 3, height: height)
            .onAppear {
                guard isActive else { return }
                withAnimation(
                    .easeInOut(duration: Double.random(in: 0.3...0.6))
                    .repeatForever(autoreverses: true)
                    .delay(Double(index) * 0.05)
                ) {
                    height = CGFloat.random(in: 6...22)
                }
            }
            .onChange(of: isActive) { _, active in
                if !active {
                    withAnimation(.easeOut(duration: 0.2)) {
                        height = 4
                    }
                }
            }
    }
}

// MARK: - Pulse Modifier

private struct PulseModifier: ViewModifier {
    @State private var isPulsing = false

    func body(content: Content) -> some View {
        content
            .opacity(isPulsing ? 0.3 : 1.0)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                    isPulsing = true
                }
            }
    }
}
