import SwiftUI
import BugbookCore

extension Notification.Name {
    static let databaseDidChange = Notification.Name("databaseDidChange")
    static let databaseNameDidChange = Notification.Name("databaseNameDidChange")
    static let inlineDatabaseRowPeek = Notification.Name("inlineDatabaseRowPeek")
    static let databaseRowModalRequested = Notification.Name("databaseRowModalRequested")
}

enum DatabaseNotificationKey {
    static let dbPath = "dbPath"
    static let rowId = "rowId"
    static let origin = "origin"
    static let autoFocusTitle = "autoFocusTitle"
    static let newName = "newName"
}

extension Notification {
    var databasePath: String? { userInfo?[DatabaseNotificationKey.dbPath] as? String }
    var databaseRowId: String? { userInfo?[DatabaseNotificationKey.rowId] as? String }
    var databaseOrigin: String? { userInfo?[DatabaseNotificationKey.origin] as? String }
    var databaseAutoFocusTitle: Bool { userInfo?[DatabaseNotificationKey.autoFocusTitle] as? Bool ?? false }
    var databaseNewName: String? { userInfo?[DatabaseNotificationKey.newName] as? String }
}

struct DatabaseFullPageView: View {
    let dbPath: String
    var initialRowId: String? = nil

    @State private var state: DatabaseViewState

    @State private var showPropertyManager = false
    @State private var showSettings = false
    @State private var showVerticalLines = true
    @State private var renamingPropertyId: String? = nil
    @State private var renamingPropertyName: String = ""
    @State private var initialPeekHandled = false

    init(dbPath: String, initialRowId: String? = nil) {
        self.dbPath = dbPath
        self.initialRowId = initialRowId
        _state = State(initialValue: DatabaseViewState(dbPath: dbPath))
    }

    private var filteredAndSortedRows: [DatabaseRow] {
        state.filteredAndSortedRows()
    }

    var body: some View {
        VStack(spacing: 0) {
            if let error = state.error {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 32))
                        .foregroundStyle(.secondary)
                    Text("Failed to load database")
                        .font(.headline)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Retry") { state.loadData() }
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let schema = state.schema {
                dbHeader(schema: schema)
                viewTabs(schema: schema)
                Divider()
                viewContent(schema: schema)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                ProgressView("Loading database...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .accessibilityIdentifier("editor")
        .sheet(isPresented: $showPropertyManager) {
            if state.schema != nil {
                PropertyManagerSheet(
                    schema: Binding(
                        get: { state.schema! },
                        set: { state.schema = $0 }
                    ),
                    rows: Binding(
                        get: { state.rows },
                        set: { state.rows = $0 }
                    ),
                    dbPath: state.dbPath,
                    dbService: state.dbService,
                    notificationOrigin: state.notificationOrigin
                )
            }
        }
        .sheet(item: $renamingPropertyId) { propId in
            if let s = state.schema, let prop = s.properties.first(where: { $0.id == propId }) {
                RenamePropertySheet(
                    propertyName: prop.name,
                    onRename: { newName in
                        state.renameProperty(propId, to: newName)
                        renamingPropertyId = nil
                    },
                    onCancel: { renamingPropertyId = nil }
                )
            }
        }
        .task {
            state.loadData {
                if let targetId = initialRowId,
                   !initialPeekHandled,
                   state.rows.contains(where: { $0.id == targetId }) {
                    initialPeekHandled = true
                    postInlineRowPeek(rowId: targetId)
                }
            }
        }
        .onDisappear {
            state.cancelAll()
        }
        .onReceive(NotificationCenter.default.publisher(for: .databaseDidChange)) { notification in
            guard let changedPath = notification.databasePath,
                  changedPath == dbPath else { return }
            guard notification.databaseOrigin != state.notificationOrigin else { return }
            state.loadData()
        }
    }

    // MARK: - Header

    private func dbHeader(schema: DatabaseSchema) -> some View {
        HStack(spacing: 8) {
            TextField("Database Name", text: $state.editingTitle)
                .onSubmit { state.persistTitle() }
                .onChange(of: state.editingTitle) { _, _ in state.scheduleTitleSave() }
                .font(.system(size: EditorTypography.bodyFontSize, weight: .semibold))
                .foregroundStyle(.primary)
                .textFieldStyle(.plain)
                .databasePointerCursor()

            Spacer()

            Button {} label: {
                Label("Search", systemImage: "magnifyingglass")
                    .labelStyle(.iconOnly)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)

            Button { showSettings.toggle() } label: {
                Label("Filter", systemImage: "slider.horizontal.3")
                    .labelStyle(.iconOnly)
                    .font(.system(size: 13))
                    .foregroundStyle(showSettings ? .primary : .secondary)
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

    // MARK: - View Tabs

    private func viewTabs(schema: DatabaseSchema) -> some View {
        HStack(spacing: 4) {
            ForEach(schema.views) { view in
                Button {
                    state.activeViewId = view.id
                    state.persistActiveView(view.id)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: iconForViewType(view.type))
                        Text(view.name)
                    }
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(view.id == state.activeViewId ? Color.primary.opacity(0.1) : Color.clear)
                    .clipShape(.rect(cornerRadius: 4))
                }
                .buttonStyle(.plain)
            }

            Menu {
                ForEach(ViewType.allCases, id: \.rawValue) { type in
                    Button { state.addView(type: type) } label: {
                        Label(type.rawValue.capitalized, systemImage: iconForViewType(type))
                    }
                }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
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
                                state.activeViewId = view.id
                                state.persistActiveView(view.id)
                            } else {
                                state.addView(type: type)
                            }
                        } label: {
                            VStack(spacing: 4) {
                                Image(systemName: iconForViewType(type))
                                    .font(.system(size: 16))
                                Text(type.rawValue.capitalized)
                                    .font(.caption2)
                            }
                            .frame(width: 58, height: 48)
                            .background(state.activeView?.type == type ? Color.primary.opacity(0.12) : Color.primary.opacity(0.04))
                            .clipShape(.rect(cornerRadius: 6))
                            .foregroundStyle(state.activeView?.type == type ? .primary : .secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)

                Divider()

                // Filter
                popoverSectionHeader("Filter")
                if let view = state.activeView, !view.filters.isEmpty {
                    ForEach(view.filters) { filter in
                        filterRow(filter, schema: schema)
                            .padding(.horizontal, 12)
                            .padding(.bottom, 4)
                    }
                }
                Menu {
                    ForEach(schema.properties.filter { $0.type != .title }) { prop in
                        Button(prop.name) { state.addFilter(propertyId: prop.id) }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus").font(.caption)
                        Text("Add filter").font(.caption)
                    }
                    .foregroundStyle(.secondary)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .padding(.horizontal, 12)
                .padding(.bottom, 12)

                Divider()

                // Sort
                popoverSectionHeader("Sort")
                if let view = state.activeView, !view.sorts.isEmpty {
                    ForEach(view.sorts) { sort in
                        sortRow(sort, schema: schema)
                            .padding(.horizontal, 12)
                            .padding(.bottom, 4)
                    }
                }
                Menu {
                    ForEach(schema.properties.filter { $0.type != .title }) { prop in
                        Button(prop.name) { state.addSort(propertyId: prop.id, ascending: true) }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus").font(.caption)
                        Text("Add sort").font(.caption)
                    }
                    .foregroundStyle(.secondary)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .padding(.horizontal, 12)
                .padding(.bottom, 12)

                Divider()

                // Properties visibility
                popoverSectionHeader("Properties")
                ForEach(schema.properties.filter { $0.type != .title }) { prop in
                    let isHidden = (state.activeView?.hiddenColumns ?? []).contains(prop.id)
                    Button { state.toggleColumnVisibility(prop.id) } label: {
                        HStack {
                            Text(prop.name).font(.callout)
                            Spacer()
                            Image(systemName: isHidden ? "eye.slash" : "eye")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .foregroundStyle(.primary)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 3)
                }

                if state.activeView?.type == .table {
                    Divider().padding(.top, 4)
                    Button { showVerticalLines.toggle() } label: {
                        HStack {
                            Text("Grid lines").font(.callout)
                            Spacer()
                            if showVerticalLines {
                                Image(systemName: "checkmark").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 3)

                    Button { state.toggleWrapCellText() } label: {
                        HStack {
                            Text("Wrap cell text").font(.callout)
                            Spacer()
                            if state.activeView?.wrapCellText == true {
                                Image(systemName: "checkmark").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .foregroundStyle(.primary)
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
            .foregroundStyle(.secondary)
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
                    Button(p.name) { state.updateFilter(filter.id, property: p.id, op: nil, value: nil) }
                }
            } label: {
                Text(prop?.name ?? "Property")
                    .font(.caption)
                    .fontWeight(.medium)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.fallbackSurfaceSubtle)
                    .clipShape(.rect(cornerRadius: 4))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            // Operator picker
            Menu {
                ForEach(ops, id: \.0) { (opKey, opLabel) in
                    Button(opLabel) { state.updateFilter(filter.id, property: nil, op: opKey, value: nil) }
                }
            } label: {
                Text(labelForOp(filter.op))
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.fallbackSurfaceSubtle)
                    .clipShape(.rect(cornerRadius: 4))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            // Value input (only for ops that need a value)
            if opNeedsValue(filter.op) {
                filterValueInput(filter, prop: prop)
            }

            Spacer()

            Button { state.removeFilter(filter.id) } label: {
                Label("Remove Filter", systemImage: "xmark.circle.fill")
                    .labelStyle(.iconOnly)
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
                    Button(option.name) { state.updateFilter(filter.id, property: nil, op: nil, value: option.id) }
                }
            } label: {
                let displayVal = prop.options?.first(where: { $0.id == filter.value })?.name ?? (filter.value.isEmpty ? "Pick value..." : filter.value)
                Text(displayVal)
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.fallbackSurfaceSubtle)
                    .clipShape(.rect(cornerRadius: 4))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        } else if prop?.type == .checkbox {
            Menu {
                Button("Checked") { state.updateFilter(filter.id, property: nil, op: nil, value: "true") }
                Button("Unchecked") { state.updateFilter(filter.id, property: nil, op: nil, value: "false") }
            } label: {
                Text(filter.value == "true" ? "Checked" : filter.value == "false" ? "Unchecked" : "Pick...")
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.fallbackSurfaceSubtle)
                    .clipShape(.rect(cornerRadius: 4))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        } else {
            // Text/number/date/etc: text field
            let binding = Binding<String>(
                get: { filter.value },
                set: { newVal in state.updateFilter(filter.id, property: nil, op: nil, value: newVal) }
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
                .foregroundStyle(.secondary)

            // Property picker
            Menu {
                ForEach(schema.properties.filter({ $0.type != .title })) { p in
                    Button(p.name) { state.updateSort(sort.id, property: p.id, ascending: nil) }
                }
            } label: {
                Text(prop?.name ?? "Property")
                    .font(.caption)
                    .fontWeight(.medium)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.fallbackSurfaceSubtle)
                    .clipShape(.rect(cornerRadius: 4))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            // Direction toggle
            Button {
                state.updateSort(sort.id, property: nil, ascending: !sort.ascending)
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: sort.ascending ? "arrow.up" : "arrow.down")
                    Text(sort.ascending ? "Ascending" : "Descending")
                }
                .font(.caption)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.fallbackSurfaceSubtle)
                .clipShape(.rect(cornerRadius: 4))
            }
            .buttonStyle(.plain)

            Spacer()

            Button { state.removeSort(sort.id) } label: {
                Label("Remove Sort", systemImage: "xmark.circle.fill")
                    .labelStyle(.iconOnly)
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
                        if let idx = state.rows.firstIndex(where: { $0.id == updated.id }) {
                            state.rows[idx] = updated
                        } else {
                            state.rows.append(updated)
                        }
                    }
                }
            )
        }

        switch state.activeView?.type ?? .table {
        case .table:
            ScrollView {
                TableView(
                    schema: schema,
                    rows: boundRows,
                    viewConfig: state.activeView ?? state.defaultViewConfig(),
                    onOpenRow: { row in openRow(row) },
                    onSave: { row in state.saveRow(row) },
                    onDelete: { row in state.deleteRow(row) },
                    onToggleColumn: { propId in state.toggleColumnVisibility(propId) },
                    onAddProperty: { type in state.addPropertyFromTable(type: type) },
                    onRenameProperty: { propId, newName in
                        state.renameProperty(propId, to: newName)
                    },
                    onDeleteProperty: { propId in state.deleteProperty(propId) },
                    onChangePropertyType: { propId, newType in state.changePropertyType(propId, to: newType) },
                    onAddSelectOption: { propId, option in state.addSelectOption(propId, option: option) },
                    onUpdateSelectOption: { propId, optId, name, color in state.updateSelectOption(propId, optionId: optId, name: name, color: color) },
                    onDeleteSelectOption: { propId, optId in state.deleteSelectOption(propId, optionId: optId) },
                    onResizeColumn: { propId, width in state.resizeColumn(propId, to: width) },
                    onReorderRows: { draggedId, targetId in
                        state.reorderRows(draggedId: draggedId, before: targetId, visibleRowIds: filteredAndSortedRows.map(\.id))
                    },
                    onNewRow: { createNewRow() },
                    showVerticalLines: showVerticalLines,
                    usesInnerScroll: false
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, -TableView.rowControlsInset)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        case .kanban:
            KanbanView(
                schema: schema,
                rows: boundRows,
                viewConfig: state.activeView ?? state.defaultViewConfig(),
                onOpenRow: { row in openRow(row) },
                onSave: { row in state.saveRow(row) },
                onUpdateGroupBy: { propId in state.updateGroupBy(propId) },
                onAddSelectOption: { propId, option in state.addSelectOption(propId, option: option) }
            )
        case .list:
            ListView(
                schema: schema,
                rows: boundRows,
                viewConfig: state.activeView ?? state.defaultViewConfig(),
                onOpenRow: { row in openRow(row) },
                onSave: { row in state.saveRow(row) },
                onNewRow: { createNewRow() }
            )
        case .calendar:
            CalendarView(
                schema: schema,
                rows: boundRows,
                viewConfig: state.activeView ?? state.defaultViewConfig(),
                onOpenRow: { row in state.requestRowModal(rowId: row.id) },
                onSave: { row in state.saveRow(row) },
                onCreateRow: { dateStr, propertyId in
                    do {
                        let newRow = try state.createRowWithDate(dateStr, propertyId: propertyId)
                        state.requestRowModal(rowId: newRow.id, autoFocusTitle: true)
                    } catch {
                        state.error = error.localizedDescription
                    }
                }
            )
        }
    }

    // MARK: - View-Specific Operations

    private func createNewRow() {
        Task {
            do {
                let newRow = try state.createRow()
                openRow(newRow)
            } catch {
                state.error = error.localizedDescription
            }
        }
    }

    private func openRow(_ row: DatabaseRow) {
        postInlineRowPeek(rowId: row.id)
    }

    private func postInlineRowPeek(rowId: String) {
        NotificationCenter.default.post(
            name: .inlineDatabaseRowPeek,
            object: nil,
            userInfo: [
                DatabaseNotificationKey.dbPath: dbPath,
                DatabaseNotificationKey.rowId: rowId
            ]
        )
    }

    // MARK: - Helpers

    private func iconForViewType(_ type: ViewType) -> String {
        type.systemImageName
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
                                .foregroundStyle(.secondary)
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
                                    .foregroundStyle(.secondary)
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
                                    .foregroundStyle(.red)
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
                    userInfo: [DatabaseNotificationKey.dbPath: dbPath, DatabaseNotificationKey.origin: notificationOrigin]
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
            userInfo: [DatabaseNotificationKey.dbPath: dbPath, DatabaseNotificationKey.origin: notificationOrigin]
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
