import Foundation
import BugbookCore

actor FirstPartyDatabaseIndexWorker {
    func refreshRowFile(at rowPath: String, schema: DatabaseSchema) throws {
        let databasePath = (rowPath as NSString).deletingLastPathComponent
        try Self.rebuildIndex(at: databasePath, schema: schema)
    }

    nonisolated static func rebuildIndex(at databasePath: String, schema: DatabaseSchema) throws {
        let rowStore = RowStore()
        let rows = rowStore.loadAllRows(in: databasePath, schema: schema, skipBody: true)
        let indexManager = IndexManager()
        try indexManager.saveIndex(
            indexManager.rebuild(dbPath: databasePath, schema: schema, rows: rows),
            at: databasePath
        )
    }
}

enum FirstPartyDatabaseFiles {
    static func dailyNotePath(in workspace: String) -> String {
        let dateString = firstPartyDateString(from: Date())
        return dailyNotePath(in: workspace, dateString: dateString)
    }

    static func openOrCreateDailyNote(in workspace: String) throws -> String {
        try ensureDailyNotesHub(in: workspace).rowPath ?? dailyNotePath(in: workspace)
    }

    static func ensureDailyNotesHub(
        in workspace: String,
        date: Date = Date()
    ) throws -> FileSystemService.FirstPartyDatabaseLocation {
        let hubPath = (workspace as NSString).appendingPathComponent("Daily Notes.md")
        let companionPath = (workspace as NSString).appendingPathComponent("Daily Notes")
        let databasePath = (companionPath as NSString).appendingPathComponent("Daily Notes Database")
        let dateString = firstPartyDateString(from: date)
        let rowPath = dailyNotePath(in: workspace, dateString: dateString)

        try ensureHubPage(path: hubPath, title: "Daily Notes", databasePath: databasePath)
        let schema = dailyNotesSchema(createdAt: firstPartyISOString(from: date))
        try ensureFirstPartyDatabase(at: databasePath, schema: schema)
        try ensureDailyNoteRow(at: rowPath, dateString: dateString, date: date, schema: schema)

        return FileSystemService.FirstPartyDatabaseLocation(
            hubPath: hubPath,
            databasePath: databasePath,
            rowPath: rowPath
        )
    }

    static func ensureMeetingsHub(in workspace: String) throws -> FileSystemService.FirstPartyDatabaseLocation {
        let hubPath = (workspace as NSString).appendingPathComponent("Meetings.md")
        let companionPath = (workspace as NSString).appendingPathComponent("Meetings")
        let databasePath = (companionPath as NSString).appendingPathComponent("Meetings Database")

        try ensureHubPage(path: hubPath, title: "Meetings", databasePath: databasePath)
        try ensureFirstPartyDatabase(at: databasePath, schema: meetingsSchema())

        return FileSystemService.FirstPartyDatabaseLocation(
            hubPath: hubPath,
            databasePath: databasePath,
            rowPath: nil
        )
    }

    static func createMeetingDatabaseRow(
        in workspace: String,
        title: String,
        date: Date,
        durationMinutes: Int? = nil,
        attendees: [String] = [],
        body: String = ""
    ) throws -> FileSystemService.FirstPartyDatabaseLocation {
        let hub = try ensureMeetingsHub(in: workspace)
        let schema = meetingsSchema()
        let dateString = firstPartyISOString(from: date)
        let row = DatabaseRow(
            id: "meeting_\(UUID().uuidString.lowercased().replacingOccurrences(of: "-", with: ""))",
            properties: meetingProperties(
                title: title,
                dateString: dateString,
                durationMinutes: durationMinutes,
                attendees: attendees
            ),
            body: body,
            createdAt: date,
            updatedAt: date
        )
        let filename = uniqueMeetingRowFilename(title: title, date: date, in: hub.databasePath)
        let rowPath = (hub.databasePath as NSString).appendingPathComponent(filename)
        try RowSerializer.serializeFlat(
            row: row,
            schema: schema,
            extraScalars: meetingPageScalars(rowId: row.id, durationMinutes: durationMinutes)
        )
        .write(toFile: rowPath, atomically: true, encoding: .utf8)
        try FirstPartyDatabaseIndexWorker.rebuildIndex(at: hub.databasePath, schema: schema)

        return FileSystemService.FirstPartyDatabaseLocation(
            hubPath: hub.hubPath,
            databasePath: hub.databasePath,
            rowPath: rowPath
        )
    }

    static func refreshMeetingsDatabaseIndex(in workspace: String) throws {
        let location = try ensureMeetingsHub(in: workspace)
        try FirstPartyDatabaseIndexWorker.rebuildIndex(at: location.databasePath, schema: meetingsSchema())
    }

    static func refreshFirstPartyDatabaseIndexForRowFile(at rowPath: String) throws {
        let databasePath = (rowPath as NSString).deletingLastPathComponent
        guard isFirstPartyDatabasePath(databasePath),
              let schema = readSchema(
                at: (databasePath as NSString).appendingPathComponent("_schema.json")
              ) ?? firstPartySchema(forDatabasePath: databasePath) else {
            return
        }
        try FirstPartyDatabaseIndexWorker.rebuildIndex(at: databasePath, schema: schema)
    }

    static func firstPartyDatabaseKindForRowFile(at rowPath: String) -> FileSystemService.FirstPartyDatabaseKind? {
        firstPartyDatabaseKind(forDatabasePath: (rowPath as NSString).deletingLastPathComponent)
    }

    static func firstPartySchemaForRowFile(at rowPath: String) -> DatabaseSchema? {
        firstPartySchema(forDatabasePath: (rowPath as NSString).deletingLastPathComponent)
    }

    static func synchronizeMeetingRowFilename(rowPath: String, title: String) throws -> String {
        let databasePath = (rowPath as NSString).deletingLastPathComponent
        guard firstPartyDatabaseKind(forDatabasePath: databasePath) == .meetings else { return rowPath }

        let sanitizedTitle = sanitizeFirstPartyFilename(title)
        guard !sanitizedTitle.isEmpty else { return rowPath }

        let currentBase = ((rowPath as NSString).lastPathComponent as NSString).deletingPathExtension
        let prefix = meetingFilenamePrefix(from: currentBase)
            ?? meetingFilenamePrefix(fromFrontmatterAt: rowPath)
        let desiredBase = [prefix, sanitizedTitle].compactMap(\.self).joined(separator: " ")
        guard desiredBase != currentBase else {
            try FirstPartyDatabaseIndexWorker.rebuildIndex(at: databasePath, schema: meetingsSchema())
            return rowPath
        }

        let newFilename = uniqueFilename(in: databasePath, base: desiredBase, ext: "md")
        let newPath = (databasePath as NSString).appendingPathComponent(newFilename)
        try FileManager.default.moveItem(atPath: rowPath, toPath: newPath)
        try FirstPartyDatabaseIndexWorker.rebuildIndex(at: databasePath, schema: meetingsSchema())
        return newPath
    }

    static func firstPartyPagePathForDatabaseRow(dbPath: String, rowId: String) -> String? {
        guard isFirstPartyDatabasePath(dbPath) else { return nil }
        return rowFilePathForDatabaseRow(dbPath: dbPath, rowId: rowId)
    }

    static func rowFilePathForDatabaseRow(dbPath: String, rowId: String) -> String? {
        guard let contents = try? FileManager.default.contentsOfDirectory(atPath: dbPath) else { return nil }

        let suffix = rowId.hasPrefix("row_") ? String(rowId.dropFirst(4)) : rowId
        for name in contents where name.hasSuffix(".md") && name.contains("(\(suffix))") {
            return (dbPath as NSString).appendingPathComponent(name)
        }

        for name in contents where name.hasSuffix(".md") && !name.hasPrefix("_") {
            let filePath = (dbPath as NSString).appendingPathComponent(name)
            guard let content = try? String(contentsOfFile: filePath, encoding: .utf8),
                  extractFrontmatterScalar("id", from: content) == rowId else {
                continue
            }
            return filePath
        }

        return nil
    }

    private static func dailyNotePath(in workspace: String, dateString: String) -> String {
        let databasePath = (workspace as NSString)
            .appendingPathComponent("Daily Notes/Daily Notes Database")
        return (databasePath as NSString).appendingPathComponent("\(dateString).md")
    }

    private static func ensureDailyNoteRow(
        at rowPath: String,
        dateString: String,
        date: Date,
        schema: DatabaseSchema
    ) throws {
        guard !FileManager.default.fileExists(atPath: rowPath) else { return }
        let row = DatabaseRow(
            id: "daily_\(dateString)",
            properties: [
                "name": .text(dateString),
                "date": .date(dateString)
            ],
            body: "# \(dateString)\n\n",
            createdAt: date,
            updatedAt: date
        )
        try RowSerializer.serializeFlat(row: row, schema: schema)
            .write(toFile: rowPath, atomically: true, encoding: .utf8)
        try FirstPartyDatabaseIndexWorker.rebuildIndex(
            at: (rowPath as NSString).deletingLastPathComponent,
            schema: schema
        )
    }

    private static func ensureHubPage(path: String, title: String, databasePath: String) throws {
        let marker = "<!-- database: \(databasePath) -->"
        if !FileManager.default.fileExists(atPath: path) {
            let content = "# \(title)\n\n\(marker)\n"
            try content.write(toFile: path, atomically: true, encoding: .utf8)
            return
        }

        let content = try String(contentsOfFile: path, encoding: .utf8)
        guard !content.contains(marker) else { return }
        let separator = content.hasSuffix("\n") ? "\n" : "\n\n"
        try (content + separator + marker + "\n").write(toFile: path, atomically: true, encoding: .utf8)
    }

    private static func ensureFirstPartyDatabase(at path: String, schema: DatabaseSchema) throws {
        if !FileManager.default.fileExists(atPath: path) {
            try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        }

        let schemaPath = (path as NSString).appendingPathComponent("_schema.json")
        try ensureFirstPartySchema(schema, at: schemaPath)

        let indexPath = (path as NSString).appendingPathComponent("_index.json")
        if !FileManager.default.fileExists(atPath: indexPath) {
            try writeEmptyIndex(to: indexPath)
        }
    }

    private static func ensureFirstPartySchema(_ schema: DatabaseSchema, at path: String) throws {
        var canonicalSchema = schema
        if let existingSchema = readSchema(at: path) {
            if existingSchema.id == schema.id {
                canonicalSchema.createdAt = existingSchema.createdAt
            }
            if firstPartySchema(existingSchema, matches: canonicalSchema) {
                return
            }
        }

        try writeSchema(canonicalSchema, to: path)
    }

    private static func readSchema(at path: String) -> DatabaseSchema? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return nil }
        return try? JSONDecoder().decode(DatabaseSchema.self, from: data)
    }

    private static func firstPartySchema(_ existingSchema: DatabaseSchema, matches canonicalSchema: DatabaseSchema) -> Bool {
        guard let existingData = encodedSchemaData(existingSchema),
              let canonicalData = encodedSchemaData(canonicalSchema) else {
            return false
        }
        return existingData == canonicalData
    }

    private static func encodedSchemaData(_ schema: DatabaseSchema) -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try? encoder.encode(schema)
    }

    private static func writeSchema(_ schema: DatabaseSchema, to path: String) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(schema)
        try data.write(to: URL(fileURLWithPath: path), options: .atomic)
    }

    private static func writeEmptyIndex(to path: String) throws {
        let json: [String: Any] = [
            "version": 1,
            "updated_at": firstPartyISOString(from: Date()),
            "rows": [:] as [String: Any],
            "indexes": [:] as [String: Any]
        ]
        let data = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: URL(fileURLWithPath: path), options: .atomic)
    }

    private static func dailyNotesSchema(createdAt: String) -> DatabaseSchema {
        DatabaseSchema(
            id: "db_daily_notes",
            name: "Daily Notes Database",
            properties: [
                PropertyDefinition(id: "name", name: "Name", type: .title),
                PropertyDefinition(id: "date", name: "Date", type: .date)
            ],
            views: [
                ViewConfig(
                    id: "view_daily_table",
                    name: "Table",
                    type: .table,
                    sorts: [SortConfig(id: "sort_daily_date_desc", property: "date", direction: "desc")]
                ),
                ViewConfig(
                    id: "view_daily_calendar",
                    name: "Calendar",
                    type: .calendar,
                    dateProperty: "date"
                )
            ],
            defaultView: "view_daily_table",
            createdAt: createdAt
        )
    }

    private static func meetingsSchema() -> DatabaseSchema {
        DatabaseSchema(
            id: "db_meetings",
            name: "Meetings Database",
            properties: [
                PropertyDefinition(id: "name", name: "Name", type: .title),
                PropertyDefinition(id: "date", name: "Date", type: .date),
                PropertyDefinition(id: "duration_minutes", name: "Duration", type: .number),
                PropertyDefinition(id: "attendees", name: "Attendees", type: .multiSelect)
            ],
            views: [
                ViewConfig(
                    id: "view_meetings_table",
                    name: "Table",
                    type: .table,
                    sorts: [SortConfig(id: "sort_meetings_date_desc", property: "date", direction: "desc")]
                ),
                ViewConfig(
                    id: "view_meetings_calendar",
                    name: "Calendar",
                    type: .calendar,
                    dateProperty: "date"
                )
            ],
            defaultView: "view_meetings_table",
            createdAt: firstPartyISOString(from: Date())
        )
    }

    private static func meetingProperties(
        title: String,
        dateString: String,
        durationMinutes: Int?,
        attendees: [String]
    ) -> [String: PropertyValue] {
        var properties: [String: PropertyValue] = [
            "name": .text(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "New Meeting" : title),
            "date": .date(dateString)
        ]
        if let durationMinutes {
            properties["duration_minutes"] = .number(Double(durationMinutes))
        }
        if !attendees.isEmpty {
            properties["attendees"] = .multiSelect(attendees)
        }
        return properties
    }

    private static func meetingPageScalars(rowId: String, durationMinutes: Int?) -> [(key: String, value: String)] {
        var scalars: [(key: String, value: String)] = [
            ("type", "meeting"),
            ("meeting_id", rowId)
        ]
        if let durationMinutes {
            scalars.append(("duration", "\(durationMinutes)m"))
        }
        return scalars
    }

    private static func isFirstPartyDatabasePath(_ path: String) -> Bool {
        firstPartyDatabaseKind(forDatabasePath: path) != nil
    }

    private static func firstPartyDatabaseKind(
        forDatabasePath path: String
    ) -> FileSystemService.FirstPartyDatabaseKind? {
        let name = (path as NSString).lastPathComponent
        let parent = ((path as NSString).deletingLastPathComponent as NSString).lastPathComponent
        if name == "Daily Notes Database" && parent == "Daily Notes" {
            return .dailyNotes
        }
        if name == "Meetings Database" && parent == "Meetings" {
            return .meetings
        }
        return nil
    }

    private static func firstPartySchema(forDatabasePath path: String) -> DatabaseSchema? {
        switch firstPartyDatabaseKind(forDatabasePath: path) {
        case .dailyNotes:
            return dailyNotesSchema(createdAt: firstPartyISOString(from: Date()))
        case .meetings:
            return meetingsSchema()
        case nil:
            return nil
        }
    }

    private static func uniqueMeetingRowFilename(title: String, date: Date, in databasePath: String) -> String {
        let timestamp = meetingFilenameDateString(from: date)
        let sanitizedTitle = sanitizeFirstPartyFilename(title)
        let baseTitle = sanitizedTitle.isEmpty ? "New Meeting" : sanitizedTitle
        let baseName = "\(timestamp) \(baseTitle)"
        return uniqueFilename(in: databasePath, base: baseName, ext: "md")
    }

    private static func meetingFilenamePrefix(from baseName: String) -> String? {
        let prefix = String(baseName.prefix(15))
        guard prefix.count == 15,
              prefix[prefix.index(prefix.startIndex, offsetBy: 4)] == "-",
              prefix[prefix.index(prefix.startIndex, offsetBy: 7)] == "-",
              prefix[prefix.index(prefix.startIndex, offsetBy: 10)] == " ",
              prefix.dropFirst(11).allSatisfy(\.isNumber) else {
            return nil
        }
        return prefix
    }

    private static func meetingFilenamePrefix(fromFrontmatterAt rowPath: String) -> String? {
        guard let content = try? String(contentsOfFile: rowPath, encoding: .utf8),
              let rawDate = extractFrontmatterScalar("date", from: content),
              let date = firstPartyISODate(from: rawDate) else {
            return nil
        }
        return meetingFilenameDateString(from: date)
    }

    private static func sanitizeFirstPartyFilename(_ name: String) -> String {
        name
            .replacingOccurrences(of: "[/\\\\:]", with: " - ", options: .regularExpression)
            .replacingOccurrences(of: "[?%*|\"<>]", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix(80)
            .description
    }

    private static func uniqueFilename(in directory: String, base: String, ext: String) -> String {
        var name = "\(base).\(ext)"
        var counter = 2
        while FileManager.default.fileExists(atPath: (directory as NSString).appendingPathComponent(name)) {
            name = "\(base) \(counter).\(ext)"
            counter += 1
        }
        return name
    }

    private static func extractFrontmatterScalar(_ key: String, from content: String) -> String? {
        guard content.hasPrefix("---") else { return nil }
        let afterFirst = content.index(content.startIndex, offsetBy: 3)
        guard let endRange = content.range(of: "\n---", range: afterFirst..<content.endIndex) else {
            return nil
        }
        let frontmatter = content[afterFirst..<endRange.lowerBound]
        for rawLine in frontmatter.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("\(key):") else { continue }
            let rawValue = line.dropFirst(key.count + 1).trimmingCharacters(in: .whitespaces)
            guard !rawValue.isEmpty else { return nil }
            if rawValue.hasPrefix("\""), rawValue.hasSuffix("\""), rawValue.count >= 2 {
                return String(rawValue.dropFirst().dropLast())
            }
            return rawValue
        }
        return nil
    }

    private static func firstPartyDateString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private static func meetingFilenameDateString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HHmm"
        return formatter.string(from: date)
    }

    private static func firstPartyISOString(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    private static func firstPartyISODate(from string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }
}
