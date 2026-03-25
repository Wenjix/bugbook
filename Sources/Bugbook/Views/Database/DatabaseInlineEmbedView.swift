import SwiftUI
import UniformTypeIdentifiers
import BugbookCore

/// Compact database embed for rendering inside a markdown page.
/// Reuses the same TableView/KanbanView/CalendarView/ListView as the full-page view.
struct DatabaseInlineEmbedView: View {
    let dbPath: String
    var onOpenRow: ((DatabaseRow) -> Void)?
    var onOpenDatabase: (() -> Void)?

    @State private var state: DatabaseViewState
    @Environment(\.workspacePath) private var workspacePath

    @State private var showSearch: Bool = false
    @State private var showSettings: Bool = false
    @State private var searchText: String = ""
    @State private var hasStartedLoading = false
    @State private var isHoveringTitle = false
    @State private var isHoveringTabs = false
    @State private var isDeleted = false
    @State private var isEditingTitle: Bool = false
    @FocusState private var isTitleFocused: Bool
    @FocusState private var isSearchFocused: Bool
    @State private var newRowScrollId: String? = nil
    @State private var draggedViewTabId: String?
    @State private var viewTabDropTargetId: String?
    @State private var tableContainerWidth: CGFloat = 0

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
                TextField("", text: $state.editingTitle)
                    .font(.system(size: EditorTypography.scaled(20), weight: .semibold))
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
                    Text(state.editingTitle.isEmpty ? "New database" : state.editingTitle)
                        .font(.system(size: EditorTypography.scaled(20), weight: .semibold))
                        .foregroundStyle(state.editingTitle.isEmpty ? .tertiary : .primary)
                }
                .buttonStyle(.plain)
            }

            // Open full page — visible on hover over title
            if isHoveringTitle {
                Button { onOpenDatabase?() } label: {
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            Spacer()

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
            Button { showSettings.toggle() } label: {
                Label("Filter", systemImage: "slider.horizontal.3")
                    .labelStyle(.iconOnly)
                    .font(.system(size: 13))
                    .foregroundStyle(showSettings ? .primary : .secondary)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .floatingPopover(isPresented: $showSettings, arrowEdge: .bottom) {
                settingsPopover(schema: schema)
            }
        }
        .padding(.leading, 12)
        .padding(.trailing, 12)
        .padding(.top, 8)
        .padding(.bottom, 4)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) {
                isHoveringTitle = hovering
            }
        }
    }

    // MARK: - View Tabs Strip

    private func viewTabsStrip(schema: DatabaseSchema) -> some View {
        HStack(spacing: 4) {
            ForEach(schema.views) { view in
                inlineViewTabButton(view: view)
            }
            if isHoveringTabs {
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
                .help("Add a new view")
            }
            Spacer()
        }
        .padding(.leading, 12)
        .padding(.trailing, 12)
        .padding(.vertical, 4)
        .onHover { isHoveringTabs = $0 }
    }

    private func inlineViewTabButton(view: ViewConfig) -> some View {
        Button {
            draggedViewTabId = nil
            viewTabDropTargetId = nil
            state.activeViewId = view.id
        } label: {
            HStack(spacing: 4) {
                if viewTabDropTargetId == view.id {
                    Capsule()
                        .fill(Color.accentColor)
                        .frame(width: 2, height: 14)
                }
                Image(systemName: iconForViewType(view.type))
                Text(view.name)
            }
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(view.id == state.activeViewId ? Color.primary.opacity(0.1) : Color.clear)
            .clipShape(.rect(cornerRadius: 4))
            .foregroundStyle(view.id == state.activeViewId ? .primary : .secondary)
            .opacity(draggedViewTabId == view.id ? 0.4 : 1.0)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive) {
                state.deleteView(view)
            } label: {
                Label("Delete View", systemImage: "trash")
            }
        }
        .onDrag {
            draggedViewTabId = view.id
            return NSItemProvider(object: view.id as NSString)
        }
        .onDrop(of: [.text], delegate: ViewTabDropDelegate(
            targetId: view.id,
            state: state,
            draggedId: $draggedViewTabId,
            dropTargetId: $viewTabDropTargetId
        ))
    }

    // MARK: - Settings Popover

    private var nonTitleProperties: [PropertyDefinition] {
        state.schema?.properties.filter { $0.type != .title } ?? []
    }

    private func settingsPopover(schema: DatabaseSchema) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Layout
                popoverSectionHeader("Layout")
                HStack(spacing: 6) {
                    ForEach([ViewType.table, .list, .kanban, .calendar], id: \.rawValue) { type in
                        Button {
                            if let view = schema.views.first(where: { $0.type == type }) {
                                state.activeViewId = view.id
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
                    ForEach(nonTitleProperties) { prop in
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
                    ForEach(nonTitleProperties) { prop in
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
                ForEach(nonTitleProperties) { prop in
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
        .popoverSurface()
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
            Menu {
                ForEach(nonTitleProperties) { p in
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

            Menu {
                ForEach(nonTitleProperties) { p in
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
                    ("greater_than_or_equal", "\u{2265}"), ("less_than_or_equal", "\u{2264}"),
                    ("is_empty", "is empty"), ("is_not_empty", "is not empty")]
        case .select, .multiSelect:
            return [("equals", "is"), ("not_equals", "is not"), ("is_empty", "is empty"), ("is_not_empty", "is not empty")]
        case .date:
            return [("equals", "is"), ("greater_than", "is after"), ("less_than", "is before"),
                    ("is_empty", "is empty"), ("is_not_empty", "is not empty")]
        case .checkbox:
            return [("is_checked", "is checked"), ("is_not_checked", "is not checked")]
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
        case "greater_than_or_equal": return "\u{2265}"
        case "less_than_or_equal": return "\u{2264}"
        case "is_checked": return "is checked"
        case "is_not_checked": return "is not checked"
        case "is_empty": return "is empty"
        case "is_not_empty": return "is not empty"
        default: return op
        }
    }

    private func opNeedsValue(_ op: String) -> Bool {
        op != "is_empty" && op != "is_not_empty" && op != "is_checked" && op != "is_not_checked"
    }

    // MARK: - View Content

    private func boundRows(filtered: [DatabaseRow]) -> Binding<[DatabaseRow]> {
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

    @ViewBuilder
    private func viewContent(schema: DatabaseSchema) -> some View {
        let filtered = filteredAndSortedRows
        let filteredIds = filtered.map(\.id)
        let boundRows = boundRows(filtered: filtered)

        switch state.activeView?.type ?? .table {
        case .table:
            // For large databases, use an inner scroll context so LazyVStack
            // can be truly lazy instead of forcing all rows to lay out for the
            // parent page's ScrollView. Small databases keep the flat layout.
            let useInnerScroll = filtered.count > 20
            let controlsInset = DatabaseZoomMetrics.size(TableView.rowControlsInset)
            ScrollView(.horizontal) {
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
                    onLoadRelationRows: { prop in state.loadRelationRows(for: prop) },
                    onListDatabases: { state.listDatabaseCandidates(workspacePath: workspacePath) },
                    onSetRelationTarget: { propId, target in state.setRelationTarget(propId, target: target) },
                    onResizeColumn: { propId, width in state.resizeColumn(propId, to: width) },
                    onReorderRows: { draggedId, targetId in
                        state.reorderRows(draggedId: draggedId, before: targetId, visibleRowIds: filteredIds)
                    },
                    onClearSorts: { state.clearSorts() },
                    onNewRow: { addNewRow() },
                    scrollToRowId: newRowScrollId,
                    usesInnerScroll: useInnerScroll,
                    containerWidth: tableContainerWidth
                )
            }
            .scrollClipDisabled()
            .scrollIndicators(.visible)
            .padding(.leading, -controlsInset)
            .frame(height: useInnerScroll ? 400 : nil)
            .background {
                GeometryReader { geo in
                    Color.clear.onAppear { tableContainerWidth = geo.size.width }
                        .onChange(of: geo.size.width) { _, w in tableContainerWidth = w }
                }
            }
        case .kanban:
            KanbanView(
                schema: schema,
                rows: boundRows,
                viewConfig: state.activeView ?? state.defaultViewConfig(),
                onOpenRow: { row in openRow(row) },
                onSave: { row in state.saveRow(row) },
                onUpdateGroupBy: { propId in state.updateGroupBy(propId) },
                onUpdateSubGroupBy: { propId in state.updateSubGroupBy(propId) },
                onAddSelectOption: { propId, option in state.addSelectOption(propId, option: option) },
                onDelete: { row in state.deleteRow(row) },
                onReorderRows: { draggedId, targetId in
                    state.reorderRows(draggedId: draggedId, before: targetId, visibleRowIds: filteredIds)
                },
                onClearSorts: { state.clearSorts() },
                onRenameSelectOption: { propId, optionId, newName in
                    state.updateSelectOption(propId, optionId: optionId, name: newName, color: nil)
                },
                onDeleteSelectOption: { propId, optionId in
                    state.deleteSelectOption(propId, optionId: optionId)
                },
                onHideColumn: { propId, optionId in
                    state.hideKanbanColumn(propertyId: propId, optionId: optionId)
                }
            )
            .frame(height: 600)
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
