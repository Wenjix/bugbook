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
    @State private var showSearch: Bool = false
    @State private var searchText: String = ""
    @State private var hasStartedLoading = false
    @State private var rowSaveTask: Task<Void, Never>? = nil
    @State private var pendingRowSaves: [String: DatabaseRow] = [:]
    @State private var loadTask: Task<Void, Never>? = nil
    @State private var notificationOrigin = UUID().uuidString
    @State private var isHoveringHeader = false
    @State private var isDeleted = false
    @State private var editingTitle: String = ""
    @State private var titleSaveTask: Task<Void, Never>? = nil
    @State private var isEditingTitle: Bool = false
    @FocusState private var isTitleFocused: Bool
    @FocusState private var isSearchFocused: Bool
    @State private var newRowScrollId: String? = nil

    private var activeView: ViewConfig? {
        schema?.views.first(where: { $0.id == activeViewId })
    }

    private var filteredAndSortedRows: [DatabaseRow] {
        guard let view = activeView, let schema = schema else { return rows }
        var result = rows

        if !searchText.isEmpty {
            let titlePropId = schema.properties.first(where: { $0.type == .title })?.id ?? ""
            result = result.filter { row in
                let val = row.properties[titlePropId] ?? .empty
                return stringFromValue(val).localizedCaseInsensitiveContains(searchText)
            }
        }

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
            if isDeleted {
                HStack(spacing: 6) {
                    Image(systemName: "trash")
                        .font(.callout)
                        .foregroundColor(.secondary)
                    Text("Database deleted")
                        .font(.callout)
                        .foregroundColor(.secondary)
                }
                .padding(12)
            } else if let error = error {
                Text(error)
                    .font(.callout)
                    .foregroundColor(.red)
                    .padding(8)
            } else if let schema = schema {
                HStack(alignment: .top, spacing: 0) {
                    VStack(alignment: .leading, spacing: 0) {
                        headerBar(schema: schema)
                        if schema.views.count > 1 {
                            viewTabsStrip(schema: schema)
                        }
                        viewContent(schema: schema)
                            .frame(maxHeight: 480)
                        newRowButton(schema: schema)
                    }

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
        .task {
            guard !hasStartedLoading else { return }
            hasStartedLoading = true
            loadData()
        }
        .onDisappear {
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
        .onReceive(NotificationCenter.default.publisher(for: .fileDeleted)) { notification in
            guard let deletedPath = notification.object as? String else { return }
            if deletedPath == dbPath || dbPath.hasPrefix(deletedPath + "/") {
                isDeleted = true
            }
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

    private func headerBar(schema: DatabaseSchema) -> some View {
        HStack(spacing: 8) {
            // Title
            if isEditingTitle {
                TextField("Untitled Database", text: $editingTitle)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                    .textFieldStyle(.plain)
                    .focused($isTitleFocused)
                    .onAppear { isTitleFocused = true }
                    .onSubmit {
                        persistTitle()
                        isEditingTitle = false
                    }
                    .onChange(of: editingTitle) { _, _ in scheduleTitleSave() }
                    .onChange(of: isTitleFocused) { _, focused in
                        if !focused { isEditingTitle = false }
                    }
            } else {
                Text(editingTitle.isEmpty ? "Untitled Database" : editingTitle)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                    .onTapGesture { isEditingTitle = true }
            }

            // Add view — always visible next to title
            Menu {
                ForEach([ViewType.table, .list, .kanban, .calendar], id: \.rawValue) { type in
                    Button { addView(type: type) } label: {
                        Label(type.rawValue.capitalized, systemImage: iconForViewType(type))
                    }
                }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()

            Spacer()

            // Hover-only: open full page
            if isHoveringHeader {
                Button { onOpenDatabase?() } label: {
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }

            // Search — icon collapses to inline field when active
            if showSearch {
                HStack(spacing: 4) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    TextField("Type to search...", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.callout)
                        .frame(width: 160)
                        .focused($isSearchFocused)
                        .onAppear { isSearchFocused = true }
                        .onExitCommand {
                            showSearch = false
                            searchText = ""
                        }
                    Button {
                        showSearch = false
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            } else {
                Button { showSearch = true } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            // Settings
            settingsMenu(schema: schema)
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 4)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) {
                isHoveringHeader = hovering
            }
        }
    }

    // MARK: - View Tabs Strip

    private func viewTabsStrip(schema: DatabaseSchema) -> some View {
        HStack(spacing: 4) {
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
                    .background(view.id == activeViewId ? Color.primary.opacity(0.1) : Color.clear)
                    .cornerRadius(4)
                    .foregroundColor(view.id == activeViewId ? .primary : .secondary)
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button(role: .destructive) {
                        deleteView(view, schema: schema)
                    } label: {
                        Label("Delete View", systemImage: "trash")
                    }
                }
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }

    private func deleteView(_ view: ViewConfig, schema: DatabaseSchema) {
        guard schema.views.count > 1 else { return } // never delete the last view
        var s = schema
        s.views.removeAll { $0.id == view.id }
        if activeViewId == view.id {
            activeViewId = s.views.first?.id ?? ""
        }
        Task {
            try? dbService.saveSchema(s, at: dbPath)
            self.schema = s
            postChangeNotification()
        }
    }

    // MARK: - Settings Menu

    private func settingsMenu(schema: DatabaseSchema) -> some View {
        Menu {
            // Layout
            Section("Layout") {
                ForEach([ViewType.table, .list, .kanban, .calendar], id: \.rawValue) { type in
                    Button {
                        if let view = schema.views.first(where: { $0.type == type }) {
                            activeViewId = view.id
                        } else {
                            addView(type: type)
                        }
                    } label: {
                        Label(
                            type.rawValue.capitalized,
                            systemImage: activeView?.type == type ? "checkmark" : iconForViewType(type)
                        )
                    }
                }
            }

            // Properties visibility
            Section("Properties") {
                ForEach(schema.properties.filter { $0.type != .title }) { prop in
                    let isHidden = (activeView?.hiddenColumns ?? []).contains(prop.id)
                    Button { toggleColumnVisibility(prop.id) } label: {
                        Label(prop.name, systemImage: isHidden ? "eye.slash" : "eye")
                    }
                }
            }

            // Filter
            Section("Filter") {
                if let view = activeView, !view.filters.isEmpty {
                    ForEach(view.filters) { filter in
                        let propName = schema.properties.first(where: { $0.id == filter.property })?.name ?? "Filter"
                        Button("Remove: \(propName)") { removeFilter(filter.id) }
                    }
                }
                Menu("Add filter") {
                    ForEach(schema.properties.filter { $0.type != .title }) { prop in
                        Button(prop.name) { addFilter(propertyId: prop.id) }
                    }
                }
            }

            // Sort
            Section("Sort") {
                if let view = activeView, !view.sorts.isEmpty {
                    ForEach(view.sorts) { sort in
                        let propName = schema.properties.first(where: { $0.id == sort.property })?.name ?? "Sort"
                        Button("Remove: \(propName)") { removeSort(sort.id) }
                    }
                }
                Menu("Add sort") {
                    ForEach(schema.properties.filter { $0.type != .title }) { prop in
                        Button(prop.name) { addSort(propertyId: prop.id, ascending: true) }
                    }
                }
            }
        } label: {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 13))
                .foregroundColor(.secondary)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
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
                onRenameProperty: { propId, newName in renameProperty(propId, to: newName) },
                onDeleteProperty: { propId in deleteProperty(propId) },
                onChangePropertyType: { propId, newType in changePropertyType(propId, to: newType) },
                onAddSelectOption: { propId, option in addSelectOption(propId, option: option) },
                onUpdateSelectOption: { propId, optId, name, color in updateSelectOption(propId, optionId: optId, name: name, color: color) },
                onDeleteSelectOption: { propId, optId in deleteSelectOption(propId, optionId: optId) },
                onResizeColumn: { propId, width in resizeColumn(propId, to: width) },
                onNewRow: { addNewRow() },
                scrollToRowId: newRowScrollId
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
            addNewRow()
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
                if editingTitle.isEmpty || editingTitle != loadedSchema.name {
                    editingTitle = loadedSchema.name
                }
                if activeViewId.isEmpty || !loadedSchema.views.contains(where: { $0.id == activeViewId }) {
                    activeViewId = loadedSchema.defaultView
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

    private func addNewRow() {
        guard let s = schema else { return }
        do {
            let newRow = try dbService.createRow(in: dbPath, schema: s)
            rows.append(newRow)
            newRowScrollId = newRow.id
            postChangeNotification()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func createRowWithDate(_ dateStr: String, schema: DatabaseSchema) {
        guard let dateProp = schema.properties.first(where: { $0.type == .date }) else {
            addNewRow()
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

    private func renameProperty(_ propertyId: String, to newName: String) {
        guard var s = schema else { return }
        Task {
            try? dbService.renameProperty(propertyId, to: newName, in: &s, rows: &rows, at: dbPath)
            schema = s
            postChangeNotification()
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

    private func addView(type: ViewType) {
        guard var s = schema else { return }
        let view = ViewConfig(
            id: "view_\(UUID().uuidString)",
            name: type.rawValue.capitalized,
            type: type,
            sorts: [],
            filters: []
        )
        Task {
            try? dbService.addView(view, to: &s, at: dbPath)
            self.schema = s
            activeViewId = view.id
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

    // MARK: - Title Rename

    private func scheduleTitleSave() {
        titleSaveTask?.cancel()
        titleSaveTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 450_000_000)
            guard !Task.isCancelled else { return }
            persistTitle()
        }
    }

    private func persistTitle() {
        guard var s = schema else { return }
        let newName = editingTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newName.isEmpty, newName != s.name else { return }
        s.name = newName
        schema = s
        Task {
            try? dbService.saveSchema(s, at: dbPath)
            postChangeNotification()
            NotificationCenter.default.post(
                name: .databaseNameDidChange,
                object: nil,
                userInfo: ["dbPath": dbPath, "newName": newName]
            )
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
