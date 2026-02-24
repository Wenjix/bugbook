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
        let rowStore = RowStore()

        // Find the row file by its ID suffix
        let suffix = RowStore.extractIdSuffix(from: rowId)
        guard let contents = try? FileManager.default.contentsOfDirectory(atPath: dbPath) else {
            throw CLIError.databaseNotFound(db)
        }

        var foundRow: DatabaseRow?
        for name in contents {
            if name.hasSuffix(".md") && !name.hasPrefix("_") && name.contains("(\(suffix))") {
                let filePath = (dbPath as NSString).appendingPathComponent(name)
                if let row = rowStore.loadRow(at: filePath, schema: schema), row.id == rowId {
                    foundRow = row
                    break
                }
            }
        }

        guard let row = foundRow else {
            throw CLIError.invalidInput("Row not found: \(rowId)")
        }

        let output = rowToJSON(row, includeBody: body)
        try outputJSON(output)
    }
}
