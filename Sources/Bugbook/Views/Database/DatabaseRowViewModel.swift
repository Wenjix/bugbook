import SwiftUI
import BugbookCore

@MainActor
@Observable
final class DatabaseRowViewModel {
    let dbPath: String
    let origin: String

    var schema: DatabaseSchema?
    var row: DatabaseRow?
    var error: String?

    private let dbService = DatabaseService()
    @ObservationIgnored private let draftStore = EditorDraftStore()
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var isLoadInFlight = false
    @ObservationIgnored private var pendingRowIdForReload: String?
    @ObservationIgnored private(set) var didEdit = false
    @ObservationIgnored private var deletedRowIds: Set<String> = []
    @ObservationIgnored private var deletionObserver: NSObjectProtocol?

    init(dbPath: String, origin: String) {
        self.dbPath = dbPath
        self.origin = origin
        // Listen for row deletions to cancel stale saves
        deletionObserver = NotificationCenter.default.addObserver(
            forName: .databaseRowDeleted,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let deletedPath = notification.userInfo?[DatabaseNotificationKey.dbPath] as? String,
                  let rowId = notification.userInfo?[DatabaseNotificationKey.rowId] as? String else { return }
            MainActor.assumeIsolated {
                guard let self, deletedPath == self.dbPath else { return }
                self.deletedRowIds.insert(rowId)
                self.draftStore.clearRowBodyDraft(dbPath: deletedPath, rowId: rowId)
                if self.row?.id == rowId {
                    self.saveTask?.cancel()
                    self.saveTask = nil
                }
            }
        }
    }

    deinit {
        if let deletionObserver {
            NotificationCenter.default.removeObserver(deletionObserver)
        }
    }

    func loadData(rowId: String) {
        if isLoadInFlight {
            pendingRowIdForReload = rowId
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

            guard !Task.isCancelled else { return }

            switch result {
            case .success(let (loadedSchema, loadedRows)):
                guard var loadedRow = loadedRows.first(where: { $0.id == rowId }) else {
                    error = "Row not found"
                    return
                }
                // Load body on demand (skipped during bulk load for performance)
                loadedRow.body = service.loadRowBody(rowId: rowId, at: path)
                if let restoredBody = draftStore.restoreRowBodyDraftIfNewer(
                    dbPath: path,
                    rowId: rowId,
                    rowFilePath: rowFilePath(rowId: rowId)
                ) {
                    loadedRow.body = restoredBody
                    didEdit = true
                }
                schema = loadedSchema
                row = loadedRow
            case .failure(let err):
                error = err.localizedDescription
            }

            if let pendingRowIdForReload {
                self.pendingRowIdForReload = nil
                loadData(rowId: pendingRowIdForReload)
            }
        }
    }

    func debouncedSave(_ row: DatabaseRow, schema: DatabaseSchema) {
        guard !deletedRowIds.contains(row.id) else { return }
        self.row = row
        didEdit = true
        draftStore.saveRowBodyDraft(
            content: row.body,
            dbPath: dbPath,
            rowId: row.id,
            rowFilePath: rowFilePath(rowId: row.id)
        )
        saveTask?.cancel()
        saveTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled, !deletedRowIds.contains(row.id) else { return }
            do {
                try dbService.saveRow(row, schema: schema, at: dbPath)
                try? dbService.incrementalIndexUpdate(row: row, schema: schema, at: dbPath)
                draftStore.clearRowBodyDraft(dbPath: dbPath, rowId: row.id)
                NotificationCenter.default.post(
                    name: .databaseDidChange,
                    object: nil,
                    userInfo: [DatabaseNotificationKey.dbPath: dbPath, DatabaseNotificationKey.origin: origin]
                )
            } catch {
                return
            }
        }
    }

    func flushAndCancel() {
        saveTask?.cancel()
        loadTask?.cancel()
        loadTask = nil
        isLoadInFlight = false
        pendingRowIdForReload = nil
        if let currentRow = row, let currentSchema = schema,
           !deletedRowIds.contains(currentRow.id) {
            do {
                try dbService.saveRow(currentRow, schema: currentSchema, at: dbPath)
                try? dbService.incrementalIndexUpdate(row: currentRow, schema: currentSchema, at: dbPath)
                draftStore.clearRowBodyDraft(dbPath: dbPath, rowId: currentRow.id)
            } catch {
                return
            }
        }
    }

    func postChangeNotification() {
        postDatabaseChangeNotification(dbPath: dbPath, origin: origin)
    }

    func addProperty(type: PropertyType) {
        guard var s = schema else { return }
        let name = type.rawValue.capitalized
        let config: PropertyConfig?
        switch type {
        case .select, .multiSelect:
            config = PropertyConfig(options: [])
        case .relation:
            config = PropertyConfig(target: nil)
        case .formula:
            config = PropertyConfig(formula: "")
        default:
            config = nil
        }
        let prop = PropertyDefinition(id: "prop_\(UUID().uuidString)", name: name, type: type, config: config)
        Task { [weak self] in
            try? self?.dbService.addProperty(prop, to: &s, at: self?.dbPath ?? "")
            self?.schema = s
            self?.postChangeNotification()
        }
    }

    func renameProperty(_ propertyId: String, to newName: String) {
        guard var s = schema else { return }
        var rows: [DatabaseRow] = []
        if let currentRow = row { rows = [currentRow] }
        Task { [weak self] in
            guard let self else { return }
            try? dbService.renameProperty(propertyId, to: newName, in: &s, rows: &rows, at: dbPath)
            schema = s
            if let updatedRow = rows.first { row = updatedRow }
            postChangeNotification()
        }
    }

    func deleteProperty(_ propertyId: String) {
        guard var s = schema else { return }
        Task { [weak self] in
            guard let self else { return }
            try? dbService.deleteProperty(propertyId, from: &s, at: dbPath)
            schema = s
            postChangeNotification()
        }
    }

    func changePropertyType(_ propertyId: String, to newType: PropertyType) {
        guard var s = schema else { return }
        var rows: [DatabaseRow] = []
        if let currentRow = row { rows = [currentRow] }
        Task { [weak self] in
            guard let self else { return }
            try? dbService.changePropertyType(propertyId, to: newType, in: &s, rows: &rows, at: dbPath)
            schema = s
            if let updatedRow = rows.first { row = updatedRow }
            postChangeNotification()
        }
    }

    func addOption(_ propertyId: String, option: SelectOption) {
        guard var s = schema else { return }
        Task { [weak self] in
            guard let self else { return }
            try? dbService.addSelectOption(option, toProperty: propertyId, in: &s, at: dbPath)
            schema = s
        }
    }

    func updateOption(_ propertyId: String, optId: String, name: String?, color: String?) {
        guard var s = schema else { return }
        Task { [weak self] in
            guard let self else { return }
            try? dbService.updateSelectOption(optId, name: name, color: color, inProperty: propertyId, in: &s, at: dbPath)
            schema = s
        }
    }

    func deleteOption(_ propertyId: String, optId: String) {
        guard var s = schema else { return }
        var rows: [DatabaseRow] = []
        if let currentRow = row { rows = [currentRow] }
        Task { [weak self] in
            guard let self else { return }
            try? dbService.deleteSelectOption(optId, fromProperty: propertyId, in: &s, rows: &rows, at: dbPath)
            schema = s
            if let updatedRow = rows.first { row = updatedRow }
        }
    }

    func loadRelationRows(for prop: PropertyDefinition) -> [RelationRowCandidate] {
        guard let target = prop.config?.target, !target.isEmpty else { return [] }
        do {
            let (targetSchema, targetRows) = try dbService.loadDatabase(at: target)
            return targetRows.map { RelationRowCandidate(id: $0.id, title: $0.title(schema: targetSchema)) }
        } catch {
            return []
        }
    }

    func rowFilePath(rowId: String) -> String? {
        let suffix = rowId.hasPrefix("row_") ? String(rowId.dropFirst(4)) : rowId
        guard let contents = try? FileManager.default.contentsOfDirectory(atPath: dbPath) else { return nil }
        for name in contents where name.hasSuffix(".md") && name.contains("(\(suffix))") {
            return (dbPath as NSString).appendingPathComponent(name)
        }
        return nil
    }

    func listAvailableDatabases(workspacePath: String? = nil) -> [RelationDatabaseCandidate] {
        let store = DatabaseStore()
        let searchRoot: String
        if let workspace = workspacePath, !workspace.isEmpty {
            searchRoot = workspace
        } else {
            searchRoot = (dbPath as NSString).deletingLastPathComponent
        }
        return store.listDatabases(in: searchRoot)
            .filter { $0.path != dbPath }
            .map { RelationDatabaseCandidate(id: $0.id, name: $0.name, path: $0.path) }
    }

    @discardableResult
    func createTemplate(name: String, defaultProperties: [String: PropertyValue] = [:], body: String = "") -> DatabaseTemplate {
        let template = DatabaseTemplate(
            id: "tmpl_\(UUID().uuidString.prefix(8).lowercased())",
            name: name,
            defaultProperties: defaultProperties,
            body: body
        )
        if schema?.templates == nil { schema?.templates = [] }
        schema?.templates?.append(template)
        if let s = schema {
            Task { [weak self] in
                guard let self else { return }
                try? dbService.saveSchema(s, at: dbPath)
                postChangeNotification()
            }
        }
        return template
    }

    func setRelationTarget(_ propertyId: String, target: String) {
        guard var s = schema,
              let idx = s.properties.firstIndex(where: { $0.id == propertyId }) else { return }
        if s.properties[idx].config == nil {
            s.properties[idx].config = PropertyConfig(target: target)
        } else {
            s.properties[idx].config?.target = target
        }
        schema = s
        Task { [weak self] in
            guard let self else { return }
            try? dbService.saveSchema(s, at: dbPath)
            postChangeNotification()
        }
    }

    func deleteRow(_ rowId: String) {
        saveTask?.cancel()
        saveTask = nil
        deletedRowIds.insert(rowId)
        draftStore.clearRowBodyDraft(dbPath: dbPath, rowId: rowId)
        try? dbService.deleteRow(rowId, in: dbPath)
        // Remove the deleted row from the index incrementally
        if let schema = schema {
            try? dbService.incrementalIndexDelete(rowId: rowId, schema: schema, at: dbPath)
        }
        // Notify all views so stale saves for this row are cancelled
        NotificationCenter.default.post(
            name: .databaseRowDeleted,
            object: nil,
            userInfo: [DatabaseNotificationKey.dbPath: dbPath, DatabaseNotificationKey.rowId: rowId]
        )
        postChangeNotification()
    }

    @ViewBuilder
    func rowPageView( // swiftlint:disable:next function_parameter_count
        onBack: @escaping () -> Void = {},
        autoFocusTitle: Bool = false,
        fullWidth: Bool = false,
        workspacePath: String? = nil,
        templates: [DatabaseTemplate] = [],
        onApplyTemplate: ((DatabaseTemplate) -> Void)? = nil,
        onNewTemplate: (() -> Void)? = nil,
        onSaveAsTemplate: (() -> Void)? = nil
    ) -> some View {
        if let schema = schema, row != nil {
            RowPageView(
                schema: schema,
                row: Binding(
                    get: { self.row! },
                    set: { newRow in self.debouncedSave(newRow, schema: schema) }
                ),
                onSave: { newRow in self.debouncedSave(newRow, schema: schema) },
                onBack: onBack,
                onAddOption: { propId, option in self.addOption(propId, option: option) },
                onUpdateOption: { propId, optId, name, color in self.updateOption(propId, optId: optId, name: name, color: color) },
                onDeleteOption: { propId, optId in self.deleteOption(propId, optId: optId) },
                onLoadRelationRows: { prop in self.loadRelationRows(for: prop) },
                onListDatabases: { self.listAvailableDatabases(workspacePath: workspacePath) },
                onSetRelationTarget: { propId, target in self.setRelationTarget(propId, target: target) },
                onAddProperty: { type in self.addProperty(type: type) },
                onRenameProperty: { propId, name in self.renameProperty(propId, to: name) },
                onDeleteProperty: { propId in self.deleteProperty(propId) },
                onChangePropertyType: { propId, type in self.changePropertyType(propId, to: type) },
                showBreadcrumb: false,
                autoFocusTitle: autoFocusTitle,
                fullWidth: fullWidth,
                dbPath: dbPath,
                templates: templates,
                onApplyTemplate: onApplyTemplate,
                onNewTemplate: onNewTemplate,
                onSaveAsTemplate: onSaveAsTemplate
            )
        }
    }
}
