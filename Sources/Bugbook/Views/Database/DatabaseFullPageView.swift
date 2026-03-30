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
    var initialRowId: String? = nil

    @State private var state: DatabaseViewState
    @Environment(\.workspacePath) private var workspacePath

    @State private var showPropertyManager = false
    @State private var showSettings = false
    @State private var showVerticalLines = true
    @State private var renamingPropertyId: String? = nil
    @State private var renamingPropertyName: String = ""
    @State private var initialPeekHandled = false
    @State private var draggedViewTabId: String?
    @State private var viewTabDropTargetId: String?
    @State private var showTemplatePicker = false
    @State private var editingTemplate: DatabaseTemplate? = nil

    init(dbPath: String, initialRowId: String? = nil) {
        self.dbPath = dbPath
        self.initialRowId = initialRowId
        _state = State(initialValue: DatabaseViewState(dbPath: dbPath))
    }

    private var filteredAndSortedRows: [DatabaseRow] {
        state.filteredAndSortedRows()
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
            if editingTemplate != nil, let schema = state.schema {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .onTapGesture {
                        if let t = editingTemplate { state.updateTemplate(t) }
                        editingTemplate = nil
                    }

                DatabaseTemplateEditorModal(
                    dbPath: dbPath,
                    schema: schema,
                    template: Binding(
                        get: { editingTemplate! },
                        set: { editingTemplate = $0 }
                    ),
                    onSave: { updated in state.updateTemplate(updated) },
                    onDelete: { templateId in
                        state.deleteTemplate(templateId)
                        editingTemplate = nil
                    },
                    onClose: {
                        if let t = editingTemplate { state.updateTemplate(t) }
                        editingTemplate = nil
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
            state.loadData()
        }
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
                                    .font(DatabaseZoomMetrics.font(16))
                                Text(type.rawValue.capitalized)
                                    .font(DatabaseZoomMetrics.font(11))
                            }
                            .frame(width: DatabaseZoomMetrics.size(58), height: DatabaseZoomMetrics.size(48))
                            .background(state.activeView?.type == type ? Color.primary.opacity(0.12) : Color.primary.opacity(0.04))
                            .clipShape(.rect(cornerRadius: DatabaseZoomMetrics.size(6)))
                            .foregroundStyle(state.activeView?.type == type ? .primary : .secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, DatabaseZoomMetrics.size(12))
                .padding(.bottom, DatabaseZoomMetrics.size(12))

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
                        Image(systemName: "plus").font(DatabaseZoomMetrics.font(12))
                        Text("Add filter").font(DatabaseZoomMetrics.font(12))
                    }
                    .foregroundStyle(.secondary)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .padding(.horizontal, DatabaseZoomMetrics.size(12))
                .padding(.bottom, DatabaseZoomMetrics.size(12))

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
                        Image(systemName: "plus").font(DatabaseZoomMetrics.font(12))
                        Text("Add sort").font(DatabaseZoomMetrics.font(12))
                    }
                    .foregroundStyle(.secondary)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .padding(.horizontal, DatabaseZoomMetrics.size(12))
                .padding(.bottom, DatabaseZoomMetrics.size(12))

                // Group by (table and kanban)
                if state.activeView?.type == .table || state.activeView?.type == .kanban {
                    Divider()
                    popoverSectionHeader("Group by")
                    groupByPicker(schema: schema)
                        .padding(.horizontal, DatabaseZoomMetrics.size(12))
                        .padding(.bottom, DatabaseZoomMetrics.size(12))
                }

                Divider()

                // Properties visibility
                popoverSectionHeader("Properties")
                ForEach(nonTitleProperties) { prop in
                    let isHidden = (state.activeView?.hiddenColumns ?? []).contains(prop.id)
                    Button { state.toggleColumnVisibility(prop.id) } label: {
                        HStack {
                            Text(prop.name).font(DatabaseZoomMetrics.font(15))
                            Spacer()
                            Image(systemName: isHidden ? "eye.slash" : "eye")
                                .font(DatabaseZoomMetrics.font(12))
                                .foregroundStyle(.secondary)
                        }
                        .foregroundStyle(.primary)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, DatabaseZoomMetrics.size(12))
                    .padding(.vertical, DatabaseZoomMetrics.size(3))
                }

                Divider().padding(.top, 4)

                Button { state.updateHideTitle(state.activeView?.hideTitle != true) } label: {
                    HStack {
                        Text("Show title").font(DatabaseZoomMetrics.font(15))
                        Spacer()
                        if state.activeView?.hideTitle != true {
                            Image(systemName: "checkmark").font(DatabaseZoomMetrics.font(12)).foregroundStyle(.secondary)
                        }
                    }
                    .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, DatabaseZoomMetrics.size(12))
                .padding(.vertical, DatabaseZoomMetrics.size(3))

                if state.activeView?.type == .table {
                    Button { showVerticalLines.toggle() } label: {
                        HStack {
                            Text("Grid lines").font(DatabaseZoomMetrics.font(15))
                            Spacer()
                            if showVerticalLines {
                                Image(systemName: "checkmark").font(DatabaseZoomMetrics.font(12)).foregroundStyle(.secondary)
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, DatabaseZoomMetrics.size(12))
                    .padding(.vertical, DatabaseZoomMetrics.size(3))

                    Button { state.toggleWrapCellText() } label: {
                        HStack {
                            Text("Wrap cell text").font(DatabaseZoomMetrics.font(15))
                            Spacer()
                            if state.activeView?.wrapCellText == true {
                                Image(systemName: "checkmark").font(DatabaseZoomMetrics.font(12)).foregroundStyle(.secondary)
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, DatabaseZoomMetrics.size(12))
                    .padding(.vertical, DatabaseZoomMetrics.size(3))
                }

                Spacer(minLength: 12)
            }
        }
        .frame(width: DatabaseZoomMetrics.size(280))
        .frame(maxHeight: DatabaseZoomMetrics.size(420))
        .popoverSurface()
    }

    private func popoverSectionHeader(_ title: String) -> some View {
        Text(title)
            .font(DatabaseZoomMetrics.font(12))
            .fontWeight(.semibold)
            .foregroundStyle(.secondary)
            .padding(.horizontal, DatabaseZoomMetrics.size(12))
            .padding(.top, DatabaseZoomMetrics.size(12))
            .padding(.bottom, DatabaseZoomMetrics.size(6))
    }

    private func filterRow(_ filter: FilterConfig, schema: DatabaseSchema) -> some View {
        let prop = schema.properties.first(where: { $0.id == filter.property })
        let ops = operatorsForType(prop?.type ?? .text)

        return HStack(spacing: 6) {
            // Property picker
            Menu {
                ForEach(nonTitleProperties) { p in
                    Button(p.name) { state.updateFilter(filter.id, property: p.id, op: nil, value: nil) }
                }
            } label: {
                Text(prop?.name ?? "Property")
                    .font(DatabaseZoomMetrics.font(12))
                    .fontWeight(.medium)
                    .padding(.horizontal, DatabaseZoomMetrics.size(6))
                    .padding(.vertical, DatabaseZoomMetrics.size(3))
                    .background(Color.fallbackSurfaceSubtle)
                    .clipShape(.rect(cornerRadius: DatabaseZoomMetrics.size(4)))
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
                    .font(DatabaseZoomMetrics.font(12))
                    .padding(.horizontal, DatabaseZoomMetrics.size(6))
                    .padding(.vertical, DatabaseZoomMetrics.size(3))
                    .background(Color.fallbackSurfaceSubtle)
                    .clipShape(.rect(cornerRadius: DatabaseZoomMetrics.size(4)))
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
                    .font(DatabaseZoomMetrics.font(12))
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
                    .font(DatabaseZoomMetrics.font(12))
                    .padding(.horizontal, DatabaseZoomMetrics.size(6))
                    .padding(.vertical, DatabaseZoomMetrics.size(3))
                    .background(Color.fallbackSurfaceSubtle)
                    .clipShape(.rect(cornerRadius: DatabaseZoomMetrics.size(4)))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        } else if prop?.type == .checkbox {
            Menu {
                Button("Checked") { state.updateFilter(filter.id, property: nil, op: nil, value: "true") }
                Button("Unchecked") { state.updateFilter(filter.id, property: nil, op: nil, value: "false") }
            } label: {
                Text(filter.value == "true" ? "Checked" : filter.value == "false" ? "Unchecked" : "Pick...")
                    .font(DatabaseZoomMetrics.font(12))
                    .padding(.horizontal, DatabaseZoomMetrics.size(6))
                    .padding(.vertical, DatabaseZoomMetrics.size(3))
                    .background(Color.fallbackSurfaceSubtle)
                    .clipShape(.rect(cornerRadius: DatabaseZoomMetrics.size(4)))
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
                .font(DatabaseZoomMetrics.font(12))
                .frame(width: DatabaseZoomMetrics.size(120))
        }
    }

    private func sortRow(_ sort: SortConfig, schema: DatabaseSchema) -> some View {
        let prop = schema.properties.first(where: { $0.id == sort.property })
        return HStack(spacing: 6) {
            Image(systemName: "arrow.up.arrow.down")
                .font(DatabaseZoomMetrics.font(11))
                .foregroundStyle(.secondary)

            // Property picker
            Menu {
                ForEach(nonTitleProperties) { p in
                    Button(p.name) { state.updateSort(sort.id, property: p.id, ascending: nil) }
                }
            } label: {
                Text(prop?.name ?? "Property")
                    .font(DatabaseZoomMetrics.font(12))
                    .fontWeight(.medium)
                    .padding(.horizontal, DatabaseZoomMetrics.size(6))
                    .padding(.vertical, DatabaseZoomMetrics.size(3))
                    .background(Color.fallbackSurfaceSubtle)
                    .clipShape(.rect(cornerRadius: DatabaseZoomMetrics.size(4)))
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
                .font(DatabaseZoomMetrics.font(12))
                .padding(.horizontal, DatabaseZoomMetrics.size(6))
                .padding(.vertical, DatabaseZoomMetrics.size(3))
                .background(Color.fallbackSurfaceSubtle)
                .clipShape(.rect(cornerRadius: DatabaseZoomMetrics.size(4)))
            }
            .buttonStyle(.plain)

            Spacer()

            Button { state.removeSort(sort.id) } label: {
                Label("Remove Sort", systemImage: "xmark.circle.fill")
                    .labelStyle(.iconOnly)
                    .font(DatabaseZoomMetrics.font(12))
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

    // MARK: - Group By

    private var groupableProperties: [PropertyDefinition] {
        state.schema?.properties.filter { $0.type == .select || $0.type == .multiSelect } ?? []
    }

    private func groupByPicker(schema: DatabaseSchema) -> some View {
        let currentGroupId = state.activeView?.groupBy ?? ""
        let currentProp = groupableProperties.first(where: { $0.id == currentGroupId })

        return Menu {
            Button("None") { state.updateGroupBy("") }
            Divider()
            ForEach(groupableProperties) { prop in
                Button {
                    state.updateGroupBy(prop.id)
                } label: {
                    HStack {
                        Text(prop.name)
                        if prop.id == currentGroupId {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(currentProp?.name ?? "None")
                    .font(DatabaseZoomMetrics.font(12))
                Image(systemName: "chevron.down")
                    .font(DatabaseZoomMetrics.font(11))
            }
            .foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
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
            GeometryReader { geo in
                ScrollView([.horizontal, .vertical]) {
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
                        onLoadRelationRows: { prop in state.loadRelationRows(for: prop) },
                        onListDatabases: { state.listDatabaseCandidates(workspacePath: workspacePath) },
                        onSetRelationTarget: { propId, target in state.setRelationTarget(propId, target: target) },
                        onResizeColumn: { propId, width in state.resizeColumn(propId, to: width) },
                        onReorderRows: { draggedId, targetId in
                            state.reorderRows(draggedId: draggedId, before: targetId, visibleRowIds: filteredIds)
                        },
                        onClearSorts: { state.clearSorts() },
                        onNewRow: { createNewRow() },
                        onSetCalculation: { propId, fn in state.setCalculation(propertyId: propId, function: fn) },
                        calculationResults: state.calculationResults(for: filtered),
                        showVerticalLines: showVerticalLines,
                        usesInnerScroll: false,
                        containerWidth: geo.size.width
                    )
                    .frame(
                        minWidth: geo.size.width,
                        minHeight: geo.size.height,
                        alignment: .topLeading
                    )
                    .fixedSize(horizontal: true, vertical: true)
                }
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
        if !state.templates.isEmpty {
            showTemplatePicker = true
        } else {
            createEmptyRow()
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
