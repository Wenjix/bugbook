import Foundation
import XCTest
@testable import Dahso

@MainActor
final class BrowserFeatureTests: XCTestCase {
    func testBrowserDocumentFactoryProducesBrowserOpenFile() {
        let content = PaneContent.browserDocument()

        guard case .document(let openFile) = content else {
            XCTFail("Expected a document pane.")
            return
        }

        XCTAssertEqual(openFile.kind, .browser)
        XCTAssertTrue(openFile.isBrowser)
        XCTAssertEqual(openFile.path, "dahso://browser")
        XCTAssertEqual(openFile.displayName, "Browser")
        XCTAssertEqual(openFile.icon, "globe")
        XCTAssertFalse(openFile.isEmptyTab)
    }

    func testTabKindBrowserFlags() {
        XCTAssertTrue(TabKind.browser.isBrowser)
        XCTAssertFalse(TabKind.browser.isMail)
        XCTAssertFalse(TabKind.browser.isCalendar)
        XCTAssertFalse(TabKind.browser.isMeetings)
        XCTAssertFalse(TabKind.browser.isDatabase)
    }

    func testBrowserExtensionStoreInstallerAcceptsRawExtensionID() {
        let extensionID = "cjpalhdlnbpafiamejdnhcphjbkeiagm"

        XCTAssertEqual(BrowserExtensionStoreInstaller.extensionID(from: extensionID), extensionID)
    }

    func testBrowserExtensionStoreInstallerParsesChromeWebStoreURLs() {
        XCTAssertEqual(
            BrowserExtensionStoreInstaller.extensionID(
                from: "https://chromewebstore.google.com/detail/ublock-origin/cjpalhdlnbpafiamejdnhcphjbkeiagm?hl=en-US"
            ),
            "cjpalhdlnbpafiamejdnhcphjbkeiagm"
        )

        XCTAssertEqual(
            BrowserExtensionStoreInstaller.extensionID(
                from: "https://chrome.google.com/webstore/detail/ublock-origin/cjpalhdlnbpafiamejdnhcphjbkeiagm"
            ),
            "cjpalhdlnbpafiamejdnhcphjbkeiagm"
        )
    }

    func testBrowserExtensionStoreInstallerExtractsCRX3ZIPPayload() throws {
        let zipPayload = Data([0x50, 0x4B, 0x03, 0x04, 0x01, 0x02])
        var crxData = Data("Cr24".utf8)
        crxData.append(contentsOf: [0x03, 0x00, 0x00, 0x00])
        crxData.append(contentsOf: [0x04, 0x00, 0x00, 0x00])
        crxData.append(contentsOf: [0xDE, 0xAD, 0xBE, 0xEF])
        crxData.append(zipPayload)

        XCTAssertEqual(try BrowserExtensionStoreInstaller.extractZIPPayload(from: crxData), zipPayload)
    }

    func testAppSettingsBrowserFieldsRoundTrip() throws {
        var settings = AppSettings.default
        settings.browserSearchEngine = .kagi
        settings.browserHistoryEnabled = false
        settings.browserSuggestionsEnabled = true
        settings.browserSuggestionLimit = 10
        settings.browserSuggestsDahsoPages = false
        settings.browserChrome.showsBackForwardButtons = true
        settings.browserChrome.showsStatusBar = true
        settings.browserQuickLaunchItems = [
            BrowserQuickLaunchItem(title: "Docs", url: "https://example.com", icon: "doc.text")
        ]
        settings.browserExtensionPaths = [
            "/tmp/extensions/one",
            "/tmp/extensions/one/",
            "/tmp/extensions/two"
        ]
        settings.browserDefaultSaveFolder = "Research/Web"

        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)

        XCTAssertEqual(decoded.browserSearchEngine, .kagi)
        XCTAssertFalse(decoded.browserHistoryEnabled)
        XCTAssertTrue(decoded.browserSuggestionsEnabled)
        XCTAssertEqual(decoded.browserSuggestionLimit, 10)
        XCTAssertFalse(decoded.browserSuggestsDahsoPages)
        XCTAssertTrue(decoded.browserChrome.showsBackForwardButtons)
        XCTAssertTrue(decoded.browserChrome.showsStatusBar)
        XCTAssertEqual(decoded.browserQuickLaunchItems, settings.browserQuickLaunchItems)
        XCTAssertEqual(decoded.browserExtensionPaths, ["/tmp/extensions/one", "/tmp/extensions/two"])
        XCTAssertEqual(decoded.browserDefaultSaveFolder, "Research/Web")
    }

    func testSavedWebPageStoreRoundTripsAndUpdatesStatus() {
        let directoryURL = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let store = SavedWebPageStore(directoryURL: directoryURL)
        let workspacePath = "/tmp/browser-tests"
        let record = SavedWebPageRecord(
            title: "Example",
            urlString: "https://example.com",
            savedAt: Date(timeIntervalSince1970: 1_234),
            folderPath: "/tmp/browser-tests/Web",
            notePath: "/tmp/browser-tests/Web/Example.md",
            status: .unread,
            summary: "Summary"
        )

        store.upsert(record, in: workspacePath)
        XCTAssertEqual(store.record(forURL: "https://example.com", in: workspacePath), record)

        store.markStatus(.read, for: record.id, in: workspacePath)
        XCTAssertEqual(store.record(forURL: "https://example.com", in: workspacePath)?.status, .read)

        store.remove(recordID: record.id, in: workspacePath)
        XCTAssertNil(store.record(forURL: "https://example.com", in: workspacePath))
    }

    func testBrowserPaneSnapshotStoreRoundTripsSnapshot() {
        let directoryURL = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let store = BrowserPaneSnapshotStore(directoryURL: directoryURL)
        let paneID = UUID()
        let snapshot = BrowserPaneSnapshot(
            paneID: paneID,
            tabs: [
                BrowserTabSnapshot(title: "Example", urlString: "https://example.com", pageZoom: 1.25)
            ],
            recentVisits: [
                BrowserRecentVisit(title: "Example", urlString: "https://example.com", visitedAt: Date(timeIntervalSince1970: 42))
            ],
            isReadLaterDrawerOpen: true
        )

        store.save(snapshot)
        XCTAssertEqual(store.snapshot(for: paneID), snapshot)

        store.removeSnapshot(for: paneID)
        XCTAssertNil(store.snapshot(for: paneID))
    }

    func testBrowserHistoryStoreRoundTripsVisits() {
        let directoryURL = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let store = BrowserHistoryStore(fileURL: directoryURL.appendingPathComponent("history.json"))
        let visit = BrowserRecentVisit(
            title: "Example",
            urlString: "https://example.com",
            visitedAt: Date(timeIntervalSince1970: 123)
        )

        store.save([visit])
        XCTAssertEqual(store.load(), [visit])

        store.clear()
        XCTAssertTrue(store.load().isEmpty)
    }

    func testBrowserPaneSessionMoveTabPreservesSelectedTab() {
        let manager = BrowserManager(snapshotStore: BrowserPaneSnapshotStore(directoryURL: temporaryDirectory()))
        let paneID = UUID()
        let session = manager.session(for: paneID)
        let secondTabID = session.openNewTab(url: URL(string: "https://example.com/second"))
        let thirdTabID = session.openNewTab(url: URL(string: "https://example.com/third"))

        session.selectTab(secondTabID)
        session.moveTab(from: 1, to: 3)

        XCTAssertEqual(session.tabs.map(\.id), [session.tabs[0].id, thirdTabID, secondTabID])
        XCTAssertEqual(session.selectedTabID, secondTabID)
    }

    func testWorkspaceManagerDetachWorkspaceLeavesFallbackWorkspace() {
        let manager = WorkspaceManager()
        manager.layoutPersistenceEnabled = false
        manager.addWorkspace(name: "One")

        let detached = manager.detachWorkspace(at: 0)

        XCTAssertEqual(detached?.name, "One")
        XCTAssertEqual(manager.workspaces.count, 1)
        XCTAssertEqual(manager.activeWorkspaceIndex, 0)
    }

    func testBrowserCleanupProposalUsesSavedAndDuplicateSignals() {
        let directoryURL = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let workspacePath = "/tmp/browser-cleanup"
        let savedStore = SavedWebPageStore(directoryURL: directoryURL.appendingPathComponent("saved", isDirectory: true))
        savedStore.upsert(
            SavedWebPageRecord(
                title: "Saved",
                urlString: "https://example.com/saved",
                folderPath: "/tmp/browser-cleanup/Web",
                notePath: "/tmp/browser-cleanup/Web/Saved.md"
            ),
            in: workspacePath
        )

        let snapshotStore = BrowserPaneSnapshotStore(directoryURL: directoryURL.appendingPathComponent("snapshots", isDirectory: true))
        let browserManager = BrowserManager(snapshotStore: snapshotStore)
        let paneID = UUID()
        let session = browserManager.session(for: paneID)
        let savedTab = BrowserTabState(title: "Saved", urlString: "https://example.com/saved")
        let duplicateTab = BrowserTabState(title: "Duplicate", urlString: "https://example.com/dup")
        let duplicateTab2 = BrowserTabState(title: "Duplicate Copy", urlString: "https://example.com/dup")
        let mailTab = BrowserTabState(title: "Mail", urlString: "https://mail.google.com/mail/u/0/#inbox")
        session.tabs = [savedTab, duplicateTab, duplicateTab2, mailTab]
        session.selectedTabID = savedTab.id

        let service = BrowserAgentService(savedPageStore: savedStore)
        let proposals = service.proposeCleanup(for: paneID, browserManager: browserManager, workspacePath: workspacePath)

        XCTAssertEqual(proposals.first(where: { $0.urlString == "https://example.com/saved" })?.decision, .close)
        XCTAssertEqual(proposals.first(where: { $0.title == "Duplicate Copy" })?.decision, .close)
        XCTAssertEqual(proposals.first(where: { $0.urlString == "https://mail.google.com/mail/u/0/#inbox" })?.decision, .close)
    }

    private func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
