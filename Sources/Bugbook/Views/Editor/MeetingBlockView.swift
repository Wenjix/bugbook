import SwiftUI

/// A single question/answer pair displayed in the meeting Q&A section.
private struct QAEntry: Identifiable {
    let id = UUID()
    let question: String
    var answer: String
    var isLoading: Bool
}

/// Meeting block view — displays meeting title, transcript, notes,
/// and an "Ask anything" bar that queries AI using the transcript + notes as context.
struct MeetingBlockView: View {
    var document: BlockDocument
    let block: Block
    @State private var questionText = ""
    @State private var qaEntries: [QAEntry] = []
    @State private var isAskingAI = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            meetingHeader

            // Transcript section
            if !block.meetingTranscript.isEmpty {
                sectionView(title: "Transcript", content: block.meetingTranscript)
            }

            // Notes section
            if !block.meetingNotes.isEmpty {
                sectionView(title: "Notes", content: block.meetingNotes)
            }

            // Q&A history
            if !qaEntries.isEmpty {
                qaSection
            }

            // Ask anything bar
            askAnythingBar
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: Radius.md)
                .fill(Color.primary.opacity(Opacity.subtle))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md)
                .strokeBorder(Color.primary.opacity(Opacity.light), lineWidth: 1)
        )
    }

    // MARK: - Subviews

    private var meetingHeader: some View {
        HStack(spacing: 6) {
            Image(systemName: "waveform")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
            Text(block.text.isEmpty ? "Meeting" : block.text)
                .font(.system(size: Typography.body, weight: .semibold))
                .foregroundStyle(.primary)
        }
        .padding(.bottom, 8)
    }

    private func sectionView(title: String, content: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: Typography.caption, weight: .medium))
                .foregroundStyle(Color.fallbackTextSecondary)
            Text(content)
                .font(.system(size: Typography.bodySmall))
                .foregroundStyle(.primary)
                .lineLimit(6)
                .textSelection(.enabled)
        }
        .padding(.bottom, 8)
    }

    private var qaSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(qaEntries) { entry in
                VStack(alignment: .leading, spacing: 4) {
                    // Question
                    HStack(alignment: .top, spacing: 6) {
                        Text("Q:")
                            .font(.system(size: Typography.bodySmall, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Text(entry.question)
                            .font(.system(size: Typography.bodySmall, weight: .medium))
                            .foregroundStyle(.primary)
                    }
                    // Answer
                    HStack(alignment: .top, spacing: 6) {
                        Text("A:")
                            .font(.system(size: Typography.bodySmall, weight: .semibold))
                            .foregroundStyle(.secondary)
                        if entry.isLoading {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Text(entry.answer)
                                .font(.system(size: Typography.bodySmall))
                                .foregroundStyle(.primary)
                                .textSelection(.enabled)
                        }
                    }
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: Radius.sm)
                        .fill(Color.primary.opacity(Opacity.subtle))
                )
            }
        }
        .padding(.bottom, 8)
    }

    private var askAnythingBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            TextField("Ask anything about this meeting...", text: $questionText)
                .textFieldStyle(.plain)
                .font(.system(size: Typography.bodySmall))
                .onSubmit { submitQuestion() }
                .disabled(isAskingAI)
            if isAskingAI {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: Radius.sm)
                .fill(Elevation.popoverBg)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.sm)
                .strokeBorder(Color.primary.opacity(Opacity.light), lineWidth: 1)
        )
    }

    // MARK: - AI Query

    private func submitQuestion() {
        let question = questionText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else { return }
        questionText = ""
        isAskingAI = true

        let entry = QAEntry(question: question, answer: "", isLoading: true)
        qaEntries.append(entry)
        let entryId = entry.id

        Task.detached {
            let answer = await Self.askClaude(
                question: question,
                transcript: block.meetingTranscript,
                notes: block.meetingNotes,
                title: block.text
            )
            await MainActor.run {
                if let idx = qaEntries.firstIndex(where: { $0.id == entryId }) {
                    qaEntries[idx].answer = answer
                    qaEntries[idx].isLoading = false
                }
                isAskingAI = false
            }
        }
    }

    /// Shell out to `claude` CLI with `--model haiku --print` for a fast answer.
    private static func askClaude(question: String, transcript: String, notes: String, title: String) async -> String {
        let contextParts = [
            title.isEmpty ? nil : "Meeting: \(title)",
            transcript.isEmpty ? nil : "Transcript:\n\(transcript)",
            notes.isEmpty ? nil : "Notes:\n\(notes)"
        ].compactMap { $0 }.joined(separator: "\n\n")

        let prompt = """
        Given the following meeting context, answer the question concisely.

        \(contextParts)

        Question: \(question)
        """

        let escaped = prompt
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "`", with: "\\`")
            .replacingOccurrences(of: "$", with: "\\$")

        let command = "claude --model haiku --print \"\(escaped)\""

        return await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/bin/zsh")
                process.arguments = ["-l", "-c", command]
                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = pipe
                do {
                    try process.run()
                    process.waitUntilExit()
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    let output = String(data: data, encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    if process.terminationStatus == 0, !output.isEmpty {
                        continuation.resume(returning: output)
                    } else {
                        continuation.resume(returning: output.isEmpty ? "Could not get an answer. Make sure the Claude CLI is installed." : output)
                    }
                } catch {
                    continuation.resume(returning: "Error: \(error.localizedDescription)")
                }
            }
        }
    }
}
