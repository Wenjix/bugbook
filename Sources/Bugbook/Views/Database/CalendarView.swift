import SwiftUI
import BugbookCore

struct CalendarView: View {
    let schema: DatabaseSchema
    @Binding var rows: [DatabaseRow]
    let viewConfig: ViewConfig
    var onOpenRow: (DatabaseRow) -> Void
    var onSave: ((DatabaseRow) -> Void)?
    var onCreateRow: (String, String?) -> Void // date string YYYY-MM-DD, property id

    @State private var displayMonth: Date = Date()
    @State private var selectedDatePropertyId: String?
    @State private var morePopoverDate: String? = nil
    @State private var dragTargetDate: String? = nil
    @State private var draggingRowId: String? = nil
    @State private var dragLocation: CGPoint = .zero
    @State private var dayFrames: [String: CGRect] = [:]

    private let calendar = Calendar.current
    private let dayNames = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
    private let maxVisibleEvents = 3

    private var dateProperties: [PropertyDefinition] {
        schema.properties.filter { $0.type == .date }
    }

    private var dateProperty: PropertyDefinition? {
        if let selectedId = selectedDatePropertyId {
            return schema.properties.first(where: { $0.id == selectedId })
        }
        if let dateId = viewConfig.dateProperty {
            return schema.properties.first(where: { $0.id == dateId })
        }
        return schema.properties.first(where: { $0.type == .date })
    }

    private var monthTitle: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: displayMonth)
    }

    private var todayString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    private var daysInMonth: [DayCell] {
        guard let range = calendar.range(of: .day, in: .month, for: displayMonth) else { return [] }
        let firstOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: displayMonth))!
        let firstWeekday = calendar.component(.weekday, from: firstOfMonth) - 1 // 0=Sun

        var cells: [DayCell] = []

        // Leading empty cells
        for i in 0..<firstWeekday {
            cells.append(DayCell(id: "empty_\(i)", day: 0, dateString: "", isCurrentMonth: false, isToday: false))
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let today = todayString

        for day in range {
            var components = calendar.dateComponents([.year, .month], from: displayMonth)
            components.day = day
            let date = calendar.date(from: components) ?? Date()
            let dateStr = formatter.string(from: date)
            cells.append(DayCell(id: dateStr, day: day, dateString: dateStr, isCurrentMonth: true, isToday: dateStr == today))
        }

        return cells
    }

    private var rowsByDate: [String: [DatabaseRow]] {
        guard let prop = dateProperty else { return [:] }
        let dayCells = daysInMonth
        let currentMonthDates = Set(dayCells.compactMap { $0.isCurrentMonth ? $0.dateString : nil })
        var map: [String: [DatabaseRow]] = [:]
        for row in rows {
            guard let val = row.properties[prop.id], case .date(let raw) = val else { continue }
            if let parsed = DatabaseDateValue.decode(from: raw) {
                for dateStr in currentMonthDates where parsed.contains(dayString: dateStr, calendar: calendar) {
                    map[dateStr, default: []].append(row)
                }
            } else if currentMonthDates.contains(raw) {
                map[raw, default: []].append(row)
            }
        }
        return map
    }

    var body: some View {
        VStack(spacing: 0) {
            // Navigation bar
            HStack {
                Button {
                    displayMonth = calendar.date(byAdding: .month, value: -1, to: displayMonth) ?? displayMonth
                } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.plain)

                Text(monthTitle)
                    .font(.headline)
                    .frame(minWidth: 160)

                Button {
                    displayMonth = calendar.date(byAdding: .month, value: 1, to: displayMonth) ?? displayMonth
                } label: {
                    Image(systemName: "chevron.right")
                }
                .buttonStyle(.plain)

                Spacer()

                // Today button
                Button("Today") {
                    displayMonth = Date()
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(Color.accentColor)

                // Date property selector
                if dateProperties.count > 1 {
                    Menu {
                        ForEach(dateProperties) { prop in
                            Button {
                                selectedDatePropertyId = prop.id
                            } label: {
                                HStack {
                                    Text(prop.name)
                                    if prop.id == dateProperty?.id {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "calendar")
                            Text(dateProperty?.name ?? "Date")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            // Large dataset warning
            if rows.count >= 2000 {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle")
                    Text("Large dataset (\(rows.count) rows) - performance may be affected")
                }
                .font(.caption)
                .foregroundStyle(.orange)
                .padding(.horizontal, 12)
                .padding(.bottom, 4)
            }

            // Day names header
            HStack(spacing: 0) {
                ForEach(dayNames, id: \.self) { name in
                    Text(name)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.bottom, 4)

            // Grid — use GeometryReader to fill available space
            let gridColumns = Array(repeating: GridItem(.flexible(), spacing: 1), count: 7)
            GeometryReader { geo in
                let numberOfRows = max(1, Int(ceil(Double(daysInMonth.count) / 7.0)))
                let cellHeight = max(110, (geo.size.height - CGFloat(numberOfRows - 1)) / CGFloat(numberOfRows))
                let dateRowMap = rowsByDate
                ZStack(alignment: .topLeading) {
                    LazyVGrid(columns: gridColumns, spacing: 1) {
                        ForEach(daysInMonth) { cell in
                            dayCell(cell, height: cellHeight, dateRowMap: dateRowMap)
                        }
                    }

                    if let draggingRow {
                        dragPreview(for: draggingRow)
                            .position(dragLocation)
                            .allowsHitTesting(false)
                    }
                }
                .coordinateSpace(name: "calendar-grid")
                .onPreferenceChange(CalendarDayFramePreferenceKey.self) { dayFrames = $0 }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func dayCell(_ cell: DayCell, height: CGFloat, dateRowMap: [String: [DatabaseRow]]) -> some View {
        HoverDayCell { isHovered in
            VStack(alignment: .leading, spacing: 2) {
                if cell.isCurrentMonth {
                    HStack {
                        Text("\(cell.day)")
                            .font(.caption)
                            .fontWeight(cell.isToday ? .bold : .medium)
                            .foregroundStyle(cell.isToday ? Color.white : Color.primary)
                            .frame(width: 22, height: 22)
                            .background(cell.isToday ? Circle().fill(Color.accentColor) : Circle().fill(Color.clear))
                        Spacer()
                        Button {
                            onCreateRow(cell.dateString, dateProperty?.id)
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .frame(width: 26, height: 22)
                                .background(
                                    RoundedRectangle(cornerRadius: 7)
                                        .fill(Color.fallbackBgSecondary)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 7)
                                                .stroke(Color.fallbackBorderColor.opacity(0.9), lineWidth: 1)
                                        )
                                )
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .opacity(isHovered ? 1 : 0)
                        .allowsHitTesting(isHovered)
                        .help("Create row")
                    }

                    let dayRows = dateRowMap[cell.dateString] ?? []
                    ForEach(dayRows.prefix(maxVisibleEvents)) { row in
                        eventPill(row)
                    }
                    if dayRows.count > maxVisibleEvents {
                        let extra = dayRows.count - maxVisibleEvents
                        Button {
                            morePopoverDate = cell.dateString
                        } label: {
                            Text("+\(extra) more")
                                .font(.caption2)
                                .foregroundStyle(Color.accentColor)
                        }
                        .buttonStyle(.plain)
                        .floatingPopover(isPresented: Binding(
                            get: { morePopoverDate == cell.dateString },
                            set: { if !$0 { morePopoverDate = nil } }
                        )) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(cell.dateString)
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.secondary)
                                Divider()
                                ForEach(dayRows) { row in
                                    eventPill(row, allowsDragging: false)
                                }
                            }
                            .padding(8)
                            .frame(minWidth: 180)
                            .popoverSurface()
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .frame(height: height)
            .padding(4)
            .contentShape(RoundedRectangle(cornerRadius: 8))
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(backgroundColor(for: cell))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(
                        dragTargetDate == cell.dateString ? Color.accentColor.opacity(0.4) : Color.primary.opacity(0.08),
                        lineWidth: dragTargetDate == cell.dateString ? 1.5 : 0.5
                    )
            )
            .background {
                if cell.isCurrentMonth {
                    GeometryReader { proxy in
                        Color.clear
                            .preference(
                                key: CalendarDayFramePreferenceKey.self,
                                value: [cell.dateString: proxy.frame(in: .named("calendar-grid"))]
                            )
                    }
                }
            }
        }
    }

    private func backgroundColor(for cell: DayCell) -> Color {
        guard cell.isCurrentMonth else { return .clear }
        if dragTargetDate == cell.dateString {
            return Color.accentColor.opacity(0.12)
        }
        return Color.fallbackCardBg
    }

    private var draggingRow: DatabaseRow? {
        guard let draggingRowId else { return nil }
        return rows.first(where: { $0.id == draggingRowId })
    }

    private func eventPill(_ row: DatabaseRow, allowsDragging: Bool = true) -> some View {
        let title = row.title(schema: schema)
        let pill = Text(title.isEmpty ? "Untitled" : title)
            .font(.caption)
            .lineLimit(1)
            .truncationMode(.tail)
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color.fallbackBgTertiary)
                    .overlay(
                        RoundedRectangle(cornerRadius: 5)
                            .stroke(Color.fallbackBorderColor.opacity(0.9), lineWidth: 1)
                    )
            )
            .opacity(draggingRowId == row.id ? 0.25 : 1)
            .contentShape(RoundedRectangle(cornerRadius: 5))

        return Group {
            if allowsDragging {
                pill
                    .gesture(
                        DragGesture(minimumDistance: 4, coordinateSpace: .named("calendar-grid"))
                            .onChanged { value in
                                beginDragging(row, at: value.location)
                            }
                            .onEnded { value in
                                completeDrag(for: row, at: value.location)
                            }
                    )
                    .onTapGesture {
                        guard draggingRowId == nil else { return }
                        onOpenRow(row)
                    }
            } else {
                pill
                    .onTapGesture { onOpenRow(row) }
            }
        }
    }

    private func dragPreview(for row: DatabaseRow) -> some View {
        let title = row.title(schema: schema)
        return Text(title.isEmpty ? "Untitled" : title)
            .font(.caption)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.ultraThinMaterial)
            .clipShape(.rect(cornerRadius: 6))
            .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
    }

    private func beginDragging(_ row: DatabaseRow, at location: CGPoint) {
        if draggingRowId == nil {
            draggingRowId = row.id
        }
        dragLocation = location
        dragTargetDate = date(at: location)
    }

    private func completeDrag(for row: DatabaseRow, at location: CGPoint) {
        dragLocation = location
        let targetDate = date(at: location)
        draggingRowId = nil
        dragTargetDate = nil

        guard let targetDate else { return }
        moveRow(row.id, to: targetDate)
    }

    private func date(at location: CGPoint) -> String? {
        daysInMonth.first { cell in
            guard cell.isCurrentMonth, let frame = dayFrames[cell.dateString] else { return false }
            return frame.contains(location)
        }?.dateString
    }

    private func moveRow(_ rowId: String, to targetDate: String) {
        guard let prop = dateProperty,
              let idx = rows.firstIndex(where: { $0.id == rowId }) else { return }

        var updatedRow = rows[idx]
        if case .date(let raw) = updatedRow.properties[prop.id],
           let parsed = DatabaseDateValue.decode(from: raw) {
            guard !parsed.contains(dayString: targetDate, calendar: calendar) else { return }
            updatedRow.properties[prop.id] = .date(parsed.movingStartDay(to: targetDate, calendar: calendar).rawValue)
        } else {
            updatedRow.properties[prop.id] = .date(targetDate)
        }

        rows[idx] = updatedRow
        onSave?(updatedRow)
    }

}

private struct DayCell: Identifiable {
    let id: String
    let day: Int
    let dateString: String
    let isCurrentMonth: Bool
    let isToday: Bool
}

private struct HoverDayCell<Content: View>: View {
    @State private var isHovered = false
    let content: (Bool) -> Content

    init(@ViewBuilder content: @escaping (Bool) -> Content) {
        self.content = content
    }

    var body: some View {
        content(isHovered)
            .onHover { isHovered = $0 }
    }
}

private struct CalendarDayFramePreferenceKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]

    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}
