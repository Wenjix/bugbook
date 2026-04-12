import SwiftUI
import DahsoCore

struct MobileDatabaseView: View {
    let dbPath: String

    @State private var viewState: MobileDatabaseViewState
    @State private var showViewPicker = false
    @State private var showNewViewSheet = false
    @State private var showFilterSort = false
    @State private var showSchemaEditor = false

    init(dbPath: String) {
        self.dbPath = dbPath
        _viewState = State(initialValue: MobileDatabaseViewState(dbPath: dbPath))
    }

    var body: some View {
        Group {
            if let schema = viewState.schema {
                VStack(spacing: 0) {
                    viewTabBar(schema: schema)
                    Divider()
                    databaseContent(schema: schema)
                }
            } else if let error = viewState.error {
                ContentUnavailableView("Error", systemImage: "exclamationmark.triangle", description: Text(error))
            } else {
                ProgressView()
            }
        }
        .navigationTitle(viewState.schema?.name ?? "Database")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button { showFilterSort = true } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                }
                .help("Filter & Sort")
                Button { showSchemaEditor = true } label: {
                    Image(systemName: "slider.horizontal.3")
                }
                .help("Edit Schema")
                Button { viewState.createRow() } label: {
                    Image(systemName: "plus")
                }
                .help("New Row")
            }
        }
        .refreshable { viewState.loadData() }
        .onAppear { viewState.loadData() }
        .sheet(isPresented: $showFilterSort) {
            MobileFilterSortView(viewState: viewState)
        }
        .sheet(isPresented: $showSchemaEditor) {
            MobileSchemaEditorView(viewState: viewState)
        }
        .sheet(isPresented: $showNewViewSheet) {
            MobileNewViewSheet(viewState: viewState)
        }
    }

    // MARK: - View Tab Bar

    @ViewBuilder
    private func viewTabBar(schema: DatabaseSchema) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(schema.views, id: \.id) { view in
                    Button {
                        viewState.activeViewId = view.id
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: viewTypeIcon(view.type))
                                .font(.caption)
                            Text(view.name)
                                .font(.subheadline)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(viewState.activeViewId == view.id ?
                            Color.accentColor.opacity(0.15) : Color.clear)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }

                Button { showNewViewSheet = true } label: {
                    Image(systemName: "plus")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
    }

    // MARK: - Content

    @ViewBuilder
    private func databaseContent(schema: DatabaseSchema) -> some View {
        let viewType = viewState.activeView?.type ?? .table

        switch viewType {
        case .table, .list:
            MobileTableContentView(viewState: viewState)
        case .kanban:
            MobileKanbanContentView(viewState: viewState)
        case .calendar:
            MobileCalendarContentView(viewState: viewState)
        }
    }

    private func viewTypeIcon(_ type: ViewType) -> String {
        switch type {
        case .table: return "tablecells"
        case .list: return "list.bullet"
        case .kanban: return "rectangle.3.group"
        case .calendar: return "calendar"
        }
    }
}

// MARK: - Table/List Content

struct MobileTableContentView: View {
    var viewState: MobileDatabaseViewState

    var body: some View {
        let rows = viewState.filteredAndSortedRows()
        if rows.isEmpty {
            ContentUnavailableView("No rows", systemImage: "doc.text")
        } else {
            List {
                ForEach(rows) { row in
                    NavigationLink {
                        MobileDatabaseRowView(
                            dbPath: viewState.dbPath,
                            schema: viewState.schema!,
                            existingRow: row
                        )
                    } label: {
                        MobileRowCellView(
                            row: row,
                            schema: viewState.schema!,
                            visibleProperties: viewState.visibleProperties
                        )
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            viewState.deleteRow(row)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
            .listStyle(.plain)
        }
    }
}

// MARK: - Row Cell

struct MobileRowCellView: View {
    let row: DatabaseRow
    let schema: DatabaseSchema
    let visibleProperties: [PropertyDefinition]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(row.title(schema: schema))
                .font(.body).fontWeight(.medium)
                .lineLimit(1)

            let extras = visibleProperties.filter { $0.type != .title }.prefix(4)
            if !extras.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(Array(extras), id: \.id) { prop in
                        MobilePropertyBadgeView(
                            property: prop,
                            value: row.properties[prop.id] ?? .empty,
                            schema: schema
                        )
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Property Badge (compact display)

struct MobilePropertyBadgeView: View {
    let property: PropertyDefinition
    let value: PropertyValue
    let schema: DatabaseSchema

    var body: some View {
        if case .empty = value { EmptyView() } else {
            Group {
                switch property.type {
                case .select:
                    if case .select(let optionId) = value,
                       let option = property.options?.first(where: { $0.id == optionId }) {
                        Text(option.name)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(colorForName(option.color).opacity(0.15))
                            .foregroundStyle(colorForName(option.color))
                            .clipShape(Capsule())
                    }
                case .multiSelect:
                    if case .multiSelect(let optionIds) = value {
                        ForEach(optionIds.prefix(3), id: \.self) { optId in
                            if let option = property.options?.first(where: { $0.id == optId }) {
                                Text(option.name)
                                    .font(.caption2)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(colorForName(option.color).opacity(0.15))
                                    .foregroundStyle(colorForName(option.color))
                                    .clipShape(Capsule())
                            }
                        }
                    }
                case .checkbox:
                    if case .checkbox(let checked) = value {
                        Image(systemName: checked ? "checkmark.circle.fill" : "circle")
                            .font(.caption)
                            .foregroundStyle(checked ? .green : .secondary)
                    }
                case .date:
                    if case .date(let raw) = value,
                       let dateVal = DatabaseDateValue.decode(from: raw) {
                        Text(dateVal.displayText())
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                case .number:
                    if case .number(let n) = value {
                        let format = property.config?.format
                        Text(formatNumber(n, format: format))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                case .url:
                    if case .url(let s) = value, !s.isEmpty {
                        Image(systemName: "link")
                            .font(.caption2)
                            .foregroundStyle(.blue)
                    }
                case .relation, .lookup, .rollup, .formula:
                    let str = value.stringValue
                    if !str.isEmpty {
                        Text(str)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                default:
                    let str = value.stringValue
                    if !str.isEmpty {
                        Text("\(property.name): \(str)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
        }
    }
}

// MARK: - Kanban Content

struct MobileKanbanContentView: View {
    var viewState: MobileDatabaseViewState

    private var groupByProperty: String? {
        viewState.activeView?.groupBy
    }

    var body: some View {
        if let groupBy = groupByProperty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    let groups = viewState.groupedRows(by: groupBy)
                    ForEach(Array(groups.enumerated()), id: \.offset) { _, group in
                        MobileKanbanColumn(
                            title: group.option?.name ?? "No value",
                            color: group.option?.color ?? "gray",
                            rows: group.rows,
                            schema: viewState.schema!,
                            viewState: viewState,
                            groupByProperty: groupBy,
                            optionId: group.option?.id
                        )
                    }
                }
                .padding()
            }
        } else {
            ContentUnavailableView(
                "No group-by property",
                systemImage: "rectangle.3.group",
                description: Text("Set a select property to group by in view settings.")
            )
        }
    }
}

struct MobileKanbanColumn: View {
    let title: String
    let color: String
    let rows: [DatabaseRow]
    let schema: DatabaseSchema
    var viewState: MobileDatabaseViewState
    let groupByProperty: String
    let optionId: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Circle()
                    .fill(colorForName(color))
                    .frame(width: 8, height: 8)
                Text(title)
                    .font(.subheadline.bold())
                Spacer()
                Text("\(rows.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)

            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 8) {
                    ForEach(rows) { row in
                        NavigationLink {
                            MobileDatabaseRowView(
                                dbPath: viewState.dbPath,
                                schema: schema,
                                existingRow: row
                            )
                        } label: {
                            MobileKanbanCard(row: row, schema: schema)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .frame(width: 260)
        .padding(.vertical, 8)
        #if os(iOS)
        .background(Color(.secondarySystemGroupedBackground))
        #else
        .background(Color(.windowBackgroundColor))
        #endif
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct MobileKanbanCard: View {
    let row: DatabaseRow
    let schema: DatabaseSchema

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(row.title(schema: schema))
                .font(.subheadline)
                .fontWeight(.medium)
                .lineLimit(2)

            let extras = schema.properties
                .filter { $0.type != .title && $0.type != .select }
                .prefix(2)
            ForEach(Array(extras), id: \.id) { prop in
                if let val = row.properties[prop.id], val != .empty {
                    MobilePropertyBadgeView(property: prop, value: val, schema: schema)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        #if os(iOS)
        .background(Color(.systemBackground))
        #else
        .background(Color(.controlBackgroundColor))
        #endif
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(color: .black.opacity(0.05), radius: 2, y: 1)
    }
}

// MARK: - Calendar Content

struct MobileCalendarContentView: View {
    var viewState: MobileDatabaseViewState

    @State private var selectedMonth = Date()
    @State private var selectedDay: String?

    private var datePropertyId: String? {
        viewState.activeView?.dateProperty ?? viewState.schema?.properties.first(where: { $0.type == .date })?.id
    }

    var body: some View {
        if let datePropId = datePropertyId {
            VStack(spacing: 0) {
                calendarHeader
                calendarGrid(datePropId: datePropId)

                if let day = selectedDay {
                    Divider()
                    dayDetail(day: day, datePropId: datePropId)
                }
            }
        } else {
            ContentUnavailableView(
                "No date property",
                systemImage: "calendar",
                description: Text("Add a date property to use calendar view.")
            )
        }
    }

    private var calendarHeader: some View {
        HStack {
            Button { changeMonth(-1) } label: {
                Image(systemName: "chevron.left")
            }
            Spacer()
            Text(monthYearString)
                .font(.headline)
            Spacer()
            Button { changeMonth(1) } label: {
                Image(systemName: "chevron.right")
            }
        }
        .padding()
    }

    private func calendarGrid(datePropId: String) -> some View {
        let days = daysInMonth()
        let rows = viewState.filteredAndSortedRows()

        return VStack(spacing: 2) {
            // Day headers
            HStack(spacing: 0) {
                ForEach(Array(["S", "M", "T", "W", "T", "F", "S"].enumerated()), id: \.offset) { _, day in
                    Text(day)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }

            // Day cells
            let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 7)
            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(days, id: \.self) { dayInfo in
                    if let day = dayInfo {
                        let dayString = canonicalDayString(day)
                        let count = countRows(rows, datePropId: datePropId, day: dayString)
                        Button {
                            selectedDay = dayString
                        } label: {
                            VStack(spacing: 2) {
                                Text("\(Calendar.current.component(.day, from: day))")
                                    .font(.caption)
                                    .foregroundStyle(isToday(day) ? .white : .primary)
                                if count > 0 {
                                    Circle()
                                        .fill(Color.accentColor)
                                        .frame(width: 5, height: 5)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 36)
                            .background(
                                isToday(day) ? Color.accentColor :
                                    (selectedDay == dayString ? Color.accentColor.opacity(0.15) : Color.clear)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                    } else {
                        Color.clear.frame(height: 36)
                    }
                }
            }
            .padding(.horizontal, 8)
        }
    }

    @ViewBuilder
    private func dayDetail(day: String, datePropId: String) -> some View {
        let rows = viewState.filteredAndSortedRows().filter { row in
            if case .date(let raw) = row.properties[datePropId],
               let dateVal = DatabaseDateValue.decode(from: raw) {
                return dateVal.contains(dayString: day)
            }
            return false
        }

        List {
            if rows.isEmpty {
                Text("No items")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(rows) { row in
                    NavigationLink {
                        MobileDatabaseRowView(
                            dbPath: viewState.dbPath,
                            schema: viewState.schema!,
                            existingRow: row
                        )
                    } label: {
                        Text(row.title(schema: viewState.schema!))
                    }
                }
            }
        }
        .listStyle(.plain)
        .frame(maxHeight: 200)
    }

    // MARK: - Calendar Helpers

    private static let monthYearFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMMM yyyy"
        return f
    }()

    private static let dayStringFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private var monthYearString: String {
        Self.monthYearFormatter.string(from: selectedMonth)
    }

    private func changeMonth(_ delta: Int) {
        selectedMonth = Calendar.current.date(byAdding: .month, value: delta, to: selectedMonth) ?? selectedMonth
        selectedDay = nil
    }

    private func daysInMonth() -> [Date?] {
        let cal = Calendar.current
        guard let range = cal.range(of: .day, in: .month, for: selectedMonth),
              let firstOfMonth = cal.date(from: cal.dateComponents([.year, .month], from: selectedMonth)) else {
            return []
        }
        let weekday = cal.component(.weekday, from: firstOfMonth) - 1 // 0=Sun
        var days: [Date?] = Array(repeating: nil, count: weekday)
        for day in range {
            if let date = cal.date(byAdding: .day, value: day - 1, to: firstOfMonth) {
                days.append(date)
            }
        }
        // Pad to complete last row
        while days.count % 7 != 0 { days.append(nil) }
        return days
    }

    private func canonicalDayString(_ date: Date) -> String {
        Self.dayStringFormatter.string(from: date)
    }

    private func isToday(_ date: Date) -> Bool {
        Calendar.current.isDateInToday(date)
    }

    private func countRows(_ rows: [DatabaseRow], datePropId: String, day: String) -> Int {
        rows.filter { row in
            if case .date(let raw) = row.properties[datePropId],
               let dateVal = DatabaseDateValue.decode(from: raw) {
                return dateVal.contains(dayString: day)
            }
            return false
        }.count
    }
}

// MARK: - Flow Layout

struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = computeLayout(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = computeLayout(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                                  proposal: .unspecified)
        }
    }

    private struct LayoutResult {
        var size: CGSize
        var positions: [CGPoint]
    }

    private func computeLayout(proposal: ProposedViewSize, subviews: Subviews) -> LayoutResult {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxX: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            maxX = max(maxX, x)
        }

        return LayoutResult(size: CGSize(width: maxX, height: y + rowHeight), positions: positions)
    }
}

// MARK: - Color Helper

func colorForName(_ name: String) -> Color {
    switch name {
    case "blue": return .blue
    case "green": return .green
    case "red": return .red
    case "yellow": return .yellow
    case "purple": return .purple
    case "pink": return .pink
    case "orange": return .orange
    case "teal": return .teal
    case "indigo": return .indigo
    case "brown": return .brown
    case "mint": return .mint
    case "cyan": return .cyan
    default: return .gray
    }
}
