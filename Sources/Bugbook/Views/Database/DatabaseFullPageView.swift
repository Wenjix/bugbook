import SwiftUI
import UniformTypeIdentifiers
import BugbookCore

extension Notification.Name {
    static let databaseDidChange = Notification.Name("databaseDidChange")
    static let databaseNameDidChange = Notification.Name("databaseNameDidChange")
    static let databaseOpenRequested = Notification.Name("databaseOpenRequested")
    static let inlineDatabaseRowPeek = Notification.Name("inlineDatabaseRowPeek")
    static let databaseRowModalRequested = Notification.Name("databaseRowModalRequested")
    static let databaseRowDeleted = Notification.Name("databaseRowDeleted")
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
    var initialRowId: String?

    @State private var state: DatabaseViewState
    @Environment(\.workspacePath) private var workspacePath

    @State private var showPropertyManager = false
    @State private var showSettings = false
    @State private var showVerticalLines = true
    @State private var renamingPropertyId: String?
    @State private var renamingPropertyName: String = ""
    @State private var initialPeekHandled = false
    @State private var draggedViewTabId: String?
    @State private var viewTabDropTargetId: String?
    @State private var showTemplatePicker = false
    @State private var editingTemplate: DatabaseTemplate?
    @AppStorage("home.pinnedDatabasePaths") private var pinnedPathsJSON: String = "[]"

    init(dbPath: String, initialRowId: String? = nil) {
        self.dbPath = dbPath
        self.initialRowId = initialRowId
        _state = State(initialValue: DatabaseViewState(dbPath: dbPath))
    }

    private var nonTitleProperties: [PropertyDefinition] {
        state.schema?.properties.filter { $0.type != .title } ?? []
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
            if let schema = state.schema {
                PropertyManagerSheet(
                    schema: Binding(
                        get: { state.schema ?? schema },
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
        .overlay {
            if showTemplatePicker {
                Color.black.opacity(0.2)
                    .ignoresSafeArea()
                    .onTapGesture { showTemplatePicker = false }

                DatabaseTemplatePickerView(
                    templates: state.templates,
                    onSelectEmpty: {
                        showTemplatePicker = false
                        createEmptyRow()
                    },
                    onSelectTemplate: { template in
                        showTemplatePicker = false
                        createRowFromTemplate(template)
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
            state.loadData(forceReload: true)
        }
        .preference(key: DatabaseViewStatePreferenceKey.self, value: DatabaseViewStatePreferenceValue(state: state))
    }

    // MARK: - Header

    private func dbHeader(schema: DatabaseSchema) -> some View {
        HStack(spacing: 8) {
            if state.activeView?.hideTitle != true {
                TextField("New database", text: $state.editingTitle, axis: .vertical)
                    .lineLimit(1...10)
                    .onSubmit { state.persistTitle() }
                    .onChange(of: state.editingTitle) { _, _ in state.scheduleTitleSave() }
                    .font(DatabaseZoomMetrics.font(17, weight: .semibold))
                    .foregroundStyle(.primary)
                    .textFieldStyle(.plain)
                    .databasePointerCursor()
            }

            Spacer()

            Button {} label: {
                Label("Search", systemImage: "magnifyingglass")
                    .labelStyle(.iconOnly)
                    .font(DatabaseZoomMetrics.font(13))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)

            Button { showSettings.toggle() } label: {
                Label("Filter", systemImage: "slider.horizontal.3")
                    .labelStyle(.iconOnly)
                    .font(DatabaseZoomMetrics.font(13))
                    .foregroundStyle(showSettings ? .primary : .secondary)
            }
            .buttonStyle(.plain)
            .floatingPopover(isPresented: $showSettings, arrowEdge: .bottom) {
                settingsPopover(schema: schema)
            }
        }
        .padding(.leading, DatabaseZoomMetrics.size(4))
        .padding(.trailing, DatabaseZoomMetrics.size(12))
        .padding(.top, DatabaseZoomMetrics.size(8))
        .padding(.bottom, DatabaseZoomMetrics.size(4))
    }

    // MARK: - View Tabs

    @State private var isHoveringTabs = false

    private func viewTabs(schema: DatabaseSchema) -> some View {
        HStack(spacing: 4) {
            ForEach(schema.views) { view in
                viewTabButton(view: view)
            }

            if isHoveringTabs {
                Menu {
                    ForEach(ViewType.allCases, id: \.rawValue) { type in
                        Button { state.addView(type: type) } label: {
                            Label(type.rawValue.capitalized, systemImage: iconForViewType(type))
                        }
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(DatabaseZoomMetrics.font(11))
                        .foregroundStyle(.secondary)
                        .frame(width: DatabaseZoomMetrics.size(20), height: DatabaseZoomMetrics.size(20))
                        .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Add a new view")
            }

            Spacer()
        }
        .padding(.leading, DatabaseZoomMetrics.size(4))
        .padding(.trailing, DatabaseZoomMetrics.size(12))
        .padding(.vertical, DatabaseZoomMetrics.size(4))
        .onHover { isHoveringTabs = $0 }
    }

    private func viewTabButton(view: ViewConfig) -> some View {
        Button {
            draggedViewTabId = nil
            viewTabDropTargetId = nil
            state.activeViewId = view.id
            state.persistActiveView(view.id)
        } label: {
            HStack(spacing: 4) {
                if viewTabDropTargetId == view.id {
                    Capsule()
                        .fill(Color.accentColor)
                        .frame(width: 2, height: DatabaseZoomMetrics.size(14))
                }
                Image(systemName: iconForViewType(view.type))
                Text(view.name)
            }
            .font(DatabaseZoomMetrics.font(12))
            .padding(.horizontal, DatabaseZoomMetrics.size(8))
            .padding(.vertical, DatabaseZoomMetrics.size(4))
            .background(view.id == state.activeViewId ? Color.primary.opacity(0.1) : Color.clear)
            .clipShape(.rect(cornerRadius: DatabaseZoomMetrics.size(4)))
            .opacity(draggedViewTabId == view.id ? 0.4 : 1.0)
        }
        .buttonStyle(.plain)
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
        DatabaseFullSettingsPopover(
            schema: schema,
            state: state,
            showVerticalLines: $showVerticalLines,
            isPinnedToHome: isPinnedToHome,
            togglePinToHome: togglePinToHome
        )
    }

    // MARK: - View Content

    private var filteredRowsBinding: Binding<[DatabaseRow]> {
        Binding(
            get: { state.filteredAndSortedRows() },
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
        let boundRows = filteredRowsBinding
        let visibleRowsProvider: () -> [DatabaseRow] = { state.filteredAndSortedRows() }

        switch state.activeView?.type ?? .table {
        case .table:
            tableContent(schema: schema, boundRows: boundRows, visibleRowsProvider: visibleRowsProvider)
        case .kanban:
            kanbanContent(schema: schema, boundRows: boundRows, visibleRowsProvider: visibleRowsProvider)
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
            calendarContent(schema: schema, boundRows: boundRows)
        }
    }

    private func tableContent(
        schema: DatabaseSchema,
        boundRows: Binding<[DatabaseRow]>,
        visibleRowsProvider: @escaping () -> [DatabaseRow]
    ) -> some View {
        let filteredRows = visibleRowsProvider()
        let filteredIds = filteredRows.map(\.id)
        return GeometryReader { geometry in
            ScrollViewReader { proxy in
                ScrollView([.horizontal, .vertical]) {
                    TableView(
                        schema: schema,
                        rows: boundRows,
                        viewConfig: state.activeView ?? state.defaultViewConfig(),
                        visibleRowsProvider: visibleRowsProvider,
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
                        onNewRow: { createNewRow() },
                        onSetCalculation: { propId, fn in state.setCalculation(propertyId: propId, function: fn) },
                        onUpdateFormula: { propId, expr in state.updateFormulaExpression(propId, expression: expr) },
                        calculationResults: state.calculationResults(for: filteredRows),
                        showVerticalLines: showVerticalLines,
                        usesInnerScroll: false,
                        containerWidth: geometry.size.width,
                        matchedRowIds: Set(state.findMatchedRowIds),
                        selectedFindRowId: state.findSelectedRowId
                    )
                    .frame(
                        minWidth: geometry.size.width,
                        minHeight: geometry.size.height,
                        alignment: .topLeading
                    )
                    .padding(.bottom, 48)
                }
                .bugbookCompactScrollIndicators()
                .onChange(of: state.findScrollRequestToken) { _, _ in
                    scrollToSelectedFindRow(using: proxy)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func kanbanContent(
        schema: DatabaseSchema,
        boundRows: Binding<[DatabaseRow]>,
        visibleRowsProvider: @escaping () -> [DatabaseRow]
    ) -> some View {
        let filteredIds = visibleRowsProvider().map(\.id)
        return KanbanView(
            schema: schema,
            rows: boundRows,
            viewConfig: state.activeView ?? state.defaultViewConfig(),
            visibleRowsProvider: visibleRowsProvider,
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
            },
            matchedRowIds: Set(state.findMatchedRowIds),
            selectedFindRowId: state.findSelectedRowId,
            findScrollRequestToken: state.findScrollRequestToken
        )
    }

    private func calendarContent(schema: DatabaseSchema, boundRows: Binding<[DatabaseRow]>) -> some View {
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

    // MARK: - View-Specific Operations

    private func createNewRow() {
        if !state.templates.isEmpty {
            showTemplatePicker = true
        } else {
            createEmptyRow()
        }
    }

    private func scrollToSelectedFindRow(using proxy: ScrollViewProxy) {
        guard let rowId = state.findSelectedRowId else { return }
        DispatchQueue.main.async {
            withAnimation(.easeInOut(duration: 0.18)) {
                proxy.scrollTo(rowId, anchor: .top)
            }
        }
    }

    private func createEmptyRow() {
        Task {
            do {
                let newRow = try state.createRow()
                openRow(newRow)
            } catch {
                state.error = error.localizedDescription
            }
        }
    }

    private func createRowFromTemplate(_ template: DatabaseTemplate) {
        do {
            let newRow = try state.createRowFromTemplate(template)
            openRow(newRow)
        } catch {
            state.error = error.localizedDescription
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

    // MARK: - Pin to Home

    private var isPinnedToHome: Bool {
        PinnedDatabasesHelper.decodePaths(from: pinnedPathsJSON).contains(dbPath)
    }

    private func togglePinToHome() {
        pinnedPathsJSON = PinnedDatabasesHelper.togglePath(dbPath, in: pinnedPathsJSON)
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
    @Environment(\.popoverDismiss) private var popoverDismiss
    @Environment(\.workspacePath) private var workspacePath
    @State private var editingNames: [String: String] = [:]
    @State private var availableDatabases: [DatabaseInfo] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Properties")
                    .font(.headline)
                Spacer()
                Button("Done") { (popoverDismiss ?? { dismiss() })() }
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

                        if prop.type == .relation {
                            relationTargetPicker(for: prop)
                        }

                        if prop.type == .formula {
                            formulaExpressionEditor(for: prop)
                        }

                        if prop.type == .lookup {
                            lookupConfigPicker(for: prop)
                        }

                        if prop.type == .rollup {
                            rollupConfigPicker(for: prop)
                        }

                        if !isTitle {
                            Button {
                                deleteProperty(prop.id)
                            } label: {
                                Image(systemName: "trash")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
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
        let config: PropertyConfig?
        switch type {
        case .select, .multiSelect:
            config = PropertyConfig(options: [])
        case .relation:
            config = PropertyConfig(target: nil)
        case .lookup:
            config = PropertyConfig(relationPropertyId: nil, targetPropertyId: nil)
        case .rollup:
            config = PropertyConfig(relationPropertyId: nil, targetPropertyId: nil, aggregationFunction: "count")
        default:
            config = nil
        }
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

    private func relationTargetPicker(for prop: PropertyDefinition) -> some View {
        Menu {
            ForEach(availableDatabases.filter({ $0.path != dbPath }), id: \.path) { db in
                Button {
                    setRelationTarget(prop.id, target: db.path)
                } label: {
                    HStack {
                        Text(db.name)
                        if prop.config?.target == db.path {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            let targetName = availableDatabases.first(where: { $0.path == prop.config?.target })?.name
            Text(targetName ?? "Select DB")
                .font(.caption)
                .foregroundStyle(targetName != nil ? .primary : .secondary)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .onAppear { loadAvailableDatabases() }
    }

    @ViewBuilder
    private func formulaExpressionEditor(for prop: PropertyDefinition) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "function")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("e.g. prop_price * prop_quantity", text: Binding(
                get: { prop.config?.formula ?? "" },
                set: { newValue in
                    guard let idx = schema.properties.firstIndex(where: { $0.id == prop.id }) else { return }
                    if schema.properties[idx].config == nil {
                        schema.properties[idx].config = PropertyConfig(formula: newValue)
                    } else {
                        schema.properties[idx].config?.formula = newValue
                    }
                    Task {
                        try? dbService.saveSchema(schema, at: dbPath)
                        postDatabaseChangeNotification(dbPath: dbPath, origin: notificationOrigin)
                    }
                }
            ))
            .textFieldStyle(.roundedBorder)
            .font(.caption.monospaced())
        }
    }

    private func lookupConfigPicker(for prop: PropertyDefinition) -> some View {
        let relationProps = schema.properties.filter { $0.type == .relation }
        let selectedRelationId = prop.config?.relationPropertyId ?? ""
        let targetProps: [PropertyDefinition] = {
            guard !selectedRelationId.isEmpty,
                  let relProp = schema.properties.first(where: { $0.id == selectedRelationId }),
                  let targetPath = relProp.config?.target, !targetPath.isEmpty else { return [] }
            return (try? dbService.loadDatabase(at: targetPath).0.properties) ?? []
        }()

        return HStack(spacing: 4) {
            Menu {
                ForEach(relationProps) { rp in
                    Button {
                        setLookupRelation(prop.id, relationPropertyId: rp.id)
                    } label: {
                        HStack {
                            Text(rp.name)
                            if selectedRelationId == rp.id {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                let relName = relationProps.first(where: { $0.id == selectedRelationId })?.name
                Text(relName ?? "Relation")
                    .font(.caption)
                    .foregroundStyle(relName != nil ? .primary : .secondary)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            if !targetProps.isEmpty {
                Menu {
                    ForEach(targetProps) { tp in
                        Button {
                            setLookupTarget(prop.id, targetPropertyId: tp.id)
                        } label: {
                            HStack {
                                Text(tp.name)
                                if prop.config?.targetPropertyId == tp.id {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    let targetName = targetProps.first(where: { $0.id == prop.config?.targetPropertyId })?.name
                    Text(targetName ?? "Property")
                        .font(.caption)
                        .foregroundStyle(targetName != nil ? .primary : .secondary)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
        }
    }

    private func setLookupRelation(_ propertyId: String, relationPropertyId: String) {
        guard let idx = schema.properties.firstIndex(where: { $0.id == propertyId }) else { return }
        if schema.properties[idx].config == nil {
            schema.properties[idx].config = PropertyConfig()
        }
        schema.properties[idx].config?.relationPropertyId = relationPropertyId
        schema.properties[idx].config?.targetPropertyId = nil
        Task {
            try? dbService.saveSchema(schema, at: dbPath)
        }
    }

    private func setLookupTarget(_ propertyId: String, targetPropertyId: String) {
        guard let idx = schema.properties.firstIndex(where: { $0.id == propertyId }) else { return }
        if schema.properties[idx].config == nil {
            schema.properties[idx].config = PropertyConfig()
        }
        schema.properties[idx].config?.targetPropertyId = targetPropertyId
        Task {
            try? dbService.saveSchema(schema, at: dbPath)
        }
    }

    // MARK: - Rollup Config

    private func rollupConfigPicker(for prop: PropertyDefinition) -> some View {
        let relationProps = schema.properties.filter { $0.type == .relation }
        let selectedRelationId = prop.config?.relationPropertyId ?? ""
        let targetProps: [PropertyDefinition] = {
            guard !selectedRelationId.isEmpty,
                  let relProp = schema.properties.first(where: { $0.id == selectedRelationId }),
                  let targetPath = relProp.config?.target, !targetPath.isEmpty else { return [] }
            return (try? dbService.loadDatabase(at: targetPath).0.properties) ?? []
        }()
        let rollupFunctions = ["sum", "count", "average", "min", "max"]

        return HStack(spacing: 4) {
            // Relation picker
            Menu {
                ForEach(relationProps) { rp in
                    Button {
                        setRollupRelation(prop.id, relationPropertyId: rp.id)
                    } label: {
                        HStack {
                            Text(rp.name)
                            if selectedRelationId == rp.id {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                let relName = relationProps.first(where: { $0.id == selectedRelationId })?.name
                Text(relName ?? "Relation")
                    .font(.caption)
                    .foregroundStyle(relName != nil ? .primary : .secondary)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            // Target property picker
            if !targetProps.isEmpty {
                Menu {
                    ForEach(targetProps) { tp in
                        Button {
                            setRollupTarget(prop.id, targetPropertyId: tp.id)
                        } label: {
                            HStack {
                                Text(tp.name)
                                if prop.config?.targetPropertyId == tp.id {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    let targetName = targetProps.first(where: { $0.id == prop.config?.targetPropertyId })?.name
                    Text(targetName ?? "Property")
                        .font(.caption)
                        .foregroundStyle(targetName != nil ? .primary : .secondary)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }

            // Aggregation function picker
            Menu {
                ForEach(rollupFunctions, id: \.self) { fn in
                    Button {
                        setRollupFunction(prop.id, function: fn)
                    } label: {
                        HStack {
                            Text(fn.capitalized)
                            if prop.config?.aggregationFunction == fn {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                let fnName = prop.config?.aggregationFunction
                Text(fnName?.capitalized ?? "Function")
                    .font(.caption)
                    .foregroundStyle(fnName != nil ? .primary : .secondary)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
    }

    private func setRollupRelation(_ propertyId: String, relationPropertyId: String) {
        guard let idx = schema.properties.firstIndex(where: { $0.id == propertyId }) else { return }
        if schema.properties[idx].config == nil {
            schema.properties[idx].config = PropertyConfig()
        }
        schema.properties[idx].config?.relationPropertyId = relationPropertyId
        schema.properties[idx].config?.targetPropertyId = nil
        schema.properties[idx].config?.aggregationFunction = schema.properties[idx].config?.aggregationFunction ?? "count"
        Task {
            try? dbService.saveSchema(schema, at: dbPath)
        }
    }

    private func setRollupTarget(_ propertyId: String, targetPropertyId: String) {
        guard let idx = schema.properties.firstIndex(where: { $0.id == propertyId }) else { return }
        if schema.properties[idx].config == nil {
            schema.properties[idx].config = PropertyConfig()
        }
        schema.properties[idx].config?.targetPropertyId = targetPropertyId
        Task {
            try? dbService.saveSchema(schema, at: dbPath)
        }
    }

    private func setRollupFunction(_ propertyId: String, function: String) {
        guard let idx = schema.properties.firstIndex(where: { $0.id == propertyId }) else { return }
        if schema.properties[idx].config == nil {
            schema.properties[idx].config = PropertyConfig()
        }
        schema.properties[idx].config?.aggregationFunction = function
        Task {
            try? dbService.saveSchema(schema, at: dbPath)
        }
    }

    private func loadAvailableDatabases() {
        guard availableDatabases.isEmpty else { return }
        let store = DatabaseStore()
        // Use workspacePath environment if available, otherwise derive from dbPath
        // (dbPath is a database folder inside the workspace, so its parent chain
        // contains the workspace root).
        let searchRoot: String
        if let workspace = workspacePath {
            searchRoot = workspace
        } else {
            // Walk up from dbPath to find the workspace root.
            // The dbPath is something like /workspace/SomeDB — scan from parent.
            searchRoot = (dbPath as NSString).deletingLastPathComponent
        }
        availableDatabases = store.listDatabases(in: searchRoot)
    }

    private func setRelationTarget(_ propertyId: String, target: String) {
        guard let idx = schema.properties.firstIndex(where: { $0.id == propertyId }) else { return }
        if schema.properties[idx].config == nil {
            schema.properties[idx].config = PropertyConfig(target: target)
        } else {
            schema.properties[idx].config?.target = target
        }
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
        var databaseRows = rows
        try? dbService.changePropertyType(propertyId, to: newType, in: &s, rows: &databaseRows, at: dbPath)
        schema = s
        rows = databaseRows
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
