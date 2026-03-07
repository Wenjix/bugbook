import SwiftUI
import BugbookCore

extension Notification.Name {
    static let databaseDidChange = Notification.Name("databaseDidChange")
    static let databaseNameDidChange = Notification.Name("databaseNameDidChange")
    static let inlineDatabaseRowPeek = Notification.Name("inlineDatabaseRowPeek")
}

struct DatabaseFullPageView: View {
    let dbPath: String
    var initialRowId: String? = nil
    @StateObject private var dbService = DatabaseService()
    @State private var schema: DatabaseSchema?
    @State private var rows: [DatabaseRow] = []
    @State private var activeViewId: String = ""
    @State private var selectedRowIndex: Int? = nil
    @State private var error: String?
    @State private var editingTitle: String = ""
    @State private var showPropertyManager = false
    @State private var showSettings = false
    @State private var showVerticalLines = true
    @State private var renamingPropertyId: String? = nil
    @State private var renamingPropertyName: String = ""
    @State private var titleSaveTask: Task<Void, Never>? = nil
    @State private var rowSaveTask: Task<Void, Never>? = nil
    @State private var pendingRowSaves: [String: DatabaseRow] = [:]
    @State private var loadTask: Task<Void, Never>? = nil
    @State private var notificationOrigin = UUID().uuidString

    private var activeView: ViewConfig? {
        schema?.views.first(where: { $0.id == activeViewId })
    }

    private var filteredAndSortedRows: [DatabaseRow] {
        guard let view = activeView else { return rows }
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
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary)
                    Text("Failed to load database")
                        .font(.headline)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Retry") { loadData() }
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let schema = schema {
                dbHeader(schema: schema)
                viewTabs(schema: schema)
                Divider()
                HStack(spacing: 0) {
                    viewContent(schema: schema)
                        .frame(maxHeight: .infinity, alignment: .topLeading)
                    if let rowIdx = selectedRowIndex, rowIdx < rows.count {
                        Divider()
                        RowPageView(
                            schema: schema,
                            row: $rows[rowIdx],
                            onSave: { row in saveRow(row) },
                            onBack: { selectedRowIndex = nil },
                            onAddOption: { propId, option in addSelectOption(propId, option: option) },
                            onUpdateOption: { propId, optId, name, color in updateSelectOption(propId, optionId: optId, name: name, color: color) },
                            onDeleteOption: { propId, optId in deleteSelectOption(propId, optionId: optId) }
                        )
                        .frame(width: 480)
                    }
                }
            } else {
                ProgressView("Loading database...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .accessibilityIdentifier("editor")
        .sheet(isPresented: $showPropertyManager) {
            if var s = schema {
                PropertyManagerSheet(schema: Binding(
                    get: { s },
                    set: { s = $0; self.schema = $0 }
                ), rows: $rows, dbPath: dbPath, dbService: dbService, notificationOrigin: notificationOrigin)
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
            loadData()
        }
        .onDisappear {
            titleSaveTask?.cancel()
            titleSaveTask = nil
            rowSaveTask?.cancel()
            rowSaveTask = nil
            loadTask?.cancel()
            loadTask = nil
            flushPendingRowSavesSynchronously()
        }
        .onReceive(NotificationCenter.default.publisher(for: .databaseDidChange)) { notification in
            guard let changedPath = notification.userInfo?["dbPath"] as? String,
                  changedPath == dbPath else { return }
            let origin = notification.userInfo?["origin"] as? String
            guard origin != notificationOrigin else { return }
            loadData()
        }
    }

    private func postChangeNotification() {
        NotificationCenter.default.post(
            name: .databaseDidChange,
            object: nil,
            userInfo: ["dbPath": dbPath, "origin": notificationOrigin]
        )
    }

    // MARK: - Header

    private func dbHeader(schema: DatabaseSchema) -> some View {
        HStack(spacing: 8) {
            TextField("Database Name", text: $editingTitle)
                .onSubmit { persistDatabaseName(editingTitle) }
                .onChange(of: editingTitle) { _, newValue in scheduleDatabaseNameSave(newValue) }
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
                .textFieldStyle(.plain)

            Spacer()

            Button {} label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)

            Button { showSettings.toggle() } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 13))
                    .foregroundColor(showSettings ? .primary : .secondary)
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showSettings, arrowEdge: .bottom) {
                settingsPopover(schema: schema)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    private func scheduleDatabaseNameSave(_ value: String) {
        titleSaveTask?.cancel()
        titleSaveTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 450_000_000)
            guard !Task.isCancelled else { return }
            persistDatabaseName(value)
        }
    }

    private func persistDatabaseName(_ rawValue: String) {
        guard var currentSchema = schema else { return }
        let newName = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newName.isEmpty else {
            editingTitle = currentSchema.name
            return
        }
        guard newName != currentSchema.name else { return }

        currentSchema.name = newName
        schema = currentSchema
        editingTitle = newName

        Task {
            try? dbService.saveSchema(currentSchema, at: dbPath)
            postChangeNotification()
            NotificationCenter.default.post(
                name: .databaseNameDidChange,
                object: nil,
                userInfo: ["dbPath": dbPath, "newName": newName]
            )
        }
    }

    // MARK: - View Tabs

    private func viewTabs(schema: DatabaseSchema) -> some View {
        HStack(spacing: 4) {
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
                    .background(view.id == activeViewId ? Color.primary.opacity(0.1) : Color.clear)
                    .cornerRadius(4)
                }
                .buttonStyle(.plain)
            }

            Menu {
                ForEach(ViewType.allCases, id: \.rawValue) { type in
                    Button { addNewView(type: type) } label: {
                        Label(type.rawValue.capitalized, systemImage: iconForViewType(type))
                    }
                }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }

    // MARK: - Settings Popover

    private func settingsPopover(schema: DatabaseSchema) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Layout
                popoverSectionHeader("Layout")
                HStack(spacing: 6) {
                    ForEach(ViewType.allCases, id: \.rawValue) { type in
                        Button {
                            if let view = schema.views.first(where: { $0.type == type }) {
                                activeViewId = view.id
                                persistActiveView(view.id)
                            } else {
                                addNewView(type: type)
                            }
                        } label: {
                            VStack(spacing: 4) {
                                Image(systemName: iconForViewType(type))
                                    .font(.system(size: 16))
                                Text(type.rawValue.capitalized)
                                    .font(.caption2)
                            }
                            .frame(width: 58, height: 48)
                            .background(activeView?.type == type ? Color.primary.opacity(0.12) : Color.primary.opacity(0.04))
                            .cornerRadius(6)
                            .foregroundColor(activeView?.type == type ? .primary : .secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)

                Divider()

                // Filter
                popoverSectionHeader("Filter")
                if let view = activeView, !view.filters.isEmpty {
                    ForEach(view.filters) { filter in
                        filterRow(filter, schema: schema)
                            .padding(.horizontal, 12)
                            .padding(.bottom, 4)
                    }
                }
                Menu {
                    ForEach(schema.properties.filter { $0.type != .title }) { prop in
                        Button(prop.name) { addFilter(propertyId: prop.id) }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus").font(.caption)
                        Text("Add filter").font(.caption)
                    }
                    .foregroundColor(.secondary)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .padding(.horizontal, 12)
                .padding(.bottom, 12)

                Divider()

                // Sort
                popoverSectionHeader("Sort")
                if let view = activeView, !view.sorts.isEmpty {
                    ForEach(view.sorts) { sort in
                        sortRow(sort, schema: schema)
                            .padding(.horizontal, 12)
                            .padding(.bottom, 4)
                    }
                }
                Menu {
                    ForEach(schema.properties.filter { $0.type != .title }) { prop in
                        Button(prop.name) { addSort(propertyId: prop.id, ascending: true) }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus").font(.caption)
                        Text("Add sort").font(.caption)
                    }
                    .foregroundColor(.secondary)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .padding(.horizontal, 12)
                .padding(.bottom, 12)

                Divider()

                // Properties visibility
                popoverSectionHeader("Properties")
                ForEach(schema.properties.filter { $0.type != .title }) { prop in
                    let isHidden = (activeView?.hiddenColumns ?? []).contains(prop.id)
                    Button { toggleColumnVisibility(prop.id) } label: {
                        HStack {
                            Text(prop.name).font(.callout)
                            Spacer()
                            Image(systemName: isHidden ? "eye.slash" : "eye")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .foregroundColor(.primary)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 3)
                }

                if activeView?.type == .table {
                    Divider().padding(.top, 4)
                    Button { showVerticalLines.toggle() } label: {
                        HStack {
                            Text("Grid lines").font(.callout)
                            Spacer()
                            if showVerticalLines {
                                Image(systemName: "checkmark").font(.caption).foregroundColor(.secondary)
                            }
                        }
                        .foregroundColor(.primary)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 3)
                }

                Spacer(minLength: 12)
            }
        }
        .frame(width: 280)
        .frame(maxHeight: 420)
    }

    private func popoverSectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundColor(.secondary)
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 6)
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
                        } else {
                            rows.append(updated)
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
                onNewRow: { createNewRow() },
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
                onSave: { row in saveRow(row) },
                onNewRow: { createNewRow() }
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

    private func loadData() {
        loadTask?.cancel()
        error = nil

        let path = dbPath
        loadTask = Task {
            let result = await Task.detached(priority: .userInitiated) { () -> Result<(DatabaseSchema, [DatabaseRow]), Error> in
                do {
                    return .success(try DatabaseService().loadDatabase(at: path))
                } catch {
                    return .failure(error)
                }
            }.value

            guard !Task.isCancelled else { return }

            switch result {
            case .success(let (loadedSchema, loadedRows)):
                schema = loadedSchema
                rows = loadedRows
                if activeViewId.isEmpty || !loadedSchema.views.contains(where: { $0.id == activeViewId }) {
                    activeViewId = loadedSchema.defaultView
                }
                editingTitle = loadedSchema.name
                if let targetId = initialRowId, selectedRowIndex == nil,
                   let idx = loadedRows.firstIndex(where: { $0.id == targetId }) {
                    selectedRowIndex = idx
                }
            case .failure(let error):
                self.error = error.localizedDescription
            }
        }
    }

    private func saveRow(_ row: DatabaseRow) {
        guard schema != nil else { return }
        if let idx = rows.firstIndex(where: { $0.id == row.id }) {
            rows[idx] = row
        }
        pendingRowSaves[row.id] = row
        schedulePendingRowSave()
    }

    private func schedulePendingRowSave() {
        rowSaveTask?.cancel()
        rowSaveTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            flushPendingRowSaves()
        }
    }

    private func flushPendingRowSaves() {
        guard let currentSchema = schema, !pendingRowSaves.isEmpty else { return }
        let rowsToPersist = Array(pendingRowSaves.values)
        pendingRowSaves.removeAll()

        Task {
            for row in rowsToPersist {
                try? dbService.saveRow(row, schema: currentSchema, at: dbPath)
            }
            postChangeNotification()
        }
    }

    private func flushPendingRowSavesSynchronously() {
        guard let currentSchema = schema, !pendingRowSaves.isEmpty else { return }
        let rowsToPersist = Array(pendingRowSaves.values)
        pendingRowSaves.removeAll()

        for row in rowsToPersist {
            try? dbService.saveRow(row, schema: currentSchema, at: dbPath)
        }
        postChangeNotification()
    }

    private func deleteRow(_ row: DatabaseRow) {
        guard let schema = schema else { return }
        pendingRowSaves.removeValue(forKey: row.id)
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

        // Auto-create a Status property for Kanban if no select property exists
        if type == .kanban && s.properties.first(where: { $0.type == .select }) == nil {
            let statusProp = PropertyDefinition(
                id: "prop_status_\(UUID().uuidString.prefix(6).lowercased())",
                name: "Status",
                type: .select,
                config: PropertyConfig(options: [
                    SelectOption(id: "opt_not_started", name: "Not started", color: "gray"),
                    SelectOption(id: "opt_in_progress", name: "In progress", color: "blue"),
                    SelectOption(id: "opt_done", name: "Done", color: "green")
                ])
            )
            Task {
                try? dbService.addProperty(statusProp, to: &s, at: dbPath)
                let view = ViewConfig(
                    id: "view_\(UUID().uuidString)",
                    name: type.rawValue.capitalized,
                    type: type,
                    sorts: [],
                    filters: [],
                    groupBy: statusProp.id
                )
                try? dbService.addView(view, to: &s, at: dbPath)
                schema = s
                activeViewId = view.id
            }
            return
        }

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
    let notificationOrigin: String
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
                NotificationCenter.default.post(
                    name: .databaseDidChange,
                    object: nil,
                    userInfo: ["dbPath": dbPath, "origin": notificationOrigin]
                )
            }
        }
    }

    private func changeType(_ propertyId: String, to newType: PropertyType) {
        var s = schema
        var r = rows
        try? dbService.changePropertyType(propertyId, to: newType, in: &s, rows: &r, at: dbPath)
        schema = s
        rows = r
        NotificationCenter.default.post(
            name: .databaseDidChange,
            object: nil,
            userInfo: ["dbPath": dbPath, "origin": notificationOrigin]
        )
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
