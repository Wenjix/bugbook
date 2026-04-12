import ArgumentParser
import Foundation
import DahsoCore

struct Create: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "create",
        abstract: "Create a new row in a database"
    )

    @OptionGroup var options: Dahso.Options

    @Argument(help: "Database name or ID")
    var db: String

    @Option(name: .long, parsing: .singleValue, help: "Property value (key=value, repeatable)")
    var set: [String] = []

    @Option(name: .long, help: "Path to body content file (- for stdin)")
    var bodyFile: String?

    func run() throws {
        let (dbPath, schema) = try resolveDatabase(db, workspace: options.resolvedWorkspace)

        let properties = try parseSetValues(set, schema: schema)

        // Validate
        let errors = SchemaValidator.validate(properties: properties, schema: schema, requireTitle: true)
        if !errors.isEmpty {
            let msgs = errors.map(\.description)
            throw CLIError.invalidInput("Validation errors: \(msgs.joined(separator: "; "))")
        }

        // Read body
        var bodyContent = ""
        if let bodyFile = bodyFile {
            if bodyFile == "-" {
                var lines: [String] = []
                while let line = readLine(strippingNewline: false) {
                    lines.append(line)
                }
                bodyContent = lines.joined()
            } else {
                let path = (bodyFile as NSString).expandingTildeInPath
                bodyContent = try String(contentsOfFile: path, encoding: .utf8)
            }
        }

        // Fall back to _template.md if no body provided
        if bodyContent.isEmpty {
            let templatePath = (dbPath as NSString).appendingPathComponent("_template.md")
            if let template = try? String(contentsOfFile: templatePath, encoding: .utf8) {
                bodyContent = template
            }
        }

        // Create the row
        let rowId = RowStore.generateRowId()
        let now = Date()
        let row = DatabaseRow(
            id: rowId,
            properties: properties,
            body: bodyContent,
            createdAt: now,
            updatedAt: now
        )

        let rowStore = RowStore()
        try rowStore.saveRow(row, schema: schema, dbPath: dbPath)

        // Update index
        let indexManager = IndexManager()
        let allRows = rowStore.loadAllRows(in: dbPath, schema: schema)
        let index = indexManager.rebuild(dbPath: dbPath, schema: schema, rows: allRows)
        try indexManager.saveIndex(index, at: dbPath)

        try outputJSON(["id": rowId, "created": true])
    }
}
