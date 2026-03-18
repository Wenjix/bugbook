import Foundation
import BugbookCore

enum CalendarViewMode: String, CaseIterable {
    case day = "Day"
    case week = "Week"
    case month = "Month"

    var shortcut: String {
        switch self {
        case .day: return "D"
        case .week: return "W"
        case .month: return "M"
        }
    }
}

@MainActor
@Observable
final class CalendarViewModel {
    var viewMode: CalendarViewMode = .week
    var selectedDate: Date = Date()
    var selectedEvent: CalendarEvent?
    var showSourcePicker = false
    var showRecordMeetingPopover = false

    // Computed from CalendarService data
    @ObservationIgnored private let calendar = Calendar.current
    @ObservationIgnored private let timeFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "h:mm a"
        return df
    }()
    @ObservationIgnored private let dayHeaderFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "EEEE, MMMM d, yyyy"
        return df
    }()
    @ObservationIgnored private let monthHeaderFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "MMMM yyyy"
        return df
    }()
    @ObservationIgnored private let weekRangeFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "MMM d"
        return df
    }()
    @ObservationIgnored private let yearFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "yyyy"
        return df
    }()
    @ObservationIgnored private let dayOfWeekFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "EEE"
        return df
    }()

    // MARK: - Date Navigation

    func goToToday() {
        selectedDate = Date()
    }

    func goForward() {
        switch viewMode {
        case .day:
            selectedDate = calendar.date(byAdding: .day, value: 1, to: selectedDate) ?? selectedDate
        case .week:
            selectedDate = calendar.date(byAdding: .weekOfYear, value: 1, to: selectedDate) ?? selectedDate
        case .month:
            selectedDate = calendar.date(byAdding: .month, value: 1, to: selectedDate) ?? selectedDate
        }
    }

    func goBack() {
        switch viewMode {
        case .day:
            selectedDate = calendar.date(byAdding: .day, value: -1, to: selectedDate) ?? selectedDate
        case .week:
            selectedDate = calendar.date(byAdding: .weekOfYear, value: -1, to: selectedDate) ?? selectedDate
        case .month:
            selectedDate = calendar.date(byAdding: .month, value: -1, to: selectedDate) ?? selectedDate
        }
    }

    // MARK: - Date Range

    var visibleDateRange: (start: Date, end: Date) {
        switch viewMode {
        case .day:
            let start = calendar.startOfDay(for: selectedDate)
            let end = calendar.date(byAdding: .day, value: 1, to: start)!
            return (start, end)
        case .week:
            let weekday = calendar.component(.weekday, from: selectedDate)
            let daysBack = (weekday - calendar.firstWeekday + 7) % 7
            let start = calendar.date(byAdding: .day, value: -daysBack, to: calendar.startOfDay(for: selectedDate))!
            let end = calendar.date(byAdding: .day, value: 7, to: start)!
            return (start, end)
        case .month:
            let comps = calendar.dateComponents([.year, .month], from: selectedDate)
            let start = calendar.date(from: comps)!
            let end = calendar.date(byAdding: .month, value: 1, to: start)!
            return (start, end)
        }
    }

    var headerTitle: String {
        switch viewMode {
        case .day:
            return dayHeaderFormatter.string(from: selectedDate)
        case .week:
            return monthHeaderFormatter.string(from: selectedDate)
        case .month:
            return monthHeaderFormatter.string(from: selectedDate)
        }
    }

    // MARK: - Days in View

    var daysInView: [Date] {
        let range = visibleDateRange
        var days: [Date] = []
        var current = range.start
        while current < range.end {
            days.append(current)
            current = calendar.date(byAdding: .day, value: 1, to: current)!
        }
        return days
    }

    // MARK: - Filtering

    /// Filter events for a given day. Assumes the caller already filtered by source visibility.
    func events(for date: Date, from allEvents: [CalendarEvent]) -> [CalendarEvent] {
        let dayStart = calendar.startOfDay(for: date)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)!

        return allEvents.filter { event in
            event.startDate < dayEnd && event.endDate > dayStart
        }.sorted { $0.startDate < $1.startDate }
    }

    func databaseItems(for date: Date, from items: [CalendarDatabaseItem]) -> [CalendarDatabaseItem] {
        let dayStart = calendar.startOfDay(for: date)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)!
        return items.filter { item in
            item.date >= dayStart && item.date < dayEnd
        }
    }

    // MARK: - Time Formatting

    func timeString(for date: Date) -> String {
        timeFormatter.string(from: date)
    }

    func durationString(start: Date, end: Date) -> String {
        let minutes = Int(end.timeIntervalSince(start) / 60)
        if minutes < 60 {
            return "\(minutes)m"
        }
        let hours = minutes / 60
        let remaining = minutes % 60
        return remaining > 0 ? "\(hours)h \(remaining)m" : "\(hours)h"
    }

    // MARK: - Hour Layout (for day/week views)

    let dayStartHour = 5
    let dayEndHour = 23

    var visibleHours: [Int] {
        Array(dayStartHour...dayEndHour)
    }

    func dayOfWeekString(_ date: Date) -> String {
        dayOfWeekFormatter.string(from: date)
    }

    func hourLabel(_ hour: Int) -> String {
        if hour == 0 { return "12 AM" }
        if hour < 12 { return "\(hour) AM" }
        if hour == 12 { return "12 PM" }
        return "\(hour - 12) PM"
    }

    func yPosition(for date: Date, hourHeight: CGFloat) -> CGFloat {
        let hour = calendar.component(.hour, from: date)
        let minute = calendar.component(.minute, from: date)
        let adjustedHour = CGFloat(hour - dayStartHour) + CGFloat(minute) / 60.0
        return adjustedHour * hourHeight
    }

    func eventHeight(start: Date, end: Date, hourHeight: CGFloat) -> CGFloat {
        let duration = end.timeIntervalSince(start) / 3600.0
        return max(CGFloat(duration) * hourHeight, hourHeight * 0.4)
    }
}
