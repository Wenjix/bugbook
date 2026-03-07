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

    func run() throws {
        let (dbPath, schema) = try resolveDatabase(db, workspace: options.resolvedWorkspace)
        guard let row = try loadRow(rowId: rowId, dbPath: dbPath, schema: schema) else {
            throw CLIError.invalidInput("Row not found: \(rowId)")
        }

        let output = rowToJSON(row, includeBody: body)
        try outputJSON(output)
    }
}
