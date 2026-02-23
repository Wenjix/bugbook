import SwiftUI

struct DatabaseFullPageView: View {
    let dbPath: String
    @StateObject private var dbService = DatabaseService()
    @State private var schema: DatabaseSchema?
    @State private var rows: [DatabaseRow] = []
    @State private var activeViewId: String = ""
    @State private var selectedRowIndex: Int? = nil
    @State private var error: String?
    @State private var editingTitle: String = ""
    @State private var showPropertyManager = false
    @State private var showFilterSort = false
    @State private var renamingPropertyId: String? = nil
    @State private var renamingPropertyName: String = ""

    private var activeView: ViewConfig? {
        schema?.views.first(where: { $0.id == activeViewId })
    }

    private var filteredAndSortedRows: [DatabaseRow] {
        guard let view = activeView, let schema = schema else { return rows }
        var result = rows

        for filter in view.filters {
            guard let prop = schema.properties.first(where: { $0.id == filter.propertyId }) else { continue }
            result = result.filter { row in
                let val = row.properties[prop.name] ?? .empty
                return matchesFilter(val, filter: filter)
            }
        }

        for sort in view.sorts.reversed() {
            guard let prop = schema.properties.first(where: { $0.id == sort.propertyId }) else { continue }
            result.sort { a, b in
                let va = a.properties[prop.name] ?? .empty
                let vb = b.properties[prop.name] ?? .empty
                let cmp = compareValues(va, vb)
                return sort.ascending ? cmp == .orderedAscending : cmp == .orderedDescending
            }
        }

        return result
    }

    var body: some View {
        VStack(spacing: 0) {
            if let error = error {
                Text(error)
                    .foregroundColor(.red)
                    .padding()
            } else if let schema = schema {
                if let rowIdx = selectedRowIndex, rowIdx < rows.count {
                    RowPageView(
                        schema: schema,
                        row: $rows[rowIdx],
                        onSave: { row in saveRow(row) },
                        onBack: { selectedRowIndex = nil }
                    )
                } else {
                    titleBar
                    toolbar(schema: schema)
                    if showFilterSort {
                        filterSortBar(schema: schema)
                    }
                    Divider()
                    viewContent(schema: schema)
                }
            } else {
                ProgressView("Loading database...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .sheet(isPresented: $showPropertyManager) {
            if var s = schema {
                PropertyManagerSheet(schema: Binding(
                    get: { s },
                    set: { s = $0; self.schema = $0 }
                ), dbPath: dbPath, dbService: dbService)
            }
        }
        .sheet(item: $renamingPropertyId) { propId in
            if let s = schema, let prop = s.properties.first(where: { $0.id == propId }) {
                RenamePropertySheet(
                    propertyName: prop.name,
                    onRename: { newName in
                        renameProperty(propId, to: newName)
                        renamingPropertyId = nil
                    },
                    onCancel: { renamingPropertyId = nil }
                )
            }
        }
        .task {
            await loadData()
        }
    }

    // MARK: - Title Bar

    private var titleBar: some View {
        HStack {
            TextField("Database Name", text: $editingTitle, onCommit: {
                schema?.name = editingTitle
                if let s = schema {
                    Task { try? dbService.saveSchema(s, at: dbPath) }
                }
            })
            .font(.title2)
            .fontWeight(.bold)
            .textFieldStyle(.plain)
            Spacer()

            Text("\(rows.count) rows")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
    }

    // MARK: - Toolbar

    private func toolbar(schema: DatabaseSchema) -> some View {
        HStack(spacing: 8) {
            // View tabs
            ForEach(schema.views) { view in
                Button {
                    activeViewId = view.id
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: iconForViewType(view.type))
                        Text(view.name)
                    }
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(view.id == activeViewId ? Color.accentColor.opacity(0.15) : Color.clear)
                    .cornerRadius(4)
                }
                .buttonStyle(.plain)
            }

            // Add view
            Menu {
                ForEach(ViewType.allCases, id: \.rawValue) { type in
                    Button(type.rawValue.capitalized) { addNewView(type: type) }
                }
            } label: {
                Image(systemName: "plus")
                    .font(.caption)
            }
            .menuStyle(.borderlessButton)
            .frame(width: 20)

            Spacer()

            // Filter/sort toggle
            Button {
                showFilterSort.toggle()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "line.3.horizontal.decrease")
                    Text("Filter")
                }
                .font(.caption)
            }
            .buttonStyle(.plain)

            // Properties
            Button {
                showPropertyManager = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "slider.horizontal.3")
                    Text("Properties")
                }
                .font(.caption)
            }
            .buttonStyle(.plain)

            // New row
            Button {
                createNewRow()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "plus")
                    Text("New")
                }
                .font(.caption)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    // MARK: - Filter/Sort Bar

    private func filterSortBar(schema: DatabaseSchema) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // Active filters
            if let view = activeView {
                ForEach(view.filters) { filter in
                    HStack(spacing: 6) {
                        let propName = schema.properties.first(where: { $0.id == filter.propertyId })?.name ?? "?"
                        Text(propName)
                            .font(.caption)
                        Text(filter.operator.rawValue)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(filter.value)
                            .font(.caption)
                        Button {
                            removeFilter(filter.id)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.caption2)
                        }
                        .buttonStyle(.plain)
                    }
                }

                // Active sorts
                ForEach(view.sorts) { sort in
                    HStack(spacing: 6) {
                        let propName = schema.properties.first(where: { $0.id == sort.propertyId })?.name ?? "?"
                        Text("Sort: \(propName)")
                            .font(.caption)
                        Image(systemName: sort.ascending ? "arrow.up" : "arrow.down")
                            .font(.caption2)
                        Button {
                            removeSort(sort.id)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.caption2)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            // Add buttons
            HStack(spacing: 12) {
                Menu("+ Filter") {
                    ForEach(schema.properties) { prop in
                        Button(prop.name) { addFilter(propertyId: prop.id) }
                    }
                }
                .font(.caption)

                Menu("+ Sort") {
                    ForEach(schema.properties) { prop in
                        Button("\(prop.name) Asc") { addSort(propertyId: prop.id, ascending: true) }
                        Button("\(prop.name) Desc") { addSort(propertyId: prop.id, ascending: false) }
                    }
                }
                .font(.caption)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(Color.gray.opacity(0.05))
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
                onAddProperty: { addPropertyFromTable() },
                onRenameProperty: { propId, _ in
                    renamingPropertyId = propId
                },
                onDeleteProperty: { propId in deleteProperty(propId) },
                onChangePropertyType: { propId, newType in changePropertyType(propId, to: newType) }
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
                onCreateRow: { dateStr in createRowWithDate(dateStr) }
            )
        }
    }

    // MARK: - Data Operations

    private func loadData() async {
        do {
            let (loadedSchema, loadedRows) = try await dbService.loadDatabase(at: dbPath)
            schema = loadedSchema
            rows = loadedRows
            activeViewId = loadedSchema.defaultViewId
            editingTitle = loadedSchema.name
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
        }
    }

    private func deleteRow(_ row: DatabaseRow) {
        rows.removeAll { $0.id == row.id }
        Task {
            try? dbService.deleteRow(row.id, in: dbPath)
            try? dbService.updateIndex(rows: rows, at: dbPath)
        }
    }

    private func createNewRow() {
        guard let schema = schema else { return }
        Task {
            do {
                let newRow = try dbService.createRow(in: dbPath, schema: schema)
                rows.append(newRow)
                openRow(newRow)
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    private func createRowWithDate(_ dateStr: String) {
        guard let schema = schema, let dateProp = schema.properties.first(where: { $0.type == .date }) else {
            createNewRow()
            return
        }
        Task {
            do {
                var newRow = try dbService.createRow(in: dbPath, schema: schema)
                newRow.properties[dateProp.name] = .date(dateStr)
                try dbService.saveRow(newRow, schema: schema, at: dbPath)
                if let idx = rows.firstIndex(where: { $0.id == newRow.id }) {
                    rows[idx] = newRow
                } else {
                    rows.append(newRow)
                }
                openRow(newRow)
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    private func openRow(_ row: DatabaseRow) {
        if let idx = rows.firstIndex(where: { $0.id == row.id }) {
            selectedRowIndex = idx
        }
    }

    // MARK: - Property Operations

    private func addPropertyFromTable() {
        guard var s = schema else { return }
        let prop = PropertyDefinition(
            id: "prop_\(UUID().uuidString)",
            name: "New Property",
            type: .text,
            options: nil
        )
        Task {
            try? dbService.addProperty(prop, to: &s, at: dbPath)
            schema = s
        }
    }

    private func renameProperty(_ propertyId: String, to newName: String) {
        guard var s = schema else { return }
        Task {
            try? dbService.renameProperty(propertyId, to: newName, in: &s, rows: &rows, at: dbPath)
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

    private func addSelectOption(_ propertyId: String, option: SelectOption) {
        guard var s = schema else { return }
        Task {
            try? dbService.addSelectOption(option, toProperty: propertyId, in: &s, at: dbPath)
            schema = s
        }
    }

    private func updateGroupBy(_ propertyId: String) {
        guard var s = schema, var view = activeView else { return }
        view.groupByPropertyId = propertyId
        Task {
            try? dbService.updateView(view, in: &s, at: dbPath)
            schema = s
        }
    }

    // MARK: - View Management

    private func addNewView(type: ViewType) {
        guard var s = schema else { return }
        let view = ViewConfig(
            id: "view_\(UUID().uuidString)",
            name: type.rawValue.capitalized,
            type: type,
            sorts: [],
            filters: [],
            groupByPropertyId: type == .kanban ? s.properties.first(where: { $0.type == .select })?.id : nil,
            datePropertyId: type == .calendar ? s.properties.first(where: { $0.type == .date })?.id : nil
        )
        Task {
            try? dbService.addView(view, to: &s, at: dbPath)
            schema = s
            activeViewId = view.id
        }
    }

    // MARK: - Filter/Sort Management

    private func addFilter(propertyId: String) {
        guard var s = schema, var view = activeView else { return }
        let filter = FilterConfig(
            id: UUID().uuidString,
            propertyId: propertyId,
            operator: .isNotEmpty,
            value: ""
        )
        view.filters.append(filter)
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
        let sort = SortConfig(id: UUID().uuidString, propertyId: propertyId, ascending: ascending)
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

    // MARK: - Helpers

    private func iconForViewType(_ type: ViewType) -> String {
        switch type {
        case .table: return "tablecells"
        case .kanban: return "rectangle.split.3x1"
        case .list: return "list.bullet"
        case .calendar: return "calendar"
        }
    }

    private func defaultViewConfig() -> ViewConfig {
        ViewConfig(id: "default", name: "Table", type: .table, sorts: [], filters: [])
    }

    private func matchesFilter(_ value: PropertyValue, filter: FilterConfig) -> Bool {
        let stringVal = stringFromValue(value)
        switch filter.operator {
        case .equals: return stringVal == filter.value
        case .notEquals: return stringVal != filter.value
        case .contains: return stringVal.localizedCaseInsensitiveContains(filter.value)
        case .doesNotContain: return !stringVal.localizedCaseInsensitiveContains(filter.value)
        case .isEmpty: return stringVal.isEmpty
        case .isNotEmpty: return !stringVal.isEmpty
        case .greaterThan: return stringVal > filter.value
        case .lessThan: return stringVal < filter.value
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
        case .empty: return ""
        }
    }
}

// MARK: - Property Manager Sheet

private struct PropertyManagerSheet: View {
    @Binding var schema: DatabaseSchema
    let dbPath: String
    let dbService: DatabaseService
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Properties")
                    .font(.headline)
                Spacer()
                Button("Done") { dismiss() }
            }

            List {
                ForEach(schema.properties) { prop in
                    HStack {
                        Text(prop.name)
                        Spacer()
                        Text(prop.type.rawValue)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Button {
                            deleteProperty(prop.id)
                        } label: {
                            Image(systemName: "trash")
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .onMove { source, destination in
                    schema.properties.move(fromOffsets: source, toOffset: destination)
                    Task {
                        let s = schema
                        try? dbService.saveSchema(s, at: dbPath)
                    }
                }
            }

            Menu("+ Add Property") {
                ForEach(PropertyType.allCases, id: \.rawValue) { type in
                    Button(type.rawValue.capitalized) { addProperty(type: type) }
                }
            }
            .font(.body)
        }
        .padding()
        .frame(minWidth: 350, minHeight: 300)
    }

    private func addProperty(type: PropertyType) {
        let prop = PropertyDefinition(
            id: "prop_\(UUID().uuidString)",
            name: "New \(type.rawValue.capitalized)",
            type: type,
            options: (type == .select || type == .multiSelect) ? [] : nil
        )
        schema.properties.append(prop)
        Task {
            try? dbService.saveSchema(schema, at: dbPath)
        }
    }

    private func deleteProperty(_ propertyId: String) {
        schema.properties.removeAll { $0.id == propertyId }
        Task {
            try? dbService.saveSchema(schema, at: dbPath)
        }
    }
}

// MARK: - Rename Property Sheet

private struct RenamePropertySheet: View {
    @State var propertyName: String
    let onRename: (String) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Text("Rename Property")
                .font(.headline)

            TextField("Property name", text: $propertyName)
                .textFieldStyle(.roundedBorder)

            HStack(spacing: 12) {
                Button("Cancel") { onCancel() }
                Button("Rename") {
                    let trimmed = propertyName.trimmingCharacters(in: .whitespaces)
                    if !trimmed.isEmpty {
                        onRename(trimmed)
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(propertyName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding()
        .frame(minWidth: 280)
    }
}

// Make String identifiable for .sheet(item:)
extension String: @retroactive Identifiable {
    public var id: String { self }
}
