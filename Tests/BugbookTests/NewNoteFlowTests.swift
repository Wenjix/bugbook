import XCTest
@testable import Bugbook

/// Pins the Cmd+N / File > New Note contract through the interfaces the
/// handler composes: a created note must become the focused pane's active,
/// open document — not just a file on disk (the legacy openTabs path created
/// orphan files without surfacing them).
@MainActor
final class NewNoteFlowTests: XCTestCase {

    private var workspace: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent("NewNoteFlowTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: workspace)
        super.tearDown()
    }

    func testNewNoteBecomesActivePaneDocument() throws {
        let fileSystem = FileSystemService()
        let manager = WorkspaceManager()
        manager.layoutPersistenceEnabled = false
        manager.addWorkspaceWith(content: .emptyDocument())
        let appState = AppState()

        // Create the note the way the New Note handler does.
        let path = try fileSystem.createNewFile(in: workspace.path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: path))

        // Open it through the pane-aware path (same as palette "New Page").
        let entry = FileEntry(
            id: path,
            name: (path as NSString).lastPathComponent,
            path: path,
            isDirectory: false
        )
        let switchedToExisting = appState.openFileReplacingCurrentTab(
            entry,
            workspaceManager: manager,
            pushHistory: true,
            preferExistingTab: false
        )

        // The new note replaced the pane's content and is now the active document.
        XCTAssertFalse(switchedToExisting, "a fresh note must replace the pane content, not focus an existing tab")
        let focusedFile = try XCTUnwrap(manager.focusedOpenFile, "focused pane must expose the opened note")
        XCTAssertEqual(focusedFile.path, path)
        XCTAssertFalse(focusedFile.isEmptyTab, "the pane must no longer be an empty placeholder tab")
        XCTAssertEqual(focusedFile.kind, .page)
    }

    /// F4: template creation routes through the same pane-aware path — the
    /// created page must surface as the focused pane's document.
    func testTemplateCreatedPageSurfacesInPane() throws {
        let fileSystem = FileSystemService()
        let manager = WorkspaceManager()
        manager.layoutPersistenceEnabled = false
        manager.addWorkspaceWith(content: .emptyDocument())
        let appState = AppState()

        let path = try fileSystem.createNewFile(in: workspace.path, name: "Weekly Review")
        try "# Weekly Review\n\n## Wins\n\n## Blockers\n".write(toFile: path, atomically: true, encoding: .utf8)

        let entry = FileEntry(
            id: path,
            name: (path as NSString).lastPathComponent,
            path: path,
            isDirectory: false
        )
        appState.openFileReplacingCurrentTab(
            entry,
            workspaceManager: manager,
            pushHistory: true,
            preferExistingTab: false
        )

        let focusedFile = try XCTUnwrap(manager.focusedOpenFile)
        XCTAssertEqual(focusedFile.path, path)
        XCTAssertEqual(focusedFile.kind, .page)
    }

    /// F4: "Open full page" for a database row must reach a pane (the legacy
    /// openTabs path made it a silent no-op in pane mode).
    func testDatabaseRowOpenFullPageReachesPane() throws {
        let manager = WorkspaceManager()
        manager.layoutPersistenceEnabled = false
        manager.addWorkspaceWith(content: .emptyDocument())
        let appState = AppState()

        let rowPath = DatabaseRowNavigationPath.make(dbPath: "/ws/Tasks", rowId: "row_42")
        let entry = FileEntry(
            id: rowPath,
            name: "Row Title",
            path: rowPath,
            isDirectory: false,
            kind: .databaseRow(dbPath: "/ws/Tasks", rowId: "row_42")
        )
        appState.openFileReplacingCurrentTab(
            entry,
            workspaceManager: manager,
            pushHistory: true,
            preferExistingTab: true
        )

        let focusedFile = try XCTUnwrap(manager.focusedOpenFile, "row page must land in the focused pane")
        XCTAssertEqual(focusedFile.kind, .databaseRow(dbPath: "/ws/Tasks", rowId: "row_42"))
        XCTAssertEqual(focusedFile.databasePath, "/ws/Tasks")
        XCTAssertEqual(focusedFile.databaseRowId, "row_42")
    }

    func testRepeatedNewNotesCreateDistinctFilesAndSurfaceEachOne() throws {
        let fileSystem = FileSystemService()
        let manager = WorkspaceManager()
        manager.layoutPersistenceEnabled = false
        manager.addWorkspaceWith(content: .emptyDocument())
        let appState = AppState()

        var paths: [String] = []
        for _ in 0..<3 {
            let path = try fileSystem.createNewFile(in: workspace.path)
            paths.append(path)
            let entry = FileEntry(
                id: path,
                name: (path as NSString).lastPathComponent,
                path: path,
                isDirectory: false
            )
            appState.openFileReplacingCurrentTab(
                entry,
                workspaceManager: manager,
                pushHistory: true,
                preferExistingTab: false
            )
            // Each press surfaces the note it just created — no orphans.
            XCTAssertEqual(manager.focusedOpenFile?.path, path)
        }

        XCTAssertEqual(Set(paths).count, 3, "each New Note must create a distinct file")
    }
}
