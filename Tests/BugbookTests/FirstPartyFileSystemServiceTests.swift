import XCTest
@testable import Bugbook
import BugbookCore

@MainActor
final class FirstPartyFileSystemServiceTests: XCTestCase {
    func testEnsureDailyNotesHubCreatesFirstPartyDatabaseAndTodayRow() throws {
        let service = FileSystemService()
        let workspace = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(atPath: workspace) }

        let date = try makeLocalDate(year: 2026, month: 5, day: 17, hour: 9, minute: 0)
        let databasePath = (workspace as NSString).appendingPathComponent("Daily Notes/Daily Notes Database")
        try FileManager.default.createDirectory(atPath: databasePath, withIntermediateDirectories: true)
        try writeSchema(staleDailyNotesSchema(), to: databasePath)

        let location = try service.ensureDailyNotesHub(in: workspace, date: date)

        XCTAssertEqual(location.hubPath, (workspace as NSString).appendingPathComponent("Daily Notes.md"))
        XCTAssertEqual(location.databasePath, databasePath)

        let hubContent = try String(contentsOfFile: location.hubPath, encoding: .utf8)
        XCTAssertTrue(hubContent.contains("# Daily Notes"))
        XCTAssertTrue(hubContent.contains("<!-- database: \(databasePath) -->"))

        let schema = try readSchema(at: databasePath)
        XCTAssertEqual(schema.id, "db_daily_notes")
        XCTAssertEqual(schema.properties.map(\.id), ["name", "date"])
        XCTAssertEqual(schema.views.map(\.type), [.table, .calendar])
        XCTAssertFalse(schema.properties.contains { ["tags", "status"].contains($0.id) })

        let rowPath = try XCTUnwrap(location.rowPath)
        XCTAssertEqual((rowPath as NSString).lastPathComponent, "Sunday, May 17th, 2026.md")

        let rowContent = try String(contentsOfFile: rowPath, encoding: .utf8)
        XCTAssertTrue(rowContent.contains("id: daily_2026-05-17"))
        XCTAssertTrue(rowContent.contains("name: \"Sunday, May 17th, 2026\""))
        XCTAssertTrue(rowContent.contains("date: 2026-05-17"))
        XCTAssertFalse(rowContent.contains("properties:"))

        let row = try XCTUnwrap(RowSerializer.parse(content: rowContent, schema: schema))
        XCTAssertEqual(row.properties["name"], .text("Sunday, May 17th, 2026"))
        XCTAssertEqual(row.properties["date"], .date("2026-05-17"))

        let rows = try readIndexRows(at: databasePath)
        let indexedRow = try XCTUnwrap(rows["daily_2026-05-17"])
        XCTAssertEqual(indexedRow["filename"] as? String, "Sunday, May 17th, 2026")
        XCTAssertEqual(
            service.firstPartyPagePathForDatabaseRow(dbPath: databasePath, rowId: "daily_2026-05-17"),
            rowPath
        )
    }

    func testEnsureDailyNotesHubMigratesLegacyNumericRowsToHumanDateTitles() throws {
        let service = FileSystemService()
        let workspace = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(atPath: workspace) }

        let databasePath = (workspace as NSString).appendingPathComponent("Daily Notes/Daily Notes Database")
        try FileManager.default.createDirectory(atPath: databasePath, withIntermediateDirectories: true)
        let legacyPath = (databasePath as NSString).appendingPathComponent("2026-05-17.md")
        try """
        ---
        id: daily_2026-05-17
        name: "2026-05-17"
        date: 2026-05-17
        ---

        # 2026-05-17

        Existing notes
        """.write(toFile: legacyPath, atomically: true, encoding: .utf8)

        let date = try makeLocalDate(year: 2026, month: 5, day: 18, hour: 9, minute: 0)
        _ = try service.ensureDailyNotesHub(in: workspace, date: date)

        let migratedPath = (databasePath as NSString).appendingPathComponent("Sunday, May 17th, 2026.md")
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacyPath))
        XCTAssertTrue(FileManager.default.fileExists(atPath: migratedPath))

        let schema = try readSchema(at: databasePath)
        let migratedContent = try String(contentsOfFile: migratedPath, encoding: .utf8)
        XCTAssertTrue(migratedContent.contains("name: \"Sunday, May 17th, 2026\""))
        XCTAssertTrue(migratedContent.contains("# Sunday, May 17th, 2026"))
        XCTAssertTrue(migratedContent.contains("Existing notes"))

        let row = try XCTUnwrap(RowSerializer.parse(content: migratedContent, schema: schema))
        XCTAssertEqual(row.properties["name"], .text("Sunday, May 17th, 2026"))

        let rows = try readIndexRows(at: databasePath)
        let indexedRow = try XCTUnwrap(rows["daily_2026-05-17"])
        XCTAssertEqual(indexedRow["filename"] as? String, "Sunday, May 17th, 2026")
    }

    func testEnsureMeetingsHubAndCreateMeetingRowUseFriendlyMarkdown() throws {
        let service = FileSystemService()
        let workspace = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(atPath: workspace) }

        let date = try makeLocalDate(year: 2026, month: 5, day: 17, hour: 14, minute: 30)
        let location = try service.createMeetingDatabaseRow(
            in: workspace,
            title: "Parent Interview",
            date: date,
            durationMinutes: 45,
            attendees: ["Alice", "Bob"],
            body: "# Parent Interview\n\nFull transcript"
        )

        XCTAssertEqual(location.hubPath, (workspace as NSString).appendingPathComponent("Meetings.md"))
        XCTAssertEqual(
            location.databasePath,
            (workspace as NSString).appendingPathComponent("Meetings/Meetings Database")
        )

        let hubContent = try String(contentsOfFile: location.hubPath, encoding: .utf8)
        XCTAssertTrue(hubContent.contains("# Meetings"))
        XCTAssertTrue(hubContent.contains("<!-- database: \(location.databasePath) -->"))

        let schema = try readSchema(at: location.databasePath)
        XCTAssertEqual(schema.id, "db_meetings")
        XCTAssertEqual(schema.properties.map(\.id), ["name", "date", "duration_minutes", "attendees"])
        XCTAssertEqual(schema.views.map(\.type), [.table, .calendar])

        let rowPath = try XCTUnwrap(location.rowPath)
        XCTAssertEqual((rowPath as NSString).lastPathComponent, "2026-05-17 1430 Parent Interview.md")

        let rowContent = try String(contentsOfFile: rowPath, encoding: .utf8)
        XCTAssertTrue(rowContent.contains("id: meeting_"))
        XCTAssertTrue(rowContent.contains("type: meeting"))
        XCTAssertTrue(rowContent.contains("meeting_id: meeting_"))
        XCTAssertTrue(rowContent.contains("name: \"Parent Interview\""))
        XCTAssertTrue(rowContent.contains("duration_minutes: 45"))
        XCTAssertTrue(rowContent.contains("duration: 45m"))
        XCTAssertTrue(rowContent.contains("attendees: [Alice, Bob]"))
        XCTAssertTrue(rowContent.contains("Full transcript"))
        XCTAssertFalse(rowContent.contains("properties:"))

        let row = try XCTUnwrap(RowSerializer.parse(content: rowContent, schema: schema))
        XCTAssertEqual(row.properties["name"], .text("Parent Interview"))
        XCTAssertEqual(row.properties["duration_minutes"], .number(45))
        XCTAssertEqual(row.properties["attendees"], .multiSelect(["Alice", "Bob"]))

        let rows = try readIndexRows(at: location.databasePath)
        let indexedRow = try XCTUnwrap(rows[row.id])
        XCTAssertEqual(indexedRow["filename"] as? String, "2026-05-17 1430 Parent Interview")
        XCTAssertEqual(
            service.firstPartyPagePathForDatabaseRow(dbPath: location.databasePath, rowId: row.id),
            rowPath
        )
        XCTAssertEqual(service.rowFilePathForDatabaseRow(dbPath: location.databasePath, rowId: row.id), rowPath)
    }

    func testEnsureDailyNotesHubCreatesMissingWorkspaceDirectory() throws {
        let service = FileSystemService()
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(atPath: root) }
        let workspace = (root as NSString).appendingPathComponent("Missing Bugbook")
        let date = try makeLocalDate(year: 2026, month: 6, day: 4, hour: 9, minute: 0)

        let location = try service.ensureDailyNotesHub(in: workspace, date: date)

        XCTAssertTrue(FileManager.default.fileExists(atPath: workspace))
        XCTAssertTrue(FileManager.default.fileExists(atPath: location.hubPath))
        XCTAssertTrue(FileManager.default.fileExists(atPath: location.databasePath))
        XCTAssertTrue(FileManager.default.fileExists(atPath: try XCTUnwrap(location.rowPath)))
    }

    func testEnsureMeetingsHubCreatesMissingWorkspaceDirectory() throws {
        let service = FileSystemService()
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(atPath: root) }
        let workspace = (root as NSString).appendingPathComponent("Missing Bugbook")

        let location = try service.ensureMeetingsHub(in: workspace)

        XCTAssertTrue(FileManager.default.fileExists(atPath: workspace))
        XCTAssertTrue(FileManager.default.fileExists(atPath: location.hubPath))
        XCTAssertTrue(FileManager.default.fileExists(atPath: location.databasePath))
    }

    func testMeetingRowEscapesYamlTitleAndSanitizesFilename() throws {
        let service = FileSystemService()
        let workspace = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(atPath: workspace) }

        let title = "Parent \"Alpha\" / Follow-up: pricing?"
        let date = try makeLocalDate(year: 2026, month: 5, day: 17, hour: 14, minute: 30)
        let location = try service.createMeetingDatabaseRow(
            in: workspace,
            title: title,
            date: date,
            attendees: ["Alice"],
            body: "# \(title)\n"
        )

        let rowPath = try XCTUnwrap(location.rowPath)
        XCTAssertEqual(
            (rowPath as NSString).lastPathComponent,
            "2026-05-17 1430 Parent Alpha - Follow-up - pricing.md"
        )

        let rowContent = try String(contentsOfFile: rowPath, encoding: .utf8)
        XCTAssertTrue(rowContent.contains("name: \"Parent \\\"Alpha\\\" / Follow-up: pricing?\""))
        XCTAssertTrue(rowContent.contains("# Parent \"Alpha\" / Follow-up: pricing?"))

        let row = try XCTUnwrap(RowSerializer.parse(
            content: rowContent,
            schema: readSchema(at: location.databasePath)
        ))
        XCTAssertEqual(row.properties["name"], .text(title))

        let rows = try readIndexRows(at: location.databasePath)
        let indexedRow = try XCTUnwrap(rows[row.id])
        let properties = try XCTUnwrap(indexedRow["properties"] as? [String: Any])
        XCTAssertEqual(properties["name"] as? String, title)
        XCTAssertEqual(indexedRow["filename"] as? String, "2026-05-17 1430 Parent Alpha - Follow-up - pricing")
    }

    func testRefreshingFirstPartyRowFileUpdatesDatabaseIndex() throws {
        let service = FileSystemService()
        let workspace = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(atPath: workspace) }

        let date = try makeLocalDate(year: 2026, month: 5, day: 17, hour: 14, minute: 30)
        let location = try service.createMeetingDatabaseRow(
            in: workspace,
            title: "Parent Interview",
            date: date,
            durationMinutes: 45,
            attendees: ["Alice"],
            body: "# Parent Interview\n"
        )
        let rowPath = try XCTUnwrap(location.rowPath)
        let originalContent = try String(contentsOfFile: rowPath, encoding: .utf8)
        let updatedContent = originalContent
            .replacingOccurrences(of: "name: \"Parent Interview\"", with: "name: \"Updated Interview\"")
            .replacingOccurrences(of: "# Parent Interview", with: "# Updated Interview")
        try updatedContent.write(toFile: rowPath, atomically: true, encoding: .utf8)

        try service.refreshFirstPartyDatabaseIndexForRowFile(at: rowPath)

        let row = try XCTUnwrap(RowSerializer.parse(
            content: updatedContent,
            schema: readSchema(at: location.databasePath)
        ))
        let rows = try readIndexRows(at: location.databasePath)
        let indexedRow = try XCTUnwrap(rows[row.id])
        let properties = try XCTUnwrap(indexedRow["properties"] as? [String: Any])
        XCTAssertEqual(properties["name"] as? String, "Updated Interview")
        XCTAssertEqual(indexedRow["filename"] as? String, "2026-05-17 1430 Parent Interview")
    }

    func testFirstPartyIndexWorkerRefreshesRowFile() async throws {
        let service = FileSystemService()
        let workspace = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(atPath: workspace) }

        let date = try makeLocalDate(year: 2026, month: 5, day: 17, hour: 14, minute: 30)
        let location = try service.createMeetingDatabaseRow(
            in: workspace,
            title: "Parent Interview",
            date: date,
            durationMinutes: 45,
            attendees: ["Alice"],
            body: "# Parent Interview\n"
        )
        let rowPath = try XCTUnwrap(location.rowPath)
        let originalContent = try String(contentsOfFile: rowPath, encoding: .utf8)
        let updatedContent = originalContent
            .replacingOccurrences(of: "name: \"Parent Interview\"", with: "name: \"Async Updated\"")
            .replacingOccurrences(of: "# Parent Interview", with: "# Async Updated")
        try updatedContent.write(toFile: rowPath, atomically: true, encoding: .utf8)

        let schema = try readSchema(at: location.databasePath)
        try await FirstPartyDatabaseIndexWorker().refreshRowFile(at: rowPath, schema: schema)

        let row = try XCTUnwrap(RowSerializer.parse(content: updatedContent, schema: schema))
        let rows = try readIndexRows(at: location.databasePath)
        let indexedRow = try XCTUnwrap(rows[row.id])
        let properties = try XCTUnwrap(indexedRow["properties"] as? [String: Any])
        XCTAssertEqual(properties["name"] as? String, "Async Updated")
    }

    func testSynchronizingMeetingRowFilenameUsesEditedTitleAndReindexes() throws {
        let service = FileSystemService()
        let workspace = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(atPath: workspace) }

        let date = try makeLocalDate(year: 2026, month: 5, day: 17, hour: 14, minute: 30)
        let location = try service.createMeetingDatabaseRow(
            in: workspace,
            title: "Parent Interview",
            date: date,
            durationMinutes: 45,
            attendees: ["Alice"],
            body: "# Parent Interview\n"
        )
        let rowPath = try XCTUnwrap(location.rowPath)
        let originalContent = try String(contentsOfFile: rowPath, encoding: .utf8)
        let updatedContent = originalContent
            .replacingOccurrences(of: "name: \"Parent Interview\"", with: "name: \"Updated/Interview\"")
            .replacingOccurrences(of: "# Parent Interview", with: "# Updated/Interview")
        try updatedContent.write(toFile: rowPath, atomically: true, encoding: .utf8)

        let newPath = try service.synchronizeMeetingRowFilename(rowPath: rowPath, title: "Updated/Interview")

        XCTAssertFalse(FileManager.default.fileExists(atPath: rowPath))
        XCTAssertTrue(FileManager.default.fileExists(atPath: newPath))
        XCTAssertEqual((newPath as NSString).lastPathComponent, "2026-05-17 1430 Updated - Interview.md")

        let row = try XCTUnwrap(RowSerializer.parse(
            content: updatedContent,
            schema: readSchema(at: location.databasePath)
        ))
        let rows = try readIndexRows(at: location.databasePath)
        let indexedRow = try XCTUnwrap(rows[row.id])
        let properties = try XCTUnwrap(indexedRow["properties"] as? [String: Any])
        XCTAssertEqual(properties["name"] as? String, "Updated/Interview")
        XCTAssertEqual(indexedRow["filename"] as? String, "2026-05-17 1430 Updated - Interview")
        XCTAssertEqual(service.firstPartyPagePathForDatabaseRow(dbPath: location.databasePath, rowId: row.id), newPath)
    }

    func testSynchronizingMeetingRowFilenameLeavesDailyRowsFixed() throws {
        let service = FileSystemService()
        let workspace = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(atPath: workspace) }

        let date = try makeLocalDate(year: 2026, month: 5, day: 17, hour: 9, minute: 0)
        let location = try service.ensureDailyNotesHub(in: workspace, date: date)
        let rowPath = try XCTUnwrap(location.rowPath)

        let newPath = try service.synchronizeMeetingRowFilename(rowPath: rowPath, title: "Renamed Daily Note")

        XCTAssertEqual(newPath, rowPath)
        XCTAssertTrue(FileManager.default.fileExists(atPath: rowPath))
        XCTAssertEqual((rowPath as NSString).lastPathComponent, "Sunday, May 17th, 2026.md")
    }

    func testFileTreeHidesFirstPartyBackingDatabases() throws {
        let service = FileSystemService()
        let workspace = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(atPath: workspace) }

        let date = try makeLocalDate(year: 2026, month: 5, day: 17, hour: 9, minute: 0)
        _ = try service.ensureDailyNotesHub(in: workspace, date: date)
        _ = try service.createMeetingDatabaseRow(
            in: workspace,
            title: "Parent Interview",
            date: date,
            body: "# Parent Interview\n"
        )

        let tree = service.buildFileTree(at: workspace)
        let names = flattenNames(tree)

        XCTAssertTrue(names.contains("Daily Notes.md"))
        XCTAssertTrue(names.contains("Meetings.md"))
        XCTAssertFalse(names.contains("Daily Notes"))
        XCTAssertFalse(names.contains("Daily Notes Database"))
        XCTAssertFalse(names.contains("Meetings Database"))
        XCTAssertFalse(names.contains("Sunday, May 17th, 2026.md"))
        XCTAssertFalse(names.contains("2026-05-17 0900 Parent Interview.md"))
    }

    private func makeTemporaryDirectory() throws -> String {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("BugbookFirstPartyFileSystemServiceTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root.path
    }

    private func makeLocalDate(
        year: Int,
        month: Int,
        day: Int,
        hour: Int,
        minute: Int
    ) throws -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return try XCTUnwrap(calendar.date(from: DateComponents(
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute
        )))
    }

    private func staleDailyNotesSchema() -> DatabaseSchema {
        DatabaseSchema(
            id: "db_daily_notes",
            name: "Daily Notes Database",
            properties: [
                PropertyDefinition(id: "name", name: "Name", type: .title),
                PropertyDefinition(id: "date", name: "Date", type: .date),
                PropertyDefinition(id: "status", name: "Status", type: .select),
                PropertyDefinition(id: "tags", name: "Tags", type: .multiSelect)
            ],
            views: [ViewConfig(id: "view_daily_table", name: "Table", type: .table)],
            defaultView: "view_daily_table",
            createdAt: "2026-01-01T00:00:00Z"
        )
    }

    private func writeSchema(_ schema: DatabaseSchema, to databasePath: String) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(schema)
        try data.write(to: URL(fileURLWithPath: databasePath).appendingPathComponent("_schema.json"))
    }

    private func readSchema(at databasePath: String) throws -> DatabaseSchema {
        let data = try Data(contentsOf: URL(fileURLWithPath: databasePath).appendingPathComponent("_schema.json"))
        return try JSONDecoder().decode(DatabaseSchema.self, from: data)
    }

    private func readIndexRows(at databasePath: String) throws -> [String: [String: Any]] {
        let data = try Data(contentsOf: URL(fileURLWithPath: databasePath).appendingPathComponent("_index.json"))
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return try XCTUnwrap(object?["rows"] as? [String: [String: Any]])
    }

    private func flattenNames(_ entries: [FileEntry]) -> [String] {
        entries.flatMap { entry in
            [entry.name] + flattenNames(entry.children ?? [])
        }
    }
}
