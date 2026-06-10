import XCTest
@testable import Bugbook

/// Raw-JSON fixture tests for the persisted-layout migrations: removed tab and
/// pane kinds from older layouts must decode to the `.removed` sentinel and be
/// pruned by the sanitizer, while genuinely corrupt payloads for live kinds
/// must fail decode instead of silently degrading.
@MainActor
final class LayoutMigrationTests: XCTestCase {

    private let decoder = JSONDecoder()

    private func openFileJSON(kind: String) -> Data {
        Data("""
        {
            "id": "11111111-1111-1111-1111-111111111111",
            "path": "bugbook://browser",
            "content": "",
            "isDirty": false,
            "isEmptyTab": false,
            "kind": \(kind),
            "navigationHistory": [],
            "navigationHistoryIndex": -1,
            "isExternal": false
        }
        """.utf8)
    }

    // MARK: - F1: TabKind discriminator migration

    func testPersistedBrowserTabDecodesAsRemovedSentinel() throws {
        let file = try decoder.decode(OpenFile.self, from: openFileJSON(kind: #"{"browser":{}}"#))
        XCTAssertEqual(file.kind, .removed)
        XCTAssertFalse(BugbookFeatureGate.allowsTabKind(file.kind))
    }

    func testUnknownFutureKindDecodesAsRemovedSentinel() throws {
        let file = try decoder.decode(OpenFile.self, from: openFileJSON(kind: #"{"hologram":{}}"#))
        XCTAssertEqual(file.kind, .removed)
    }

    func testLiveKindsStillDecode() throws {
        XCTAssertEqual(
            try decoder.decode(OpenFile.self, from: openFileJSON(kind: #"{"page":{}}"#)).kind,
            .page
        )
        XCTAssertEqual(
            try decoder.decode(
                OpenFile.self,
                from: openFileJSON(kind: #"{"databaseRow":{"dbPath":"/ws/db","rowId":"row_1"}}"#)
            ).kind,
            .databaseRow(dbPath: "/ws/db", rowId: "row_1")
        )
    }

    func testCorruptDatabaseRowPayloadFailsDecode() {
        // Missing rowId — a real payload error on a live kind must rethrow,
        // not silently become .page.
        XCTAssertThrowsError(
            try decoder.decode(OpenFile.self, from: openFileJSON(kind: #"{"databaseRow":{"dbPath":"/ws/db"}}"#))
        )
    }

    func testSanitizerDropsRestoredBrowserTabWithoutZombie() throws {
        let browserFile = try decoder.decode(OpenFile.self, from: openFileJSON(kind: #"{"browser":{}}"#))
        let pageTab = PaneContent.document(openFile: OpenFile(
            id: UUID(),
            path: "/ws/Note.md",
            content: "",
            isDirty: false,
            isEmptyTab: false,
            kind: .page
        ))
        let paneID = UUID()
        let workspace = Workspace(
            id: UUID(),
            name: "Restored",
            icon: nil,
            root: .leaf(.init(
                id: paneID,
                tabs: [.document(openFile: browserFile), pageTab],
                selectedTabIndex: 0
            )),
            focusedPaneId: paneID,
            createdAt: Date()
        )

        let result = workspace.sanitizedForCurrentMode()

        XCTAssertTrue(result.changed)
        guard case .leaf(let leaf) = result.workspace.root else {
            return XCTFail("Expected a single leaf")
        }
        XCTAssertEqual(leaf.tabs.map(\.id), [pageTab.id], "browser tab must be stripped, page kept")
    }

    // MARK: - F7: removed pane types prune, splits collapse

    func testPersistedTerminalPaneDecodesAsPrunableSentinel() throws {
        let json = Data("""
        {"type": "terminal", "sessionID": "22222222-2222-2222-2222-222222222222"}
        """.utf8)
        let content = try decoder.decode(PaneContent.self, from: json)
        guard case .document(let file) = content else {
            return XCTFail("Expected a document sentinel")
        }
        XCTAssertEqual(file.kind, .removed)
        XCTAssertFalse(file.isEmptyTab, "sentinel must not masquerade as an allowed empty tab")
        XCTAssertFalse(BugbookFeatureGate.allowsPaneContent(content))
    }

    func testPersistedNotesTerminalSplitRestoresAsSingleNotesPane() throws {
        let terminalContent = try decoder.decode(PaneContent.self, from: Data("""
        {"type": "terminal", "sessionID": "22222222-2222-2222-2222-222222222222"}
        """.utf8))
        let notesTab = PaneContent.document(openFile: OpenFile(
            id: UUID(),
            path: "/ws/Daily.md",
            content: "",
            isDirty: false,
            isEmptyTab: false,
            kind: .page
        ))
        let notesPaneID = UUID()
        let terminalPaneID = terminalContent.id
        let workspace = Workspace(
            id: UUID(),
            name: "Restored",
            icon: nil,
            root: .split(PaneNode.Split(
                id: UUID(),
                axis: .horizontal,
                ratio: 0.5,
                first: .leaf(.init(id: notesPaneID, tabs: [notesTab], selectedTabIndex: 0)),
                second: .leaf(.init(id: terminalPaneID, tabs: [terminalContent], selectedTabIndex: 0))
            )),
            focusedPaneId: terminalPaneID,
            createdAt: Date()
        )

        let result = workspace.sanitizedForCurrentMode()

        XCTAssertTrue(result.changed)
        guard case .leaf(let leaf) = result.workspace.root else {
            return XCTFail("Split must collapse to the surviving notes pane, not keep a blank sibling")
        }
        XCTAssertEqual(leaf.id, notesPaneID)
        XCTAssertEqual(leaf.tabs.map(\.id), [notesTab.id])
        XCTAssertEqual(result.workspace.focusedPaneId, notesPaneID, "focus must move to the surviving pane")
    }

    func testWorkspaceOfOnlyRemovedPanesFallsBackToEmptyDocument() throws {
        let terminalContent = try decoder.decode(PaneContent.self, from: Data("""
        {"type": "terminal", "sessionID": "33333333-3333-3333-3333-333333333333"}
        """.utf8))
        let paneID = terminalContent.id
        let workspace = Workspace(
            id: UUID(),
            name: "Restored",
            icon: nil,
            root: .leaf(.init(id: paneID, tabs: [terminalContent], selectedTabIndex: 0)),
            focusedPaneId: paneID,
            createdAt: Date()
        )

        let result = workspace.sanitizedForCurrentMode()

        XCTAssertTrue(result.changed)
        guard case .leaf(let leaf) = result.workspace.root,
              case .document(let file) = leaf.activeContent else {
            return XCTFail("Expected a fallback empty-document leaf")
        }
        XCTAssertTrue(file.isEmptyTab)
        XCTAssertEqual(result.workspace.focusedPaneId, leaf.id)
    }
}
