import SwiftUI
import BugbookCore

struct CalendarMonthView: View {
    let selectedDate: Date
    let events: [CalendarEvent]
    let databaseItems: [CalendarDatabaseItem]
    let calendarVM: CalendarViewModel
    let calendarSources: [CalendarSource]
    var onEventTapped: (CalendarEvent) -> Void
    var onDatabaseItemTapped: (CalendarDatabaseItem) -> Void

    @State private var hoveredDay: Date?

    private let calendar = Calendar.current
    private let weekdays = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

    var body: some View {
        VStack(spacing: 0) {
            // Weekday headers
            HStack(spacing: 0) {
                ForEach(weekdays, id: \.self) { day in
                    Text(day)
                        .font(.system(size: Typography.caption, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.vertical, 6)

            Divider()

            // Day grid
            ScrollView {
                let weeks = monthWeeks
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 0) {
                    ForEach(weeks, id: \.self) { day in
                        monthDayCell(day)
                    }
                }
            }
        }
    }

    // MARK: - Month Grid

    private var monthWeeks: [Date] {
        let comps = calendar.dateComponents([.year, .month], from: selectedDate)
        guard let firstOfMonth = calendar.date(from: comps) else { return [] }

        let firstWeekday = calendar.component(.weekday, from: firstOfMonth)
        let offset = -((firstWeekday - calendar.firstWeekday + 7) % 7)
        guard let gridStart = calendar.date(byAdding: .day, value: offset, to: firstOfMonth) else { return [] }

        // 6 weeks to cover any month layout
        return (0..<42).compactMap { calendar.date(byAdding: .day, value: $0, to: gridStart) }
    }

    private func monthDayCell(_ day: Date) -> some View {
        let isCurrentMonth = calendar.component(.month, from: day) == calendar.component(.month, from: selectedDate)
        let dayEvents = calendarVM.events(for: day, from: events)
        let dayDbItems = calendarVM.databaseItems(for: day, from: databaseItems)
            .filter { !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        return VStack(alignment: .leading, spacing: 2) {
            // Day number
            HStack {
                Text("\(calendar.component(.day, from: day))")
                    .font(.system(size: Typography.bodySmall, weight: calendar.isDateInToday(day) ? .bold : .regular))
                    .foregroundStyle(
                        calendar.isDateInToday(day) ? Color.fallbackAccentFg :
                        isCurrentMonth ? Color.primary : Color.secondary.opacity(0.5)
                    )
                    .frame(width: 24, height: 24)
                    .background {
                        if calendar.isDateInToday(day) {
                            Circle().fill(Color.accentColor)
                        }
                    }
                Spacer()
            }
            .padding(.leading, 4)
            .padding(.top, 4)

            // Events (max 3 visible)
            VStack(spacing: 1) {
                ForEach(Array(dayEvents.prefix(3)), id: \.id) { event in
                    Button(action: { onEventTapped(event) }) {
                        let color = eventColor(for: event)
                        HStack(spacing: 3) {
                            if !event.isAllDay {
                                Circle().fill(color).frame(width: 5, height: 5)
                            }
                            if let blockProfile = event.blockProfile {
                                CalendarBlockIndicator(profile: blockProfile, showsText: false)
                            }
                            Text(event.isAllDay ? event.title : "\(calendarVM.timeString(for: event.startDate)) \(event.title)")
                                .font(.system(size: Typography.caption2))
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(event.isAllDay ? color.opacity(0.12) : Color.clear)
                        .clipShape(.rect(cornerRadius: 2))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(isCurrentMonth ? Color.primary : Color.secondary.opacity(0.5))
                }

                ForEach(Array(dayDbItems.prefix(max(0, 3 - dayEvents.count))), id: \.id) { item in
                    Button(action: { onDatabaseItemTapped(item) }) {
                        HStack(spacing: 3) {
                            Circle().fill(TagColor.color(for: item.color)).frame(width: 5, height: 5)
                            Text(item.title)
                                .font(.system(size: Typography.caption2))
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }

                let totalItems = dayEvents.count + dayDbItems.count
                if totalItems > 3 {
                    Text("+\(totalItems - 3) more")
                        .font(.system(size: Typography.caption2))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                }
            }

            Spacer(minLength: 0)
        }
        .frame(minHeight: 90)
        .background(
            calendar.isDateInToday(day) ? Color.accentColor.opacity(0.04) :
            hoveredDay == day ? Color.primary.opacity(Opacity.subtle) :
            isCurrentMonth ? Color.clear : Color.primary.opacity(0.02)
        )
        .overlay(
            Rectangle()
                .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
        )
        .onHover { hovering in hoveredDay = hovering ? day : nil }
    }

    private func eventColor(for event: CalendarEvent) -> Color {
        if let source = calendarSources.first(where: { $0.id == event.calendarId }) {
            let hex = source.color
            if hex.hasPrefix("#") {
                return Color(hex: String(hex.dropFirst()))
            }
            return TagColor.color(for: hex)
        }
        return Color.accentColor
    }
}
