import Foundation
import UserNotifications
import BugbookCore

/// Schedules macOS notifications for upcoming calendar events that qualify as meetings.
/// A meeting qualifies if: non-all-day AND (2+ attendees OR has a conference URL).
/// Notifications fire at meeting start time with "Record" and "Open Notes" actions.
@MainActor
@Observable
class MeetingNotificationService {
    private var scheduledEventIds: Set<String> = []
    private var pollingTask: Task<Void, Never>?

    static let categoryIdentifier = "MEETING_REMINDER"
    static let recordActionIdentifier = "RECORD_MEETING"
    static let openNotesActionIdentifier = "OPEN_NOTES"

    /// Request notification permission and register action category.
    func setup() {
        let center = UNUserNotificationCenter.current()

        // Define actions
        let recordAction = UNNotificationAction(
            identifier: Self.recordActionIdentifier,
            title: "Record",
            options: [.foreground]
        )
        let openNotesAction = UNNotificationAction(
            identifier: Self.openNotesActionIdentifier,
            title: "Open Notes",
            options: [.foreground]
        )

        let category = UNNotificationCategory(
            identifier: Self.categoryIdentifier,
            actions: [recordAction, openNotesAction],
            intentIdentifiers: [],
            options: []
        )
        center.setNotificationCategories([category])

        // Request permission
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// Start polling calendar events and scheduling notifications.
    func startPolling(calendarService: CalendarService) {
        pollingTask?.cancel()
        pollingTask = Task {
            while !Task.isCancelled {
                scheduleNotifications(for: calendarService.events)
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }

    /// Schedule notifications for qualifying events that start within the next hour.
    private func scheduleNotifications(for events: [CalendarEvent]) {
        let now = Date()
        let horizon = now.addingTimeInterval(3600) // 1 hour ahead

        for event in events {
            guard !event.isAllDay,
                  event.startDate > now,
                  event.startDate <= horizon,
                  !scheduledEventIds.contains(event.id),
                  isMeetingEvent(event) else { continue }

            scheduleNotification(for: event)
            scheduledEventIds.insert(event.id)
        }

        // Prune IDs for events that have already started (no longer need tracking)
        let pastIds = Set(events.filter { $0.startDate <= now }.map(\.id))
        scheduledEventIds.subtract(pastIds)
    }

    /// Check if an event qualifies as a meeting (2+ attendees or has conference URL).
    private func isMeetingEvent(_ event: CalendarEvent) -> Bool {
        if event.attendees.count >= 2 { return true }
        if let url = event.conferenceURL, !url.isEmpty { return true }
        return false
    }

    private func scheduleNotification(for event: CalendarEvent) {
        let content = UNMutableNotificationContent()
        content.title = event.title
        content.body = formatMeetingBody(event)
        content.sound = .default
        content.categoryIdentifier = Self.categoryIdentifier
        content.userInfo = ["eventId": event.id, "eventTitle": event.title]

        // Fire at the event start time
        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: event.startDate
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)

        let request = UNNotificationRequest(
            identifier: "meeting-\(event.id)",
            content: content,
            trigger: trigger
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                Log.app.error("Failed to schedule meeting notification: \(error.localizedDescription)")
            }
        }
    }

    private func formatMeetingBody(_ event: CalendarEvent) -> String {
        var parts: [String] = []
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        parts.append("Starts at \(formatter.string(from: event.startDate))")
        if !event.attendees.isEmpty {
            let names = event.attendees.prefix(3).compactMap { $0.displayName ?? $0.email }
            parts.append("with \(names.joined(separator: ", "))")
        }
        return parts.joined(separator: " ")
    }
}
