import Foundation
import DahsoCore

@MainActor
@Observable
class MeetingNoteService {
    var isCreating = false
    var error: String?

    @ObservationIgnored private let fm = FileManager.default
    @ObservationIgnored private let eventStore = CalendarEventStore()

    // MARK: - Create Meeting Note

    /// Creates a meeting note page for a calendar event, or returns the existing linked page.
    /// Returns the file path to navigate to.
    func createOrOpenMeetingNote(
        for event: CalendarEvent,
        workspace: String
    ) async -> String? {
        // If already linked, return existing path
        if let existing = event.linkedPagePath,
           fm.fileExists(atPath: existing) {
            return existing
        }

        isCreating = true
        defer { isCreating = false }

        // Build the page content
        let content = buildMeetingNoteContent(for: event)
        let filename = sanitizeFilename(event.title)
        let dateStr = formatDateForFilename(event.startDate)
        let pageName = "\(dateStr) — \(filename)"
        let pagePath = (workspace as NSString).appendingPathComponent("\(pageName).md")

        // Check if a note with this name already exists
        if fm.fileExists(atPath: pagePath) {
            // Link the event to the existing note
            try? eventStore.linkEventToPage(eventId: event.id, pagePath: pagePath, in: workspace)
            return pagePath
        }

        // Create the page off the main thread
        let event = event
        let workspace = workspace
        do {
            try await Task.detached {
                try content.write(toFile: pagePath, atomically: true, encoding: .utf8)
            }.value
            try eventStore.linkEventToPage(eventId: event.id, pagePath: pagePath, in: workspace)

            // Create person pages for attendees
            await Task.detached { [fm] in
                self.ensurePersonPagesSync(for: event.attendees, workspace: workspace, fm: fm)
            }.value

            return pagePath
        } catch {
            self.error = error.localizedDescription
            return nil
        }
    }

    // MARK: - Import Recording

    /// Create a meeting note from an imported audio recording.
    /// Transcribes the file, generates an AI summary (if API key available), and writes the note.
    /// Returns the file path to navigate to.
    func importRecording(
        fileURL: URL,
        workspace: String,
        transcriptionService: TranscriptionService,
        aiService: AiService,
        apiKey: String,
        model: AnthropicModel
    ) async -> String? {
        isCreating = true
        defer { isCreating = false }

        do {
            let segments = try await transcriptionService.transcribe(fileURL: fileURL)
            let transcript = TranscriptionService.markdownFromSegments(segments)

            // Build filename from recording name
            let baseName = (fileURL.lastPathComponent as NSString).deletingPathExtension
            let dateStr = formatDateForFilename(Date())
            let pageName = "\(dateStr) — \(Self.sanitize(baseName))"
            let pagePath = (workspace as NSString).appendingPathComponent("\(pageName).md")

            // Build content
            var content = buildImportedRecordingContent(
                title: baseName,
                segments: segments,
                transcript: transcript
            )

            // Try AI summary if API key available
            if !apiKey.isEmpty {
                let plainTranscript = segments.map { $0.text }.joined(separator: " ")
                if let summary = try? await aiService.summarizeTranscript(plainTranscript, apiKey: apiKey, model: model) {
                    content = content.replacingOccurrences(
                        of: "## Summary\n\n_AI summary will appear here when an API key is configured._",
                        with: "## Summary\n\n\(summary.summary)"
                    )
                    content = content.replacingOccurrences(
                        of: "## Action Items\n\n- [ ] ",
                        with: "## Action Items\n\n\(summary.actionItems)"
                    )
                }
            }

            try content.write(toFile: pagePath, atomically: true, encoding: .utf8)
            return pagePath
        } catch {
            self.error = error.localizedDescription
            return nil
        }
    }

    private func buildImportedRecordingContent(title: String, segments: [TranscriptSegment], transcript: String) -> String {
        var lines: [String] = []

        // YAML frontmatter
        lines.append("---")
        lines.append("title: \(Self.yamlEscape(title))")
        lines.append("date: \(Self.isoDateFormatter.string(from: Date()))")
        if let last = segments.last {
            let duration = Int(last.timestamp) / 60
            lines.append("duration: \(duration)m")
        }
        let speakers = Set(segments.map(\.speaker)).sorted()
        if !speakers.isEmpty {
            lines.append("participants:")
            for speaker in speakers {
                lines.append("  - \(speaker)")
            }
        }
        lines.append("type: meeting")
        lines.append("source: recording")
        lines.append("---")
        lines.append("")

        lines.append("# \(title)")
        lines.append("")
        lines.append("## Summary")
        lines.append("")
        lines.append("_AI summary will appear here when an API key is configured._")
        lines.append("")
        lines.append("## Notes")
        lines.append("")
        lines.append("")
        lines.append("## Action Items")
        lines.append("")
        lines.append("- [ ] ")
        lines.append("")
        lines.append(transcript)

        return lines.joined(separator: "\n")
    }
    // MARK: - Create Ad-Hoc Meeting Page

    /// Creates a blank meeting page with `type: meeting` frontmatter. Returns the file path.
    /// Appends a counter to the filename if a collision exists.
    func createAdHocMeetingPage(title: String, date: Date, workspace: String) -> String? {
        let dateStr = formatDateForFilename(date)
        let baseFilename = Self.sanitize(title)
        let baseName = "\(dateStr) — \(baseFilename)"

        // Find a unique filename — bounded so a misbehaving fileExists can't spin forever.
        var pagePath = (workspace as NSString).appendingPathComponent("\(baseName).md")
        var counter = 2
        while fm.fileExists(atPath: pagePath) && counter <= 999 {
            pagePath = (workspace as NSString).appendingPathComponent("\(baseName) \(counter).md")
            counter += 1
        }
        guard !fm.fileExists(atPath: pagePath) else { return nil }

        // Empty H1 so the title block renders the placeholder ("New Meeting")
        // and the user can start typing immediately without having to delete text.
        var lines: [String] = []
        lines.append("---")
        lines.append("title: \(Self.yamlEscape(title))")
        lines.append("date: \(Self.isoDateFormatter.string(from: date))")
        lines.append("type: meeting")
        lines.append("meeting_id: \(UUID().uuidString)")
        lines.append("---")
        lines.append("")
        lines.append("# ")
        lines.append("")

        let content = lines.joined(separator: "\n")
        do {
            try content.write(toFile: pagePath, atomically: true, encoding: .utf8)
            return pagePath
        } catch {
            self.error = error.localizedDescription
            return nil
        }
    }

    // MARK: - Cached Formatters

    private static let longDateFormatter: DateFormatter = {
        let df = DateFormatter(); df.dateFormat = "EEEE, MMMM d, yyyy"; return df
    }()
    private static let shortTimeFormatter: DateFormatter = {
        let df = DateFormatter(); df.dateFormat = "h:mm a"; return df
    }()
    static let isoDateFormatter: ISO8601DateFormatter = {
        let df = ISO8601DateFormatter()
        df.formatOptions = [.withInternetDateTime]
        return df
    }()
    static let filenameDateFormatter: DateFormatter = {
        let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd"; return df
    }()

    // MARK: - Content Builder

    private func buildMeetingNoteContent(for event: CalendarEvent) -> String {
        var lines: [String] = []

        // YAML frontmatter
        lines.append("---")
        lines.append("title: \(Self.yamlEscape(event.title))")
        lines.append("date: \(Self.isoDateFormatter.string(from: event.startDate))")
        if !event.isAllDay {
            let duration = Int(event.endDate.timeIntervalSince(event.startDate) / 60)
            lines.append("duration: \(duration)m")
        }
        if !event.attendees.isEmpty {
            lines.append("participants:")
            for attendee in event.attendees {
                let name = attendee.displayName ?? attendee.email
                lines.append("  - \(Self.yamlEscape(name))")
            }
        }
        lines.append("type: meeting")
        lines.append("meeting_id: \(UUID().uuidString)")
        lines.append("---")
        lines.append("")

        // Title
        lines.append("# \(event.title)")
        lines.append("")

        // Metadata
        lines.append("**Date:** \(Self.longDateFormatter.string(from: event.startDate))")

        if !event.isAllDay {
            lines.append("**Time:** \(Self.shortTimeFormatter.string(from: event.startDate)) – \(Self.shortTimeFormatter.string(from: event.endDate))")
        }

        if let location = event.location, !location.isEmpty {
            lines.append("**Location:** \(location)")
        }

        if let url = event.conferenceURL, !url.isEmpty {
            lines.append("**Meeting Link:** \(url)")
        }

        lines.append("")

        // Attendees as wikilinks
        if !event.attendees.isEmpty {
            lines.append("## Attendees")
            lines.append("")
            for attendee in event.attendees {
                let name = attendee.displayName ?? attendee.email
                let wikilink = "[[\(sanitizeWikilinkName(name))]]"
                let statusIcon = attendeeStatusIcon(attendee.responseStatus)
                lines.append("- \(statusIcon) \(wikilink)")
            }
            lines.append("")
        }

        // Sections
        lines.append("## Notes")
        lines.append("")
        lines.append("")
        lines.append("## Action Items")
        lines.append("")
        lines.append("- [ ] ")
        lines.append("")

        // Event description if present
        if let notes = event.notes, !notes.isEmpty {
            lines.append("## Event Description")
            lines.append("")
            lines.append(notes)
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Person Pages

    private nonisolated func ensurePersonPagesSync(for attendees: [Attendee], workspace: String, fm: FileManager) {
        for attendee in attendees {
            let name = attendee.displayName ?? attendee.email
            let safeName = Self.sanitize(name)
            let personPath = (workspace as NSString).appendingPathComponent("\(safeName).md")

            guard !fm.fileExists(atPath: personPath) else { continue }

            let content = """
            # \(name)

            **Email:** \(attendee.email)

            ## Meeting History

            _Backlinks from meeting notes will appear here._
            """

            try? content.write(toFile: personPath, atomically: true, encoding: .utf8)
        }
    }

    // MARK: - Helpers

    private func sanitizeFilename(_ name: String) -> String {
        Self.sanitize(name)
    }

    nonisolated static func sanitize(_ name: String) -> String {
        name.replacingOccurrences(of: "[/\\\\?%*:|\"<>]", with: "-", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
            .prefix(80)
            .description
    }

    private func sanitizeWikilinkName(_ name: String) -> String {
        // Remove characters that break wikilinks but keep most formatting
        name.replacingOccurrences(of: "[\\[\\]|]", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    private func formatDateForFilename(_ date: Date) -> String {
        Self.filenameDateFormatter.string(from: date)
    }

    /// Wrap value in quotes if it contains YAML-special characters.
    static func yamlEscape(_ value: String) -> String {
        let needsQuoting = value.contains(":")
            || value.contains("#")
            || value.contains("\"")
            || value.contains("'")
            || value.hasPrefix("-")
            || value.hasPrefix("{")
            || value.hasPrefix("[")
        if needsQuoting {
            return "\"\(value.replacingOccurrences(of: "\"", with: "\\\""))\""
        }
        return value
    }

    private func attendeeStatusIcon(_ status: Attendee.ResponseStatus) -> String {
        switch status {
        case .accepted: return "✓"
        case .declined: return "✗"
        case .tentative: return "?"
        case .needsAction: return "·"
        }
    }
}
