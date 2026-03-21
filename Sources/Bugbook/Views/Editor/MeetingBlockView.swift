import SwiftUI
import AppKit

/// Notes-first meeting recording block. Shows a prominent notes area with
/// the live transcript hidden behind a disclosure toggle.
struct MeetingBlockView: View {
    var document: BlockDocument
    let block: Block
    @State private var isRecording = false
    @State private var showTranscript = false
    @State private var audioLevel: CGFloat = 0.3

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            recordingHeader
            if isRecording {
                waveformIndicator
            }
            notesArea
            transcriptToggle
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.secondary.opacity(0.2), lineWidth: 1)
        )
    }

    // MARK: - Recording Header

    private var recordingHeader: some View {
        HStack(spacing: 8) {
            if isRecording {
                PulsingDotView()
                Text("Recording...")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            } else if !block.text.isEmpty || !block.meetingNotes.isEmpty {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.system(size: 12))
                Text("Recording complete")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            } else {
                Image(systemName: "mic.fill")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 12))
                Text("Meeting")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                isRecording.toggle()
            } label: {
                Text(isRecording ? "Stop" : "Record")
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
        }
    }

    // MARK: - Waveform

    private var waveformIndicator: some View {
        HStack(spacing: 2) {
            ForEach(0..<20, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.red.opacity(0.6))
                    .frame(width: 3, height: barHeight(for: index))
            }
        }
        .frame(height: 20)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private func barHeight(for index: Int) -> CGFloat {
        // Deterministic wave pattern based on index and audio level
        let base = sin(Double(index) * 0.7) * 0.5 + 0.5
        return max(3, CGFloat(base) * 18 * audioLevel)
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
                    .font(.system(size: 13))
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 8)
                    .padding(.top, 8)
                    .allowsHitTesting(false)
            }
        }
        .frame(minHeight: 120)
    }

    // MARK: - Transcript Toggle

    private var transcriptToggle: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    showTranscript.toggle()
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .medium))
                        .rotationEffect(.degrees(showTranscript ? 90 : 0))
                    Text("Show transcript")
                        .font(.system(size: 12))
                    if !block.text.isEmpty {
                        Text("(\(block.text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.count) words)")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }
                }
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)

            if showTranscript {
                ScrollView {
                    Text(block.text.isEmpty ? "No transcript yet..." : block.text)
                        .font(.system(size: 12))
                        .foregroundStyle(block.text.isEmpty ? .tertiary : .secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                }
                .frame(maxHeight: 200)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(nsColor: .textBackgroundColor).opacity(0.5))
                )
                .padding(.top, 6)
            }
        }
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
        textView.font = .systemFont(ofSize: 13)
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
            // Restore selection if still valid
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
