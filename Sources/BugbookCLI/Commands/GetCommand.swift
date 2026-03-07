import ArgumentParser
import Foundation
import BugbookCore

struct Get: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "get",
        abstract: "Get a single row by ID"
    )

    @OptionGroup var options: Bugbook.Options

    @Argument(help: "Database name or ID")
    var db: String

    @Argument(help: "Row ID")
    var rowId: String

    @Flag(help: "Include row body content")
    var body: Bool = false

    @Option(help: "Comma-separated list of property IDs or names to include")
    var fields: String?

    @Flag(name: .long, help: "Include raw schema property IDs and stored values alongside friendly properties")
    var rawProperties: Bool = false

    func run() throws {
        let (dbPath, schema) = try resolveDatabase(db, workspace: options.resolvedWorkspace)
        guard let row = try loadRow(rowId: rowId, dbPath: dbPath, schema: schema) else {
            throw CLIError.invalidInput("Row not found: \(rowId)")
        }

        let fieldList = try fields?
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .map { try resolveSchemaPropertyID($0, schema: schema) }

        let output = rowToJSON(
            row,
            schema: schema,
            includeBody: body,
            fields: fieldList,
            includeRawProperties: rawProperties
        )
        try outputJSON(output)
    }
}
