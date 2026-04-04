import ArgumentParser
import Foundation
import BugbookCore

struct Batch: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "batch",
        abstract: "Execute batch operations from stdin JSON"
    )

    @OptionGroup var options: Bugbook.Options

    @Argument(help: "Database name or ID")
    var db: String

    func run() throws {
        let (dbPath, schema) = try resolveDatabase(db, workspace: options.resolvedWorkspace)

        // Read JSON from stdin
        var input = ""
        while let line = readLine(strippingNewline: false) {
            input += line
        }

        guard let data = input.data(using: .utf8),
              let ops = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw CLIError.invalidInput("Expected JSON array from stdin")
        }

        let rowStore = RowStore()
        var created: [String] = []
        var updated: [String] = []
        var deleted: [String] = []
        var errors: [[String: Any]] = []

        // Validate all operations first
        for (i, op) in ops.enumerated() {
            guard let opType = op["op"] as? String else {
                errors.append(["operation": i, "message": "Missing 'op' field"])
                continue
            }

            switch opType {
            case "create":
                guard let setValues = op["set"] as? [String: Any] else {
                    errors.append(["operation": i, "message": "Missing 'set' field for create"])
                    continue
                }
                let properties = convertJSONToProperties(setValues, schema: schema)
                let valErrors = SchemaValidator.validate(properties: properties, schema: schema, requireTitle: true)
                for err in valErrors {
                    errors.append(["operation": i, "message": err.description])
                }

            case "update":
                guard let _ = op["id"] as? String else {
                    errors.append(["operation": i, "message": "Missing 'id' field for update"])
                    continue
                }
                if let setValues = op["set"] as? [String: Any] {
                    let properties = convertJSONToProperties(setValues, schema: schema)
                    let valErrors = SchemaValidator.validate(properties: properties, schema: schema)
                    for err in valErrors {
                        errors.append(["operation": i, "message": err.description])
                    }
                }

            case "delete":
                guard let _ = op["id"] as? String else {
                    errors.append(["operation": i, "message": "Missing 'id' field for delete"])
                    continue
                }

            default:
                errors.append(["operation": i, "message": "Unknown operation: \(opType)"])
            }
        }

        // If validation errors, abort
        if !errors.isEmpty {
            try outputJSON(["created": created, "updated": updated, "deleted": deleted, "errors": errors])
            return
        }

        // Execute operations
        for (i, op) in ops.enumerated() {
            guard let opType = op["op"] as? String else { continue }

            switch opType {
            case "create":
                guard let setValues = op["set"] as? [String: Any] else { continue }
                let properties = convertJSONToProperties(setValues, schema: schema)
                let rowId = RowStore.generateRowId()
                let now = Date()
                let row = DatabaseRow(id: rowId, properties: properties, body: "", createdAt: now, updatedAt: now)
                do {
                    try rowStore.saveRow(row, schema: schema, dbPath: dbPath)
                    created.append(rowId)
                } catch {
                    errors.append(["operation": i, "message": error.localizedDescription])
                }

            case "update":
                guard let rowId = op["id"] as? String else { continue }
                let suffix = RowStore.extractIdSuffix(from: rowId)

                // Find and load existing row
                guard let contents = try? FileManager.default.contentsOfDirectory(atPath: dbPath) else { continue }
                var existingRow: DatabaseRow?
                for name in contents {
                    if name.hasSuffix(".md") && !name.hasPrefix("_") && name.contains("(\(suffix))") {
                        let filePath = (dbPath as NSString).appendingPathComponent(name)
                        if let row = rowStore.loadRow(at: filePath, schema: schema), row.id == rowId {
                            existingRow = row
                            break
                        }
                    }
                }

                guard var row = existingRow else {
                    errors.append(["operation": i, "message": "Row not found: \(rowId)"])
                    continue
                }

                if let setValues = op["set"] as? [String: Any] {
                    let properties = convertJSONToProperties(setValues, schema: schema)
                    for (key, value) in properties {
                        row.properties[key] = value
                    }
                }
                row.updatedAt = Date()

                do {
                    try rowStore.saveRow(row, schema: schema, dbPath: dbPath)
                    updated.append(rowId)
                } catch {
                    errors.append(["operation": i, "message": error.localizedDescription])
                }

            case "delete":
                guard let rowId = op["id"] as? String else { continue }
                do {
                    try rowStore.deleteRow(rowId: rowId, dbPath: dbPath)
                    deleted.append(rowId)
                } catch {
                    errors.append(["operation": i, "message": error.localizedDescription])
                }

            default:
                break
            }
        }

        // Rebuild index once at the end
        let indexManager = IndexManager()
        let allRows = rowStore.loadAllRows(in: dbPath, schema: schema)
        let index = indexManager.rebuild(dbPath: dbPath, schema: schema, rows: allRows)
        try indexManager.saveIndex(index, at: dbPath)

        try outputJSON([
            "created": created,
            "updated": updated,
            "deleted": deleted,
            "errors": errors,
        ])
    }
}

/// Convert raw JSON dictionary values to typed PropertyValues using the schema.
private func convertJSONToProperties(_ json: [String: Any], schema: DatabaseSchema) -> [String: PropertyValue] {
    var result: [String: PropertyValue] = [:]
    for (key, val) in json {
        guard let propDef = schema.properties.first(where: { $0.id == key }) else {
            // Unknown property, try as text
            if let s = val as? String { result[key] = .text(s) }
            continue
        }

        switch propDef.type {
        case .title, .text:
            if let s = val as? String { result[key] = .text(s) }
        case .number:
            if let n = val as? Double { result[key] = .number(n) }
            else if let n = val as? Int { result[key] = .number(Double(n)) }
            else if let s = val as? String, let n = Double(s) { result[key] = .number(n) }
        case .select:
            if let s = val as? String { result[key] = .select(s) }
        case .multiSelect:
            if let arr = val as? [String] { result[key] = .multiSelect(arr) }
            else if let s = val as? String {
                result[key] = .multiSelect(s.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) })
            }
        case .date:
            if let s = val as? String { result[key] = .date(s) }
        case .checkbox:
            if let b = val as? Bool { result[key] = .checkbox(b) }
            else if let s = val as? String { result[key] = .checkbox(s == "true") }
        case .url:
            if let s = val as? String { result[key] = .url(s) }
        case .email:
            if let s = val as? String { result[key] = .email(s) }
        case .relation:
            if let arr = val as? [String] { result[key] = .relationMany(arr) }
            else if let s = val as? String {
                if s.contains(",") {
                    result[key] = .relationMany(s.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) })
                } else {
                    result[key] = .relation(s)
                }
            }
        case .formula:
            break // Formula values are computed, not stored.
        }
    }
    return result
}
