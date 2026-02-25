import SwiftUI
import BugbookCore

extension Notification.Name {
    static let databaseDidChange = Notification.Name("databaseDidChange")
    static let databaseNameDidChange = Notification.Name("databaseNameDidChange")
}

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
    @State private var showVerticalLines = true
    @State private var renamingPropertyId: String? = nil
    @State private var renamingPropertyName: String = ""

    private var activeView: ViewConfig? {
        schema?.views.first(where: { $0.id == activeViewId })
    }

    private var filteredAndSortedRows: [DatabaseRow] {
        guard let view = activeView, let schema = schema else { return rows }
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
                        onBack: { selectedRowIndex = nil },
                        onAddOption: { propId, option in addSelectOption(propId, option: option) },
                        onUpdateOption: { propId, optId, name, color in updateSelectOption(propId, optionId: optId, name: name, color: color) },
                        onDeleteOption: { propId, optId in deleteSelectOption(propId, optionId: optId) }
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
                ), rows: $rows, dbPath: dbPath, dbService: dbService)
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
        .onReceive(NotificationCenter.default.publisher(for: .databaseDidChange)) { notification in
            guard let changedPath = notification.userInfo?["dbPath"] as? String,
                  changedPath == dbPath else { return }
            Task { await loadData() }
        }
    }

    private func postChangeNotification() {
        NotificationCenter.default.post(name: .databaseDidChange, object: nil, userInfo: ["dbPath": dbPath])
    }

    // MARK: - Title Bar

    private var titleBar: some View {
        HStack {
            TextField("Database Name", text: $editingTitle, onCommit: {
                schema?.name = editingTitle
                if let s = schema {
                    Task {
                        try? dbService.saveSchema(s, at: dbPath)
                        postChangeNotification()
                        NotificationCenter.default.post(
                            name: .databaseNameDidChange,
                            object: nil,
                            userInfo: ["dbPath": dbPath, "newName": editingTitle]
                        )
                    }
                }
            })
            .font(.title2)
            .fontWeight(.bold)
            .textFieldStyle(.plain)
            Spacer()
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
                    persistActiveView(view.id)
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
                    Button {
                        addNewView(type: type)
                    } label: {
                        Label(type.rawValue.capitalized, systemImage: iconForViewType(type))
                    }
                }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()

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
                if activeView?.type == .table {
                    Divider()
                    Button {
                        showVerticalLines.toggle()
                    } label: {
                        HStack {
                            Text("Grid lines")
                            if showVerticalLines { Image(systemName: "checkmark") }
                        }
                    }
                }
            } label: {
                Image(systemName: "eye")
                    .font(.caption)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()

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
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    // MARK: - Filter/Sort Bar

    private func filterSortBar(schema: DatabaseSchema) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let view = activeView {
                // Active filters
                ForEach(view.filters) { filter in
                    filterRow(filter, schema: schema)
                }

                // Active sorts
                ForEach(view.sorts) { sort in
                    sortRow(sort, schema: schema)
                }
            }

            // Add buttons
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
        .background(Color.fallbackSurfaceSubtle)
    }

    private func filterRow(_ filter: FilterConfig, schema: DatabaseSchema) -> some View {
        let prop = schema.properties.first(where: { $0.id == filter.property })
        let ops = operatorsForType(prop?.type ?? .text)

        return HStack(spacing: 6) {
            // Property picker
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
                    .background(Color.fallbackSurfaceSubtle)
                    .cornerRadius(4)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            // Operator picker
            Menu {
                ForEach(ops, id: \.0) { (opKey, opLabel) in
                    Button(opLabel) { updateFilter(filter.id, property: nil, op: opKey, value: nil) }
                }
            } label: {
                Text(labelForOp(filter.op))
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.fallbackSurfaceSubtle)
                    .cornerRadius(4)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            // Value input (only for ops that need a value)
            if opNeedsValue(filter.op) {
                filterValueInput(filter, prop: prop)
            }

            Spacer()

            Button { removeFilter(filter.id) } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private func filterValueInput(_ filter: FilterConfig, prop: PropertyDefinition?) -> some View {
        if let prop = prop, (prop.type == .select || prop.type == .multiSelect), let options = prop.options {
            // Select/multiSelect: show option picker
            Menu {
                ForEach(options) { option in
                    Button(option.name) { updateFilter(filter.id, property: nil, op: nil, value: option.id) }
                }
            } label: {
                let displayVal = prop.options?.first(where: { $0.id == filter.value })?.name ?? (filter.value.isEmpty ? "Pick value..." : filter.value)
                Text(displayVal)
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.fallbackSurfaceSubtle)
                    .cornerRadius(4)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        } else if prop?.type == .checkbox {
            Menu {
                Button("Checked") { updateFilter(filter.id, property: nil, op: nil, value: "true") }
                Button("Unchecked") { updateFilter(filter.id, property: nil, op: nil, value: "false") }
            } label: {
                Text(filter.value == "true" ? "Checked" : filter.value == "false" ? "Unchecked" : "Pick...")
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.fallbackSurfaceSubtle)
                    .cornerRadius(4)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        } else {
            // Text/number/date/etc: text field
            let binding = Binding<String>(
                get: { filter.value },
                set: { newVal in updateFilter(filter.id, property: nil, op: nil, value: newVal) }
            )
            TextField("Value", text: binding)
                .textFieldStyle(.roundedBorder)
                .font(.caption)
                .frame(width: 120)
        }
    }

    private func sortRow(_ sort: SortConfig, schema: DatabaseSchema) -> some View {
        let prop = schema.properties.first(where: { $0.id == sort.property })
        return HStack(spacing: 6) {
            Image(systemName: "arrow.up.arrow.down")
                .font(.caption2)
                .foregroundColor(.secondary)

            // Property picker
            Menu {
                ForEach(schema.properties.filter({ $0.type != .title })) { p in
                    Button(p.name) { updateSort(sort.id, property: p.id, ascending: nil) }
                }
            } label: {
                Text(prop?.name ?? "Property")
                    .font(.caption)
                    .fontWeight(.medium)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.fallbackSurfaceSubtle)
                    .cornerRadius(4)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            // Direction toggle
            Button {
                updateSort(sort.id, property: nil, ascending: !sort.ascending)
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: sort.ascending ? "arrow.up" : "arrow.down")
                    Text(sort.ascending ? "Ascending" : "Descending")
                }
                .font(.caption)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.fallbackSurfaceSubtle)
                .cornerRadius(4)
            }
            .buttonStyle(.plain)

            Spacer()

            Button { removeSort(sort.id) } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Filter/Sort Helpers

    private func operatorsForType(_ type: PropertyType) -> [(String, String)] {
        switch type {
        case .text, .title, .url, .email:
            return [("equals", "is"), ("not_equals", "is not"), ("contains", "contains"),
                    ("not_contains", "doesn't contain"), ("is_empty", "is empty"), ("is_not_empty", "is not empty")]
        case .number:
            return [("equals", "="), ("not_equals", "\u{2260}"), ("greater_than", ">"), ("less_than", "<"),
                    ("is_empty", "is empty"), ("is_not_empty", "is not empty")]
        case .select, .multiSelect:
            return [("equals", "is"), ("not_equals", "is not"), ("is_empty", "is empty"), ("is_not_empty", "is not empty")]
        case .date:
            return [("equals", "is"), ("greater_than", "after"), ("less_than", "before"),
                    ("is_empty", "is empty"), ("is_not_empty", "is not empty")]
        case .checkbox:
            return [("equals", "is")]
        case .relation:
            return [("is_empty", "is empty"), ("is_not_empty", "is not empty")]
        }
    }

    private func labelForOp(_ op: String) -> String {
        switch op {
        case "equals": return "is"
        case "not_equals": return "is not"
        case "contains": return "contains"
        case "not_contains": return "doesn't contain"
        case "greater_than": return ">"
        case "less_than": return "<"
        case "is_empty": return "is empty"
        case "is_not_empty": return "is not empty"
        default: return op
        }
    }

    private func opNeedsValue(_ op: String) -> Bool {
        op != "is_empty" && op != "is_not_empty"
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
                onRenameProperty: { propId, newName in
                    renameProperty(propId, to: newName)
                },
                onDeleteProperty: { propId in deleteProperty(propId) },
                onChangePropertyType: { propId, newType in changePropertyType(propId, to: newType) },
                onAddSelectOption: { propId, option in addSelectOption(propId, option: option) },
                onUpdateSelectOption: { propId, optId, name, color in updateSelectOption(propId, optionId: optId, name: name, color: color) },
                onDeleteSelectOption: { propId, optId in deleteSelectOption(propId, optionId: optId) },
                onResizeColumn: { propId, width in resizeColumn(propId, to: width) },
                showVerticalLines: showVerticalLines
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
            if activeViewId.isEmpty {
                activeViewId = loadedSchema.defaultView
            }
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

    private func createNewRow() {
        guard let schema = schema else { return }
        Task {
            do {
                let newRow = try dbService.createRow(in: dbPath, schema: schema)
                rows.append(newRow)
                openRow(newRow)
                postChangeNotification()
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
                newRow.properties[dateProp.id] = .date(dateStr)
                try dbService.saveRow(newRow, schema: schema, at: dbPath)
                if let idx = rows.firstIndex(where: { $0.id == newRow.id }) {
                    rows[idx] = newRow
                } else {
                    rows.append(newRow)
                }
                openRow(newRow)
                postChangeNotification()
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

    private func resizeColumn(_ propertyId: String, to width: CGFloat) {
        guard var s = schema, var view = activeView else { return }
        if view.columnWidths == nil { view.columnWidths = [:] }
        view.columnWidths?[propertyId] = Double(width)
        Task {
            try? dbService.updateView(view, in: &s, at: dbPath)
            schema = s
        }
    }

    private func renameProperty(_ propertyId: String, to newName: String) {
        guard var s = schema else { return }
        guard let idx = s.properties.firstIndex(where: { $0.id == propertyId }) else { return }
        s.properties[idx].name = newName
        schema = s
        Task {
            try? dbService.saveSchema(s, at: dbPath)
            for row in rows {
                try? dbService.saveRow(row, schema: s, at: dbPath)
            }
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

    private func updateGroupBy(_ propertyId: String) {
        guard var s = schema, var view = activeView else { return }
        view.groupBy = propertyId
        Task {
            try? dbService.updateView(view, in: &s, at: dbPath)
            schema = s
        }
    }

    // MARK: - View Management

    private func persistActiveView(_ viewId: String) {
        guard var s = schema, s.defaultView != viewId else { return }
        Task {
            try? dbService.setDefaultView(viewId, in: &s, at: dbPath)
            schema = s
        }
    }

    private func addNewView(type: ViewType) {
        guard var s = schema else { return }
        let view = ViewConfig(
            id: "view_\(UUID().uuidString)",
            name: type.rawValue.capitalized,
            type: type,
            sorts: [],
            filters: [],
            groupBy: type == .kanban ? s.properties.first(where: { $0.type == .select })?.id : nil,
            dateProperty: type == .calendar ? s.properties.first(where: { $0.type == .date })?.id : nil
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
        let prop = s.properties.first(where: { $0.id == propertyId })
        let defaultOp = (prop?.type == .checkbox) ? "equals" : "is_not_empty"
        let defaultValue = (prop?.type == .checkbox) ? "true" : ""
        let filter = FilterConfig(property: propertyId, op: defaultOp, value: defaultValue)
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

    private func updateSort(_ sortId: String, property: String?, ascending: Bool?) {
        guard var s = schema, var view = activeView,
              let idx = view.sorts.firstIndex(where: { $0.id == sortId }) else { return }
        if let property = property { view.sorts[idx].property = property }
        if let ascending = ascending { view.sorts[idx].direction = ascending ? "asc" : "desc" }
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

// MARK: - Property Manager Sheet

private struct PropertyManagerSheet: View {
    @Binding var schema: DatabaseSchema
    @Binding var rows: [DatabaseRow]
    let dbPath: String
    let dbService: DatabaseService
    @Environment(\.dismiss) private var dismiss
    @State private var editingNames: [String: String] = [:]

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
                    let isTitle = prop.type == .title
                    HStack {
                        TextField("Name", text: Binding(
                            get: { editingNames[prop.id] ?? prop.name },
                            set: { editingNames[prop.id] = $0 }
                        ), onCommit: {
                            let newName = (editingNames[prop.id] ?? prop.name).trimmingCharacters(in: .whitespaces)
                            if !newName.isEmpty {
                                renameProperty(prop.id, to: newName)
                            }
                            editingNames.removeValue(forKey: prop.id)
                        })
                        .textFieldStyle(.plain)

                        Spacer()

                        if isTitle {
                            Text(prop.type.rawValue.capitalized)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else {
                            Menu {
                                ForEach(PropertyType.allCases.filter({ $0 != .title }), id: \.rawValue) { type in
                                    Button(type.rawValue.capitalized) {
                                        changeType(prop.id, to: type)
                                    }
                                }
                            } label: {
                                Text(prop.type.rawValue.capitalized)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .menuStyle(.borderlessButton)
                            .fixedSize()
                        }

                        if !isTitle {
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
                ForEach(PropertyType.allCases.filter({ $0 != .title }), id: \.rawValue) { type in
                    Button(type.rawValue.capitalized) { addProperty(type: type) }
                }
            }
            .font(.body)
        }
        .padding()
        .frame(minWidth: 350, minHeight: 300)
    }

    private func addProperty(type: PropertyType) {
        let config: PropertyConfig? = (type == .select || type == .multiSelect) ? PropertyConfig(options: []) : nil
        let prop = PropertyDefinition(
            id: "prop_\(UUID().uuidString)",
            name: "New \(type.rawValue.capitalized)",
            type: type,
            config: config
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

    private func renameProperty(_ propertyId: String, to newName: String) {
        if let idx = schema.properties.firstIndex(where: { $0.id == propertyId }) {
            schema.properties[idx].name = newName
            Task {
                try? dbService.saveSchema(schema, at: dbPath)
                NotificationCenter.default.post(name: .databaseDidChange, object: nil, userInfo: ["dbPath": dbPath])
            }
        }
    }

    private func changeType(_ propertyId: String, to newType: PropertyType) {
        var s = schema
        var r = rows
        try? dbService.changePropertyType(propertyId, to: newType, in: &s, rows: &r, at: dbPath)
        schema = s
        rows = r
        NotificationCenter.default.post(name: .databaseDidChange, object: nil, userInfo: ["dbPath": dbPath])
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
