import XCTest
@testable import BugbookCore

final class FirstPartyRowStoreTests: XCTestCase {
    func testFlatFrontmatterRowsParseWithSchemaProperties() throws {
        let schema = makeDailySchema()
        let content = """
        ---
        id: daily_2026-05-17
        name: "2026-05-17"
        date: 2026-05-17
        ---

        # 2026-05-17
        """

        let row = try XCTUnwrap(RowSerializer.parse(content: content, schema: schema))

        XCTAssertEqual(row.id, "daily_2026-05-17")
        XCTAssertEqual(row.properties["name"], .text("2026-05-17"))
        XCTAssertEqual(row.properties["date"], .date("2026-05-17"))
        XCTAssertEqual(row.body, "# 2026-05-17")
    }

    func testRowStorePreservesFixedFilenameAndFlatFrontmatter() throws {
        let dbURL = try makeTemporaryDatabase()
        defer { try? FileManager.default.removeItem(at: dbURL) }

        let schema = makeDailySchema()
        let rowPath = dbURL.appendingPathComponent("2026-05-17.md")
        try """
        ---
        id: daily_2026-05-17
        name: "2026-05-17"
        date: 2026-05-17
        ---

        # 2026-05-17
        """
        .write(to: rowPath, atomically: true, encoding: .utf8)

        let store = RowStore()
        var row = try XCTUnwrap(store.loadAllRows(in: dbURL.path, schema: schema).first)
        row.body = "# 2026-05-17\n\nUpdated"
        row.properties["name"] = .text("2026-05-17")
        try store.saveRow(row, schema: schema, dbPath: dbURL.path)

        let saved = try String(contentsOf: rowPath, encoding: .utf8)
        XCTAssertTrue(FileManager.default.fileExists(atPath: rowPath.path))
        XCTAssertFalse(saved.contains("properties:"))
        XCTAssertTrue(saved.contains("name: \"2026-05-17\""))
        XCTAssertTrue(saved.contains("Updated"))
        XCTAssertEqual(store.loadRowBody(rowId: "daily_2026-05-17", dbPath: dbURL.path), "# 2026-05-17\n\nUpdated")

        let index = IndexManager().rebuild(dbPath: dbURL.path, schema: schema, rows: [row])
        let rows = try XCTUnwrap(index["rows"] as? [String: [String: Any]])
        XCTAssertEqual(rows["daily_2026-05-17"]?["filename"] as? String, "2026-05-17")
    }

    private func makeDailySchema() -> DatabaseSchema {
        DatabaseSchema(
            id: "db_daily_notes",
            name: "Daily Notes Database",
            properties: [
                PropertyDefinition(id: "name", name: "Name", type: .title),
                PropertyDefinition(id: "date", name: "Date", type: .date)
            ],
            views: [ViewConfig(id: "view_daily_table", name: "Table", type: .table)],
            defaultView: "view_daily_table",
            createdAt: "2026-05-17T00:00:00Z"
        )
    }

    private func makeTemporaryDatabase() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("BugbookFirstPartyRowStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
