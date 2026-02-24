import ArgumentParser
import Foundation
import BugbookCore

struct Update: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "update",
        abstract: "Update an existing row"
    )

    @OptionGroup var options: Bugbook.Options

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

        // Find existing row
        let suffix = RowStore.extractIdSuffix(from: rowId)
        guard let contents = try? FileManager.default.contentsOfDirectory(atPath: dbPath) else {
            throw CLIError.databaseNotFound(db)
        }

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
            if bodyFile == "-" {
                var lines: [String] = []
                while let line = readLine(strippingNewline: false) {
                    lines.append(line)
                }
                row.body = lines.joined()
            } else {
                let path = (bodyFile as NSString).expandingTildeInPath
                row.body = try String(contentsOfFile: path, encoding: .utf8)
            }
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
