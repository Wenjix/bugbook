import AppKit
import Foundation
import XCTest
@testable import Dahso

@MainActor
final class BrowserEngineTests: XCTestCase {
    func testBrowserManagerSyncsTabStateFromEngineEvents() {
        let engine = FakeBrowserEngine()
        let snapshotStore = BrowserPaneSnapshotStore(directoryURL: temporaryDirectory())
        let manager = BrowserManager(engine: engine, snapshotStore: snapshotStore)
        let paneID = UUID()
        let session = manager.session(for: paneID)
        let tabID = tryUnwrap(session.selectedTabID)

        _ = manager.ensurePage(for: paneID, tabID: tabID)
        let page = tryUnwrap(engine.pages[tabID])

        page.emit(
            .stateChanged(
                BrowserPageState(
                    title: "Example Page",
                    url: URL(string: "https://example.com/path"),
                    isLoading: false,
                    estimatedProgress: 1.0,
                    canGoBack: true,
                    canGoForward: false,
                    pageZoom: 1.25
                )
            )
        )

        let activeTab = tryUnwrap(session.activeTab)
        XCTAssertEqual(activeTab.title, "Example Page")
        XCTAssertEqual(activeTab.urlString, "https://example.com/path")
        XCTAssertTrue(activeTab.canGoBack)
        XCTAssertFalse(activeTab.canGoForward)
        XCTAssertEqual(activeTab.pageZoom, 1.25, accuracy: 0.001)
        XCTAssertEqual(activeTab.securityIconName, "lock.fill")
    }

    func testBrowserManagerOpensPopupTargetsInNewTabs() {
        let engine = FakeBrowserEngine()
        let snapshotStore = BrowserPaneSnapshotStore(directoryURL: temporaryDirectory())
        let manager = BrowserManager(engine: engine, snapshotStore: snapshotStore)
        let paneID = UUID()
        let session = manager.session(for: paneID)
        let initialTabID = tryUnwrap(session.selectedTabID)

        _ = manager.ensurePage(for: paneID, tabID: initialTabID)
        let page = tryUnwrap(engine.pages[initialTabID])
        let popupURL = tryUnwrap(URL(string: "https://example.com/popup"))

        page.emit(.openInNewTab(popupURL))

        XCTAssertEqual(session.tabs.count, 2)
        XCTAssertEqual(session.activeTab?.urlString, popupURL.absoluteString)
        XCTAssertNotNil(engine.pages[session.selectedTabID ?? UUID()])
    }

    func testBrowserManagerPropagatesHoverAndDownloadState() {
        let engine = FakeBrowserEngine()
        let snapshotStore = BrowserPaneSnapshotStore(directoryURL: temporaryDirectory())
        let manager = BrowserManager(engine: engine, snapshotStore: snapshotStore)
        let paneID = UUID()
        let session = manager.session(for: paneID)
        let tabID = tryUnwrap(session.selectedTabID)

        _ = manager.ensurePage(for: paneID, tabID: tabID)
        let page = tryUnwrap(engine.pages[tabID])

        page.emit(.hoverURLChanged("https://example.com/hover"))
        XCTAssertEqual(session.activeTab?.hoverURLString, "https://example.com/hover")

        page.emit(.downloadStatusChanged("Download finished"))
        XCTAssertEqual(session.lastDownloadMessage, "Download finished")
    }

    func testBrowserManagerRestoresSnapshotIntoEnginePages() {
        let directoryURL = temporaryDirectory()
        let snapshotStore = BrowserPaneSnapshotStore(directoryURL: directoryURL)
        let paneID = UUID()
        let snapshot = BrowserPaneSnapshot(
            paneID: paneID,
            tabs: [
                BrowserTabSnapshot(
                    id: UUID(),
                    title: "Restored",
                    urlString: "https://example.com/restored",
                    pageZoom: 1.4
                )
            ]
        )
        snapshotStore.save(snapshot)

        let engine = FakeBrowserEngine()
        let manager = BrowserManager(engine: engine, snapshotStore: snapshotStore)
        let session = manager.session(for: paneID)
        let tabID = tryUnwrap(session.selectedTabID)

        let page = manager.ensurePage(for: paneID, tabID: tabID)

        XCTAssertEqual(session.activeTab?.urlString, "https://example.com/restored")
        XCTAssertEqual(page.state.url?.absoluteString, "https://example.com/restored")
        XCTAssertEqual(page.state.pageZoom, 1.4, accuracy: 0.001)
    }

    func testBrowserAgentServiceSavesPageUsingEngineJavaScript() async throws {
        let directoryURL = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let store = SavedWebPageStore(directoryURL: directoryURL.appendingPathComponent("saved", isDirectory: true))
        let snapshotStore = BrowserPaneSnapshotStore(directoryURL: directoryURL.appendingPathComponent("snapshots", isDirectory: true))
        let engine = FakeBrowserEngine()
        let manager = BrowserManager(engine: engine, snapshotStore: snapshotStore)
        let paneID = UUID()
        let session = manager.session(for: paneID)
        let tabID = tryUnwrap(session.selectedTabID)

        _ = manager.ensurePage(for: paneID, tabID: tabID)
        let page = tryUnwrap(engine.pages[tabID])
        page.javaScriptResult = """
        {"title":"Deep Link","text":"First sentence. Second sentence. Third sentence.","url":"https://example.com/deep"}
        """

        let fileSystem = FileSystemService()
        let service = BrowserAgentService(savedPageStore: store)
        let workspacePath = directoryURL.appendingPathComponent("workspace", isDirectory: true).path
        try FileManager.default.createDirectory(atPath: workspacePath, withIntermediateDirectories: true)

        let result = try await service.saveTab(
            from: paneID,
            tabID: tabID,
            browserManager: manager,
            fileSystem: fileSystem,
            workspacePath: workspacePath,
            settings: AppSettings.default,
            aiService: nil
        )

        XCTAssertEqual(result.record.title, "Deep Link")
        XCTAssertEqual(result.record.urlString, "https://example.com/deep")
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.notePath))
        let content = try String(contentsOfFile: result.notePath, encoding: .utf8)
        XCTAssertTrue(content.contains("https://example.com/deep"))
        XCTAssertTrue(content.contains("First sentence"))
    }

    func testBrowserManagerClearsCookiesThroughEngine() async throws {
        let engine = FakeBrowserEngine()
        let snapshotStore = BrowserPaneSnapshotStore(directoryURL: temporaryDirectory())
        let manager = BrowserManager(engine: engine, snapshotStore: snapshotStore)

        try await manager.clearCookies()

        XCTAssertEqual(engine.clearCookiesCallCount, 1)
    }

    func testBrowserManagerDoesNotRecordHistoryWhenDisabled() {
        let directoryURL = temporaryDirectory()
        let engine = FakeBrowserEngine()
        let snapshotStore = BrowserPaneSnapshotStore(directoryURL: directoryURL.appendingPathComponent("snapshots", isDirectory: true))
        let historyStore = BrowserHistoryStore(fileURL: directoryURL.appendingPathComponent("history.json"))
        let manager = BrowserManager(engine: engine, snapshotStore: snapshotStore, historyStore: historyStore)
        let paneID = UUID()
        let session = manager.session(for: paneID)
        let tabID = tryUnwrap(session.selectedTabID)

        _ = manager.ensurePage(for: paneID, tabID: tabID)
        let page = tryUnwrap(engine.pages[tabID])
        manager.setHistoryEnabled(false)

        page.emit(.didFinishNavigation(title: "Example", url: URL(string: "https://example.com")!))

        XCTAssertTrue(manager.browsingHistory.isEmpty)
        XCTAssertTrue(session.recentVisits.isEmpty)
        XCTAssertTrue(historyStore.load().isEmpty)
    }

    func testBrowserManagerForwardsConfiguredExtensionPathsToEngine() {
        let engine = FakeBrowserEngine()
        let snapshotStore = BrowserPaneSnapshotStore(directoryURL: temporaryDirectory())
        let manager = BrowserManager(engine: engine, snapshotStore: snapshotStore)
        let paths = ["/tmp/extensions/one", "/tmp/extensions/two"]

        manager.configureExtensions(paths)

        XCTAssertEqual(engine.configuredExtensionPaths, paths)
    }

    func testBrowserManagerClearHistoryRemovesGlobalAndSessionHistory() {
        let directoryURL = temporaryDirectory()
        let engine = FakeBrowserEngine()
        let snapshotStore = BrowserPaneSnapshotStore(directoryURL: directoryURL.appendingPathComponent("snapshots", isDirectory: true))
        let historyStore = BrowserHistoryStore(fileURL: directoryURL.appendingPathComponent("history.json"))
        let manager = BrowserManager(engine: engine, snapshotStore: snapshotStore, historyStore: historyStore)
        let paneID = UUID()
        let session = manager.session(for: paneID)
        let tabID = tryUnwrap(session.selectedTabID)

        _ = manager.ensurePage(for: paneID, tabID: tabID)
        let page = tryUnwrap(engine.pages[tabID])
        page.emit(.didFinishNavigation(title: "Example", url: URL(string: "https://example.com")!))

        XCTAssertEqual(manager.browsingHistory.count, 1)
        XCTAssertEqual(session.recentVisits.count, 1)
        XCTAssertEqual(historyStore.load().count, 1)

        manager.clearHistory()

        XCTAssertTrue(manager.browsingHistory.isEmpty)
        XCTAssertTrue(session.recentVisits.isEmpty)
        XCTAssertTrue(historyStore.load().isEmpty)
        XCTAssertTrue(snapshotStore.snapshot(for: paneID)?.recentVisits.isEmpty == true)
    }

    private func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func tryUnwrap<T>(_ value: T?, file: StaticString = #filePath, line: UInt = #line) -> T {
        guard let value else {
            XCTFail("Expected non-nil value", file: file, line: line)
            fatalError("Unexpected nil")
        }
        return value
    }
}

@MainActor
private final class FakeBrowserEngine: BrowserEngine {
    private(set) var pages: [UUID: FakeBrowserPage] = [:]
    private(set) var clearCookiesCallCount = 0
    private(set) var configuredExtensionPaths: [String] = []

    func makePage(
        for paneID: UUID,
        tabID: UUID,
        initialURL: URL?,
        eventHandler: @escaping BrowserPageEventHandler
    ) -> any BrowserPage {
        let page = FakeBrowserPage(initialURL: initialURL, eventHandler: eventHandler)
        pages[tabID] = page
        return page
    }

    func configureExtensions(_ extensionPaths: [String]) {
        configuredExtensionPaths = extensionPaths
    }

    func clearCookies() async throws {
        clearCookiesCallCount += 1
    }
}

@MainActor
private final class FakeBrowserPage: BrowserPage {
    let hostView = NSView(frame: .zero)
    var state: BrowserPageState
    var javaScriptResult = ""
    private let eventHandler: BrowserPageEventHandler

    init(initialURL: URL?, eventHandler: @escaping BrowserPageEventHandler) {
        self.eventHandler = eventHandler
        self.state = BrowserPageState(
            title: nil,
            url: initialURL,
            isLoading: false,
            estimatedProgress: 0,
            canGoBack: false,
            canGoForward: false,
            pageZoom: 1.0
        )
    }

    func load(_ request: URLRequest) {
        state.url = request.url
        eventHandler(.stateChanged(state))
    }

    func goBack() {}
    func goForward() {}
    func reload() {}
    func stopLoading() {}

    func setPageZoom(_ zoom: Double) {
        state.pageZoom = zoom
        eventHandler(.stateChanged(state))
    }

    func printPage() {}

    func find(_ query: String, forward: Bool) {}

    func evaluateJavaScript(_ script: String) async throws -> String {
        javaScriptResult
    }

    func dispose() {}

    func emit(_ event: BrowserPageEvent) {
        switch event {
        case .stateChanged(let nextState):
            state = nextState
        default:
            break
        }
        eventHandler(event)
    }
}
