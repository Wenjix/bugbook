import SwiftUI
import BugbookCore

/// Compact database embed for rendering inside a markdown page.
/// Reuses the same TableView/KanbanView/CalendarView/ListView as the full-page view.
struct DatabaseInlineEmbedView: View {
    let dbPath: String
    var onOpenRow: ((DatabaseRow) -> Void)?
    var onOpenDatabase: (() -> Void)?

    @State private var state: DatabaseViewState

    @State private var showSearch: Bool = false
    @State private var searchText: String = ""
    @State private var hasStartedLoading = false
    @State private var isHoveringHeader = false
    @State private var isDeleted = false
    @State private var isEditingTitle: Bool = false
    @FocusState private var isTitleFocused: Bool
    @FocusState private var isSearchFocused: Bool
    @State private var newRowScrollId: String? = nil

    init(dbPath: String, onOpenRow: ((DatabaseRow) -> Void)? = nil, onOpenDatabase: (() -> Void)? = nil) {
        self.dbPath = dbPath
        self.onOpenRow = onOpenRow
        self.onOpenDatabase = onOpenDatabase
        _state = State(initialValue: DatabaseViewState(dbPath: dbPath))
    }

    private var filteredAndSortedRows: [DatabaseRow] {
        state.filteredAndSortedRows(extraFilter: searchFilter)
    }

    private var searchFilter: ((DatabaseRow) -> Bool)? {
        guard !searchText.isEmpty, let schema = state.schema else { return nil }
        let titlePropId = schema.properties.first(where: { $0.type == .title })?.id ?? ""
        return { row in
            let val = row.properties[titlePropId] ?? .empty
            return stringFromValue(val).localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if isDeleted {
                HStack(spacing: 6) {
                    Image(systemName: "trash")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Text("Database deleted")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .padding(12)
            } else if let error = state.error {
                Text(error)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .padding(8)
            } else if let schema = state.schema {
                VStack(alignment: .leading, spacing: 0) {
                    headerBar(schema: schema)
                    if schema.views.count > 1 {
                        viewTabsStrip(schema: schema)
                    }
                    viewContent(schema: schema)
                }
            } else {
                HStack(spacing: 6) {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("Loading...")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .padding(8)
            }
        }
        .task {
            guard !hasStartedLoading else { return }
            hasStartedLoading = true
            state.loadData()
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
        .onReceive(NotificationCenter.default.publisher(for: .fileDeleted)) { notification in
            guard let deletedPath = notification.object as? String else { return }
            if deletedPath == dbPath || dbPath.hasPrefix(deletedPath + "/") {
                isDeleted = true
            }
        }
    }

    // MARK: - Header

    private func headerBar(schema: DatabaseSchema) -> some View {
        HStack(spacing: 8) {
            // Title
            if isEditingTitle {
                TextField("Untitled Database", text: $state.editingTitle)
                    .font(.system(size: EditorTypography.bodyFontSize, weight: .semibold))
                    .foregroundStyle(.primary)
                    .textFieldStyle(.plain)
                    .focused($isTitleFocused)
                    .databasePointerCursor()
                    .onAppear { isTitleFocused = true }
                    .onSubmit {
                        state.persistTitle()
                        isEditingTitle = false
                    }
                    .onChange(of: state.editingTitle) { _, _ in state.scheduleTitleSave() }
                    .onChange(of: isTitleFocused) { _, focused in
                        if !focused { isEditingTitle = false }
                    }
            } else {
                Button { isEditingTitle = true } label: {
                    Text(state.editingTitle.isEmpty ? "Untitled Database" : state.editingTitle)
                        .font(.system(size: EditorTypography.bodyFontSize, weight: .semibold))
                        .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)
            }

            // Add view — always visible next to title
            Menu {
                ForEach([ViewType.table, .list, .kanban, .calendar], id: \.rawValue) { type in
                    Button { state.addView(type: type) } label: {
                        Label(type.rawValue.capitalized, systemImage: iconForViewType(type))
                    }
                }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
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
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            // Search — icon collapses to inline field when active
            if showSearch {
                HStack(spacing: 4) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
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
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            } else {
                Button { showSearch = true } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
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
                    state.activeViewId = view.id
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
                    .foregroundStyle(view.id == state.activeViewId ? .primary : .secondary)
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button(role: .destructive) {
                        state.deleteView(view)
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

    // MARK: - Settings Menu

    private func settingsMenu(schema: DatabaseSchema) -> some View {
        Menu {
            // Layout
            Section("Layout") {
                ForEach([ViewType.table, .list, .kanban, .calendar], id: \.rawValue) { type in
                    Button {
                        if let view = schema.views.first(where: { $0.type == type }) {
                            state.activeViewId = view.id
                        } else {
                            state.addView(type: type)
                        }
                    } label: {
                        Label(
                            type.rawValue.capitalized,
                            systemImage: state.activeView?.type == type ? "checkmark" : iconForViewType(type)
                        )
                    }
                }
            }

            // Properties visibility
            Section("Properties") {
                ForEach(schema.properties.filter { $0.type != .title }) { prop in
                    let isHidden = (state.activeView?.hiddenColumns ?? []).contains(prop.id)
                    Button { state.toggleColumnVisibility(prop.id) } label: {
                        Label(prop.name, systemImage: isHidden ? "eye.slash" : "eye")
                    }
                }
            }

            // Filter
            Section("Filter") {
                if let view = state.activeView, !view.filters.isEmpty {
                    ForEach(view.filters) { filter in
                        let propName = schema.properties.first(where: { $0.id == filter.property })?.name ?? "Filter"
                        Button("Remove: \(propName)") { state.removeFilter(filter.id) }
                    }
                }
                Menu("Add filter") {
                    ForEach(schema.properties.filter { $0.type != .title }) { prop in
                        Button(prop.name) { state.addFilter(propertyId: prop.id) }
                    }
                }
            }

            // Sort
            Section("Sort") {
                if let view = state.activeView, !view.sorts.isEmpty {
                    ForEach(view.sorts) { sort in
                        let propName = schema.properties.first(where: { $0.id == sort.property })?.name ?? "Sort"
                        Button("Remove: \(propName)") { state.removeSort(sort.id) }
                    }
                }
                Menu("Add sort") {
                    ForEach(schema.properties.filter { $0.type != .title }) { prop in
                        Button(prop.name) { state.addSort(propertyId: prop.id, ascending: true) }
                    }
                }
            }

            if state.activeView?.type == .table {
                Section("Table") {
                    Button {
                        state.toggleWrapCellText()
                    } label: {
                        Label("Wrap cell text", systemImage: state.activeView?.wrapCellText == true ? "checkmark" : "text.justify.left")
                    }
                }
            }
        } label: {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
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
            TableView(
                schema: schema,
                rows: boundRows,
                viewConfig: state.activeView ?? state.defaultViewConfig(),
                onOpenRow: { row in openRow(row) },
                onSave: { row in state.saveRow(row) },
                onDelete: { row in state.deleteRow(row) },
                onToggleColumn: { propId in state.toggleColumnVisibility(propId) },
                onAddProperty: { type in state.addPropertyFromTable(type: type) },
                onRenameProperty: { propId, newName in state.renameProperty(propId, to: newName) },
                onDeleteProperty: { propId in state.deleteProperty(propId) },
                onChangePropertyType: { propId, newType in state.changePropertyType(propId, to: newType) },
                onAddSelectOption: { propId, option in state.addSelectOption(propId, option: option) },
                onUpdateSelectOption: { propId, optId, name, color in state.updateSelectOption(propId, optionId: optId, name: name, color: color) },
                onDeleteSelectOption: { propId, optId in state.deleteSelectOption(propId, optionId: optId) },
                onResizeColumn: { propId, width in state.resizeColumn(propId, to: width) },
                onReorderRows: { draggedId, targetId in
                    state.reorderRows(draggedId: draggedId, before: targetId, visibleRowIds: filteredAndSortedRows.map(\.id))
                },
                onNewRow: { addNewRow() },
                scrollToRowId: newRowScrollId,
                usesInnerScroll: false
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.leading, -TableView.rowControlsInset)
        case .kanban:
            KanbanView(
                schema: schema,
                rows: boundRows,
                viewConfig: state.activeView ?? state.defaultViewConfig(),
                onOpenRow: { row in openRow(row) },
                onSave: { row in state.saveRow(row) },
                onUpdateGroupBy: { propId in state.updateGroupBy(propId) },
                onAddSelectOption: { propId, option in state.addSelectOption(propId, option: option) },
                onDelete: { row in state.deleteRow(row) }
            )
        case .list:
            ListView(
                schema: schema,
                rows: boundRows,
                viewConfig: state.activeView ?? state.defaultViewConfig(),
                onOpenRow: { row in openRow(row) },
                onSave: { row in state.saveRow(row) },
                onNewRow: { addNewRow() }
            )
        case .calendar:
            CalendarView(
                schema: schema,
                rows: boundRows,
                viewConfig: state.activeView ?? state.defaultViewConfig(),
                onOpenRow: { row in state.requestRowModal(rowId: row.id) },
                onSave: { row in state.saveRow(row) },
                onCreateRow: { dateStr, propertyId in createRowWithDate(dateStr, propertyId: propertyId) }
            )
            .frame(minHeight: 520)
        }
    }

    // MARK: - View-Specific Operations

    private func addNewRow() {
        do {
            let newRow = try state.createRow()
            newRowScrollId = newRow.id
        } catch {
            state.error = error.localizedDescription
        }
    }

    private func createRowWithDate(_ dateStr: String, propertyId: String?) {
        do {
            let newRow = try state.createRowWithDate(dateStr, propertyId: propertyId)
            state.requestRowModal(rowId: newRow.id, autoFocusTitle: true)
        } catch {
            state.error = error.localizedDescription
        }
    }

    private func openRow(_ row: DatabaseRow) {
        NotificationCenter.default.post(
            name: .inlineDatabaseRowPeek,
            object: nil,
            userInfo: [
                DatabaseNotificationKey.dbPath: dbPath,
                DatabaseNotificationKey.rowId: row.id
            ]
        )
    }

    // MARK: - Helpers

    private func iconForViewType(_ type: ViewType) -> String {
        type.systemImageName
    }
}
