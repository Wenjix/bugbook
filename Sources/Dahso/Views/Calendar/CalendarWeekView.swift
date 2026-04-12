import SwiftUI
import DahsoCore

struct CalendarWeekView: View {
    let days: [Date]
    let events: [CalendarEvent]
    let databaseItems: [CalendarDatabaseItem]
    let calendarVM: CalendarViewModel
    let calendarSources: [CalendarSource]
    var onEventTapped: (CalendarEvent) -> Void
    var onDatabaseItemTapped: (CalendarDatabaseItem) -> Void
    var onCreateEvent: ((Date, Date) -> Void)?

    @State private var hoveredEventId: String?
    @State private var hoveredDbItemId: String?

    // Drag-to-create state
    @State private var dragStart: CGPoint?
    @State private var dragCurrent: CGPoint?
    @State private var dragDayIndex: Int?

    private let hourHeight: CGFloat = 48
    private let timeGutterWidth: CGFloat = 58
    private let calendar = Calendar.current

    var body: some View {
        VStack(spacing: 0) {
            dayHeaderRow
                .fixedSize(horizontal: false, vertical: true)
            Divider()

            let allDayEvents = allDayEventsByDay
            if allDayEvents.values.contains(where: { !$0.isEmpty }) {
                allDayRow(allDayEvents)
                Divider()
            }

            ScrollView(.vertical) {
                ScrollViewReader { proxy in
                    ZStack(alignment: .topLeading) {
                        timeGridBackground
                        dayColumnDividers
                        eventOverlays
                        currentTimeIndicator
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

    // MARK: - Day Headers (Notion style: "Sun 15" inline)

    private var dayHeaderRow: some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: timeGutterWidth)

            ForEach(days, id: \.self) { day in
                Text("\(calendarVM.dayOfWeekString(day)) \(calendar.component(.day, from: day))")
                    .font(.system(size: 10, weight: isToday(day) ? .semibold : .regular))
                    .foregroundStyle(isToday(day) ? Color.accentColor : Color.secondary.opacity(0.6))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
        }
    }

    // MARK: - All-Day Row

    private var allDayEventsByDay: [Date: [CalendarEvent]] {
        var result: [Date: [CalendarEvent]] = [:]
        for day in days {
            let dayStart = calendar.startOfDay(for: day)
            result[dayStart] = events.filter { event in
                guard event.isAllDay else { return false }
                let eventDayStart = calendar.startOfDay(for: event.startDate)
                let eventDayEnd = calendar.startOfDay(for: event.endDate)
                return dayStart >= eventDayStart && dayStart < eventDayEnd
            }
        }
        return result
    }

    @ViewBuilder
    private func allDayRow(_ eventsByDay: [Date: [CalendarEvent]]) -> some View {
        HStack(spacing: 0) {
            Text("All-day")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .frame(width: timeGutterWidth, alignment: .trailing)
                .padding(.trailing, 4)

            ForEach(days, id: \.self) { day in
                let dayStart = calendar.startOfDay(for: day)
                VStack(spacing: 2) {
                    ForEach(eventsByDay[dayStart] ?? [], id: \.id) { event in
                        allDayEventChip(event)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 2)
            }
        }
        .padding(.vertical, 4)
    }

    private func allDayEventChip(_ event: CalendarEvent) -> some View {
        let color = eventColor(for: event)
        return Button(action: { onEventTapped(event) }) {
            HStack(spacing: 4) {
                Circle().fill(color).frame(width: 6, height: 6)
                Text(event.title)
                    .font(.system(size: Typography.caption2, weight: .medium))
                    .lineLimit(1)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(color.opacity(0.1))
            .foregroundStyle(color)
            .clipShape(.rect(cornerRadius: Radius.xs))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Time Grid

    /// Hours too close to the current time indicator get hidden to avoid overlap.
    private func shouldHideHourLabel(_ hour: Int) -> Bool {
        guard days.contains(where: { isToday($0) }) else { return false }
        let nowHour = Calendar.current.component(.hour, from: Date())
        let nowMinute = Calendar.current.component(.minute, from: Date())
        // Hide current hour when indicator is far from the top of the cell
        if hour == nowHour && nowMinute > 20 { return true }
        // Hide next hour if current time is within 20min of it
        if hour == nowHour + 1 && nowMinute >= 40 { return true }
        return false
    }

    private var timeGridBackground: some View {
        VStack(spacing: 0) {
            ForEach(calendarVM.visibleHours, id: \.self) { hour in
                HStack(spacing: 0) {
                    HStack {
                        Spacer()
                        if !shouldHideHourLabel(hour) {
                            Text(calendarVM.hourLabel(hour))
                                .font(.system(size: 10))
                                .foregroundStyle(.quaternary)
                                .padding(.trailing, 4)
                        }
                    }
                    .frame(width: timeGutterWidth, alignment: .topTrailing)
                    .offset(y: -5)

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

    // MARK: - Vertical Day Dividers

    private var dayColumnDividers: some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: timeGutterWidth)

            ForEach(Array(days.enumerated()), id: \.offset) { index, _ in
                if index > 0 {
                    Rectangle()
                        .fill(Color.primary.opacity(0.06))
                        .frame(width: 1)
                }
                Spacer()
                    .frame(maxWidth: .infinity)
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
        var columns: [Int: CalendarEvent] = [:]
        var layouts: [EventLayout] = []

        for event in sorted {
            columns = columns.filter { _, occupant in occupant.endDate > event.startDate }
            var col = 0
            while columns[col] != nil { col += 1 }
            columns[col] = event
            layouts.append(EventLayout(event: event, column: col, totalColumns: 0))
        }

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

            ForEach(Array(days.enumerated()), id: \.offset) { index, day in
                GeometryReader { geo in
                    ZStack(alignment: .topLeading) {
                        // Today column background
                        if isToday(day) {
                            Rectangle()
                                .fill(Color.accentColor.opacity(0.02))
                        }

                        let dayEvents = calendarVM.events(for: day, from: events)
                            .filter { !$0.isAllDay }
                        let layouts = computeOverlapLayout(dayEvents)
                        ForEach(layouts, id: \.event.id) { layout in
                            timedEventBlock(layout.event, column: layout.column, totalColumns: layout.totalColumns, containerWidth: geo.size.width)
                        }

                        let dbItems = calendarVM.databaseItems(for: day, from: databaseItems)
                            .filter { !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                        ForEach(dbItems, id: \.id) { item in
                            databaseItemBlock(item)
                        }
                    }

                    // Drag-to-create preview for this column
                    if let preview = dragPreview, dragDayIndex == index {
                        Rectangle()
                            .fill(Color.accentColor.opacity(0.18))
                            .overlay(
                                Rectangle()
                                    .fill(Color.accentColor)
                                    .frame(width: 2),
                                alignment: .leading
                            )
                            .frame(height: preview.height)
                            .offset(y: preview.y)
                            .allowsHitTesting(false)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 1)
                .contentShape(Rectangle())
                .gesture(
                    onCreateEvent != nil ? dragCreateGesture(dayIndex: index, day: day) : nil
                )
            }
        }
    }

    // MARK: - Drag-to-create gesture

    private struct DragPreview {
        let y: CGFloat
        let height: CGFloat
    }

    private var dragPreview: DragPreview? {
        guard let start = dragStart, let current = dragCurrent else { return nil }
        let minY = min(start.y, current.y)
        let height = max(abs(current.y - start.y), hourHeight * 0.5)
        return DragPreview(y: minY, height: height)
    }

    private func dragCreateGesture(dayIndex: Int, day: Date) -> some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .local)
            .onChanged { value in
                if dragDayIndex == nil {
                    dragDayIndex = dayIndex
                    dragStart = value.startLocation
                }
                dragCurrent = value.location
            }
            .onEnded { value in
                defer {
                    dragStart = nil
                    dragCurrent = nil
                    dragDayIndex = nil
                }
                guard dragDayIndex == dayIndex,
                      let start = dragStart else { return }

                let startY = min(start.y, value.location.y)
                let endY = max(start.y, value.location.y)

                let startTime = date(from: startY, on: day)
                var endTime = date(from: endY, on: day)
                if endTime <= startTime {
                    endTime = startTime.addingTimeInterval(1800)
                }
                onCreateEvent?(startTime, endTime)
            }
    }

    private func date(from y: CGFloat, on day: Date) -> Date {
        let totalSeconds = (y / hourHeight) * 3600
        let hour = Int(totalSeconds / 3600)
        let minute = Int((totalSeconds.truncatingRemainder(dividingBy: 3600)) / 60)
        let clampedHour = max(0, min(23, calendarVM.dayStartHour + hour))
        var comps = calendar.dateComponents([.year, .month, .day], from: day)
        comps.hour = clampedHour
        comps.minute = (minute / 15) * 15  // snap to 15 min
        comps.second = 0
        return calendar.date(from: comps) ?? day
    }

    private func timedEventBlock(_ event: CalendarEvent, column: Int, totalColumns: Int, containerWidth: CGFloat) -> some View {
        let y = calendarVM.yPosition(for: event.startDate, hourHeight: hourHeight)
        let h = calendarVM.eventHeight(start: event.startDate, end: event.endDate, hourHeight: hourHeight)
        let isHovered = hoveredEventId == event.id
        let eventColor = self.eventColor(for: event)

        let cols = max(totalColumns, 1)
        let gutter: CGFloat = 1
        let colWidth = (containerWidth - gutter * CGFloat(cols + 1)) / CGFloat(cols)
        let xOffset = gutter + CGFloat(column) * (colWidth + gutter)

        return Button(action: { onEventTapped(event) }) {
            VStack(alignment: .leading, spacing: 1) {
                // Short events: "Title 9 AM" inline. Tall events: title + time range
                if h <= hourHeight * 0.5 {
                    HStack(spacing: 0) {
                        Text(event.title)
                            .font(.system(size: 11, weight: .medium))
                            .lineLimit(1)
                        Text(" \(calendarVM.timeString(for: event.startDate))")
                            .font(.system(size: 10))
                            .opacity(0.8)
                    }
                } else {
                    HStack(spacing: 3) {
                        Text(event.title)
                            .font(.system(size: 11, weight: .medium))
                            .lineLimit(h > hourHeight ? 3 : 1)
                        if event.linkedPagePath != nil {
                            Image(systemName: "waveform")
                                .font(.system(size: 8))
                                .opacity(0.7)
                        }
                    }
                    Text("\(calendarVM.timeString(for: event.startDate))–\(calendarVM.timeString(for: event.endDate))")
                        .font(.system(size: 10))
                        .opacity(0.8)
                }
            }
            .padding(.leading, 6)
            .padding(.trailing, 4)
            .padding(.vertical, 2)
            .frame(width: colWidth, alignment: .leading)
            .frame(height: h, alignment: .top)
            .foregroundStyle(eventColor)
            .background(eventColor.opacity(isHovered ? 0.14 : 0.08))
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(eventColor)
                    .frame(width: 2)
            }
            .clipShape(.rect(cornerRadius: Radius.xs))
        }
        .buttonStyle(.plain)
        .onHover { hovering in hoveredEventId = hovering ? event.id : nil }
        .offset(x: xOffset, y: y)
    }

    private func databaseItemBlock(_ item: CalendarDatabaseItem) -> some View {
        let y = calendarVM.yPosition(for: item.date, hourHeight: hourHeight)
        let color = TagColor.color(for: item.color)
        let isHovered = hoveredDbItemId == item.id

        return Button(action: { onDatabaseItemTapped(item) }) {
            HStack(spacing: 4) {
                Circle()
                    .fill(color)
                    .frame(width: 5, height: 5)
                Text(item.title)
                    .font(.system(size: Typography.caption2))
                    .lineLimit(1)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(color.opacity(isHovered ? 0.14 : 0.06))
            .clipShape(.rect(cornerRadius: Radius.xs))
            .foregroundStyle(color)
        }
        .buttonStyle(.plain)
        .onHover { hovering in hoveredDbItemId = hovering ? item.id : nil }
        .offset(y: y)
    }

    // MARK: - Current Time

    @ViewBuilder
    private var currentTimeIndicator: some View {
        let now = Date()
        if days.contains(where: { isToday($0) }) {
            let y = calendarVM.yPosition(for: now, hourHeight: hourHeight)
            let nowColor = StatusColor.error

            // Time label in gutter (single line, e.g. "6:38 PM")
            HStack(spacing: 0) {
                HStack(spacing: 0) {
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

            // Thin red line from gutter across all columns, thicker on today
            HStack(alignment: .top, spacing: 0) {
                Color.clear.frame(width: timeGutterWidth)

                // Per-column lines using same layout as event overlays
                ForEach(Array(days.enumerated()), id: \.offset) { index, day in
                    Rectangle()
                        .fill(isToday(day) ? nowColor : nowColor.opacity(0.3))
                        .frame(height: isToday(day) ? 2 : 1)
                        .frame(maxWidth: .infinity)
                        .offset(y: isToday(day) ? y - 0.5 : y)
                }
            }
            .allowsHitTesting(false)
        }
    }

    // MARK: - Helpers

    private func isToday(_ date: Date) -> Bool {
        calendar.isDateInToday(date)
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
