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
    @State private var newRowScrollId: String?
    @State private var draggedViewTabId: String?
    @State private var viewTabDropTargetId: String?
    @State private var tableContainerWidth: CGFloat = 0
    @State private var showTemplatePicker = false
    @State private var editingTemplate: DatabaseTemplate?

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
        .overlay {
            if showTemplatePicker {
                Color.black.opacity(0.2)
                    .ignoresSafeArea()
                    .onTapGesture { showTemplatePicker = false }

                DatabaseTemplatePickerView(
                    templates: state.templates,
                    onSelectEmpty: {
                        showTemplatePicker = false
                        addEmptyRow()
                    },
                    onSelectTemplate: { template in
                        showTemplatePicker = false
                        addRowFromTemplate(template)
                    },
                    onNewTemplate: {
                        showTemplatePicker = false
                        let newTemplate = state.createTemplate(name: "Untitled")
                        editingTemplate = newTemplate
                    },
                    onDismiss: { showTemplatePicker = false }
                )
            }
        }
        .overlay {
            if let editingTemplate, let schema = state.schema {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .onTapGesture {
                        state.updateTemplate(self.editingTemplate ?? editingTemplate)
                        self.editingTemplate = nil
                    }

                DatabaseTemplateEditorModal(
                    dbPath: dbPath,
                    schema: schema,
                    template: Binding(
                        get: { self.editingTemplate ?? editingTemplate },
                        set: { self.editingTemplate = $0 }
                    ),
                    onSave: { updated in state.updateTemplate(updated) },
                    onDelete: { templateId in
                        state.deleteTemplate(templateId)
                        self.editingTemplate = nil
                    },
                    onClose: {
                        state.updateTemplate(self.editingTemplate ?? editingTemplate)
                        self.editingTemplate = nil
                    }
                )
            }
        }
        .task {
            startLoadingIfNeeded()
        }
        .onAppear {
            startLoadingIfNeeded()
        }
        .onDisappear {
            state.cancelAll()
            if state.schema == nil {
                hasStartedLoading = false
            }
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

    private func startLoadingIfNeeded() {
        guard !hasStartedLoading else { return }
        hasStartedLoading = true
        state.loadData()
    }

    // MARK: - Header

    private func headerBar(schema: DatabaseSchema) -> some View {
        HStack(spacing: 8) {
            // Title
            if state.activeView?.hideTitle != true {
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

    private func settingsPopover(schema: DatabaseSchema) -> some View {
        DatabaseInlineSettingsPopover(schema: schema, state: state)
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
                    onUpdateSelectOption: { propId, optId, name, color in
                        state.updateSelectOption(propId, optionId: optId, name: name, color: color)
                    },
                    onDeleteSelectOption: { propId, optId in state.deleteSelectOption(propId, optionId: optId) },
                    onLoadRelationRows: { prop in state.loadRelationRows(for: prop) },
                    onListDatabases: { state.listDatabaseCandidates(workspacePath: workspacePath) },
                    onSetRelationTarget: { propId, target in state.setRelationTarget(propId, target: target) },
                    onResolveLookup: { row, prop in state.resolveLookupValue(for: row, property: prop) },
                    onResolveRollup: { row, prop in state.resolveRollupValue(for: row, property: prop) },
                    onResizeColumn: { propId, width in state.resizeColumn(propId, to: width) },
                    onReorderRows: { draggedId, targetId in
                        state.reorderRows(draggedId: draggedId, before: targetId, visibleRowIds: filteredIds)
                    },
                    onClearSorts: { state.clearSorts() },
                    onNewRow: { addNewRow() },
                    onSetCalculation: { propId, fn in state.setCalculation(propertyId: propId, function: fn) },
                    onUpdateFormula: { propId, expr in state.updateFormulaExpression(propId, expression: expr) },
                    calculationResults: state.calculationResults(for: filtered),
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
                        .onChange(of: geo.size.width) { _, width in tableContainerWidth = width }
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
        if !state.templates.isEmpty {
            showTemplatePicker = true
        } else {
            addEmptyRow()
        }
    }

    private func addEmptyRow() {
        do {
            let newRow = try state.createRow()
            newRowScrollId = newRow.id
        } catch {
            state.error = error.localizedDescription
        }
    }

    private func addRowFromTemplate(_ template: DatabaseTemplate) {
        do {
            let newRow = try state.createRowFromTemplate(template)
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
