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

    private func rowsForDate(_ dateStr: String) -> [DatabaseRow] {
        guard let prop = dateProperty else { return [] }
        return rows.filter { row in
            if let val = row.properties[prop.id], case .date(let raw) = val {
                return DatabaseDateValue.decode(from: raw)?.contains(dayString: dateStr, calendar: calendar) ?? (raw == dateStr)
            }
            return false
        }
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
                LazyVGrid(columns: gridColumns, spacing: 1) {
                    ForEach(daysInMonth) { cell in
                        dayCell(cell, height: cellHeight)
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func dayCell(_ cell: DayCell, height: CGFloat) -> some View {
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

                    let dayRows = rowsForDate(cell.dateString)
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
                                    eventPill(row)
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
            .background(cell.isCurrentMonth ? Color.fallbackCardBg : Color.clear)
            .overlay(
                Rectangle()
                    .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
            )
            .dropDestination(for: String.self) { droppedIds, _ in
                guard let prop = dateProperty, cell.isCurrentMonth else { return false }
                for droppedId in droppedIds {
                    if let idx = rows.firstIndex(where: { $0.id == droppedId }) {
                        if case .date(let raw) = rows[idx].properties[prop.id],
                           let parsed = DatabaseDateValue.decode(from: raw) {
                            rows[idx].properties[prop.id] = .date(parsed.movingStartDay(to: cell.dateString, calendar: calendar).rawValue)
                        } else {
                            rows[idx].properties[prop.id] = .date(cell.dateString)
                        }
                        onSave?(rows[idx])
                    }
                }
                return true
            }
        }
    }

    private func eventPill(_ row: DatabaseRow) -> some View {
        let title = row.title(schema: schema)
        return Text(title.isEmpty ? "Untitled" : title)
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
            .draggable(row.id) {
                Text(title)
                    .padding(6)
                    .background(.ultraThinMaterial)
                    .clipShape(.rect(cornerRadius: 4))
            }
            .simultaneousGesture(TapGesture().onEnded { onOpenRow(row) })
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
