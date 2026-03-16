import SwiftUI
import BugbookCore

@MainActor
@Observable
final class DatabaseViewState {
    let dbPath: String
    let dbService = DatabaseService()
    let notificationOrigin = UUID().uuidString

    var schema: DatabaseSchema? { didSet { _cacheVersion &+= 1 } }
    var rows: [DatabaseRow] = [] { didSet { _cacheVersion &+= 1 } }
    var activeViewId: String = "" { didSet { _cacheVersion &+= 1 } }
    var error: String?
    var editingTitle: String = ""

    @ObservationIgnored private var _cacheVersion: UInt64 = 0
    @ObservationIgnored private var _cachedAtVersion: UInt64 = UInt64.max
    @ObservationIgnored private var _cachedFilteredRows: [DatabaseRow] = []

    @ObservationIgnored private var titleSaveTask: Task<Void, Never>?
    @ObservationIgnored private var rowSaveTask: Task<Void, Never>?
    @ObservationIgnored private var pendingRowSaves: [String: DatabaseRow] = [:]
    @ObservationIgnored private var deletedRowIds: Set<String> = []
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var isLoadInFlight = false
    @ObservationIgnored private var reloadRequestedWhileLoading = false

    var activeView: ViewConfig? {
        schema?.views.first(where: { $0.id == activeViewId })
    }

    init(dbPath: String) {
        self.dbPath = dbPath
    }

    // MARK: - Filtered/Sorted Rows

    func filteredAndSortedRows(extraFilter: ((DatabaseRow) -> Bool)? = nil) -> [DatabaseRow] {
        guard activeView != nil else { return rows }

        let base = computeBaseFilteredRows()

        if let extraFilter {
            return base.filter(extraFilter)
        }
        return base
    }

    /// Returns filtered+sorted rows using a cache that invalidates when rows, schema, or activeViewId change.
    private func computeBaseFilteredRows() -> [DatabaseRow] {
        if _cachedAtVersion == _cacheVersion {
            return _cachedFilteredRows
        }

        guard let view = activeView else { return rows }
        var result = applyManualRowOrder(view.manualRowOrder, to: rows)

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

        _cachedFilteredRows = result
        _cachedAtVersion = _cacheVersion
        return result
    }

    // MARK: - Data Loading

    func loadData(onLoaded: (() -> Void)? = nil) {
        if isLoadInFlight {
            reloadRequestedWhileLoading = true
            return
        }

        error = nil
        isLoadInFlight = true

        let path = dbPath
        let service = dbService
        loadTask = Task { [weak self] in
            guard let self else { return }
            let result = await Task.detached(priority: .userInitiated) { () -> Result<(DatabaseSchema, [DatabaseRow]), Error> in
                do {
                    return .success(try service.loadDatabase(at: path))
                } catch {
                    return .failure(error)
                }
            }.value

            defer {
                loadTask = nil
                isLoadInFlight = false
            }

            // If cancelled but schema was never set, retry once so the spinner
            // doesn't persist forever (e.g., after a view hierarchy rebuild).
            if Task.isCancelled {
                if schema == nil {
                    Task { @MainActor [weak self] in
                        self?.loadData(onLoaded: onLoaded)
                    }
                }
                return
            }

            switch result {
            case .success(let (loadedSchema, loadedRows)):
                schema = loadedSchema
                let deleted = deletedRowIds
                rows = deleted.isEmpty ? loadedRows : loadedRows.filter { !deleted.contains($0.id) }
                if editingTitle.isEmpty || editingTitle != loadedSchema.name {
                    editingTitle = loadedSchema.name
                }
                if activeViewId.isEmpty || !loadedSchema.views.contains(where: { $0.id == self.activeViewId }) {
                    self.activeViewId = loadedSchema.defaultView
                }
                // Sync tab displayName with schema name so breadcrumbs show the correct title
                if !loadedSchema.name.isEmpty {
                    NotificationCenter.default.post(
                        name: .databaseNameDidChange,
                        object: nil,
                        userInfo: [DatabaseNotificationKey.dbPath: dbPath, DatabaseNotificationKey.newName: loadedSchema.name]
                    )
                }
                onLoaded?()
            case .failure(let error):
                self.error = error.localizedDescription
            }

            if reloadRequestedWhileLoading {
                reloadRequestedWhileLoading = false
                loadData()
            }
        }
    }

    // MARK: - Row Operations

    func saveRow(_ row: DatabaseRow) {
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

    func flushPendingRowSaves() {
        guard let currentSchema = schema, !pendingRowSaves.isEmpty else { return }
        let deleted = deletedRowIds
        let rowsToPersist = pendingRowSaves.values.filter { !deleted.contains($0.id) }
        pendingRowSaves.removeAll()

        guard !rowsToPersist.isEmpty else { return }
        let service = dbService
        let path = dbPath
        Task { [weak self] in
            for row in rowsToPersist {
                try? service.saveRow(row, schema: currentSchema, at: path)
            }
            self?.postChangeNotification()
        }
    }

    func flushPendingRowSavesSynchronously() {
        guard let currentSchema = schema, !pendingRowSaves.isEmpty else { return }
        let deleted = deletedRowIds
        let rowsToPersist = pendingRowSaves.values.filter { !deleted.contains($0.id) }
        pendingRowSaves.removeAll()

        guard !rowsToPersist.isEmpty else { return }
        for row in rowsToPersist {
            try? dbService.saveRow(row, schema: currentSchema, at: dbPath)
        }
        postChangeNotification()
    }

    func deleteRow(_ row: DatabaseRow) {
        guard let schema = schema else { return }
        pendingRowSaves.removeValue(forKey: row.id)
        deletedRowIds.insert(row.id)
        rows.removeAll { $0.id == row.id }
        // Synchronous to prevent race with loadData reintroducing deleted rows
        try? dbService.deleteRow(row.id, in: dbPath)
        try? dbService.updateIndex(rows: rows, schema: schema, at: dbPath)
        // Notify all views so stale saves for this row are cancelled
        NotificationCenter.default.post(
            name: .databaseRowDeleted,
            object: nil,
            userInfo: [DatabaseNotificationKey.dbPath: dbPath, DatabaseNotificationKey.rowId: row.id]
        )
        postChangeNotification()
    }

    @discardableResult
    func createRow() throws -> DatabaseRow {
        guard let s = schema else {
            throw NSError(domain: "Bugbook.Database", code: 1, userInfo: [NSLocalizedDescriptionKey: "Schema unavailable"])
        }
        let newRow = try dbService.createRow(in: dbPath, schema: s)
        rows.append(newRow)
        postChangeNotification()
        return newRow
    }

    @discardableResult
    func createRowWithDate(_ dateStr: String, propertyId: String?) throws -> DatabaseRow {
        let (preparedSchema, datePropertyId) = try ensureCalendarDateProperty(preferredPropertyId: propertyId)
        var newRow = try dbService.createRow(in: dbPath, schema: preparedSchema)
        newRow.properties[datePropertyId] = .date(
            DatabaseDateValue(start: dateStr).rawValue
        )
        try dbService.saveRow(newRow, schema: preparedSchema, at: dbPath)
        self.schema = preparedSchema
        if let idx = rows.firstIndex(where: { $0.id == newRow.id }) {
            rows[idx] = newRow
        } else {
            rows.append(newRow)
        }
        postChangeNotification()
        return newRow
    }

    func requestRowModal(rowId: String, autoFocusTitle: Bool = false) {
        requestDatabaseRowModal(dbPath: dbPath, rowId: rowId, autoFocusTitle: autoFocusTitle)
    }

    // MARK: - Notifications

    func postChangeNotification() {
        postDatabaseChangeNotification(dbPath: dbPath, origin: notificationOrigin)
    }

    // MARK: - Property Operations

    func addSelectOption(_ propertyId: String, option: SelectOption) {
        guard var s = schema else { return }
        Task {
            try? dbService.addSelectOption(option, toProperty: propertyId, in: &s, at: dbPath)
            schema = s
        }
    }

    func updateSelectOption(_ propertyId: String, optionId: String, name: String?, color: String?) {
        guard var s = schema else { return }
        Task {
            try? dbService.updateSelectOption(optionId, name: name, color: color, inProperty: propertyId, in: &s, at: dbPath)
            schema = s
        }
    }

    func deleteSelectOption(_ propertyId: String, optionId: String) {
        guard var s = schema else { return }
        Task {
            try? dbService.deleteSelectOption(optionId, fromProperty: propertyId, in: &s, rows: &rows, at: dbPath)
            schema = s
        }
    }

    func renameProperty(_ propertyId: String, to newName: String) {
        guard var s = schema else { return }
        Task {
            try? dbService.renameProperty(propertyId, to: newName, in: &s, rows: &rows, at: dbPath)
            schema = s
            postChangeNotification()
        }
    }

    func deleteProperty(_ propertyId: String) {
        guard var s = schema else { return }
        Task {
            try? dbService.deleteProperty(propertyId, from: &s, at: dbPath)
            schema = s
        }
    }

    func changePropertyType(_ propertyId: String, to newType: PropertyType) {
        guard var s = schema else { return }
        Task {
            try? dbService.changePropertyType(propertyId, to: newType, in: &s, rows: &rows, at: dbPath)
            schema = s
        }
    }

    func addPropertyFromTable(type: PropertyType) {
        guard var s = schema else { return }
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
        Task {
            try? dbService.addProperty(prop, to: &s, at: dbPath)
            schema = s
        }
    }

    func toggleColumnVisibility(_ propertyId: String) {
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

    // MARK: - View Operations

    func resizeColumn(_ propertyId: String, to width: CGFloat) {
        guard var s = schema, var view = activeView else { return }
        if view.columnWidths == nil { view.columnWidths = [:] }
        view.columnWidths?[propertyId] = Double(width)
        if let idx = s.views.firstIndex(where: { $0.id == view.id }) {
            s.views[idx] = view
        }
        schema = s
        Task {
            try? dbService.updateView(view, in: &s, at: dbPath)
        }
    }

    func reorderRows(draggedId: String, before targetId: String?, visibleRowIds: [String]) {
        guard var s = schema, var view = activeView else { return }
        view.manualRowOrder = reorderedManualRowOrder(
            currentOrder: view.manualRowOrder,
            allRows: rows,
            visibleRowIds: visibleRowIds,
            draggedId: draggedId,
            targetId: targetId
        )
        if let viewIndex = s.views.firstIndex(where: { $0.id == view.id }) {
            s.views[viewIndex] = view
        }
        schema = s
        Task {
            try? dbService.updateView(view, in: &s, at: dbPath)
        }
    }

    func toggleWrapCellText() {
        guard var s = schema, var view = activeView, view.type == .table else { return }
        view.wrapCellText = !(view.wrapCellText ?? false)
        Task {
            try? dbService.updateView(view, in: &s, at: dbPath)
            schema = s
        }
    }

    func updateGroupBy(_ propertyId: String) {
        guard var s = schema, var view = activeView else { return }
        view.groupBy = propertyId
        Task {
            try? dbService.updateView(view, in: &s, at: dbPath)
            schema = s
        }
    }

    func addView(type: ViewType) {
        guard var s = schema else { return }

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
                    name: uniqueViewName(for: type, in: s),
                    type: type,
                    sorts: [],
                    filters: [],
                    groupBy: statusProp.id
                )
                try? dbService.addView(view, to: &s, at: dbPath)
                self.schema = s
                activeViewId = view.id
            }
            return
        }

        let calendarDatePropertyId: String?
        if type == .calendar {
            calendarDatePropertyId = try? Bugbook.ensureCalendarDateProperty(
                schema: &s, activeViewId: "", preferredPropertyId: nil,
                dbService: dbService, dbPath: dbPath
            )
        } else {
            calendarDatePropertyId = nil
        }

        let view = ViewConfig(
            id: "view_\(UUID().uuidString)",
            name: uniqueViewName(for: type, in: s),
            type: type,
            sorts: [],
            filters: [],
            groupBy: type == .kanban ? s.properties.first(where: { $0.type == .select })?.id : nil,
            dateProperty: calendarDatePropertyId
        )
        Task {
            try? dbService.addView(view, to: &s, at: dbPath)
            self.schema = s
            activeViewId = view.id
        }
    }

    /// Returns a unique name like "Table", "Table 2", "Table 3", etc.
    private func uniqueViewName(for type: ViewType, in schema: DatabaseSchema) -> String {
        let baseName = type.rawValue.capitalized
        let existingNames = Set(schema.views.map(\.name))
        if !existingNames.contains(baseName) { return baseName }
        var counter = 2
        while existingNames.contains("\(baseName) \(counter)") { counter += 1 }
        return "\(baseName) \(counter)"
    }

    func deleteView(_ view: ViewConfig) {
        guard var s = schema, s.views.count > 1 else { return }
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

    func persistActiveView(_ viewId: String) {
        guard var s = schema, s.defaultView != viewId else { return }
        Task {
            try? dbService.setDefaultView(viewId, in: &s, at: dbPath)
            schema = s
        }
    }

    // MARK: - Filter/Sort

    func addFilter(propertyId: String) {
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

    func updateFilter(_ filterId: String, property: String?, op: String?, value: String?) {
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

    func hideKanbanColumn(propertyId: String, optionId: String) {
        guard var s = schema, var view = activeView else { return }
        let filter = FilterConfig(property: propertyId, op: "not_equals", value: optionId)
        view.filters.append(filter)
        Task {
            try? dbService.updateView(view, in: &s, at: dbPath)
            schema = s
        }
    }

    func removeFilter(_ filterId: String) {
        guard var s = schema, var view = activeView else { return }
        view.filters.removeAll { $0.id == filterId }
        Task {
            try? dbService.updateView(view, in: &s, at: dbPath)
            schema = s
        }
    }

    func addSort(propertyId: String, ascending: Bool) {
        guard var s = schema, var view = activeView else { return }
        let sort = SortConfig(property: propertyId, direction: ascending ? "asc" : "desc")
        view.sorts.append(sort)
        Task {
            try? dbService.updateView(view, in: &s, at: dbPath)
            schema = s
        }
    }

    func updateSort(_ sortId: String, property: String?, ascending: Bool?) {
        guard var s = schema, var view = activeView,
              let idx = view.sorts.firstIndex(where: { $0.id == sortId }) else { return }
        if let property = property { view.sorts[idx].property = property }
        if let ascending = ascending { view.sorts[idx].direction = ascending ? "asc" : "desc" }
        Task {
            try? dbService.updateView(view, in: &s, at: dbPath)
            schema = s
        }
    }

    func removeSort(_ sortId: String) {
        guard var s = schema, var view = activeView else { return }
        view.sorts.removeAll { $0.id == sortId }
        Task {
            try? dbService.updateView(view, in: &s, at: dbPath)
            schema = s
        }
    }

    func clearSorts() {
        guard var s = schema, var view = activeView, !view.sorts.isEmpty else { return }
        view.sorts.removeAll()
        if let viewIndex = s.views.firstIndex(where: { $0.id == view.id }) {
            s.views[viewIndex] = view
        }
        schema = s
        Task {
            try? dbService.updateView(view, in: &s, at: dbPath)
            postChangeNotification()
        }
    }

    // MARK: - Title

    func scheduleTitleSave() {
        titleSaveTask?.cancel()
        titleSaveTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 450_000_000)
            guard !Task.isCancelled else { return }
            persistTitle()
        }
    }

    func persistTitle() {
        guard var s = schema else { return }
        let newName = editingTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newName.isEmpty else {
            editingTitle = s.name
            return
        }
        guard newName != s.name else { return }
        s.name = newName
        schema = s
        editingTitle = newName
        Task {
            try? dbService.saveSchema(s, at: dbPath)
            postChangeNotification()
            NotificationCenter.default.post(
                name: .databaseNameDidChange,
                object: nil,
                userInfo: [DatabaseNotificationKey.dbPath: dbPath, DatabaseNotificationKey.newName: newName]
            )
        }
    }

    // MARK: - Relation

    private var relationRowCache: [String: [RelationRowCandidate]] = [:]

    func loadRelationRows(for prop: PropertyDefinition) -> [RelationRowCandidate] {
        guard let target = prop.config?.target, !target.isEmpty else { return [] }
        if let cached = relationRowCache[target] { return cached }
        do {
            let (targetSchema, targetRows) = try dbService.loadDatabase(at: target)
            let candidates = targetRows.map { RelationRowCandidate(id: $0.id, title: $0.title(schema: targetSchema)) }
            relationRowCache[target] = candidates
            return candidates
        } catch {
            return []
        }
    }

    func listAvailableDatabases(workspacePath: String?) -> [DatabaseInfo] {
        let store = DatabaseStore()
        let searchRoot: String
        if let workspace = workspacePath, !workspace.isEmpty {
            searchRoot = workspace
        } else {
            searchRoot = (dbPath as NSString).deletingLastPathComponent
        }
        return store.listDatabases(in: searchRoot).filter { $0.path != dbPath }
    }

    private var databaseCandidateCache: [RelationDatabaseCandidate]?

    func listDatabaseCandidates(workspacePath: String?) -> [RelationDatabaseCandidate] {
        if let cached = databaseCandidateCache { return cached }
        let result = listAvailableDatabases(workspacePath: workspacePath).map {
            RelationDatabaseCandidate(id: $0.id, name: $0.name, path: $0.path)
        }
        databaseCandidateCache = result
        return result
    }

    func setRelationTarget(_ propertyId: String, target: String) {
        guard var s = schema,
              let idx = s.properties.firstIndex(where: { $0.id == propertyId }) else { return }
        if s.properties[idx].config == nil {
            s.properties[idx].config = PropertyConfig(target: target)
        } else {
            s.properties[idx].config?.target = target
        }

        // Auto-name the property after the target database (like Notion).
        // Look up the real schema name; fall back to the folder name.
        let targetStore = DatabaseStore()
        let searchRoot = (dbPath as NSString).deletingLastPathComponent
        let targetInfo = targetStore.listDatabases(in: searchRoot).first(where: { $0.path == target })
        let targetName = targetInfo?.name ?? (target as NSString).lastPathComponent
        if !targetName.isEmpty, s.properties[idx].name == "New Relation" || s.properties[idx].name.isEmpty {
            s.properties[idx].name = targetName
        }

        schema = s
        Task {
            try? dbService.saveSchema(s, at: dbPath)
            postChangeNotification()
        }
    }

    // MARK: - Lifecycle

    func cancelAll() {
        titleSaveTask?.cancel()
        titleSaveTask = nil
        rowSaveTask?.cancel()
        rowSaveTask = nil
        loadTask?.cancel()
        loadTask = nil
        isLoadInFlight = false
        reloadRequestedWhileLoading = false
        flushPendingRowSavesSynchronously()
    }

    // MARK: - Helpers

    func defaultViewConfig() -> ViewConfig {
        defaultDatabaseViewConfig()
    }

    func ensureCalendarDateProperty(preferredPropertyId: String?) throws -> (DatabaseSchema, String) {
        guard var currentSchema = schema else {
            throw NSError(domain: "Bugbook.Database", code: 1, userInfo: [NSLocalizedDescriptionKey: "Schema unavailable"])
        }
        let datePropertyId = try Bugbook.ensureCalendarDateProperty(
            schema: &currentSchema,
            activeViewId: activeViewId,
            preferredPropertyId: preferredPropertyId,
            dbService: dbService,
            dbPath: dbPath
        )
        return (currentSchema, datePropertyId)
    }
}
