import SwiftUI

struct CalendarView: View {
    let schema: DatabaseSchema
    @Binding var rows: [DatabaseRow]
    let viewConfig: ViewConfig
    var onOpenRow: (DatabaseRow) -> Void
    var onCreateRow: (String) -> Void // date string YYYY-MM-DD

    @State private var displayMonth: Date = Date()

    private let calendar = Calendar.current
    private let dayNames = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

    private var dateProperty: PropertyDefinition? {
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

    private var daysInMonth: [DayCell] {
        guard let range = calendar.range(of: .day, in: .month, for: displayMonth) else { return [] }
        let firstOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: displayMonth))!
        let firstWeekday = calendar.component(.weekday, from: firstOfMonth) - 1 // 0=Sun

        var cells: [DayCell] = []

        // Leading empty cells
        for i in 0..<firstWeekday {
            cells.append(DayCell(id: "empty_\(i)", day: 0, dateString: "", isCurrentMonth: false))
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"

        for day in range {
            var components = calendar.dateComponents([.year, .month], from: displayMonth)
            components.day = day
            let date = calendar.date(from: components) ?? Date()
            cells.append(DayCell(id: formatter.string(from: date), day: day, dateString: formatter.string(from: date), isCurrentMonth: true))
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
            // Navigation
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
            }
            .padding(.vertical, 8)

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
                        .fontWeight(.medium)
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
                    }
                    .buttonStyle(.plain)
                }
                if dayRows.count > 3 {
                    Text("+\(dayRows.count - 3) more")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 70, alignment: .topLeading)
        .padding(4)
        .background(cell.isCurrentMonth ? Color(nsColor: .controlBackgroundColor) : Color.clear)
        .cornerRadius(4)
    }
}

private struct DayCell: Identifiable {
    let id: String
    let day: Int
    let dateString: String
    let isCurrentMonth: Bool
}
