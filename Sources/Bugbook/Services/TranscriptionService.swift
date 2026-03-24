import Foundation

/// Parsed result from AI-generated meeting summary.
struct MeetingStructuredOutput {
    var title: String
    var summary: String
    var topics: [(heading: String, body: String)]
    var actionItems: [(text: String, isChecked: Bool)]
    var cleanedTranscript: String
    var userNotes: String
}

@MainActor
@Observable
class TranscriptionService {
    var isGenerating = false
    var error: String?

    private let aiService: AiService

    init(aiService: AiService) {
        self.aiService = aiService
    }

    // MARK: - Structured Summary Generation

    /// Generate a structured meeting document from raw transcript and user notes.
    /// Returns markdown text with AI-extracted title, topics, action items, and cleaned transcript.
    func generateStructuredSummary(
        rawTranscript: String,
        userNotes: String,
        engine: PreferredAIEngine,
        workspacePath: String,
        apiKey: String = ""
    ) async throws -> MeetingStructuredOutput {
        isGenerating = true
        error = nil
        defer { isGenerating = false }

        let prompt = buildPrompt(rawTranscript: rawTranscript, userNotes: userNotes)

        do {
            let response = try await aiService.generateContent(
                engine: engine,
                workspacePath: workspacePath,
                prompt: prompt,
                apiKey: apiKey
            )
            return parseResponse(response, userNotes: userNotes)
        } catch {
            self.error = error.localizedDescription
            throw error
        }
    }

    /// Convert structured output back to markdown for insertion into a page.
    func renderMarkdown(from output: MeetingStructuredOutput) -> String {
        var lines: [String] = []

        // Title
        lines.append("# \(output.title)")
        lines.append("")

        // Summary
        if !output.summary.isEmpty {
            lines.append("## Summary")
            lines.append("")
            lines.append(output.summary)
            lines.append("")
        }

        // Key Topics
        for topic in output.topics {
            lines.append("## \(topic.heading)")
            lines.append("")
            lines.append(topic.body)
            lines.append("")
        }

        // Action Items
        if !output.actionItems.isEmpty {
            lines.append("## Action Items")
            lines.append("")
            for item in output.actionItems {
                let checkbox = item.isChecked ? "- [x]" : "- [ ]"
                lines.append("\(checkbox) \(item.text)")
            }
            lines.append("")
        }

        // User Notes (inline)
        if !output.userNotes.isEmpty {
            lines.append("## Notes")
            lines.append("")
            lines.append(output.userNotes)
            lines.append("")
        }

        // Cleaned Transcript
        if !output.cleanedTranscript.isEmpty {
            lines.append("## Transcript")
            lines.append("")
            lines.append(output.cleanedTranscript)
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Prompt

    private func buildPrompt(rawTranscript: String, userNotes: String) -> String {
        """
        You are processing a meeting recording. Given the raw transcript and user notes below, \
        produce a structured meeting document in markdown.

        Rules:
        - Clean the transcript: remove filler words (um, uh, like, you know, so, basically, right), \
        fix grammar, remove false starts and repetitions. Keep the meaning intact.
        - Extract a concise meeting title (no # prefix, just the text).
        - Write a 2-3 sentence summary of the meeting.
        - Identify key topics discussed and create a ## heading for each with a brief paragraph.
        - Extract action items as checkbox list items (- [ ] format).
        - Integrate the user's notes where relevant.

        Output format (use EXACTLY this structure):
        TITLE: <meeting title>

        ## Summary
        <2-3 sentence summary>

        ## <Topic 1>
        <paragraph about topic 1>

        ## <Topic 2>
        <paragraph about topic 2>

        ## Action Items
        - [ ] <action item 1>
        - [ ] <action item 2>

        ## Notes
        <user notes integrated with context>

        ## Transcript
        <cleaned transcript>

        ---

        RAW TRANSCRIPT:
        \(rawTranscript)

        USER NOTES:
        \(userNotes.isEmpty ? "(none)" : userNotes)
        """
    }

    // MARK: - Parsing

    private func parseResponse(_ response: String, userNotes: String) -> MeetingStructuredOutput {
        let lines = response.components(separatedBy: "\n")

        var title = ""
        var summary = ""
        var topics: [(heading: String, body: String)] = []
        var actionItems: [(text: String, isChecked: Bool)] = []
        var cleanedTranscript = ""
        var notes = ""

        enum Section {
            case none, summary, topic, actionItems, notes, transcript
        }

        var currentSection: Section = .none
        var currentTopicHeading = ""
        var currentTopicBody: [String] = []
        var sectionBody: [String] = []

        func flushTopic() {
            if !currentTopicHeading.isEmpty {
                topics.append((heading: currentTopicHeading, body: currentTopicBody.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)))
                currentTopicHeading = ""
                currentTopicBody = []
            }
        }

        func flushSection() {
            let text = sectionBody.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            switch currentSection {
            case .summary: summary = text
            case .notes: notes = text
            case .transcript: cleanedTranscript = text
            default: break
            }
            sectionBody = []
        }

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Parse title line
            if trimmed.hasPrefix("TITLE:") {
                title = trimmed.replacingOccurrences(of: "TITLE:", with: "").trimmingCharacters(in: .whitespaces)
                continue
            }

            // Detect section headings
            if trimmed.hasPrefix("## ") {
                flushSection()
                flushTopic()

                let heading = trimmed.replacingOccurrences(of: "## ", with: "")
                let headingLower = heading.lowercased()

                if headingLower == "summary" {
                    currentSection = .summary
                } else if headingLower == "action items" {
                    currentSection = .actionItems
                } else if headingLower == "notes" {
                    currentSection = .notes
                } else if headingLower == "transcript" {
                    currentSection = .transcript
                } else {
                    // It's a topic heading
                    currentSection = .topic
                    currentTopicHeading = heading
                }
                continue
            }

            // Parse action items
            if currentSection == .actionItems {
                if trimmed.hasPrefix("- [x]") || trimmed.hasPrefix("- [X]") {
                    let text = trimmed.dropFirst(5).trimmingCharacters(in: .whitespaces)
                    actionItems.append((text: text, isChecked: true))
                } else if trimmed.hasPrefix("- [ ]") {
                    let text = trimmed.dropFirst(5).trimmingCharacters(in: .whitespaces)
                    actionItems.append((text: text, isChecked: false))
                } else if trimmed.hasPrefix("- ") {
                    // Treat unformatted list items as unchecked action items
                    let text = trimmed.dropFirst(2).trimmingCharacters(in: .whitespaces)
                    if !text.isEmpty {
                        actionItems.append((text: text, isChecked: false))
                    }
                }
                continue
            }

            // Accumulate body text for current section
            if currentSection == .topic {
                currentTopicBody.append(line)
            } else {
                sectionBody.append(line)
            }
        }

        // Flush remaining
        flushSection()
        flushTopic()

        // Fallback: if title is empty, use first line or default
        if title.isEmpty {
            title = "Meeting Notes"
        }

        // Use original user notes if AI didn't return a notes section
        if notes.isEmpty {
            notes = userNotes
        }

        return MeetingStructuredOutput(
            title: title,
            summary: summary,
            topics: topics,
            actionItems: actionItems,
            cleanedTranscript: cleanedTranscript,
            userNotes: notes
        )
    }
}
