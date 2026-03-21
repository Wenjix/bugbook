import SwiftUI
import AppKit

/// Meeting block with transcript, notes, and an "Ask anything" AI query bar.
struct MeetingBlockView: View {
    var document: BlockDocument
    let block: Block
    @State private var isRecording = false
    @State private var questionText = ""
    @State private var qaHistory: [(question: String, answer: String, isLoading: Bool)] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            meetingHeader
            meetingContent
            askAnythingBar
            qaList
        }
        .background(Color.fallbackBgSecondary)
        .clipShape(.rect(cornerRadius: Radius.sm))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.sm)
                .stroke(Color.fallbackBorderColor, lineWidth: 1)
        )
    }

    // MARK: - Header

    private var meetingHeader: some View {
        HStack(spacing: 8) {
            if isRecording {
                Circle()
                    .fill(Color.red)
                    .frame(width: 8, height: 8)
                Text("Recording")
                    .font(.system(size: Typography.caption, weight: .medium))
                    .foregroundStyle(.red)
            } else {
                Image(systemName: "waveform")
                    .font(.system(size: Typography.caption))
                    .foregroundStyle(Color.fallbackTextSecondary)
                Text("Meeting")
                    .font(.system(size: Typography.caption, weight: .medium))
                    .foregroundStyle(Color.fallbackTextSecondary)
            }

            Spacer()

            if isRecording {
                Button {
                    isRecording = false
                } label: {
                    Image(systemName: "stop.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(Opacity.subtle))
    }

    // MARK: - Content

    private var meetingContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !block.meetingNotes.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Notes")
                        .font(.system(size: Typography.caption, weight: .medium))
                        .foregroundStyle(Color.fallbackTextSecondary)
                    Text(block.meetingNotes)
                        .font(.system(size: Typography.body))
                        .foregroundStyle(Color.fallbackTextPrimary)
                        .textSelection(.enabled)
                }
            }

            if !block.text.isEmpty {
                DisclosureGroup("Transcript") {
                    Text(block.text)
                        .font(.system(size: Typography.body))
                        .foregroundStyle(Color.fallbackTextPrimary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .font(.system(size: Typography.caption, weight: .medium))
                .foregroundStyle(Color.fallbackTextSecondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Ask Anything Bar

    private var askAnythingBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkle")
                .font(.system(size: 12))
                .foregroundStyle(Color.fallbackTextSecondary)

            TextField("Ask anything about this meeting...", text: $questionText)
                .textFieldStyle(.plain)
                .font(.system(size: Typography.body))
                .onSubmit {
                    submitQuestion()
                }

            if !questionText.isEmpty {
                Button {
                    submitQuestion()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(Color.fallbackAccent)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(Opacity.subtle))
    }

    // MARK: - Q&A History

    @ViewBuilder
    private var qaList: some View {
        if !qaHistory.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(qaHistory.enumerated()), id: \.offset) { _, qa in
                    VStack(alignment: .leading, spacing: 6) {
                        // Question
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "person.circle.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(Color.fallbackTextSecondary)
                            Text(qa.question)
                                .font(.system(size: Typography.body))
                                .foregroundStyle(Color.fallbackTextPrimary)
                        }

                        // Answer
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "sparkle")
                                .font(.system(size: 14))
                                .foregroundStyle(Color.fallbackAccent)
                            if qa.isLoading {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Text(qa.answer)
                                    .font(.system(size: Typography.body))
                                    .foregroundStyle(Color.fallbackTextPrimary)
                                    .textSelection(.enabled)
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)

                    if qaHistory.last?.question != qa.question {
                        Divider()
                            .padding(.horizontal, 12)
                    }
                }
            }
        }
    }

    // MARK: - Ask via Claude CLI

    private func submitQuestion() {
        let question = questionText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else { return }
        questionText = ""

        let index = qaHistory.count
        qaHistory.append((question: question, answer: "", isLoading: true))

        let transcript = block.text
        let notes = block.meetingNotes

        Task.detached {
            let answer = await Self.askClaude(question: question, transcript: transcript, notes: notes)
            await MainActor.run {
                if index < qaHistory.count {
                    qaHistory[index] = (question: question, answer: answer, isLoading: false)
                }
            }
        }
    }

    private static func askClaude(question: String, transcript: String, notes: String) async -> String {
        var contextParts: [String] = []
        if !transcript.isEmpty {
            contextParts.append("Transcript:\n\(transcript)")
        }
        if !notes.isEmpty {
            contextParts.append("Notes:\n\(notes)")
        }
        let context = contextParts.joined(separator: "\n\n")

        let prompt: String
        if context.isEmpty {
            prompt = "The user is asking about a meeting but no transcript or notes are available yet. Question: \(question)"
        } else {
            prompt = "\(context)\n\nQuestion: \(question)"
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["claude", "--model", "haiku", "--print", prompt]

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
            process.waitUntilExit()

            let data = stdout.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            if output.isEmpty {
                let errData = stderr.fileHandleForReading.readDataToEndOfFile()
                let errOutput = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return errOutput.isEmpty ? "No response generated." : "Error: \(errOutput)"
            }

            return output
        } catch {
            return "Failed to run claude CLI: \(error.localizedDescription)"
        }
    }
}
