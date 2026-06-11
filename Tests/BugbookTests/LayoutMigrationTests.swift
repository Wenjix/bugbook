import XCTest
@testable import Bugbook

/// Raw-JSON fixture tests for the persisted-layout migrations:
/// - removed tab kinds decode to the `.removed` sentinel (and corrupt live-kind
///   payloads fail decode instead of silently degrading),
/// - v1 pane-tree layouts (splits, per-leaf tab strips) flatten IN TREE ORDER
///   into one top-level tab per document,
/// - v2 layouts decode as-is.
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

    /// A v1 PaneContent document JSON blob for a page at `path`.
    private func documentTabJSON(id: String, path: String, name: String) -> String {
        """
        {
            "type": "document",
            "openFile": {
                "id": "\(id)",
                "path": "\(path)",
                "content": "",
                "isDirty": false,
                "isEmptyTab": false,
                "kind": {"page": {}},
                "displayName": "\(name)",
                "navigationHistory": [],
                "navigationHistoryIndex": -1,
                "isExternal": false
            }
        }
        """
    }

    // MARK: - TabKind discriminator migration (round 3, still pinned)

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

    // MARK: - v1 pane-tree layout → v2 tabs migration

    /// A v1 layout with a 2-way split: the left leaf holds two documents (A
    /// active, B background), the right leaf holds one (C, focused). The whole
    /// thing must flatten IN TREE ORDER into 3 top-level tabs — no document
    /// dropped — with the old focused document as the active tab.
    func testV1SplitLayoutFlattensInTreeOrderIntoOneTabPerDocument() throws {
        let json = Data("""
        {
            "version": 1,
            "activeWorkspaceIndex": 0,
            "workspaces": [
                {
                    "id": "AAAAAAAA-0000-0000-0000-000000000001",
                    "name": "Workspace",
                    "root": {
                        "type": "split",
                        "split": {
                            "id": "BBBBBBBB-0000-0000-0000-000000000001",
                            "axis": "horizontal",
                            "ratio": 0.5,
                            "first": {
                                "type": "leaf",
                                "leaf": {
                                    "id": "CCCCCCCC-0000-0000-0000-000000000001",
                                    "tabs": [
                                        \(documentTabJSON(id: "DDDDDDDD-0000-0000-0000-00000000000A", path: "/ws/A.md", name: "A")),
                                        \(documentTabJSON(id: "DDDDDDDD-0000-0000-0000-00000000000B", path: "/ws/B.md", name: "B"))
                                    ],
                                    "selectedTabIndex": 0
                                }
                            },
                            "second": {
                                "type": "leaf",
                                "leaf": {
                                    "id": "CCCCCCCC-0000-0000-0000-000000000002",
                                    "tabs": [
                                        \(documentTabJSON(id: "DDDDDDDD-0000-0000-0000-00000000000C", path: "/ws/C.md", name: "C"))
                                    ],
                                    "selectedTabIndex": 0
                                }
                            }
                        }
                    },
                    "focusedPaneId": "CCCCCCCC-0000-0000-0000-000000000002",
                    "createdAt": 700000000
                }
            ]
        }
        """.utf8)

        let layout = try WorkspaceManager.decodeLayout(from: json)

        XCTAssertTrue(layout.migrated)
        XCTAssertEqual(
            layout.workspaces.compactMap { $0.openFile?.path },
            ["/ws/A.md", "/ws/B.md", "/ws/C.md"],
            "documents must flatten in tree order with none dropped"
        )
        // The old active workspace's focused leaf had C selected → C is the active tab.
        XCTAssertEqual(layout.workspaces[layout.activeWorkspaceIndex].openFile?.path, "/ws/C.md")
        // One document per tab — every tab is a plain document workspace.
        XCTAssertEqual(layout.workspaces.count, 3)
    }

    /// A v1 layout containing a terminal pane and a browser tab: both decode
    /// to `.removed` sentinels, survive the flatten, and are pruned by the
    /// sanitizer — the surviving notes document is all that remains.
    func testV1LayoutWithRemovedKindsSanitizesThemAway() throws {
        let json = Data("""
        {
            "version": 1,
            "activeWorkspaceIndex": 0,
            "workspaces": [
                {
                    "id": "AAAAAAAA-0000-0000-0000-000000000002",
                    "name": "Workspace",
                    "root": {
                        "type": "split",
                        "split": {
                            "id": "BBBBBBBB-0000-0000-0000-000000000002",
                            "axis": "vertical",
                            "ratio": 0.6,
                            "first": {
                                "type": "leaf",
                                "leaf": {
                                    "id": "CCCCCCCC-0000-0000-0000-000000000003",
                                    "tabs": [
                                        \(documentTabJSON(id: "DDDDDDDD-0000-0000-0000-00000000000D", path: "/ws/Daily.md", name: "Daily")),
                                        {
                                            "type": "document",
                                            "openFile": {
                                                "id": "DDDDDDDD-0000-0000-0000-00000000000E",
                                                "path": "bugbook://browser",
                                                "content": "",
                                                "isDirty": false,
                                                "isEmptyTab": false,
                                                "kind": {"browser": {}},
                                                "navigationHistory": [],
                                                "navigationHistoryIndex": -1,
                                                "isExternal": false
                                            }
                                        }
                                    ],
                                    "selectedTabIndex": 0
                                }
                            },
                            "second": {
                                "type": "leaf",
                                "leaf": {
                                    "id": "CCCCCCCC-0000-0000-0000-000000000004",
                                    "tabs": [
                                        {"type": "terminal", "sessionID": "EEEEEEEE-0000-0000-0000-000000000001"}
                                    ],
                                    "selectedTabIndex": 0
                                }
                            }
                        }
                    },
                    "focusedPaneId": "CCCCCCCC-0000-0000-0000-000000000003",
                    "createdAt": 700000000
                }
            ]
        }
        """.utf8)

        let layout = try WorkspaceManager.decodeLayout(from: json)
        XCTAssertTrue(layout.migrated)
        XCTAssertEqual(layout.workspaces.count, 3, "flatten keeps every tab; sanitize prunes after")

        let manager = WorkspaceManager()
        manager.layoutPersistenceEnabled = false
        manager.workspaces = layout.workspaces
        manager.activeWorkspaceIndex = layout.activeWorkspaceIndex

        XCTAssertTrue(manager.sanitizeForCurrentMode())

        XCTAssertEqual(
            manager.workspaces.compactMap { $0.openFile?.path },
            ["/ws/Daily.md"],
            "removed-kind tabs (browser, terminal) must be sanitized away"
        )
    }

    /// Current-version layouts decode untouched.
    func testV2LayoutDecodesAsIs() throws {
        let json = Data("""
        {
            "version": 2,
            "activeWorkspaceIndex": 1,
            "workspaces": [
                {
                    "id": "AAAAAAAA-0000-0000-0000-000000000003",
                    "name": "A",
                    "content": \(documentTabJSON(id: "DDDDDDDD-0000-0000-0000-00000000001A", path: "/ws/A.md", name: "A")),
                    "createdAt": 700000000
                },
                {
                    "id": "AAAAAAAA-0000-0000-0000-000000000004",
                    "name": "B",
                    "content": \(documentTabJSON(id: "DDDDDDDD-0000-0000-0000-00000000001B", path: "/ws/B.md", name: "B")),
                    "createdAt": 700000000
                }
            ]
        }
        """.utf8)

        let layout = try WorkspaceManager.decodeLayout(from: json)
        XCTAssertFalse(layout.migrated)
        XCTAssertEqual(layout.activeWorkspaceIndex, 1)
        XCTAssertEqual(layout.workspaces.compactMap { $0.openFile?.path }, ["/ws/A.md", "/ws/B.md"])
    }

    /// v2 layouts round-trip through encode/decode (the re-persisted shape).
    func testV2LayoutRoundTripsThroughWorkspaceCodable() throws {
        let tab = Workspace(
            id: UUID(),
            name: "Note",
            icon: nil,
            content: .document(openFile: OpenFile(
                id: UUID(),
                path: "/ws/Note.md",
                content: "",
                isDirty: false,
                isEmptyTab: false,
                kind: .page
            )),
            createdAt: Date()
        )
        let data = try JSONEncoder().encode(tab)
        let decoded = try decoder.decode(Workspace.self, from: data)
        XCTAssertEqual(decoded.id, tab.id)
        XCTAssertEqual(decoded.openFile?.path, "/ws/Note.md")
    }
}
