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
                guard let loadedRow = loadedRows.first(where: { $0.id == rowId }) else {
                    error = "Row not found"
                    return
                }
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
        let prop = PropertyDefinition(id: "prop_\(UUID().uuidString)", name: name, type: type)
        Task {
            try? dbService.addProperty(prop, to: &s, at: dbPath)
            schema = s
            postChangeNotification()
        }
    }

    func renameProperty(_ propertyId: String, to newName: String) {
        guard var s = schema else { return }
        var rows: [DatabaseRow] = []
        if let currentRow = row { rows = [currentRow] }
        Task {
            try? dbService.renameProperty(propertyId, to: newName, in: &s, rows: &rows, at: dbPath)
            schema = s
            if let updatedRow = rows.first { row = updatedRow }
            postChangeNotification()
        }
    }

    func deleteProperty(_ propertyId: String) {
        guard var s = schema else { return }
        Task {
            try? dbService.deleteProperty(propertyId, from: &s, at: dbPath)
            schema = s
            postChangeNotification()
        }
    }

    func changePropertyType(_ propertyId: String, to newType: PropertyType) {
        guard var s = schema else { return }
        var rows: [DatabaseRow] = []
        if let currentRow = row { rows = [currentRow] }
        Task {
            try? dbService.changePropertyType(propertyId, to: newType, in: &s, rows: &rows, at: dbPath)
            schema = s
            if let updatedRow = rows.first { row = updatedRow }
            postChangeNotification()
        }
    }

    func addOption(_ propertyId: String, option: SelectOption) {
        guard var s = schema else { return }
        Task {
            try? dbService.addSelectOption(option, toProperty: propertyId, in: &s, at: dbPath)
            schema = s
        }
    }

    func updateOption(_ propertyId: String, optId: String, name: String?, color: String?) {
        guard var s = schema else { return }
        Task {
            try? dbService.updateSelectOption(optId, name: name, color: color, inProperty: propertyId, in: &s, at: dbPath)
            schema = s
        }
    }

    func deleteOption(_ propertyId: String, optId: String) {
        guard var s = schema else { return }
        var rows: [DatabaseRow] = []
        if let currentRow = row { rows = [currentRow] }
        Task {
            try? dbService.deleteSelectOption(optId, fromProperty: propertyId, in: &s, rows: &rows, at: dbPath)
            schema = s
            if let updatedRow = rows.first { row = updatedRow }
        }
    }

    func deleteRow(_ rowId: String) {
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
                onAddProperty: { type in self.addProperty(type: type) },
                onRenameProperty: { propId, name in self.renameProperty(propId, to: name) },
                onDeleteProperty: { propId in self.deleteProperty(propId) },
                onChangePropertyType: { propId, type in self.changePropertyType(propId, to: type) },
                showBreadcrumb: false,
                autoFocusTitle: autoFocusTitle
            )
        }
    }
}
