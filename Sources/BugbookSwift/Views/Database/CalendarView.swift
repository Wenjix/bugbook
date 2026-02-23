import SwiftUI

struct CalendarView: View {
    let schema: DatabaseSchema
    @Binding var rows: [DatabaseRow]
    let viewConfig: ViewConfig
    var onOpenRow: (DatabaseRow) -> Void
    var onCreateRow: (String) -> Void // date string YYYY-MM-DD

    @State private var displayMonth: Date = Date()
    @State private var selectedDatePropertyId: String?

    private let calendar = Calendar.current
    private let dayNames = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

    private var dateProperties: [PropertyDefinition] {
        schema.properties.filter { $0.type == .date }
    }

    private var dateProperty: PropertyDefinition? {
        if let selectedId = selectedDatePropertyId {
            return schema.properties.first(where: { $0.id == selectedId })
        }
        if let dateId = viewConfig.datePropertyId {
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
            if let val = row.properties[prop.name], case .date(let d) = val {
                return d == dateStr
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
                .foregroundColor(.accentColor)

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
                        .foregroundColor(.secondary)
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
                .foregroundColor(.orange)
                .padding(.horizontal, 12)
                .padding(.bottom, 4)
            }

            // Day names header
            HStack(spacing: 0) {
                ForEach(dayNames, id: \.self) { name in
                    Text(name)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.bottom, 4)

            // Grid
            let gridColumns = Array(repeating: GridItem(.flexible(), spacing: 1), count: 7)
            LazyVGrid(columns: gridColumns, spacing: 1) {
                ForEach(daysInMonth) { cell in
                    dayCell(cell)
                }
            }
        }
        .padding(12)
    }

    private func dayCell(_ cell: DayCell) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if cell.isCurrentMonth {
                HStack {
                    Text("\(cell.day)")
                        .font(.caption)
                        .fontWeight(cell.isToday ? .bold : .medium)
                        .foregroundColor(cell.isToday ? .white : .primary)
                        .frame(width: 22, height: 22)
                        .background(cell.isToday ? Circle().fill(Color.accentColor) : Circle().fill(Color.clear))
                    Spacer()
                    Button {
                        onCreateRow(cell.dateString)
                    } label: {
                        Image(systemName: "plus")
                            .font(.caption2)
                    }
                    .buttonStyle(.plain)
                    .opacity(0.5)
                }

                let dayRows = rowsForDate(cell.dateString)
                ForEach(dayRows.prefix(3)) { row in
                    Button {
                        onOpenRow(row)
                    } label: {
                        Text(row.title)
                            .font(.caption2)
                            .lineLimit(1)
                            .foregroundColor(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.accentColor.opacity(0.1))
                            .cornerRadius(3)
                    }
                    .buttonStyle(.plain)
                    .draggable(row.id) {
                        Text(row.title)
                            .padding(6)
                            .background(.ultraThinMaterial)
                            .cornerRadius(4)
                    }
                }
                if dayRows.count > 3 {
                    Text("+\(dayRows.count - 3) more")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 80, alignment: .topLeading)
        .padding(4)
        .background(cell.isToday ? Color.accentColor.opacity(0.05) : (cell.isCurrentMonth ? Color(nsColor: .controlBackgroundColor) : Color.clear))
        .cornerRadius(4)
        .dropDestination(for: String.self) { droppedIds, _ in
            guard let prop = dateProperty, cell.isCurrentMonth else { return false }
            for droppedId in droppedIds {
                if let idx = rows.firstIndex(where: { $0.id == droppedId }) {
                    rows[idx].properties[prop.name] = .date(cell.dateString)
                }
            }
            return true
        }
    }

}

private struct DayCell: Identifiable {
    let id: String
    let day: Int
    let dateString: String
    let isCurrentMonth: Bool
    let isToday: Bool
}
