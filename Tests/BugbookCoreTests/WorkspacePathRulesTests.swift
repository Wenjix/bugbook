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
}
