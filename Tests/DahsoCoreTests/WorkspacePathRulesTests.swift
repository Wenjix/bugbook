import XCTest
@testable import DahsoCore

final class WorkspacePathRulesTests: XCTestCase {
    func testIgnoresHiddenComponents() {
        XCTAssertTrue(WorkspacePathRules.shouldIgnoreRelativePath(".dahso/agents/tasks.json"))
    }

    func testIgnoresLogseqBackupPaths() {
        XCTAssertTrue(
            WorkspacePathRules.shouldIgnoreRelativePath(
                "logseq/bak/Dahso Strategy/2026-03-07T00_55_42.570Z.Desktop.md"
            )
        )
    }

    func testDoesNotIgnoreRegularPages() {
        XCTAssertFalse(WorkspacePathRules.shouldIgnoreRelativePath("Dahso Strategy.md"))
        XCTAssertFalse(WorkspacePathRules.shouldIgnoreRelativePath("Daily Notes/2026-03-07.md"))
    }

    func testLocalFallbackCanSkipRichestSiblingScanForNonblockingStartup() throws {
        let documentsURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let richSiblingURL = documentsURL.appendingPathComponent("Dahso 2", isDirectory: true)
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

    func testLocalFallbackCanResolveRichestSiblingWhenAllowed() throws {
        let documentsURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let richSiblingURL = documentsURL.appendingPathComponent("Dahso 2", isDirectory: true)
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
