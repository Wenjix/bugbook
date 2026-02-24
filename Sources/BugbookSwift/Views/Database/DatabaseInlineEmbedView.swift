import SwiftUI
import BugbookCore

/// Compact database embed for rendering inside a markdown page.
/// Reuses the same TableView/KanbanView/CalendarView/ListView as the full-page view.
struct DatabaseInlineEmbedView: View {
    let dbPath: String
    var onOpenRow: ((DatabaseRow) -> Void)?
    var onOpenDatabase: (() -> Void)?

    @StateObject private var dbService = DatabaseService()
    @State private var schema: DatabaseSchema?
    @State private var rows: [DatabaseRow] = []
    @State private var activeViewId: String = ""
    @State private var selectedRowIndex: Int? = nil
    @State private var error: String?
    @State private var showFilterSort: Bool = false

    private var activeView: ViewConfig? {
        schema?.views.first(where: { $0.id == activeViewId })
    }

    private var filteredAndSortedRows: [DatabaseRow] {
        guard let view = activeView, schema != nil else { return rows }
        var result = rows

        for filter in view.filters {
            result = result.filter { row in
                let val = row.properties[filter.property] ?? .empty
                return matchesFilter(val, filter: filter)
            }
        }

        for sort in view.sorts.reversed() {
            result.sort { a, b in
                let va = a.properties[sort.property] ?? .empty
                let vb = b.properties[sort.property] ?? .empty
                let cmp = compareValues(va, vb)
                return sort.ascending ? cmp == .orderedAscending : cmp == .orderedDescending
            }
        }

        return result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let error = error {
                Text(error)
                    .font(.callout)
                    .foregroundColor(.red)
                    .padding(8)
            } else if let schema = schema {
                if let rowIdx = selectedRowIndex, rowIdx < rows.count {
                    RowPageView(
                        schema: schema,
                        row: $rows[rowIdx],
                        onSave: { row in saveRow(row) },
                        onBack: { selectedRowIndex = nil },
                        onAddOption: { propId, option in addSelectOption(propId, option: option) },
                        onUpdateOption: { propId, optId, name, color in updateSelectOption(propId, optionId: optId, name: name, color: color) },
                        onDeleteOption: { propId, optId in deleteSelectOption(propId, optionId: optId) }
                    )
                    .frame(maxHeight: 450)
                } else {
                    headerBar(schema: schema)
                    if showFilterSort {
                        inlineFilterSortBar(schema: schema)
                    }
                    Divider()
                    ScrollView {
                        viewContent(schema: schema)
                    }
                    .frame(maxHeight: 450)
                    Divider()
                    newRowButton(schema: schema)
                }
            } else {
                HStack(spacing: 6) {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("Loading...")
                        .font(.callout)
                        .foregroundColor(.secondary)
                }
                .padding(8)
            }
        }
        .background(Color.clear)
        .task {
            await loadData()
        }
        .onReceive(NotificationCenter.default.publisher(for: .databaseDidChange)) { notification in
            guard let changedPath = notification.userInfo?["dbPath"] as? String,
                  changedPath == dbPath else { return }
            Task { await loadData() }
        }
    }

    private func postChangeNotification() {
        NotificationCenter.default.post(name: .databaseDidChange, object: nil, userInfo: ["dbPath": dbPath])
    }

    // MARK: - Header

    private func headerBar(schema: DatabaseSchema) -> some View {
        HStack(spacing: 6) {
            // Database name + open button
            Button {
                onOpenDatabase?()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "tablecells")
                        .font(.callout)
                    Text(schema.name)
                        .font(.callout)
                        .fontWeight(.semibold)
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 9, weight: .semibold))
                }
                .foregroundColor(.accentColor)
            }
            .buttonStyle(.plain)

            // View tabs
            ForEach(schema.views) { view in
                Button {
                    activeViewId = view.id
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: iconForViewType(view.type))
                        Text(view.name)
                    }
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(view.id == activeViewId ? Color.accentColor.opacity(0.15) : Color.clear)
                    .cornerRadius(4)
                }
                .buttonStyle(.plain)
            }

            Spacer()

            // Column visibility
            Menu {
                ForEach(schema.properties.filter({ $0.type != .title })) { prop in
                    let isHidden = (activeView?.hiddenColumns ?? []).contains(prop.id)
                    Button {
                        toggleColumnVisibility(prop.id)
                    } label: {
                        HStack {
                            Text(prop.name)
                            if !isHidden { Image(systemName: "checkmark") }
                        }
                    }
                }
            } label: {
                Image(systemName: "eye")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()

            // Filter toggle
            Button {
                showFilterSort.toggle()
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "line.3.horizontal.decrease")
                    Text("Filter")
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Filter/Sort Bar

    private func inlineFilterSortBar(schema: DatabaseSchema) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let view = activeView {
                ForEach(view.filters) { filter in
                    inlineFilterRow(filter, schema: schema)
                }
                ForEach(view.sorts) { sort in
                    inlineSortRow(sort, schema: schema)
                }
            }
            HStack(spacing: 12) {
                Menu {
                    ForEach(schema.properties.filter({ $0.type != .title })) { prop in
                        Button(prop.name) { addFilter(propertyId: prop.id) }
                    }
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "plus")
                        Text("Add filter")
                    }
                    .font(.caption)
                    .foregroundColor(.accentColor)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()

                Menu {
                    ForEach(schema.properties.filter({ $0.type != .title })) { prop in
                        Button(prop.name) { addSort(propertyId: prop.id, ascending: true) }
                    }
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "plus")
                        Text("Add sort")
                    }
                    .font(.caption)
                    .foregroundColor(.accentColor)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()

                Spacer()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.gray.opacity(0.04))
    }

    private func inlineFilterRow(_ filter: FilterConfig, schema: DatabaseSchema) -> some View {
        let prop = schema.properties.first(where: { $0.id == filter.property })
        return HStack(spacing: 6) {
            Menu {
                ForEach(schema.properties.filter({ $0.type != .title })) { p in
                    Button(p.name) { updateFilter(filter.id, property: p.id, op: nil, value: nil) }
                }
            } label: {
                Text(prop?.name ?? "Property")
                    .font(.caption)
                    .fontWeight(.medium)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(4)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            Text(filter.op.replacingOccurrences(of: "_", with: " "))
                .font(.caption)
                .foregroundColor(.secondary)

            Spacer()

            Button { removeFilter(filter.id) } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
    }

    private func inlineSortRow(_ sort: SortConfig, schema: DatabaseSchema) -> some View {
        let prop = schema.properties.first(where: { $0.id == sort.property })
        return HStack(spacing: 6) {
            Image(systemName: "arrow.up.arrow.down")
                .font(.caption2)
                .foregroundColor(.secondary)
            Text(prop?.name ?? "Property")
                .font(.caption)
                .fontWeight(.medium)
            Text(sort.ascending ? "Ascending" : "Descending")
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            Button { removeSort(sort.id) } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - View Content

    @ViewBuilder
    private func viewContent(schema: DatabaseSchema) -> some View {
        let filtered = filteredAndSortedRows
        var boundRows: Binding<[DatabaseRow]> {
            Binding(
                get: { filtered },
                set: { newVal in
                    for updated in newVal {
                        if let idx = rows.firstIndex(where: { $0.id == updated.id }) {
                            rows[idx] = updated
                        }
                    }
                }
            )
        }

        switch activeView?.type ?? .table {
        case .table:
            TableView(
                schema: schema,
                rows: boundRows,
                viewConfig: activeView ?? defaultViewConfig(),
                onOpenRow: { row in openRow(row) },
                onSave: { row in saveRow(row) },
                onDelete: { row in deleteRow(row) },
                onToggleColumn: { propId in toggleColumnVisibility(propId) },
                onAddProperty: { type in addPropertyFromTable(type: type) },
                onDeleteProperty: { propId in deleteProperty(propId) },
                onChangePropertyType: { propId, newType in changePropertyType(propId, to: newType) },
                onAddSelectOption: { propId, option in addSelectOption(propId, option: option) },
                onUpdateSelectOption: { propId, optId, name, color in updateSelectOption(propId, optionId: optId, name: name, color: color) },
                onDeleteSelectOption: { propId, optId in deleteSelectOption(propId, optionId: optId) },
                onResizeColumn: { propId, width in resizeColumn(propId, to: width) }
            )
        case .kanban:
            KanbanView(
                schema: schema,
                rows: boundRows,
                viewConfig: activeView ?? defaultViewConfig(),
                onOpenRow: { row in openRow(row) },
                onSave: { row in saveRow(row) },
                onUpdateGroupBy: { propId in updateGroupBy(propId) },
                onAddSelectOption: { propId, option in addSelectOption(propId, option: option) }
            )
        case .list:
            ListView(
                schema: schema,
                rows: boundRows,
                viewConfig: activeView ?? defaultViewConfig(),
                onOpenRow: { row in openRow(row) },
                onSave: { row in saveRow(row) }
            )
        case .calendar:
            CalendarView(
                schema: schema,
                rows: boundRows,
                viewConfig: activeView ?? defaultViewConfig(),
                onOpenRow: { row in openRow(row) },
                onCreateRow: { dateStr in createRowWithDate(dateStr, schema: schema) }
            )
        }
    }

    // MARK: - New Row Button

    private func newRowButton(schema: DatabaseSchema) -> some View {
        Button {
            addNewRow(schema: schema)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "plus")
                    .font(.caption)
                Text("New")
                    .font(.callout)
            }
            .foregroundColor(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Data Operations

    private func loadData() async {
        do {
            let (loadedSchema, loadedRows) = try await dbService.loadDatabase(at: dbPath)
            schema = loadedSchema
            rows = loadedRows
            activeViewId = loadedSchema.defaultView
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func saveRow(_ row: DatabaseRow) {
        guard let schema = schema else { return }
        if let idx = rows.firstIndex(where: { $0.id == row.id }) {
            rows[idx] = row
        }
        Task {
            try? dbService.saveRow(row, schema: schema, at: dbPath)
            postChangeNotification()
        }
    }

    private func deleteRow(_ row: DatabaseRow) {
        guard let schema = schema else { return }
        rows.removeAll { $0.id == row.id }
        Task {
            try? dbService.deleteRow(row.id, in: dbPath)
            try? dbService.updateIndex(rows: rows, schema: schema, at: dbPath)
            postChangeNotification()
        }
    }

    private func addNewRow(schema: DatabaseSchema) {
        do {
            let newRow = try dbService.createRow(in: dbPath, schema: schema)
            rows.append(newRow)
            postChangeNotification()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func createRowWithDate(_ dateStr: String, schema: DatabaseSchema) {
        guard let dateProp = schema.properties.first(where: { $0.type == .date }) else {
            addNewRow(schema: schema)
            return
        }
        do {
            var newRow = try dbService.createRow(in: dbPath, schema: schema)
            newRow.properties[dateProp.id] = .date(dateStr)
            try dbService.saveRow(newRow, schema: schema, at: dbPath)
            if let idx = rows.firstIndex(where: { $0.id == newRow.id }) {
                rows[idx] = newRow
            } else {
                rows.append(newRow)
            }
            postChangeNotification()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func openRow(_ row: DatabaseRow) {
        if let idx = rows.firstIndex(where: { $0.id == row.id }) {
            selectedRowIndex = idx
        }
    }

    private func addSelectOption(_ propertyId: String, option: SelectOption) {
        guard var s = schema else { return }
        Task {
            try? dbService.addSelectOption(option, toProperty: propertyId, in: &s, at: dbPath)
            schema = s
        }
    }

    private func updateSelectOption(_ propertyId: String, optionId: String, name: String?, color: String?) {
        guard var s = schema else { return }
        Task {
            try? dbService.updateSelectOption(optionId, name: name, color: color, inProperty: propertyId, in: &s, at: dbPath)
            schema = s
        }
    }

    private func deleteSelectOption(_ propertyId: String, optionId: String) {
        guard var s = schema else { return }
        Task {
            try? dbService.deleteSelectOption(optionId, fromProperty: propertyId, in: &s, rows: &rows, at: dbPath)
            schema = s
        }
    }

    private func resizeColumn(_ propertyId: String, to width: CGFloat) {
        guard var s = schema, var view = activeView else { return }
        if view.columnWidths == nil { view.columnWidths = [:] }
        view.columnWidths?[propertyId] = Double(width)
        Task {
            try? dbService.updateView(view, in: &s, at: dbPath)
            schema = s
        }
    }

    private func toggleColumnVisibility(_ propertyId: String) {
        guard var s = schema, var view = activeView else { return }
        var hidden = view.hiddenColumns ?? []
        if hidden.contains(propertyId) {
            hidden.removeAll { $0 == propertyId }
        } else {
            hidden.append(propertyId)
        }
        view.hiddenColumns = hidden
        Task {
            try? dbService.updateView(view, in: &s, at: dbPath)
            schema = s
        }
    }

    private func addPropertyFromTable(type: PropertyType) {
        guard var s = schema else { return }
        let config: PropertyConfig? = (type == .select || type == .multiSelect) ? PropertyConfig(options: []) : nil
        let prop = PropertyDefinition(
            id: "prop_\(UUID().uuidString)",
            name: "New \(type.rawValue.capitalized)",
            type: type,
            config: config
        )
        Task {
            try? dbService.addProperty(prop, to: &s, at: dbPath)
            schema = s
        }
    }

    private func deleteProperty(_ propertyId: String) {
        guard var s = schema else { return }
        Task {
            try? dbService.deleteProperty(propertyId, from: &s, at: dbPath)
            schema = s
        }
    }

    private func changePropertyType(_ propertyId: String, to newType: PropertyType) {
        guard var s = schema else { return }
        Task {
            try? dbService.changePropertyType(propertyId, to: newType, in: &s, rows: &rows, at: dbPath)
            schema = s
        }
    }

    private func updateGroupBy(_ propertyId: String) {
        guard var s = schema, var view = activeView else { return }
        view.groupBy = propertyId
        Task {
            try? dbService.updateView(view, in: &s, at: dbPath)
            schema = s
        }
    }

    // MARK: - Filter/Sort Management

    private func addFilter(propertyId: String) {
        guard var s = schema, var view = activeView else { return }
        let filter = FilterConfig(property: propertyId, op: "is_not_empty", value: "")
        view.filters.append(filter)
        Task {
            try? dbService.updateView(view, in: &s, at: dbPath)
            schema = s
        }
    }

    private func updateFilter(_ filterId: String, property: String?, op: String?, value: String?) {
        guard var s = schema, var view = activeView,
              let idx = view.filters.firstIndex(where: { $0.id == filterId }) else { return }
        if let property = property { view.filters[idx].property = property }
        if let op = op { view.filters[idx].op = op }
        if let value = value { view.filters[idx].value = value }
        Task {
            try? dbService.updateView(view, in: &s, at: dbPath)
            schema = s
        }
    }

    private func removeFilter(_ filterId: String) {
        guard var s = schema, var view = activeView else { return }
        view.filters.removeAll { $0.id == filterId }
        Task {
            try? dbService.updateView(view, in: &s, at: dbPath)
            schema = s
        }
    }

    private func addSort(propertyId: String, ascending: Bool) {
        guard var s = schema, var view = activeView else { return }
        let sort = SortConfig(property: propertyId, direction: ascending ? "asc" : "desc")
        view.sorts.append(sort)
        Task {
            try? dbService.updateView(view, in: &s, at: dbPath)
            schema = s
        }
    }

    private func removeSort(_ sortId: String) {
        guard var s = schema, var view = activeView else { return }
        view.sorts.removeAll { $0.id == sortId }
        Task {
            try? dbService.updateView(view, in: &s, at: dbPath)
            schema = s
        }
    }

    // MARK: - Helpers

    private func defaultViewConfig() -> ViewConfig {
        ViewConfig(id: "default", name: "Table", type: .table, sorts: [], filters: [])
    }

    private func iconForViewType(_ type: ViewType) -> String {
        switch type {
        case .table: return "tablecells"
        case .kanban: return "rectangle.split.3x1"
        case .list: return "list.bullet"
        case .calendar: return "calendar"
        }
    }

    private func matchesFilter(_ value: PropertyValue, filter: FilterConfig) -> Bool {
        let stringVal = stringFromValue(value)
        switch filter.op {
        case "equals": return stringVal == filter.value
        case "not_equals": return stringVal != filter.value
        case "contains": return stringVal.localizedCaseInsensitiveContains(filter.value)
        case "not_contains": return !stringVal.localizedCaseInsensitiveContains(filter.value)
        case "is_empty": return stringVal.isEmpty
        case "is_not_empty": return !stringVal.isEmpty
        case "greater_than": return stringVal > filter.value
        case "less_than": return stringVal < filter.value
        default: return true
        }
    }

    private func compareValues(_ a: PropertyValue, _ b: PropertyValue) -> ComparisonResult {
        stringFromValue(a).compare(stringFromValue(b))
    }

    private func stringFromValue(_ value: PropertyValue) -> String {
        switch value {
        case .text(let s): return s
        case .number(let n): return String(n)
        case .select(let s): return s
        case .multiSelect(let arr): return arr.joined(separator: ",")
        case .date(let s): return s
        case .checkbox(let b): return b ? "1" : "0"
        case .url(let s): return s
        case .email(let s): return s
        case .relation(let s): return s
        case .relationMany(let arr): return arr.joined(separator: ",")
        case .empty: return ""
        }
    }
}
