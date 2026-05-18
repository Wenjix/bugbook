import XCTest
@testable import Bugbook
import BugbookCore

final class DatabaseServiceLoadTests: XCTestCase {
    func testDisplayLoadUsesIndexedSnapshotWhenIndexIsStale() throws {
        let dbPath = makeTemporaryDatabase()
        defer { try? FileManager.default.removeItem(atPath: dbPath) }

        let schema = makeSchema()
        let rows = makeRows()
        try writeDatabase(schema: schema, rows: rows, indexedRows: [rows[0]], dbPath: dbPath)

        let result = try DatabaseService().loadDatabaseForDisplay(at: dbPath)

        XCTAssertEqual(result.rows.map(\.id), ["row_first1"])
        XCTAssertTrue(result.needsDiskRefresh)
    }

    func testDiskRefreshingLoadRebuildsStaleIndex() throws {
        let dbPath = makeTemporaryDatabase()
        defer { try? FileManager.default.removeItem(atPath: dbPath) }

        let schema = makeSchema()
        let rows = makeRows()
        try writeDatabase(schema: schema, rows: rows, indexedRows: [rows[0]], dbPath: dbPath)

        let (loadedSchema, loadedRows) = try DatabaseService().loadDatabaseFromDiskRefreshingIndex(at: dbPath)

        XCTAssertEqual(loadedSchema.id, schema.id)
        XCTAssertEqual(loadedRows.map(\.id), rows.map(\.id))

        let indexManager = IndexManager()
        let rebuilt = try XCTUnwrap(indexManager.loadIndex(at: dbPath))
        XCTAssertFalse(indexManager.isStale(indexData: rebuilt, dbPath: dbPath))
        XCTAssertEqual((rebuilt["rows"] as? [String: Any])?.count, rows.count)
    }

    private func makeSchema() -> DatabaseSchema {
        DatabaseSchema(
            id: "db_load_test",
            name: "Load Test",
            properties: [
                PropertyDefinition(id: "prop_title", name: "Title", type: .title),
                PropertyDefinition(id: "prop_done", name: "Done", type: .checkbox)
            ],
            views: [ViewConfig(id: "view_table", name: "All", type: .table)],
            defaultView: "view_table",
            createdAt: "2026-01-01T00:00:00Z"
        )
    }

    private func makeRows() -> [DatabaseRow] {
        [
            DatabaseRow(
                id: "row_first1",
                properties: ["prop_title": .text("First"), "prop_done": .checkbox(false)],
                createdAt: Date(timeIntervalSince1970: 1),
                updatedAt: Date(timeIntervalSince1970: 1)
            ),
            DatabaseRow(
                id: "row_second",
                properties: ["prop_title": .text("Second"), "prop_done": .checkbox(true)],
                createdAt: Date(timeIntervalSince1970: 2),
                updatedAt: Date(timeIntervalSince1970: 2)
            )
        ]
    }

    private func writeDatabase(
        schema: DatabaseSchema,
        rows: [DatabaseRow],
        indexedRows: [DatabaseRow],
        dbPath: String
    ) throws {
        try DatabaseStore().saveSchema(schema, at: dbPath)

        let rowStore = RowStore()
        for row in rows {
            try rowStore.saveRow(row, schema: schema, dbPath: dbPath)
        }

        let indexManager = IndexManager()
        let index = indexManager.rebuild(dbPath: dbPath, schema: schema, rows: indexedRows)
        try indexManager.saveIndex(index, at: dbPath)
    }

    private func makeTemporaryDatabase() -> String {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("BugbookDatabaseServiceLoadTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url.path
    }
}
