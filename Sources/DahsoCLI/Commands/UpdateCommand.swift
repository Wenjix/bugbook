import ArgumentParser
import Foundation
import DahsoCore

struct Update: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "update",
        abstract: "Update an existing row"
    )

    @OptionGroup var options: Dahso.Options

    @Argument(help: "Database name or ID")
    var db: String

    @Argument(help: "Row ID")
    var rowId: String

    @Option(name: .long, parsing: .singleValue, help: "Property value (key=value, repeatable)")
    var set: [String] = []

    @Option(name: .long, help: "Path to body content file (- for stdin)")
    var bodyFile: String?

    func run() throws {
        let (dbPath, schema) = try resolveDatabase(db, workspace: options.resolvedWorkspace)
        let rowStore = RowStore()
        guard var row = try loadRow(rowId: rowId, dbPath: dbPath, schema: schema) else {
            throw CLIError.invalidInput("Row not found: \(rowId)")
        }

        // Parse and apply property updates
        if !set.isEmpty {
            let updates = try parseSetValues(set, schema: schema)
            let errors = SchemaValidator.validate(properties: updates, schema: schema)
            if !errors.isEmpty {
                let msgs = errors.map(\.description)
                throw CLIError.invalidInput("Validation errors: \(msgs.joined(separator: "; "))")
            }
            for (key, value) in updates {
                row.properties[key] = value
            }
        }

        // Read body
        if let bodyFile = bodyFile {
            row.body = try readTextInput(from: bodyFile)
        }

        row.updatedAt = Date()
        try rowStore.saveRow(row, schema: schema, dbPath: dbPath)

        // Update index
        let indexManager = IndexManager()
        let allRows = rowStore.loadAllRows(in: dbPath, schema: schema)
        let index = indexManager.rebuild(dbPath: dbPath, schema: schema, rows: allRows)
        try indexManager.saveIndex(index, at: dbPath)

        try outputJSON(["id": rowId, "updated": true])
    }
}
