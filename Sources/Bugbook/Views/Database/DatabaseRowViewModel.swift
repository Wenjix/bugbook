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
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private(set) var didEdit = false

    init(dbPath: String, origin: String) {
        self.dbPath = dbPath
        self.origin = origin
    }

    func loadData(rowId: String) {
        loadTask?.cancel()
        error = nil

        let path = dbPath
        let service = dbService
        loadTask = Task {
            let result = await Task.detached(priority: .userInitiated) { () -> Result<(DatabaseSchema, [DatabaseRow]), Error> in
                do {
                    return .success(try service.loadDatabase(at: path))
                } catch {
                    return .failure(error)
                }
            }.value

            guard !Task.isCancelled else { return }

            switch result {
            case .success(let (loadedSchema, loadedRows)):
                guard var loadedRow = loadedRows.first(where: { $0.id == rowId }) else {
                    error = "Row not found"
                    return
                }
                // Load body on demand (skipped during bulk load for performance)
                loadedRow.body = service.loadRowBody(rowId: rowId, at: path)
                schema = loadedSchema
                row = loadedRow
            case .failure(let err):
                error = err.localizedDescription
            }
        }
    }

    func debouncedSave(_ row: DatabaseRow, schema: DatabaseSchema) {
        self.row = row
        didEdit = true
        saveTask?.cancel()
        saveTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            try? dbService.saveRow(row, schema: schema, at: dbPath)
            NotificationCenter.default.post(
                name: .databaseDidChange,
                object: nil,
                userInfo: [DatabaseNotificationKey.dbPath: dbPath, DatabaseNotificationKey.origin: origin]
            )
        }
    }

    func flushAndCancel() {
        saveTask?.cancel()
        if let currentRow = row, let currentSchema = schema {
            try? dbService.saveRow(currentRow, schema: currentSchema, at: dbPath)
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

    func listAvailableDatabases() -> [RelationDatabaseCandidate] {
        let store = DatabaseStore()
        let searchRoot = (dbPath as NSString).deletingLastPathComponent
        return store.listDatabases(in: searchRoot)
            .filter { $0.path != dbPath }
            .map { RelationDatabaseCandidate(id: $0.id, name: $0.name, path: $0.path) }
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
        try? dbService.deleteRow(rowId, in: dbPath)
        postChangeNotification()
    }

    @ViewBuilder
    func rowPageView(onBack: @escaping () -> Void = {}, autoFocusTitle: Bool = false) -> some View {
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
                onListDatabases: { self.listAvailableDatabases() },
                onSetRelationTarget: { propId, target in self.setRelationTarget(propId, target: target) },
                onAddProperty: { type in self.addProperty(type: type) },
                onRenameProperty: { propId, name in self.renameProperty(propId, to: name) },
                onDeleteProperty: { propId in self.deleteProperty(propId) },
                onChangePropertyType: { propId, type in self.changePropertyType(propId, to: type) },
                showBreadcrumb: false,
                autoFocusTitle: autoFocusTitle,
                dbPath: dbPath
            )
        }
    }
}
