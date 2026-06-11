import XCTest
@testable import Bugbook

/// Pins the round-4 UI-defect fixes through the model interfaces:
/// - D2: launch must not clobber a restored focused document with the daily
///   note (`hasRestoredDocument` is the launch-navigation decision input).
/// - D3: navigating an empty tab to an already-open document must not strand
///   the empty tab as an unreachable zombie.
@MainActor
final class TabLifecycleTests: XCTestCase {

    private func documentTab(path: String, name: String) -> PaneContent {
        .document(openFile: OpenFile(
            id: UUID(),
            path: path,
            content: "",
            isDirty: false,
            isEmptyTab: false,
            kind: .page,
            displayName: name
        ))
    }

    // MARK: - D2: restored focused document survives launch

    func testRestoredFocusedDocumentReportsRestoredState() {
        let manager = WorkspaceManager()
        manager.layoutPersistenceEnabled = false
        manager.addWorkspaceWith(content: documentTab(path: "/ws/Harbor.md", name: "Harbor"))

        XCTAssertTrue(
            manager.hasRestoredDocument,
            "launch must see the restored document and skip forcing the daily note"
        )
        XCTAssertEqual(manager.focusedOpenFile?.path, "/ws/Harbor.md")
    }

    func testFreshEmptyTabReportsNoRestoredDocument() {
        let manager = WorkspaceManager()
        manager.layoutPersistenceEnabled = false
        manager.addWorkspace()

        XCTAssertFalse(
            manager.hasRestoredDocument,
            "a fresh install / empty tab is when the daily note start page applies"
        )
    }

    // MARK: - D3: no zombie empty tab when routing to an already-open document

    func testEmptyTabRoutingToOpenDocumentPrunesTheEmptyTab() {
        let state = AppState()
        let manager = WorkspaceManager()
        manager.layoutPersistenceEnabled = false

        // Daily note already open in tab 0; Cmd+T adds an empty tab.
        manager.addWorkspaceWith(content: documentTab(path: "/ws/Daily.md", name: "Daily"))
        manager.addWorkspace()
        XCTAssertEqual(manager.workspaces.count, 2)
        XCTAssertEqual(manager.activeWorkspaceIndex, 1)

        // The empty tab's start-page routing opens the daily note, which is
        // already open — switch to it AND prune the stranded empty tab.
        let switched = state.openFileReplacingCurrentTab(
            FileEntry(id: "/ws/Daily.md", name: "Daily.md", path: "/ws/Daily.md", isDirectory: false),
            workspaceManager: manager,
            pushHistory: true,
            preferExistingTab: true
        )

        XCTAssertTrue(switched)
        XCTAssertEqual(manager.workspaces.count, 1, "the empty tab must not remain as a zombie")
        XCTAssertEqual(manager.activeWorkspaceIndex, 0)
        XCTAssertEqual(manager.focusedOpenFile?.path, "/ws/Daily.md")
    }

    func testNonEmptyTabIsNotPrunedWhenSwitchingToExistingDocument() {
        let state = AppState()
        let manager = WorkspaceManager()
        manager.layoutPersistenceEnabled = false

        manager.addWorkspaceWith(content: documentTab(path: "/ws/Daily.md", name: "Daily"))
        manager.addWorkspaceWith(content: documentTab(path: "/ws/Notes.md", name: "Notes"))

        let switched = state.openFileReplacingCurrentTab(
            FileEntry(id: "/ws/Daily.md", name: "Daily.md", path: "/ws/Daily.md", isDirectory: false),
            workspaceManager: manager,
            pushHistory: true,
            preferExistingTab: true
        )

        XCTAssertTrue(switched)
        XCTAssertEqual(manager.workspaces.count, 2, "real document tabs are never pruned by a switch")
        XCTAssertEqual(manager.focusedOpenFile?.path, "/ws/Daily.md")
    }

    func testEmptyTabReplacedInPlaceWhenDocumentNotOpenElsewhere() {
        let state = AppState()
        let manager = WorkspaceManager()
        manager.layoutPersistenceEnabled = false

        manager.addWorkspaceWith(content: documentTab(path: "/ws/Other.md", name: "Other"))
        manager.addWorkspace()

        let switched = state.openFileReplacingCurrentTab(
            FileEntry(id: "/ws/Daily.md", name: "Daily.md", path: "/ws/Daily.md", isDirectory: false),
            workspaceManager: manager,
            pushHistory: true,
            preferExistingTab: true
        )

        XCTAssertFalse(switched, "not open elsewhere — the empty tab becomes the document")
        XCTAssertEqual(manager.workspaces.count, 2)
        XCTAssertEqual(manager.focusedOpenFile?.path, "/ws/Daily.md")
    }
}
