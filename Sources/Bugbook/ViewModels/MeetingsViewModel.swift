import Foundation
import BugbookCore

/// Represents a single meeting entry in the Meetings tab list.
struct MeetingItem: Identifiable, Hashable {
    let id: String
    let title: String
    let date: Date
    let endDate: Date?
    let attendees: [String]
    /// File path to navigate to when tapped (nil for calendar-only events with no linked page)
    let pagePath: String?
    /// Calendar event source, if any
    let calendarEventId: String?
    let isAllDay: Bool

    var attendeeSummary: String {
        guard !attendees.isEmpty else { return "" }
        if attendees.count <= 3 {
            return attendees.joined(separator: ", ")
        }
        return attendees.prefix(2).joined(separator: ", ") + " +\(attendees.count - 2)"
    }
}

@MainActor
@Observable
final class MeetingsViewModel {
    var upcomingByDay: [(date: Date, items: [MeetingItem])] = []
    var pastByDay: [(date: Date, items: [MeetingItem])] = []
    var searchText: String = ""
    var isLoading = false

    @ObservationIgnored private let calendar = Calendar.current
    @ObservationIgnored private let fm = FileManager.default

    // MARK: - Cached Formatters

    @ObservationIgnored private static let meetingFilenameRegex: NSRegularExpression? = {
        try? NSRegularExpression(pattern: #"^\d{4}-\d{2}-\d{2}\s*[—–-]\s*"#)
    }()

    @ObservationIgnored private static let dateParser: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        return df
    }()

    // MARK: - Load

    func load(workspace: String, calendarEvents: [CalendarEvent]) {
        isLoading = true
        defer { isLoading = false }

        var all: [MeetingItem] = []

        // 1. Calendar events (with or without linked pages)
        for event in calendarEvents {
            let names = event.attendees.compactMap { $0.displayName ?? $0.email.components(separatedBy: "@").first }
            all.append(MeetingItem(
                id: "cal_\(event.id)",
                title: event.title,
                date: event.startDate,
                endDate: event.endDate,
                attendees: names,
                pagePath: event.linkedPagePath,
                calendarEventId: event.id,
                isAllDay: event.isAllDay
            ))
        }

        // 2. Meeting note pages (YYYY-MM-DD — *.md) that aren't already linked
        let linkedPaths = Set(calendarEvents.compactMap(\.linkedPagePath))
        discoverMeetingNotePages(workspace: workspace, linkedPaths: linkedPaths, into: &all)

        // Partition into upcoming vs past
        let now = Date()
        let upcoming = all.filter { $0.date >= calendar.startOfDay(for: now) }
            .sorted { $0.date < $1.date }
        let past = all.filter { $0.date < calendar.startOfDay(for: now) }
            .sorted { $0.date > $1.date }

        // Group by day
        upcomingByDay = groupByDay(upcoming)
        pastByDay = groupByDay(past)
    }

    // MARK: - Filtering

    var filteredUpcoming: [(date: Date, items: [MeetingItem])] {
        guard !searchText.isEmpty else { return upcomingByDay }
        return filterGroups(upcomingByDay)
    }

    var filteredPast: [(date: Date, items: [MeetingItem])] {
        guard !searchText.isEmpty else { return pastByDay }
        return filterGroups(pastByDay)
    }

    private func filterGroups(_ groups: [(date: Date, items: [MeetingItem])]) -> [(date: Date, items: [MeetingItem])] {
        let query = searchText.lowercased()
        return groups.compactMap { group in
            let filtered = group.items.filter {
                $0.title.lowercased().contains(query) ||
                $0.attendees.contains(where: { $0.lowercased().contains(query) })
            }
            return filtered.isEmpty ? nil : (group.date, filtered)
        }
    }

    // MARK: - Meeting Note Discovery

    private func discoverMeetingNotePages(workspace: String, linkedPaths: Set<String>, into items: inout [MeetingItem]) {
        guard let contents = try? fm.contentsOfDirectory(atPath: workspace) else { return }
        let regex = Self.meetingFilenameRegex

        for filename in contents where filename.hasSuffix(".md") {
            let fullPath = (workspace as NSString).appendingPathComponent(filename)
            guard !linkedPaths.contains(fullPath) else { continue }

            let basename = (filename as NSString).deletingPathExtension
            // Check if filename matches YYYY-MM-DD — Title pattern
            guard let regex else { continue }
            let range = NSRange(basename.startIndex..., in: basename)
            guard regex.firstMatch(in: basename, range: range) != nil else { continue }

            let dateStr = String(basename.prefix(10))
            guard let date = Self.dateParser.date(from: dateStr) else { continue }

            // Extract title after the separator
            let titleStart = basename.index(basename.startIndex, offsetBy: min(basename.count, 13))
            let title = String(basename[titleStart...]).trimmingCharacters(in: .whitespaces)

            items.append(MeetingItem(
                id: "file_\(fullPath)",
                title: title.isEmpty ? basename : title,
                date: date,
                endDate: nil,
                attendees: [],
                pagePath: fullPath,
                calendarEventId: nil,
                isAllDay: true
            ))
        }
    }

    // MARK: - Grouping

    private func groupByDay(_ items: [MeetingItem]) -> [(date: Date, items: [MeetingItem])] {
        var dict: [Date: [MeetingItem]] = [:]
        for item in items {
            let day = calendar.startOfDay(for: item.date)
            dict[day, default: []].append(item)
        }
        return dict.sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
    }

    // MARK: - Date Labels

    func relativeLabel(for date: Date) -> String {
        let now = Date()
        let startOfToday = calendar.startOfDay(for: now)
        let day = calendar.startOfDay(for: date)

        if day == startOfToday { return "Today" }

        let diff = calendar.dateComponents([.day], from: startOfToday, to: day).day ?? 0
        if diff == 1 { return "Tomorrow" }
        if diff == -1 { return "Yesterday" }
        if diff > 1 && diff <= 6 { return dayFormatter.string(from: date) }

        return fullDateFormatter.string(from: date)
    }

    @ObservationIgnored private let dayFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "EEEE"
        return df
    }()

    @ObservationIgnored private let fullDateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "EEEE, MMM d"
        return df
    }()

    @ObservationIgnored let timeFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "h:mm a"
        return df
    }()
}
