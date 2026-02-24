import ArgumentParser
import Foundation
import BugbookCore

struct Delete: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "delete",
        abstract: "Delete a row from a database"
    )

    @OptionGroup var options: Bugbook.Options

    @Argument(help: "Database name or ID")
    var db: String

    @Argument(help: "Row ID")
    var rowId: String

    func run() throws {
        let (dbPath, schema) = try resolveDatabase(db, workspace: options.resolvedWorkspace)
        let rowStore = RowStore()

        try rowStore.deleteRow(rowId: rowId, dbPath: dbPath)

        // Update index
        let indexManager = IndexManager()
        let allRows = rowStore.loadAllRows(in: dbPath, schema: schema)
        let index = indexManager.rebuild(dbPath: dbPath, schema: schema, rows: allRows)
        try indexManager.saveIndex(index, at: dbPath)

        try outputJSON(["id": rowId, "deleted": true])
    }
}
