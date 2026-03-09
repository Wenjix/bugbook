import SwiftUI
import BugbookCore

@MainActor
final class DatabaseRowViewModel: ObservableObject {
    let dbPath: String
    let origin: String

    @Published var schema: DatabaseSchema?
    @Published var row: DatabaseRow?
    @Published var error: String?

    private let dbService = DatabaseService()
    private var saveTask: Task<Void, Never>?

    init(dbPath: String, origin: String) {
        self.dbPath = dbPath
        self.origin = origin
    }

    func loadData(rowId: String) {
        error = nil
        do {
            let (loadedSchema, loadedRows) = try dbService.loadDatabase(at: dbPath)
            guard let loadedRow = loadedRows.first(where: { $0.id == rowId }) else {
                error = "Row not found"
                return
            }
            schema = loadedSchema
            row = loadedRow
        } catch {
            self.error = error.localizedDescription
        }
    }

    func debouncedSave(_ row: DatabaseRow, schema: DatabaseSchema) {
        self.row = row
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
