import SwiftUI

/// Floating meeting summary panel. Placed inside a meeting note page to generate
/// structured output from raw transcript text and user notes.
struct MeetingBlockView: View {
    var document: BlockDocument
    var transcriptionService: TranscriptionService
    var settings: AppSettings

    @State private var isExpanded = false
    @State private var rawTranscript = ""
    @State private var showResult = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerRow

            if isExpanded {
                transcriptInput
                generateButton
            }

            if showResult, let error = transcriptionService.error {
                errorBanner(error)
            }
        }
        .padding(16)
        .background(Color.fallbackBgSecondary)
        .clipShape(.rect(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.fallbackDividerColor, lineWidth: 1)
        )
    }

    // MARK: - Subviews

    private var headerRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "waveform")
                .foregroundStyle(.secondary)
                .font(.system(size: 14))

            Text("Meeting Summary")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.fallbackTextPrimary)

            Spacer()

            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
        }
    }

    private var transcriptInput: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Paste raw transcript")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            TextEditor(text: $rawTranscript)
                .font(.system(size: 13, design: .monospaced))
                .frame(minHeight: 100, maxHeight: 200)
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(Color.fallbackEditorBg)
                .clipShape(.rect(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.fallbackDividerColor, lineWidth: 1)
                )
        }
    }

    private var generateButton: some View {
        Button {
            Task { await generateSummary() }
        } label: {
            HStack(spacing: 6) {
                if transcriptionService.isGenerating {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "sparkles")
                        .font(.system(size: 12))
                }
                Text(transcriptionService.isGenerating ? "Generating..." : "Generate Summary")
                    .font(.system(size: 13, weight: .medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(Color.accentColor.opacity(transcriptionService.isGenerating ? 0.5 : 1))
            .foregroundStyle(.white)
            .clipShape(.rect(cornerRadius: 6))
        }
        .buttonStyle(.borderless)
        .disabled(rawTranscript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || transcriptionService.isGenerating)
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 12))
            Text(message)
                .font(.system(size: 12))
                .lineLimit(3)
        }
        .foregroundStyle(.red)
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.red.opacity(0.08))
        .clipShape(.rect(cornerRadius: 6))
    }

    // MARK: - Generate

    private func generateSummary() async {
        showResult = true

        // Gather user notes from the current document blocks
        let userNotes = extractUserNotes()

        do {
            let output = try await transcriptionService.generateStructuredSummary(
                rawTranscript: rawTranscript,
                userNotes: userNotes,
                engine: settings.preferredAIEngine,
                workspacePath: document.workspacePath ?? "",
                apiKey: settings.anthropicApiKey
            )

            // Replace the document content with structured output
            let markdown = transcriptionService.renderMarkdown(from: output)
            replaceDocumentContent(with: markdown)

            withAnimation {
                isExpanded = false
                rawTranscript = ""
            }
        } catch {
            // Error is already stored in transcriptionService.error
        }
    }

    /// Extract text from existing Notes / bullet blocks in the document as user notes.
    private func extractUserNotes() -> String {
        var capturing = false
        var notes: [String] = []

        for block in document.blocks {
            // Start capturing after a "Notes" heading
            if block.type == .heading, block.text.lowercased().trimmingCharacters(in: .whitespaces) == "notes" {
                capturing = true
                continue
            }
            // Stop capturing at the next heading
            if capturing, block.type == .heading {
                break
            }
            if capturing, !block.text.isEmpty {
                notes.append(block.text)
            }
        }

        return notes.joined(separator: "\n")
    }

    /// Replace the document blocks with parsed markdown content.
    private func replaceDocumentContent(with markdown: String) {
        let lines = markdown.components(separatedBy: "\n")
        var newBlocks: [Block] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("# ") {
                newBlocks.append(Block(type: .heading, text: String(trimmed.dropFirst(2)), headingLevel: 1))
            } else if trimmed.hasPrefix("## ") {
                newBlocks.append(Block(type: .heading, text: String(trimmed.dropFirst(3)), headingLevel: 2))
            } else if trimmed.hasPrefix("### ") {
                newBlocks.append(Block(type: .heading, text: String(trimmed.dropFirst(4)), headingLevel: 3))
            } else if trimmed.hasPrefix("- [x] ") || trimmed.hasPrefix("- [X] ") {
                newBlocks.append(Block(type: .taskItem, text: String(trimmed.dropFirst(6)), isChecked: true))
            } else if trimmed.hasPrefix("- [ ] ") {
                newBlocks.append(Block(type: .taskItem, text: String(trimmed.dropFirst(6)), isChecked: false))
            } else if trimmed.hasPrefix("- ") {
                newBlocks.append(Block(type: .bulletListItem, text: String(trimmed.dropFirst(2))))
            } else if trimmed == "---" {
                newBlocks.append(Block(type: .horizontalRule))
            } else if trimmed.isEmpty {
                // Skip consecutive empty lines but keep one paragraph break
                if let last = newBlocks.last, last.type != .paragraph || !last.text.isEmpty {
                    newBlocks.append(Block(type: .paragraph, text: ""))
                }
            } else {
                newBlocks.append(Block(type: .paragraph, text: trimmed))
            }
        }

        // Ensure at least one block
        if newBlocks.isEmpty {
            newBlocks.append(Block(type: .paragraph, text: ""))
        }

        document.blocks = newBlocks
    }
}
