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
}
