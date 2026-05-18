import XCTest
@testable import BugbookCore

final class WorkspacePathRulesTests: XCTestCase {
    func testIgnoresHiddenComponents() {
        XCTAssertTrue(WorkspacePathRules.shouldIgnoreRelativePath(".bugbook/agents/tasks.json"))
    }

    func testIgnoresLogseqBackupPaths() {
        XCTAssertTrue(
            WorkspacePathRules.shouldIgnoreRelativePath(
                "logseq/bak/Bugbook Strategy/2026-03-07T00_55_42.570Z.Desktop.md"
            )
        )
    }

    func testDoesNotIgnoreRegularPages() {
        XCTAssertFalse(WorkspacePathRules.shouldIgnoreRelativePath("Bugbook Strategy.md"))
        XCTAssertFalse(WorkspacePathRules.shouldIgnoreRelativePath("Daily Notes/2026-03-07.md"))
    }

    func testLocalFallbackCanSkipRichestSiblingScanForNonblockingStartup() throws {
        let documentsURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let richSiblingURL = documentsURL.appendingPathComponent("Bugbook 2", isDirectory: true)
        try FileManager.default.createDirectory(at: richSiblingURL, withIntermediateDirectories: true)
        try "# Page".write(
            to: richSiblingURL.appendingPathComponent("Existing Page.md"),
            atomically: true,
            encoding: .utf8
        )
        defer { try? FileManager.default.removeItem(at: documentsURL) }

        let fallbackPath = WorkspaceResolver.localFallbackWorkspacePath(
            documentsURL: documentsURL,
            createIfMissing: true,
            resolveRichestSibling: false
        )

        XCTAssertEqual(
            fallbackPath,
            documentsURL.appendingPathComponent(WorkspaceResolver.defaultFolderName, isDirectory: true).path
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: fallbackPath))
    }

    func testLocalFallbackCreatesBrokenSymlinkTargetForNonblockingStartup() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let documentsURL = rootURL.appendingPathComponent("Documents", isDirectory: true)
        let targetURL = rootURL
            .appendingPathComponent("Mobile Documents", isDirectory: true)
            .appendingPathComponent("iCloud~com~bugbook~app", isDirectory: true)
            .appendingPathComponent("Documents", isDirectory: true)
            .appendingPathComponent("Bugbook", isDirectory: true)
        let symlinkURL = documentsURL.appendingPathComponent("Bugbook", isDirectory: true)
        try FileManager.default.createDirectory(at: documentsURL, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: symlinkURL.path, withDestinationPath: targetURL.path)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let fallbackPath = WorkspaceResolver.localFallbackWorkspacePath(
            documentsURL: documentsURL,
            createIfMissing: true,
            resolveRichestSibling: false
        )

        XCTAssertEqual(fallbackPath, symlinkURL.path)
        var targetIsDirectory: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: targetURL.path, isDirectory: &targetIsDirectory))
        XCTAssertTrue(targetIsDirectory.boolValue)
        XCTAssertTrue(FileManager.default.fileExists(atPath: symlinkURL.path))
    }

    func testLocalFallbackCanResolveRichestSiblingWhenAllowed() throws {
        let documentsURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let richSiblingURL = documentsURL.appendingPathComponent("Bugbook 2", isDirectory: true)
        try FileManager.default.createDirectory(at: richSiblingURL, withIntermediateDirectories: true)
        try "# Page".write(
            to: richSiblingURL.appendingPathComponent("Existing Page.md"),
            atomically: true,
            encoding: .utf8
        )
        defer { try? FileManager.default.removeItem(at: documentsURL) }

        let fallbackPath = WorkspaceResolver.localFallbackWorkspacePath(
            documentsURL: documentsURL,
            createIfMissing: true,
            resolveRichestSibling: true
        )

        XCTAssertEqual(fallbackPath, richSiblingURL.path)
    }
}
