import SwiftUI
import BugbookCore

struct CalendarDayView: View {
    let date: Date
    let events: [CalendarEvent]
    let databaseItems: [CalendarDatabaseItem]
    let calendarVM: CalendarViewModel
    var onEventTapped: (CalendarEvent) -> Void
    var onDatabaseItemTapped: (CalendarDatabaseItem) -> Void

    @State private var hoveredEventId: String?

    private let hourHeight: CGFloat = 48
    private let timeGutterWidth: CGFloat = 44

    var body: some View {
        ScrollView(.vertical) {
            ZStack(alignment: .topLeading) {
                // Time grid
                VStack(spacing: 0) {
                    ForEach(calendarVM.visibleHours, id: \.self) { hour in
                        HStack(spacing: 0) {
                            HStack {
                                Spacer()
                                Text(calendarVM.hourLabel(hour))
                                    .font(.system(size: 10))
                                    .foregroundStyle(.quaternary)
                                    .padding(.trailing, 4)
                            }
                            .frame(width: timeGutterWidth, alignment: .topTrailing)
                            .offset(y: -6)

                            VStack(spacing: 0) {
                                Divider().opacity(0.3)
                                Spacer()
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .frame(height: hourHeight)
                    }
                }

                // Events
                HStack(spacing: 0) {
                    Color.clear.frame(width: timeGutterWidth)

                    ZStack(alignment: .topLeading) {
                        let timedEvents = calendarVM.events(for: date, from: events)
                            .filter { !$0.isAllDay }

                        ForEach(timedEvents, id: \.id) { event in
                            let y = calendarVM.yPosition(for: event.startDate, hourHeight: hourHeight)
                            let h = calendarVM.eventHeight(start: event.startDate, end: event.endDate, hourHeight: hourHeight)
                            let isHovered = hoveredEventId == event.id
                            let eventColor = Color.accentColor

                            Button(action: { onEventTapped(event) }) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(event.title)
                                        .font(.system(size: Typography.body, weight: .medium))
                                        .lineLimit(3)
                                    Text("\(calendarVM.timeString(for: event.startDate))–\(calendarVM.timeString(for: event.endDate))")
                                        .font(.system(size: Typography.caption))
                                        .opacity(0.8)
                                    if let location = event.location, !location.isEmpty {
                                        Text(location)
                                            .font(.system(size: Typography.caption))
                                            .opacity(0.6)
                                    }
                                }
                                .padding(.leading, 8)
                                .padding(.trailing, 6)
                                .padding(.vertical, 4)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .frame(height: h, alignment: .top)
                                .foregroundStyle(eventColor)
                                .background(eventColor.opacity(isHovered ? 0.14 : 0.08))
                                .overlay(alignment: .leading) {
                                    Rectangle().fill(eventColor).frame(width: 2)
                                }
                                .clipShape(.rect(cornerRadius: Radius.sm))
                            }
                            .buttonStyle(.plain)
                            .onHover { hovering in hoveredEventId = hovering ? event.id : nil }
                            .padding(.horizontal, 4)
                            .offset(y: y)
                        }

                        // Database items
                        let dbItems = calendarVM.databaseItems(for: date, from: databaseItems)
                        ForEach(dbItems, id: \.id) { item in
                            let y = calendarVM.yPosition(for: item.date, hourHeight: hourHeight)
                            let color = TagColor.color(for: item.color)

                            Button(action: { onDatabaseItemTapped(item) }) {
                                HStack(spacing: 6) {
                                    Circle().fill(color).frame(width: 5, height: 5)
                                    Text(item.title)
                                        .font(.system(size: Typography.bodySmall))
                                        .lineLimit(1)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(color.opacity(0.06))
                                .clipShape(.rect(cornerRadius: Radius.xs))
                                .foregroundStyle(color)
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal, 4)
                            .offset(y: y)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }

                // Current time
                if Calendar.current.isDateInToday(date) {
                    let now = Date()
                    let y = calendarVM.yPosition(for: now, hourHeight: hourHeight)
                    let nowColor = StatusColor.error

                    // Time label in gutter
                    HStack(spacing: 0) {
                        HStack {
                            Spacer()
                            Text(calendarVM.timeString(for: now))
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(nowColor)
                                .padding(.trailing, 4)
                        }
                        .frame(width: timeGutterWidth)
                        Spacer()
                    }
                    .offset(y: y - 6)
                    .allowsHitTesting(false)

                    HStack(spacing: 0) {
                        Color.clear.frame(width: timeGutterWidth - 4)
                        Circle().fill(nowColor).frame(width: 8, height: 8)
                        Rectangle().fill(nowColor).frame(height: 1.5)
                    }
                    .offset(y: y - 4)
                    .allowsHitTesting(false)
                }
            }
            .frame(height: CGFloat(calendarVM.visibleHours.count) * hourHeight)
        }
    }
}
