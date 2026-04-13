import SwiftUI
import DahsoCore

struct CalendarDayView: View {
    let date: Date
    let events: [CalendarEvent]
    let databaseItems: [CalendarDatabaseItem]
    let calendarVM: CalendarViewModel
    let calendarSources: [CalendarSource]
    var onEventTapped: (CalendarEvent) -> Void
    var onDatabaseItemTapped: (CalendarDatabaseItem) -> Void
    var onCreateEvent: ((Date, Date) -> Void)?

    @State private var hoveredEventId: String?

    // Drag-to-create state
    @State private var dragStart: CGFloat?
    @State private var dragCurrent: CGFloat?

    private let hourHeight: CGFloat = 48
    private let timeGutterWidth: CGFloat = 44

    private var dayEvents: [CalendarEvent] {
        calendarVM.events(for: date, from: events)
    }

    private var timedEvents: [CalendarEvent] {
        dayEvents.filter { !$0.isAllDay }
    }

    private var allDayEvents: [CalendarEvent] {
        dayEvents.filter { $0.isAllDay }
    }

    private var dayDbItems: [CalendarDatabaseItem] {
        calendarVM.databaseItems(for: date, from: databaseItems)
            .filter { !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    var body: some View {
        VStack(spacing: 0) {
            if !allDayEvents.isEmpty {
                allDaySection
                Divider()
            }

            ScrollView(.vertical) {
                ScrollViewReader { proxy in
                    ZStack(alignment: .topLeading) {
                        timeGrid
                        eventOverlays
                        nowIndicator

                        // Empty state — shown over the grid when no events
                        if dayEvents.isEmpty && dayDbItems.isEmpty {
                            VStack(spacing: 6) {
                                Text("Nothing scheduled")
                                    .font(.system(size: Typography.bodySmall, weight: .medium))
                                    .foregroundStyle(.secondary)
                                Text("Your day is clear")
                                    .font(.system(size: Typography.caption))
                                    .foregroundStyle(.tertiary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.top, hourHeight * 2)
                        }
                    }
                    .frame(height: CGFloat(calendarVM.visibleHours.count) * hourHeight)
                    .onAppear {
                        let targetHour = max(calendarVM.dayStartHour, Calendar.current.component(.hour, from: Date()) - 1)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            proxy.scrollTo(targetHour, anchor: .top)
                        }
                    }
                }
            }
        }
    }

    // MARK: - All-Day Section

    private var allDaySection: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(allDayEvents, id: \.id) { event in
                let color = eventColor(for: event)
                Button(action: { onEventTapped(event) }) {
                    HStack(spacing: 6) {
                        Circle().fill(color).frame(width: 6, height: 6)
                        Text(event.title)
                            .font(.system(size: Typography.caption, weight: .medium))
                            .lineLimit(1)
                        Spacer()
                        Text("All day")
                            .font(.system(size: Typography.caption2))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(color.opacity(Opacity.light))
                    .foregroundStyle(color)
                    .clipShape(.rect(cornerRadius: Radius.sm))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }

    // MARK: - Time Grid

    private var timeGrid: some View {
        VStack(spacing: 0) {
            ForEach(calendarVM.visibleHours, id: \.self) { hour in
                HStack(spacing: 0) {
                    HStack {
                        Spacer()
                        if !shouldHideHourLabel(hour) {
                            Text(calendarVM.hourLabel(hour))
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.tertiary)
                                .padding(.trailing, 4)
                        }
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
                .id(hour)
            }
        }
    }

    // MARK: - Overlap Layout

    private struct EventLayout {
        let event: CalendarEvent
        let column: Int
        let totalColumns: Int
    }

    private func computeOverlapLayout(_ events: [CalendarEvent]) -> [EventLayout] {
        let sorted = events.sorted { $0.startDate < $1.startDate }
        var columns: [Int: CalendarEvent] = [:]  // column index -> last event occupying it
        var layouts: [EventLayout] = []

        for event in sorted {
            // Free columns whose event ended before this event starts
            columns = columns.filter { _, occupant in occupant.endDate > event.startDate }

            // Find the lowest available column
            var col = 0
            while columns[col] != nil { col += 1 }
            columns[col] = event

            layouts.append(EventLayout(event: event, column: col, totalColumns: 0))
        }

        // Second pass: assign totalColumns per overlap group.
        // For each event, totalColumns = max(col+1) among all events it overlaps with.
        for i in layouts.indices {
            var maxCol = layouts[i].column
            for j in layouts.indices where i != j {
                let a = layouts[i].event
                let b = layouts[j].event
                if a.startDate < b.endDate && b.startDate < a.endDate {
                    maxCol = max(maxCol, layouts[j].column)
                }
            }
            layouts[i] = EventLayout(
                event: layouts[i].event,
                column: layouts[i].column,
                totalColumns: maxCol + 1
            )
        }

        return layouts
    }

    // MARK: - Event Overlays

    private var eventOverlays: some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: timeGutterWidth)

            GeometryReader { geo in
                let layouts = computeOverlapLayout(timedEvents)
                ZStack(alignment: .topLeading) {
                    ForEach(layouts, id: \.event.id) { layout in
                        timedEventCard(layout.event, column: layout.column, totalColumns: layout.totalColumns, containerWidth: geo.size.width)
                    }

                    ForEach(dayDbItems, id: \.id) { item in
                        databaseItemCard(item)
                    }
                }

                // Drag-to-create preview
                if let start = dragStart, let current = dragCurrent {
                    let minY = min(start, current)
                    let height = max(abs(current - start), hourHeight * 0.5)
                    Rectangle()
                        .fill(Color.accentColor.opacity(0.18))
                        .overlay(
                            Rectangle()
                                .fill(Color.accentColor)
                                .frame(width: 3),
                            alignment: .leading
                        )
                        .frame(height: height)
                        .offset(y: minY)
                        .allowsHitTesting(false)
                        .padding(.horizontal, 4)
                }
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .gesture(onCreateEvent != nil ? dragCreateGesture : nil)
        }
    }

    // MARK: - Drag-to-create

    private var dragCreateGesture: some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .local)
            .onChanged { value in
                if dragStart == nil {
                    dragStart = value.startLocation.y
                }
                dragCurrent = value.location.y
            }
            .onEnded { value in
                defer {
                    dragStart = nil
                    dragCurrent = nil
                }
                guard let start = dragStart else { return }
                let startY = min(start, value.location.y)
                let endY = max(start, value.location.y)

                let startTime = timeFromY(startY)
                var endTime = timeFromY(endY)
                if endTime <= startTime {
                    endTime = startTime.addingTimeInterval(1800)
                }
                onCreateEvent?(startTime, endTime)
            }
    }

    private func timeFromY(_ y: CGFloat) -> Date {
        let totalSeconds = (y / hourHeight) * 3600
        let hour = Int(totalSeconds / 3600)
        let minute = Int((totalSeconds.truncatingRemainder(dividingBy: 3600)) / 60)
        let clampedHour = max(0, min(23, calendarVM.dayStartHour + hour))
        var comps = Calendar.current.dateComponents([.year, .month, .day], from: date)
        comps.hour = clampedHour
        comps.minute = (minute / 15) * 15  // snap to 15 min
        comps.second = 0
        return Calendar.current.date(from: comps) ?? date
    }

    private func timedEventCard(_ event: CalendarEvent, column: Int, totalColumns: Int, containerWidth: CGFloat) -> some View {
        let y = calendarVM.yPosition(for: event.startDate, hourHeight: hourHeight)
        let h = calendarVM.eventHeight(start: event.startDate, end: event.endDate, hourHeight: hourHeight)
        let isHovered = hoveredEventId == event.id
        let color = eventColor(for: event)

        let cols = max(totalColumns, 1)
        let gutter: CGFloat = 4
        let colWidth = (containerWidth - gutter * CGFloat(cols + 1)) / CGFloat(cols)
        let xOffset = gutter + CGFloat(column) * (colWidth + gutter)

        return Button(action: { onEventTapped(event) }) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(event.title)
                        .font(.system(size: Typography.body, weight: .medium))
                        .lineLimit(3)
                    if event.linkedPagePath != nil {
                        Image(systemName: "waveform")
                            .font(.system(size: 9))
                            .opacity(0.7)
                    }
                }
                Text("\(calendarVM.timeString(for: event.startDate)) – \(calendarVM.timeString(for: event.endDate))")
                    .font(.system(size: Typography.caption))
                    .opacity(0.8)
                if let location = event.location, !location.isEmpty {
                    Text(location)
                        .font(.system(size: Typography.caption))
                        .opacity(0.6)
                }
            }
            .padding(.leading, 10)
            .padding(.trailing, 6)
            .padding(.vertical, 4)
            .frame(width: colWidth, alignment: .leading)
            .frame(height: h, alignment: .top)
            .foregroundStyle(color)
            .background(color.opacity(isHovered ? 0.14 : Opacity.light))
            .overlay(alignment: .leading) {
                Rectangle().fill(color).frame(width: 3)
            }
            .clipShape(.rect(cornerRadius: Radius.sm))
        }
        .buttonStyle(.plain)
        .onHover { hovering in hoveredEventId = hovering ? event.id : nil }
        .offset(x: xOffset, y: y)
    }

    private func databaseItemCard(_ item: CalendarDatabaseItem) -> some View {
        let y = calendarVM.yPosition(for: item.date, hourHeight: hourHeight)
        let color = TagColor.color(for: item.color)

        return Button(action: { onDatabaseItemTapped(item) }) {
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

    // MARK: - Now Indicator

    @ViewBuilder
    private var nowIndicator: some View {
        if Calendar.current.isDateInToday(date) {
            let now = Date()
            let y = calendarVM.yPosition(for: now, hourHeight: hourHeight)
            let nowColor = StatusColor.error

            // Time label in gutter
            HStack(spacing: 0) {
                HStack {
                    Spacer()
                    Text(calendarVM.timeString(for: now))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(nowColor)
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.trailing, 4)
                }
                .frame(width: timeGutterWidth)
                Spacer()
            }
            .offset(y: y - 6)
            .allowsHitTesting(false)

            // Dot + line
            HStack(spacing: 0) {
                Color.clear.frame(width: timeGutterWidth - 4)
                Circle().fill(nowColor).frame(width: 8, height: 8)
                Rectangle().fill(nowColor).frame(height: 1.5)
            }
            .offset(y: y - 4)
            .allowsHitTesting(false)
        }
    }

    // MARK: - Helpers

    private func shouldHideHourLabel(_ hour: Int) -> Bool {
        guard Calendar.current.isDateInToday(date) else { return false }
        let nowHour = Calendar.current.component(.hour, from: Date())
        let nowMinute = Calendar.current.component(.minute, from: Date())
        if hour == nowHour && nowMinute > 20 { return true }
        if hour == nowHour + 1 && nowMinute >= 40 { return true }
        return false
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
