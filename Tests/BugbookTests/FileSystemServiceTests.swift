import XCTest
@testable import Bugbook

@MainActor
final class FileSystemServiceTests: XCTestCase {
    private func makeTemporaryDirectory() throws -> String {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("BugbookTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root.path
    }

    private func setModificationDate(_ date: Date, at path: String) throws {
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: path)
    }

    private func inodeNumber(at path: String) throws -> NSNumber {
        let attributes = try FileManager.default.attributesOfItem(atPath: path)
        guard let inode = attributes[.systemFileNumber] as? NSNumber else {
            throw XCTSkip("systemFileNumber was unavailable for \(path)")
        }
        return inode
    }

    private func subpaths(in path: String) throws -> [String] {
        try FileManager.default.subpathsOfDirectory(atPath: path)
    }

    func testFileSystemServiceInitDoesNotScanLegacyWorkspaces() {
        let service = FileSystemService()

        XCTAssertTrue(
            service.legacyWorkspaces.isEmpty,
            "Startup construction should not scan home-directory legacy workspace candidates."
        )
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

    func testRenameMarkdownFileMovesCompanionFolder() throws {
        let service = FileSystemService()
        let workspace = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(atPath: workspace) }

        let oldPath = (workspace as NSString).appendingPathComponent("Old Title.md")
        let oldCompanion = (workspace as NSString).appendingPathComponent("Old Title")
        let childPath = (oldCompanion as NSString).appendingPathComponent("Child.md")
        let newPath = (workspace as NSString).appendingPathComponent("New Title.md")
        let newChildPath = ((workspace as NSString).appendingPathComponent("New Title") as NSString)
            .appendingPathComponent("Child.md")

        try "# Old Title\n".write(toFile: oldPath, atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(atPath: oldCompanion, withIntermediateDirectories: true)
        try "# Child\n".write(toFile: childPath, atomically: true, encoding: .utf8)

        try service.renameFile(from: oldPath, to: newPath)

        XCTAssertFalse(FileManager.default.fileExists(atPath: oldPath))
        XCTAssertFalse(FileManager.default.fileExists(atPath: oldCompanion))
        XCTAssertTrue(FileManager.default.fileExists(atPath: newPath))
        XCTAssertTrue(FileManager.default.fileExists(atPath: newChildPath))
    }

    func testRenameMarkdownFileRejectsCompanionFolderConflict() throws {
        let service = FileSystemService()
        let workspace = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(atPath: workspace) }

        let oldPath = (workspace as NSString).appendingPathComponent("Old Title.md")
        let oldCompanion = (workspace as NSString).appendingPathComponent("Old Title")
        let newPath = (workspace as NSString).appendingPathComponent("New Title.md")
        let newCompanion = (workspace as NSString).appendingPathComponent("New Title")

        try "# Old Title\n".write(toFile: oldPath, atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(atPath: oldCompanion, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(atPath: newCompanion, withIntermediateDirectories: true)

        XCTAssertThrowsError(try service.renameFile(from: oldPath, to: newPath))
        XCTAssertTrue(FileManager.default.fileExists(atPath: oldPath))
        XCTAssertTrue(FileManager.default.fileExists(atPath: oldCompanion))
        XCTAssertFalse(FileManager.default.fileExists(atPath: newPath))
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

    func testResolveFavoritesPreservesNestedChildren() throws {
        let service = FileSystemService()
        let workspace = try makeTemporaryDirectory()
        defer {
            service.saveFavoritePaths([], for: workspace)
            try? FileManager.default.removeItem(atPath: workspace)
        }

        let hubPath = (workspace as NSString).appendingPathComponent("Knowledge Vault.md")
        let companionPath = (workspace as NSString).appendingPathComponent("Knowledge Vault")
        let childPath = (companionPath as NSString).appendingPathComponent("Agent Flow.md")
        try "# Knowledge Vault\n".write(toFile: hubPath, atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(atPath: companionPath, withIntermediateDirectories: true)
        try "# Agent Flow\n".write(toFile: childPath, atomically: true, encoding: .utf8)

        service.saveFavoritePaths([hubPath], for: workspace)
        let tree = service.buildFileTree(at: workspace)
        let favorites = service.resolveFavorites(for: workspace, fileTree: tree)

        let favorite = try XCTUnwrap(favorites.first)
        XCTAssertEqual(favorite.id, "favorite:\(hubPath)")
        XCTAssertEqual(favorite.name, "Knowledge Vault.md")
        XCTAssertEqual(favorite.children?.map(\.name), ["Agent Flow.md"])
    }

    func testResolveFavoritesDropsFirstPartySidebarFavorites() throws {
        let service = FileSystemService()
        let workspace = try makeTemporaryDirectory()
        defer {
            service.saveFavoritePaths([], for: workspace)
            try? FileManager.default.removeItem(atPath: workspace)
        }

        let dailyNotesPath = (workspace as NSString).appendingPathComponent("Daily Notes.md")
        let meetingsPath = (workspace as NSString).appendingPathComponent("Meetings.md")
        let favoritePath = (workspace as NSString).appendingPathComponent("Knowledge Vault.md")
        try "# Daily Notes\n".write(toFile: dailyNotesPath, atomically: true, encoding: .utf8)
        try "# Meetings\n".write(toFile: meetingsPath, atomically: true, encoding: .utf8)
        try "# Knowledge Vault\n".write(toFile: favoritePath, atomically: true, encoding: .utf8)

        service.saveFavoritePaths([dailyNotesPath, favoritePath, meetingsPath], for: workspace)
        let tree = service.buildFileTree(at: workspace)
        let favorites = service.resolveFavorites(for: workspace, fileTree: tree)

        XCTAssertEqual(favorites.map(\.path), [favoritePath])
        XCTAssertEqual(service.favoritePaths(for: workspace), [favoritePath])
    }

    func testReorderFavoritePathPersistsVisibleOrder() throws {
        let service = FileSystemService()
        let workspace = try makeTemporaryDirectory()
        defer {
            service.saveFavoritePaths([], for: workspace)
            try? FileManager.default.removeItem(atPath: workspace)
        }

        let first = (workspace as NSString).appendingPathComponent("Action Zone.md")
        let second = (workspace as NSString).appendingPathComponent("Alignment Zone.md")
        let third = (workspace as NSString).appendingPathComponent("Knowledge Vault.md")
        service.saveFavoritePaths([first, second, third], for: workspace)

        service.reorderFavoritePath(
            first,
            toVisibleIndex: 3,
            visiblePaths: [first, second, third],
            for: workspace
        )

        XCTAssertEqual(service.favoritePaths(for: workspace), [second, third, first])
    }

    func testDetectLegacyWorkspacesFindsKnownLegacyRootsWithContent() throws {
        let service = FileSystemService()
        let homePath = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(atPath: homePath) }

        let homeURL = URL(fileURLWithPath: homePath, isDirectory: true)
        let dahsoDocuments = homeURL
            .appendingPathComponent("Documents/Dahso", isDirectory: true)
        let dahsoSupport = homeURL
            .appendingPathComponent("Library/Application Support/Dahso", isDirectory: true)
        let dahsoICloud = homeURL
            .appendingPathComponent(
                "Library/Mobile Documents/iCloud~com~dahso~app/Documents/Dahso",
                isDirectory: true
            )
        let bugbookLegacy = homeURL
            .appendingPathComponent("Library/Application Support/bugbook", isDirectory: true)
        let bugbookSupport = homeURL
            .appendingPathComponent("Library/Application Support/com.bugbook.app", isDirectory: true)
        let bugbookICloud = homeURL
            .appendingPathComponent(
                "Library/Mobile Documents/iCloud~com~bugbook~app/Documents/Bugbook 2",
                isDirectory: true
            )

        try FileManager.default.createDirectory(at: dahsoDocuments, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dahsoSupport, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dahsoICloud, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: bugbookLegacy, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: bugbookSupport, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: bugbookICloud, withIntermediateDirectories: true)

        try "documents".write(
            to: dahsoDocuments.appendingPathComponent("Meeting.md"),
            atomically: true,
            encoding: .utf8
        )
        try "support".write(
            to: dahsoSupport.appendingPathComponent("Local.md"),
            atomically: true,
            encoding: .utf8
        )
        try "dahso-icloud".write(
            to: dahsoICloud.appendingPathComponent("Cloud.md"),
            atomically: true,
            encoding: .utf8
        )
        try "legacy".write(
            to: bugbookLegacy.appendingPathComponent("Legacy.md"),
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
            [
                .documentsDahso,
                .dahsoApplicationSupport,
                .dahsoICloud,
                .applicationSupportBugbook,
                .bugbookApplicationSupport,
                .bugbookICloud
            ]
        )
        XCTAssertEqual(
            detected.map(\.path),
            [
                dahsoDocuments,
                dahsoSupport,
                dahsoICloud,
                bugbookLegacy,
                bugbookSupport,
                bugbookICloud
            ]
        )
        XCTAssertEqual(
            detected.map(\.kind.title),
            [
                "Bugbook documents workspace",
                "Bugbook application support data",
                "Bugbook iCloud workspace",
                "Old Bugbook application support data",
                "Bugbook application support data",
                "Bugbook iCloud workspace"
            ]
        )
    }

    func testDetectLegacyWorkspacesIgnoresExcludedTopLevelCacheFolders() throws {
        let service = FileSystemService()
        let homePath = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(atPath: homePath) }

        let homeURL = URL(fileURLWithPath: homePath, isDirectory: true)
        let bugbookLegacy = homeURL
            .appendingPathComponent("Library/Application Support/bugbook", isDirectory: true)
        let cacheDirectory = bugbookLegacy.appendingPathComponent("MailCache", isDirectory: true)
        try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        try "cache".write(
            to: cacheDirectory.appendingPathComponent("state.db"),
            atomically: true,
            encoding: .utf8
        )

        XCTAssertTrue(service.detectLegacyWorkspaces(homeDirectory: homeURL).isEmpty)
    }

    func testDetectLegacyWorkspacesCountsHiddenWorkspaceMarkers() throws {
        let service = FileSystemService()
        let homePath = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(atPath: homePath) }

        let homeURL = URL(fileURLWithPath: homePath, isDirectory: true)
        let bugbookLegacy = homeURL
            .appendingPathComponent("Library/Application Support/bugbook", isDirectory: true)
        try FileManager.default.createDirectory(at: bugbookLegacy, withIntermediateDirectories: true)
        try "workspace".write(
            to: bugbookLegacy.appendingPathComponent(".qmd-context-marker"),
            atomically: true,
            encoding: .utf8
        )

        let detected = service.detectLegacyWorkspaces(homeDirectory: homeURL)

        XCTAssertEqual(detected.map(\.kind), [.applicationSupportBugbook])
        XCTAssertEqual(detected.map(\.path), [bugbookLegacy])
    }

    func testDetectLegacyWorkspacesCountsOnlyLegacyMeetingStoresInsideHiddenAppFolders() throws {
        let service = FileSystemService()
        let homePath = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(atPath: homePath) }

        let homeURL = URL(fileURLWithPath: homePath, isDirectory: true)
        let dahsoDocuments = homeURL
            .appendingPathComponent("Documents/Dahso", isDirectory: true)
        let meetingsDirectory = dahsoDocuments
            .appendingPathComponent(".dahso", isDirectory: true)
            .appendingPathComponent("meetings", isDirectory: true)

        try FileManager.default.createDirectory(at: meetingsDirectory, withIntermediateDirectories: true)
        try "{}".write(
            to: meetingsDirectory.appendingPathComponent("meeting-id.json"),
            atomically: true,
            encoding: .utf8
        )

        let detected = service.detectLegacyWorkspaces(homeDirectory: homeURL)

        XCTAssertEqual(detected.map(\.kind), [.documentsDahso])
        XCTAssertEqual(detected.map(\.path), [dahsoDocuments])
    }

    func testRefreshLegacyWorkspacesInBackgroundPopulatesDetectedWorkspaces() async throws {
        let service = FileSystemService()
        let homePath = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(atPath: homePath) }

        let homeURL = URL(fileURLWithPath: homePath, isDirectory: true)
        let bugbookLegacy = homeURL
            .appendingPathComponent("Library/Application Support/bugbook", isDirectory: true)
        try FileManager.default.createDirectory(at: bugbookLegacy, withIntermediateDirectories: true)
        try "legacy".write(
            to: bugbookLegacy.appendingPathComponent("Legacy.md"),
            atomically: true,
            encoding: .utf8
        )

        let detected = await service.refreshLegacyWorkspacesInBackground(homeDirectory: homeURL)

        XCTAssertEqual(detected.map(\.kind), [.applicationSupportBugbook])
        XCTAssertEqual(service.legacyWorkspaces.map(\.path), [bugbookLegacy])
    }

    func testMigrateLegacyWorkspaceSkipsEqualMtimeConflicts() async throws {
        let service = FileSystemService()
        let legacyPath = try makeTemporaryDirectory()
        let destinationPath = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(atPath: legacyPath) }
        defer { try? FileManager.default.removeItem(atPath: destinationPath) }

        let legacyRoot = URL(fileURLWithPath: legacyPath, isDirectory: true)
        let destinationRoot = URL(fileURLWithPath: destinationPath, isDirectory: true)
        let legacyFile = legacyRoot.appendingPathComponent("a.txt")
        let destinationFile = destinationRoot.appendingPathComponent("a.txt")
        let sharedDate = Date(timeIntervalSince1970: 1_700_000_000)

        try "legacy-content".write(to: legacyFile, atomically: true, encoding: .utf8)
        try "current".write(to: destinationFile, atomically: true, encoding: .utf8)
        try setModificationDate(sharedDate, at: legacyFile.path)
        try setModificationDate(sharedDate, at: destinationFile.path)

        let legacyWorkspace = FileSystemService.LegacyWorkspace(
            path: legacyRoot,
            kind: .applicationSupportBugbook
        )

        try await service.migrateLegacyWorkspace(legacyWorkspace, into: destinationRoot)

        XCTAssertEqual(
            try String(contentsOf: destinationFile, encoding: .utf8),
            "current"
        )
    }

    func testMigrateLegacyWorkspaceUsesAtomicReplaceWithoutLeavingArtifacts() async throws {
        let service = FileSystemService()
        let legacyPath = try makeTemporaryDirectory()
        let destinationPath = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(atPath: legacyPath) }
        defer { try? FileManager.default.removeItem(atPath: destinationPath) }

        let legacyRoot = URL(fileURLWithPath: legacyPath, isDirectory: true)
        let destinationRoot = URL(fileURLWithPath: destinationPath, isDirectory: true)
        let legacyFile = legacyRoot.appendingPathComponent("a.txt")
        let destinationFile = destinationRoot.appendingPathComponent("a.txt")

        try "legacy replacement".write(to: legacyFile, atomically: true, encoding: .utf8)
        try "current".write(to: destinationFile, atomically: true, encoding: .utf8)

        let now = Date()
        try setModificationDate(now, at: legacyFile.path)
        try setModificationDate(now.addingTimeInterval(-3600), at: destinationFile.path)

        let sourceInode = try inodeNumber(at: legacyFile.path)
        let originalDestinationInode = try inodeNumber(at: destinationFile.path)
        let legacyWorkspace = FileSystemService.LegacyWorkspace(
            path: legacyRoot,
            kind: .applicationSupportBugbook
        )

        try await service.migrateLegacyWorkspace(legacyWorkspace, into: destinationRoot)

        XCTAssertEqual(
            try String(contentsOf: destinationFile, encoding: .utf8),
            "legacy replacement"
        )
        XCTAssertNotEqual(try inodeNumber(at: destinationFile.path), sourceInode)
        XCTAssertNotEqual(try inodeNumber(at: destinationFile.path), originalDestinationInode)
        XCTAssertFalse(
            try subpaths(in: destinationPath).contains { path in
                path.contains(".bugbook-migrate-tmp-") || path.contains(".bugbook-backup-")
            }
        )
    }

    func testMigrateLegacyWorkspaceCopiesAllowedHiddenFilesAndSkipsKnownToolingState() async throws {
        let service = FileSystemService()
        let legacyPath = try makeTemporaryDirectory()
        let destinationPath = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(atPath: legacyPath) }
        defer { try? FileManager.default.removeItem(atPath: destinationPath) }

        let legacyRoot = URL(fileURLWithPath: legacyPath, isDirectory: true)
        let destinationRoot = URL(fileURLWithPath: destinationPath, isDirectory: true)
        let gitDirectory = legacyRoot.appendingPathComponent(".git", isDirectory: true)
        let notesDirectory = legacyRoot.appendingPathComponent("notes", isDirectory: true)

        try FileManager.default.createDirectory(at: gitDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: notesDirectory, withIntermediateDirectories: true)
        try "ref: refs/heads/main".write(
            to: gitDirectory.appendingPathComponent("HEAD"),
            atomically: true,
            encoding: .utf8
        )
        try "finder noise".write(
            to: legacyRoot.appendingPathComponent(".DS_Store"),
            atomically: true,
            encoding: .utf8
        )
        try "workspace".write(
            to: legacyRoot.appendingPathComponent(".qmd-context-marker"),
            atomically: true,
            encoding: .utf8
        )
        try "secret".write(
            to: notesDirectory.appendingPathComponent(".secret"),
            atomically: true,
            encoding: .utf8
        )

        let legacyWorkspace = FileSystemService.LegacyWorkspace(
            path: legacyRoot,
            kind: .applicationSupportBugbook
        )

        try await service.migrateLegacyWorkspace(legacyWorkspace, into: destinationRoot)

        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: destinationRoot.appendingPathComponent(".qmd-context-marker").path
            )
        )
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: destinationRoot.appendingPathComponent("notes/.secret").path
            )
        )
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: destinationRoot.appendingPathComponent(".git/HEAD").path
            )
        )
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: destinationRoot.appendingPathComponent(".DS_Store").path
            )
        )
    }

    func testMigrateLegacyWorkspaceMovesOldMeetingStoresIntoBugbookMeetingStore() async throws {
        let service = FileSystemService()
        let legacyPath = try makeTemporaryDirectory()
        let destinationPath = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(atPath: legacyPath) }
        defer { try? FileManager.default.removeItem(atPath: destinationPath) }

        let legacyRoot = URL(fileURLWithPath: legacyPath, isDirectory: true)
        let destinationRoot = URL(fileURLWithPath: destinationPath, isDirectory: true)
        let dahsoMeetings = legacyRoot
            .appendingPathComponent(".dahso", isDirectory: true)
            .appendingPathComponent("meetings", isDirectory: true)
        let bugbookMeetings = legacyRoot
            .appendingPathComponent(".bugbook", isDirectory: true)
            .appendingPathComponent("meetings", isDirectory: true)
        let legacyCalendar = legacyRoot
            .appendingPathComponent(".bugbook", isDirectory: true)
            .appendingPathComponent("calendar", isDirectory: true)

        try FileManager.default.createDirectory(at: dahsoMeetings, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: bugbookMeetings, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: legacyCalendar, withIntermediateDirectories: true)

        try #"{"source":"dahso"}"#.write(
            to: dahsoMeetings.appendingPathComponent("old-meeting.json"),
            atomically: true,
            encoding: .utf8
        )
        try #"{"source":"bugbook"}"#.write(
            to: bugbookMeetings.appendingPathComponent("new-meeting.json"),
            atomically: true,
            encoding: .utf8
        )
        try #"{"events":[]}"#.write(
            to: legacyCalendar.appendingPathComponent("events.json"),
            atomically: true,
            encoding: .utf8
        )

        let legacyWorkspace = FileSystemService.LegacyWorkspace(
            path: legacyRoot,
            kind: .documentsDahso
        )

        try await service.migrateLegacyWorkspace(legacyWorkspace, into: destinationRoot)

        XCTAssertEqual(
            try String(
                contentsOf: destinationRoot.appendingPathComponent(".bugbook/meetings/old-meeting.json"),
                encoding: .utf8
            ),
            #"{"source":"dahso"}"#
        )
        XCTAssertEqual(
            try String(
                contentsOf: destinationRoot.appendingPathComponent(".bugbook/meetings/new-meeting.json"),
                encoding: .utf8
            ),
            #"{"source":"bugbook"}"#
        )
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: destinationRoot.appendingPathComponent(".dahso/meetings/old-meeting.json").path
            )
        )
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: destinationRoot.appendingPathComponent(".bugbook/calendar/events.json").path
            )
        )
    }

    func testMigrateLegacyWorkspaceSkipsSymbolicLinks() async throws {
        let service = FileSystemService()
        let legacyPath = try makeTemporaryDirectory()
        let destinationPath = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(atPath: legacyPath) }
        defer { try? FileManager.default.removeItem(atPath: destinationPath) }

        let legacyRoot = URL(fileURLWithPath: legacyPath, isDirectory: true)
        let destinationRoot = URL(fileURLWithPath: destinationPath, isDirectory: true)
        let realFile = legacyRoot.appendingPathComponent("real.txt")
        let linkFile = legacyRoot.appendingPathComponent("link.txt")

        try "real".write(to: realFile, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(at: linkFile, withDestinationURL: realFile)

        let legacyWorkspace = FileSystemService.LegacyWorkspace(
            path: legacyRoot,
            kind: .applicationSupportBugbook
        )

        try await service.migrateLegacyWorkspace(legacyWorkspace, into: destinationRoot)

        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: destinationRoot.appendingPathComponent("real.txt").path
            )
        )
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: destinationRoot.appendingPathComponent("link.txt").path
            )
        )
    }

    func testMigrateLegacyWorkspaceCreatesBrokenSymlinkDestinationTarget() async throws {
        let service = FileSystemService()
        let rootPath = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(atPath: rootPath) }

        let root = URL(fileURLWithPath: rootPath, isDirectory: true)
        let legacyRoot = root.appendingPathComponent("Legacy", isDirectory: true)
        let linkParent = root.appendingPathComponent("Documents", isDirectory: true)
        let symlinkRoot = linkParent.appendingPathComponent("Bugbook", isDirectory: true)
        let targetRoot = root
            .appendingPathComponent("Mobile Documents", isDirectory: true)
            .appendingPathComponent("iCloud~com~bugbook~app", isDirectory: true)
            .appendingPathComponent("Documents", isDirectory: true)
            .appendingPathComponent("Bugbook", isDirectory: true)
        let legacyFile = legacyRoot.appendingPathComponent("Legacy.md")
        let migratedFile = targetRoot.appendingPathComponent("Legacy.md")

        try FileManager.default.createDirectory(at: legacyRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: linkParent, withIntermediateDirectories: true)
        try "legacy".write(to: legacyFile, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(at: symlinkRoot, withDestinationURL: targetRoot)

        let legacyWorkspace = FileSystemService.LegacyWorkspace(
            path: legacyRoot,
            kind: .applicationSupportBugbook
        )

        try await service.migrateLegacyWorkspace(legacyWorkspace, into: symlinkRoot)

        var targetIsDirectory: ObjCBool = false
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: targetRoot.path, isDirectory: &targetIsDirectory)
        )
        XCTAssertTrue(targetIsDirectory.boolValue)
        XCTAssertEqual(try String(contentsOf: migratedFile, encoding: .utf8), "legacy")
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: symlinkRoot.appendingPathComponent("Legacy.md").path
            )
        )
    }

    func testMigrateLegacyWorkspaceThrowsTypeMismatchAndAppStateSurfacesIt() async throws {
        let service = FileSystemService()
        let legacyPath = try makeTemporaryDirectory()
        let destinationPath = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(atPath: legacyPath) }
        defer { try? FileManager.default.removeItem(atPath: destinationPath) }

        let legacyRoot = URL(fileURLWithPath: legacyPath, isDirectory: true)
        let destinationRoot = URL(fileURLWithPath: destinationPath, isDirectory: true)
        let sourceFile = legacyRoot.appendingPathComponent("foo")
        let destinationDirectory = destinationRoot.appendingPathComponent("foo", isDirectory: true)

        try "legacy".write(to: sourceFile, atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)

        let legacyWorkspace = FileSystemService.LegacyWorkspace(
            path: legacyRoot,
            kind: .applicationSupportBugbook
        )
        let expectedSourcePath = sourceFile.resolvingSymlinksInPath().path
        let expectedDestinationPath = destinationDirectory.resolvingSymlinksInPath().path
        var caughtError: FileSystemService.MigrationError?

        do {
            try await service.migrateLegacyWorkspace(legacyWorkspace, into: destinationRoot)
            XCTFail("Expected a type mismatch error")
        } catch let error as FileSystemService.MigrationError {
            caughtError = error
            guard case let .typeMismatch(sourcePath, destPath, sourceKind, destKind) = error else {
                return XCTFail("Expected a type mismatch error, got \(error)")
            }
            XCTAssertEqual(
                URL(fileURLWithPath: sourcePath).resolvingSymlinksInPath().path,
                expectedSourcePath
            )
            XCTAssertEqual(
                URL(fileURLWithPath: destPath).resolvingSymlinksInPath().path,
                expectedDestinationPath
            )
            XCTAssertEqual(sourceKind, .file)
            XCTAssertEqual(destKind, .directory)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        let appState = AppState()
        appState.workspacePath = destinationPath
        appState.legacyWorkspaces = [legacyWorkspace]

        await appState.migrateLegacyWorkspace(legacyWorkspace, using: service)

        let expectedDescription = try XCTUnwrap(caughtError?.localizedDescription)

        XCTAssertEqual(
            appState.legacyWorkspaceErrorMessage(for: legacyWorkspace),
            expectedDescription
        )
        XCTAssertEqual(
            appState.aggregatedLegacyMigrationError,
            expectedDescription
        )
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
            kind: .applicationSupportBugbook
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
        XCTAssertEqual(try String(contentsOf: legacyPlan, encoding: .utf8), "legacy plan")
        XCTAssertEqual(try String(contentsOf: legacyArchive, encoding: .utf8), "archive")
        XCTAssertTrue(FileManager.default.fileExists(atPath: legacyPlan.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: legacyArchive.path))
    }
}
