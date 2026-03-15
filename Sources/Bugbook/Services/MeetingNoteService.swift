import Foundation
import BugbookCore

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

    // MARK: - Cached Formatters

    private static let longDateFormatter: DateFormatter = {
        let df = DateFormatter(); df.dateFormat = "EEEE, MMMM d, yyyy"; return df
    }()
    private static let shortTimeFormatter: DateFormatter = {
        let df = DateFormatter(); df.dateFormat = "h:mm a"; return df
    }()
    private static let filenameDateFormatter: DateFormatter = {
        let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd"; return df
    }()

    // MARK: - Content Builder

    private func buildMeetingNoteContent(for event: CalendarEvent) -> String {
        var lines: [String] = []

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

    private func attendeeStatusIcon(_ status: Attendee.ResponseStatus) -> String {
        switch status {
        case .accepted: return "✓"
        case .declined: return "✗"
        case .tentative: return "?"
        case .needsAction: return "·"
        }
    }
}
