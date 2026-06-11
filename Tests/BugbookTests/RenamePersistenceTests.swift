import XCTest
@testable import Bugbook

/// Round-4b defect fixes, pinned through the model interfaces:
/// - D7a: title → filename derivation strips markdown/formatting artifacts.
/// - D7b: a renamed tab's path survives a persist/restore round-trip.
/// - D7c: a restored tab pointing at a missing file is pruned, not blank.
/// - D8: the active tab index persists across switch + relaunch.
@MainActor
final class RenamePersistenceTests: XCTestCase {

    private var root: URL!
    private var layoutURL: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("RenamePersistenceTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        layoutURL = root.appendingPathComponent("layouts.json")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
        super.tearDown()
    }

    @discardableResult
    private func writeFile(named name: String) throws -> String {
        let path = root.appendingPathComponent(name).path
        try "# \(name)\n\nBody.\n".write(toFile: path, atomically: true, encoding: .utf8)
        return path
    }

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

    // MARK: - D7a: title → filename derivation

    func testFilenameDerivationStripsMarkdownArtifacts() {
        XCTAssertEqual(FileSystemService.filenameSafeTitle("**Bold title**"), "Bold title")
        XCTAssertEqual(FileSystemService.filenameSafeTitle("*Harbor* probe. "), "Harbor probe")
        XCTAssertEqual(FileSystemService.filenameSafeTitle("# Heading title"), "Heading title")
        XCTAssertEqual(FileSystemService.filenameSafeTitle("`code` and ~~strike~~"), "code and strike")
        XCTAssertEqual(FileSystemService.filenameSafeTitle("Autosave probe. "), "Autosave probe")
    }

    func testFilenameDerivationReplacesReservedCharactersAndKeepsUnderscores() {
        XCTAssertEqual(FileSystemService.filenameSafeTitle("a/b: c"), "a-b- c")
        // `%` and `?` are in the (pre-existing) reserved set; trailing
        // separators are trimmed.
        XCTAssertEqual(FileSystemService.filenameSafeTitle("what? 50%"), "what- 50")
        XCTAssertEqual(FileSystemService.filenameSafeTitle("snake_case_title"), "snake_case_title")
        XCTAssertEqual(FileSystemService.filenameSafeTitle("  spaced   out  "), "spaced out")
        XCTAssertEqual(FileSystemService.filenameSafeTitle("***"), "")
    }

    // MARK: - D7b: renamed tab path survives persist/restore

    func testRenamedTabPathRoundTripsThroughPersistedLayout() throws {
        let oldPath = try writeFile(named: "Harbor.md")

        let managerA = WorkspaceManager(layoutFileURL: layoutURL)
        managerA.addWorkspaceWith(content: documentTab(path: oldPath, name: "Harbor"))
        let tabId = try XCTUnwrap(managerA.activeTabID)

        // Simulate the rename flow: file moves on disk, the tab is rewritten
        // (path + history), and the layout persists.
        let newPath = root.appendingPathComponent("Harbor Renamed.md").path
        try FileManager.default.moveItem(atPath: oldPath, toPath: newPath)
        managerA.updateOpenFile(tabId: tabId) { file in
            file.path = newPath
            file.navigationHistory = file.navigationHistory.map { $0 == oldPath ? newPath : $0 }
        }
        managerA.persistNow()

        let managerB = WorkspaceManager(layoutFileURL: layoutURL)
        managerB.restoreOrCreateDefault()

        XCTAssertEqual(managerB.workspaces.count, 1)
        XCTAssertEqual(
            managerB.focusedOpenFile?.path, newPath,
            "the restored tab must point at the renamed file, not the stale path"
        )
    }

    // MARK: - D7c: missing-file tabs are pruned at restore, not blank

    func testRestorePrunesTabsWhoseFileNoLongerExists() throws {
        let livePath = try writeFile(named: "Alive.md")
        let stalePath = root.appendingPathComponent("Gone.md").path // never written

        let managerA = WorkspaceManager(layoutFileURL: layoutURL)
        managerA.addWorkspaceWith(content: documentTab(path: livePath, name: "Alive"))
        managerA.addWorkspaceWith(content: documentTab(path: stalePath, name: "Gone"))
        managerA.persistNow()

        let managerB = WorkspaceManager(layoutFileURL: layoutURL)
        managerB.restoreOrCreateDefault()

        XCTAssertEqual(
            managerB.workspaces.compactMap { $0.openFile?.path },
            [livePath],
            "a tab pointing at a nonexistent file must be pruned instead of restoring blank"
        )
    }

    func testPruneKeepsNonPageAndEmptyTabs() {
        let emptyTab = Workspace.makeDefault()
        let meetings = Workspace(
            id: UUID(), name: "Meetings", icon: nil, content: .meetingsDocument(), createdAt: Date()
        )
        let missingPage = Workspace(
            id: UUID(), name: "Gone", icon: nil,
            content: documentTab(path: "/definitely/not/here.md", name: "Gone"),
            createdAt: Date()
        )

        let pruned = WorkspaceManager.prunedMissingDocuments([emptyTab, meetings, missingPage])
        XCTAssertEqual(pruned.map(\.id), [emptyTab.id, meetings.id])
    }

    // MARK: - D8: active tab index round-trips

    func testSwitchingTabsPersistsActiveIndexAcrossRestore() async throws {
        let pathA = try writeFile(named: "A.md")
        let pathB = try writeFile(named: "B.md")
        let pathC = try writeFile(named: "C.md")

        let managerA = WorkspaceManager(layoutFileURL: layoutURL)
        managerA.addWorkspaceWith(content: documentTab(path: pathA, name: "A"))
        managerA.addWorkspaceWith(content: documentTab(path: pathB, name: "B"))
        managerA.addWorkspaceWith(content: documentTab(path: pathC, name: "C"))
        XCTAssertEqual(managerA.activeWorkspaceIndex, 2)

        // switchWorkspace must SCHEDULE the persist itself — wait out the
        // 500ms debounce instead of flushing manually.
        managerA.switchWorkspace(to: 0)
        try await Task.sleep(nanoseconds: 900_000_000)

        let managerB = WorkspaceManager(layoutFileURL: layoutURL)
        managerB.restoreOrCreateDefault()

        XCTAssertEqual(managerB.workspaces.count, 3)
        XCTAssertEqual(
            managerB.activeWorkspaceIndex, 0,
            "relaunch must restore the tab the user was on"
        )
        XCTAssertEqual(managerB.focusedOpenFile?.path, pathA)
    }

    func testCycleWorkspacePersistsActiveIndexAcrossRestore() async throws {
        let pathA = try writeFile(named: "A.md")
        let pathB = try writeFile(named: "B.md")

        let managerA = WorkspaceManager(layoutFileURL: layoutURL)
        managerA.addWorkspaceWith(content: documentTab(path: pathA, name: "A"))
        managerA.addWorkspaceWith(content: documentTab(path: pathB, name: "B"))

        managerA.cycleWorkspace(step: 1) // wraps 1 -> 0
        XCTAssertEqual(managerA.activeWorkspaceIndex, 0)
        try await Task.sleep(nanoseconds: 900_000_000)

        let managerB = WorkspaceManager(layoutFileURL: layoutURL)
        managerB.restoreOrCreateDefault()
        XCTAssertEqual(managerB.activeWorkspaceIndex, 0)
    }
}
