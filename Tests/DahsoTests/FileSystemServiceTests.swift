import XCTest
@testable import Dahso

@MainActor
final class FileSystemServiceTests: XCTestCase {
    private func makeTemporaryDirectory() throws -> String {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("DahsoTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root.path
    }

    private func setModificationDate(_ date: Date, at path: String) throws {
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: path)
    }

    func testMovePageMovesDatabaseFolderAsSingleItem() throws {
        let service = FileSystemService()
        let workspace = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(atPath: workspace) }

        let sourceDir = (workspace as NSString).appendingPathComponent("Source")
        let destDir = (workspace as NSString).appendingPathComponent("Parent Page")
        try FileManager.default.createDirectory(atPath: sourceDir, withIntermediateDirectories: true)

        let databasePath = try service.createDatabase(in: sourceDir, name: "Project Board")
        let movedPath = try service.movePage(at: databasePath, toDirectory: destDir)

        XCTAssertEqual(movedPath, (destDir as NSString).appendingPathComponent("Project Board"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: databasePath))
        XCTAssertTrue(FileManager.default.fileExists(atPath: (movedPath as NSString).appendingPathComponent("_schema.json")))
        XCTAssertTrue(FileManager.default.fileExists(atPath: (movedPath as NSString).appendingPathComponent("_index.json")))
    }

    func testMovePageRejectsMovingDatabaseIntoOwnChildren() throws {
        let service = FileSystemService()
        let workspace = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(atPath: workspace) }

        let databasePath = try service.createDatabase(in: workspace, name: "Project Board")
        let nestedDestination = (databasePath as NSString).appendingPathComponent("Nested")

        XCTAssertThrowsError(try service.movePage(at: databasePath, toDirectory: nestedDestination))
    }

    func testCreateDatabaseUnderPageUsesCompanionFolder() throws {
        let service = FileSystemService()
        let workspace = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(atPath: workspace) }

        let pagePath = (workspace as NSString).appendingPathComponent("Alignment Zone.md")
        try "# Alignment Zone\n".write(toFile: pagePath, atomically: true, encoding: .utf8)

        let databasePath = try service.createDatabase(underPage: pagePath, name: "Tasks")

        XCTAssertEqual(databasePath, (workspace as NSString).appendingPathComponent("Alignment Zone/Tasks"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: (databasePath as NSString).appendingPathComponent("_schema.json")))
    }

    func testRetargetDatabaseEmbedsInWorkspaceUpdatesStoredMarkers() throws {
        let service = FileSystemService()
        let workspace = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(atPath: workspace) }

        let oldDatabasePath = (workspace as NSString).appendingPathComponent("Project Board")
        let newDatabasePath = (workspace as NSString).appendingPathComponent("Alignment Zone/Project Board")
        let pagePath = (workspace as NSString).appendingPathComponent("Alignment Zone.md")
        let original = """
        # Alignment Zone

        <!-- database: \(oldDatabasePath) -->
        """
        try original.write(toFile: pagePath, atomically: true, encoding: .utf8)

        service.retargetDatabaseEmbedsInWorkspace(
            from: oldDatabasePath,
            to: newDatabasePath,
            workspace: workspace
        )

        let updated = try String(contentsOfFile: pagePath, encoding: .utf8)
        XCTAssertTrue(updated.contains("<!-- database: \(newDatabasePath) -->"))
        XCTAssertFalse(updated.contains("<!-- database: \(oldDatabasePath) -->"))
    }

    func testBuildFileTreeHidesCaptureStorageFolders() throws {
        let service = FileSystemService()
        let workspace = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(atPath: workspace) }

        let inboxPath = (workspace as NSString).appendingPathComponent("Inbox")
        let rawPath = (workspace as NSString).appendingPathComponent("raw")
        let attachmentsPath = (workspace as NSString).appendingPathComponent("Attachments")

        try FileManager.default.createDirectory(atPath: inboxPath, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(atPath: rawPath, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(atPath: attachmentsPath, withIntermediateDirectories: true)

        let inboxNote = (inboxPath as NSString).appendingPathComponent("Photo 2.03 PM.md")
        let rawNote = (rawPath as NSString).appendingPathComponent("2026-04-05-photo.md")
        let rootPage = (workspace as NSString).appendingPathComponent("Museum Notes.md")

        try "Inbox capture".write(toFile: inboxNote, atomically: true, encoding: .utf8)
        try "Raw capture".write(toFile: rawNote, atomically: true, encoding: .utf8)
        try "# Museum Notes\n".write(toFile: rootPage, atomically: true, encoding: .utf8)

        let tree = service.buildFileTree(at: workspace)
        let names = tree.map(\.name)

        XCTAssertTrue(names.contains("Museum Notes.md"))
        XCTAssertFalse(names.contains("Photo 2.03 PM.md"))
        XCTAssertFalse(names.contains("2026-04-05-photo.md"))
    }

    func testDetectLegacyWorkspacesFindsKnownLegacyRootsWithContent() throws {
        let service = FileSystemService()
        let homePath = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(atPath: homePath) }

        let homeURL = URL(fileURLWithPath: homePath, isDirectory: true)
        let dahsoLegacy = homeURL
            .appendingPathComponent("Library/Application Support/dahso", isDirectory: true)
        let bugbookSupport = homeURL
            .appendingPathComponent("Library/Application Support/com.bugbook.app", isDirectory: true)
        let bugbookICloud = homeURL
            .appendingPathComponent(
                "Library/Mobile Documents/iCloud~com~bugbook~app/Documents/Bugbook 2",
                isDirectory: true
            )

        try FileManager.default.createDirectory(at: dahsoLegacy, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: bugbookSupport, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: bugbookICloud, withIntermediateDirectories: true)

        try "legacy".write(
            to: dahsoLegacy.appendingPathComponent("Legacy.md"),
            atomically: true,
            encoding: .utf8
        )
        try "bugbook".write(
            to: bugbookSupport.appendingPathComponent("Inbox.md"),
            atomically: true,
            encoding: .utf8
        )
        try "icloud".write(
            to: bugbookICloud.appendingPathComponent("Workspace.md"),
            atomically: true,
            encoding: .utf8
        )

        let detected = service.detectLegacyWorkspaces(homeDirectory: homeURL)

        XCTAssertEqual(
            detected.map(\.kind),
            [.applicationSupportDahso, .bugbookApplicationSupport, .bugbookICloud]
        )
        XCTAssertEqual(detected.map(\.path), [dahsoLegacy, bugbookSupport, bugbookICloud])
    }

    func testDetectLegacyWorkspacesIgnoresExcludedTopLevelCacheFolders() throws {
        let service = FileSystemService()
        let homePath = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(atPath: homePath) }

        let homeURL = URL(fileURLWithPath: homePath, isDirectory: true)
        let dahsoLegacy = homeURL
            .appendingPathComponent("Library/Application Support/dahso", isDirectory: true)
        let cacheDirectory = dahsoLegacy.appendingPathComponent("MailCache", isDirectory: true)
        try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        try "cache".write(
            to: cacheDirectory.appendingPathComponent("state.db"),
            atomically: true,
            encoding: .utf8
        )

        XCTAssertTrue(service.detectLegacyWorkspaces(homeDirectory: homeURL).isEmpty)
    }

    func testMigrateLegacyWorkspaceCopiesMissingFilesAndPreservesNewerDestinationFiles() async throws {
        let service = FileSystemService()
        let legacyPath = try makeTemporaryDirectory()
        let destinationPath = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(atPath: legacyPath) }
        defer { try? FileManager.default.removeItem(atPath: destinationPath) }

        let legacyRoot = URL(fileURLWithPath: legacyPath, isDirectory: true)
        let destinationRoot = URL(fileURLWithPath: destinationPath, isDirectory: true)
        let legacyNotes = legacyRoot.appendingPathComponent("Notes", isDirectory: true)
        let destinationNotes = destinationRoot.appendingPathComponent("Notes", isDirectory: true)
        let legacyPlan = legacyNotes.appendingPathComponent("Plan.md")
        let destinationPlan = destinationNotes.appendingPathComponent("Plan.md")
        let legacyArchive = legacyRoot.appendingPathComponent("Archive.md")
        let cacheFile = legacyRoot
            .appendingPathComponent("MailCache", isDirectory: true)
            .appendingPathComponent("cache.db")

        try FileManager.default.createDirectory(at: legacyNotes, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destinationNotes, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: cacheFile.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        try "legacy plan".write(to: legacyPlan, atomically: true, encoding: .utf8)
        try "current plan".write(to: destinationPlan, atomically: true, encoding: .utf8)
        try "archive".write(to: legacyArchive, atomically: true, encoding: .utf8)
        try "cache".write(to: cacheFile, atomically: true, encoding: .utf8)

        let now = Date()
        try setModificationDate(now.addingTimeInterval(-3600), at: legacyPlan.path)
        try setModificationDate(now, at: destinationPlan.path)

        let legacyWorkspace = FileSystemService.LegacyWorkspace(
            path: legacyRoot,
            kind: .applicationSupportDahso
        )

        try await service.migrateLegacyWorkspace(legacyWorkspace, into: destinationRoot)

        XCTAssertEqual(
            try String(contentsOf: destinationPlan, encoding: .utf8),
            "current plan"
        )
        XCTAssertEqual(
            try String(contentsOf: destinationRoot.appendingPathComponent("Archive.md"), encoding: .utf8),
            "archive"
        )
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: destinationRoot.appendingPathComponent("MailCache/cache.db").path
            )
        )
    }
}
