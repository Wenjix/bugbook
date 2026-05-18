import Foundation

public struct MutationEngine {

    /// Execute a batch mutation: validate all, then execute all, then rebuild index.
    /// If any validation fails, returns errors with no side effects.
    public static func execute(mutation: Mutation, schema: DatabaseSchema, dbPath: String,
                               rowStore: RowStore, indexManager: IndexManager) -> MutationResult {
        // 1. Validate ALL operations first
        var validationErrors: [MutationError] = []

        for (i, op) in mutation.operations.enumerated() {
            switch op {
            case .createRow(let properties, _):
                let errors = SchemaValidator.validate(properties: properties, schema: schema, requireTitle: true)
                for e in errors {
                    validationErrors.append(MutationError(operation: i, message: e.description))
                }

            case .updateRow(_, let properties):
                let errors = SchemaValidator.validate(properties: properties, schema: schema)
                for e in errors {
                    validationErrors.append(MutationError(operation: i, message: e.description))
                }

            case .updateRowBody, .deleteRow:
                break
            }
        }

        // 2. If any validation fails, return errors (no partial execution)
        if !validationErrors.isEmpty {
            return MutationResult(errors: validationErrors)
        }

        // 3. Execute all operations
        var created: [String] = []
        var updated: [String] = []
        var deleted: [String] = []
        var executionErrors: [MutationError] = []

        for (i, op) in mutation.operations.enumerated() {
            switch op {
            case .createRow(let properties, let body):
                let rowId = RowStore.generateRowId()
                let now = Date()
                let row = DatabaseRow(
                    id: rowId,
                    properties: properties,
                    body: body ?? "",
                    createdAt: now,
                    updatedAt: now
                )
                do {
                    try rowStore.saveRow(row, schema: schema, dbPath: dbPath)
                    created.append(rowId)
                } catch {
                    executionErrors.append(MutationError(operation: i, message: "Failed to create row: \(error.localizedDescription)"))
                }

            case .updateRow(let rowId, let properties):
                guard var existing = findRow(rowId: rowId, dbPath: dbPath, schema: schema, rowStore: rowStore) else {
                    executionErrors.append(MutationError(operation: i, message: "Row \(rowId) not found"))
                    continue
                }
                for (key, value) in properties {
                    existing.properties[key] = value
                }
                existing.updatedAt = Date()
                do {
                    try rowStore.saveRow(existing, schema: schema, dbPath: dbPath)
                    updated.append(rowId)
                } catch {
                    executionErrors.append(MutationError(operation: i, message: "Failed to update row: \(error.localizedDescription)"))
                }

            case .updateRowBody(let rowId, let body):
                guard var existing = findRow(rowId: rowId, dbPath: dbPath, schema: schema, rowStore: rowStore) else {
                    executionErrors.append(MutationError(operation: i, message: "Row \(rowId) not found"))
                    continue
                }
                existing.body = body
                existing.updatedAt = Date()
                do {
                    try rowStore.saveRow(existing, schema: schema, dbPath: dbPath)
                    updated.append(rowId)
                } catch {
                    executionErrors.append(MutationError(operation: i, message: "Failed to update row body: \(error.localizedDescription)"))
                }

            case .deleteRow(let rowId):
                do {
                    try rowStore.deleteRow(rowId: rowId, dbPath: dbPath)
                    deleted.append(rowId)
                } catch {
                    executionErrors.append(MutationError(operation: i, message: "Failed to delete row: \(error.localizedDescription)"))
                }
            }
        }

        // 4. Rebuild index once at the end (if any writes succeeded)
        if !created.isEmpty || !updated.isEmpty || !deleted.isEmpty {
            let allRows = rowStore.loadAllRows(in: dbPath, schema: schema)
            let index = indexManager.rebuild(dbPath: dbPath, schema: schema, rows: allRows)
            try? indexManager.saveIndex(index, at: dbPath)
        }

        return MutationResult(created: created, updated: updated, deleted: deleted, errors: executionErrors)
    }

    /// Find a row by ID within a database directory.
    private static func findRow(rowId: String, dbPath: String, schema: DatabaseSchema, rowStore: RowStore) -> DatabaseRow? {
        let suffix = RowStore.extractIdSuffix(from: rowId)
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(atPath: dbPath) else { return nil }
        for name in contents {
            if name.contains("(\(suffix))") && name.hasSuffix(".md") {
                let filePath = (dbPath as NSString).appendingPathComponent(name)
                return rowStore.loadRow(at: filePath, schema: schema)
            }
        }
        return nil
    }
}
