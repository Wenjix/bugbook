import AppKit
import Foundation
import Observation
import WebKit

@MainActor
@Observable
final class BrowserManager {
    private(set) var sessions: [UUID: BrowserPaneSession] = [:]

    @ObservationIgnored private let snapshotStore: BrowserPaneSnapshotStore
    @ObservationIgnored private let processPool = WKProcessPool()
    @ObservationIgnored private let websiteDataStore = WKWebsiteDataStore.default()

    init(snapshotStore: BrowserPaneSnapshotStore = BrowserPaneSnapshotStore()) {
        self.snapshotStore = snapshotStore
    }

    func session(for paneID: UUID) -> BrowserPaneSession {
        if let session = sessions[paneID] {
            return session
        }

        let snapshot = snapshotStore.snapshot(for: paneID) ?? BrowserPaneSnapshot(paneID: paneID)
        let session = BrowserPaneSession(paneID: paneID, snapshot: snapshot)
        session.manager = self
        sessions[paneID] = session
        return session
    }

    func closeSession(_ paneID: UUID) {
        guard let session = sessions.removeValue(forKey: paneID) else { return }
        session.dispose()
        snapshotStore.removeSnapshot(for: paneID)
    }

    func cleanup(validPaneIDs: Set<UUID>) {
        let stalePaneIDs = Set(sessions.keys).subtracting(validPaneIDs)
        for paneID in stalePaneIDs {
            closeSession(paneID)
        }
    }

    func persistSession(_ paneID: UUID) {
        guard let session = sessions[paneID] else { return }
        snapshotStore.save(session.snapshot)
    }

    func persistAllSessions() {
        for paneID in sessions.keys {
            persistSession(paneID)
        }
    }

    func ensureWebView(for paneID: UUID, tabID: UUID) -> WKWebView {
        let session = session(for: paneID)
        if let existing = session.webViews[tabID] {
            return existing
        }

        let configuration = WKWebViewConfiguration()
        configuration.processPool = processPool
        configuration.websiteDataStore = websiteDataStore
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.applicationNameForUserAgent = "HarborDesktop"

        let userContentController = WKUserContentController()
        let coordinator = BrowserWebViewCoordinator(manager: self, paneID: paneID, tabID: tabID)
        userContentController.add(coordinator, name: BrowserWebViewCoordinator.hoverScriptName)
        userContentController.addUserScript(coordinator.hoverUserScript)
        configuration.userContentController = userContentController

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = coordinator
        webView.uiDelegate = coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.setValue(false, forKey: "drawsBackground")
        if #available(macOS 13.3, *), AppEnvironment.isDev {
            webView.isInspectable = true
        }

        coordinator.attach(to: webView)
        session.coordinators[tabID] = coordinator
        session.webViews[tabID] = webView

        if let tab = session.tabs.first(where: { $0.id == tabID }),
           let url = URL(string: tab.urlString),
           !tab.urlString.isEmpty {
            webView.load(URLRequest(url: url))
        }

        session.sync(tabID: tabID, from: webView)
        return webView
    }

    func activeWebView(for paneID: UUID) -> WKWebView? {
        guard let session = sessions[paneID],
              let tabID = session.selectedTabID else { return nil }
        return ensureWebView(for: paneID, tabID: tabID)
    }

    func openURL(_ url: URL, in paneID: UUID, newTab: Bool = false) {
        let session = session(for: paneID)
        let tabID: UUID
        if newTab {
            tabID = session.openNewTab(url: url)
        } else {
            tabID = session.selectedTabID ?? session.openNewTab(url: url)
            session.updateTab(tabID: tabID) { tab in
                tab.urlString = url.absoluteString
                tab.securityIconName = Self.securityIcon(for: url)
            }
        }

        let webView = ensureWebView(for: paneID, tabID: tabID)
        webView.load(URLRequest(url: url))
        persistSession(paneID)
    }

    func goBack(in paneID: UUID) {
        activeWebView(for: paneID)?.goBack()
    }

    func goForward(in paneID: UUID) {
        activeWebView(for: paneID)?.goForward()
    }

    func reload(in paneID: UUID) {
        activeWebView(for: paneID)?.reload()
    }

    func stopLoading(in paneID: UUID) {
        activeWebView(for: paneID)?.stopLoading()
    }

    func setPageZoom(_ zoom: Double, in paneID: UUID) {
        guard let session = sessions[paneID],
              let tabID = session.selectedTabID,
              let webView = activeWebView(for: paneID) else { return }
        webView.pageZoom = zoom
        session.updateTab(tabID: tabID) { tab in
            tab.pageZoom = zoom
        }
        persistSession(paneID)
    }

    func printActiveTab(in paneID: UUID) {
        guard let webView = activeWebView(for: paneID) else { return }
        let operation = webView.printOperation(with: .shared)
        operation.run()
    }

    func find(_ query: String, in paneID: UUID, forward: Bool = true) {
        guard let webView = activeWebView(for: paneID) else { return }
        let configuration = WKFindConfiguration()
        configuration.backwards = !forward
        configuration.wraps = true
        webView.find(query, configuration: configuration) { _ in }
    }

    fileprivate func recordVisit(title: String, url: URL, paneID: UUID) {
        let session = session(for: paneID)
        let visit = BrowserRecentVisit(title: title, urlString: url.absoluteString)
        session.recordVisit(visit)
        persistSession(paneID)
    }

    fileprivate func updateHoverURL(_ urlString: String?, paneID: UUID, tabID: UUID) {
        guard let session = sessions[paneID] else { return }
        session.updateTab(tabID: tabID) { tab in
            tab.hoverURLString = urlString
        }
    }

    fileprivate func updateTabState(from webView: WKWebView, paneID: UUID, tabID: UUID) {
        let session = session(for: paneID)
        session.sync(tabID: tabID, from: webView)
        persistSession(paneID)
    }

    fileprivate func configureDownload(_ download: WKDownload, paneID: UUID) {
        let delegate = BrowserDownloadDelegate(manager: self, paneID: paneID)
        download.delegate = delegate
        session(for: paneID).downloadDelegates[ObjectIdentifier(download)] = delegate
    }

    static func securityIcon(for url: URL?) -> String {
        guard let scheme = url?.scheme?.lowercased() else { return "magnifyingglass" }
        switch scheme {
        case "https": return "lock.fill"
        case "http": return "lock.open"
        default: return "magnifyingglass"
        }
    }
}

@MainActor
@Observable
final class BrowserPaneSession {
    let paneID: UUID
    var tabs: [BrowserTabState]
    var selectedTabID: UUID?
    var recentVisits: [BrowserRecentVisit]
    var isReadLaterDrawerOpen: Bool
    var lastDownloadMessage: String?

    @ObservationIgnored weak var manager: BrowserManager?
    @ObservationIgnored fileprivate var webViews: [UUID: WKWebView] = [:]
    @ObservationIgnored fileprivate var coordinators: [UUID: BrowserWebViewCoordinator] = [:]
    @ObservationIgnored fileprivate var downloadDelegates: [ObjectIdentifier: BrowserDownloadDelegate] = [:]

    init(paneID: UUID, snapshot: BrowserPaneSnapshot) {
        self.paneID = paneID
        let restoredTabs = snapshot.tabs.map {
            BrowserTabState(
                id: $0.id,
                title: $0.title,
                urlString: $0.urlString,
                savedRecordID: $0.savedRecordID,
                pageZoom: $0.pageZoom,
                securityIconName: BrowserManager.securityIcon(for: URL(string: $0.urlString))
            )
        }
        let initialTabs = restoredTabs.isEmpty ? [BrowserTabState()] : restoredTabs
        self.tabs = initialTabs
        self.selectedTabID = snapshot.selectedTabID ?? initialTabs.first?.id
        self.recentVisits = snapshot.recentVisits
        self.isReadLaterDrawerOpen = snapshot.isReadLaterDrawerOpen
    }

    var activeTab: BrowserTabState? {
        guard let selectedTabID else { return tabs.first }
        return tabs.first { $0.id == selectedTabID }
    }

    var snapshot: BrowserPaneSnapshot {
        BrowserPaneSnapshot(
            paneID: paneID,
            tabs: tabs.map {
                BrowserTabSnapshot(
                    id: $0.id,
                    title: $0.title,
                    urlString: $0.urlString,
                    savedRecordID: $0.savedRecordID,
                    pageZoom: $0.pageZoom
                )
            },
            selectedTabID: selectedTabID,
            recentVisits: recentVisits,
            isReadLaterDrawerOpen: isReadLaterDrawerOpen
        )
    }

    @discardableResult
    func openNewTab(url: URL? = nil, select: Bool = true) -> UUID {
        let tab = BrowserTabState(
            title: url?.host ?? "New Tab",
            urlString: url?.absoluteString ?? "",
            securityIconName: BrowserManager.securityIcon(for: url)
        )
        tabs.append(tab)
        if select {
            selectedTabID = tab.id
        }
        if let manager {
            _ = manager.ensureWebView(for: paneID, tabID: tab.id)
            if let url {
                manager.openURL(url, in: paneID, newTab: false)
            }
        }
        return tab.id
    }

    func closeTab(_ tabID: UUID) {
        tabs.removeAll { $0.id == tabID }
        webViews[tabID]?.navigationDelegate = nil
        webViews[tabID]?.uiDelegate = nil
        webViews.removeValue(forKey: tabID)
        coordinators.removeValue(forKey: tabID)
        if tabs.isEmpty {
            tabs = [BrowserTabState()]
        }
        if selectedTabID == tabID {
            selectedTabID = tabs.first?.id
        }
        manager?.persistSession(paneID)
    }

    func selectTab(_ tabID: UUID) {
        selectedTabID = tabID
        if let activeTab,
           let manager {
            let webView = manager.ensureWebView(for: paneID, tabID: activeTab.id)
            if activeTab.pageZoom != Double(webView.pageZoom) {
                webView.pageZoom = activeTab.pageZoom
            }
        }
        manager?.persistSession(paneID)
    }

    func updateSavedRecordID(_ recordID: UUID?, for tabID: UUID) {
        updateTab(tabID: tabID) { tab in
            tab.savedRecordID = recordID
        }
        manager?.persistSession(paneID)
    }

    func updateTab(tabID: UUID, transform: (inout BrowserTabState) -> Void) {
        guard let index = tabs.firstIndex(where: { $0.id == tabID }) else { return }
        transform(&tabs[index])
    }

    func sync(tabID: UUID, from webView: WKWebView) {
        updateTab(tabID: tabID) { tab in
            tab.title = webView.title?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? (webView.title ?? tab.title) : tab.title
            tab.urlString = webView.url?.absoluteString ?? tab.urlString
            tab.isLoading = webView.isLoading
            tab.estimatedProgress = webView.estimatedProgress
            tab.canGoBack = webView.canGoBack
            tab.canGoForward = webView.canGoForward
            tab.securityIconName = BrowserManager.securityIcon(for: webView.url)
            if webView.pageZoom > 0 {
                tab.pageZoom = webView.pageZoom
            }
        }
    }

    func recordVisit(_ visit: BrowserRecentVisit) {
        recentVisits.removeAll { $0.urlString == visit.urlString }
        recentVisits.insert(visit, at: 0)
        if recentVisits.count > 20 {
            recentVisits = Array(recentVisits.prefix(20))
        }
    }

    func toggleReadLaterDrawer() {
        isReadLaterDrawerOpen.toggle()
        manager?.persistSession(paneID)
    }

    func dispose() {
        for (_, webView) in webViews {
            webView.stopLoading()
            webView.navigationDelegate = nil
            webView.uiDelegate = nil
        }
        coordinators.removeAll()
        webViews.removeAll()
        downloadDelegates.removeAll()
    }
}

@MainActor
final class BrowserWebViewCoordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
    static let hoverScriptName = "browserLinkHover"

    private weak var manager: BrowserManager?
    private let paneID: UUID
    private let tabID: UUID
    private var observations: [NSKeyValueObservation] = []

    init(manager: BrowserManager, paneID: UUID, tabID: UUID) {
        self.manager = manager
        self.paneID = paneID
        self.tabID = tabID
    }

    var hoverUserScript: WKUserScript {
        let source = """
        document.addEventListener('mouseover', function(event) {
          const anchor = event.target.closest('a[href]');
          window.webkit.messageHandlers.\(Self.hoverScriptName).postMessage(anchor ? anchor.href : "");
        }, true);
        document.addEventListener('mouseout', function(event) {
          const anchor = event.target.closest('a[href]');
          if (anchor) {
            window.webkit.messageHandlers.\(Self.hoverScriptName).postMessage("");
          }
        }, true);
        """
        return WKUserScript(source: source, injectionTime: .atDocumentEnd, forMainFrameOnly: false)
    }

    func attach(to webView: WKWebView) {
        observations = [
            webView.observe(\.title, options: [.initial, .new]) { [weak self] webView, _ in
                self?.scheduleStateUpdate(from: webView)
            },
            webView.observe(\.url, options: [.initial, .new]) { [weak self] webView, _ in
                self?.scheduleStateUpdate(from: webView)
            },
            webView.observe(\.estimatedProgress, options: [.initial, .new]) { [weak self] webView, _ in
                self?.scheduleStateUpdate(from: webView)
            },
            webView.observe(\.isLoading, options: [.initial, .new]) { [weak self] webView, _ in
                self?.scheduleStateUpdate(from: webView)
            },
            webView.observe(\.canGoBack, options: [.initial, .new]) { [weak self] webView, _ in
                self?.scheduleStateUpdate(from: webView)
            },
            webView.observe(\.canGoForward, options: [.initial, .new]) { [weak self] webView, _ in
                self?.scheduleStateUpdate(from: webView)
            },
        ]
    }

    nonisolated private func scheduleStateUpdate(from webView: WKWebView) {
        Task { @MainActor [weak self] in
            guard let self, let manager else { return }
            manager.updateTabState(from: webView, paneID: paneID, tabID: tabID)
        }
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == Self.hoverScriptName else { return }
        let urlString = message.body as? String
        manager?.updateHoverURL(urlString?.isEmpty == true ? nil : urlString, paneID: paneID, tabID: tabID)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        manager?.updateTabState(from: webView, paneID: paneID, tabID: tabID)
        if let url = webView.url {
            manager?.recordVisit(title: webView.title ?? url.host ?? url.absoluteString, url: url, paneID: paneID)
        }
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        manager?.updateTabState(from: webView, paneID: paneID, tabID: tabID)
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        manager?.configureDownload(download, paneID: paneID)
    }

    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        manager?.configureDownload(download, paneID: paneID)
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        guard navigationAction.targetFrame == nil,
              let url = navigationAction.request.url else {
            return nil
        }
        manager?.openURL(url, in: paneID, newTab: true)
        return nil
    }
}

@MainActor
final class BrowserDownloadDelegate: NSObject, WKDownloadDelegate {
    private weak var manager: BrowserManager?
    private let paneID: UUID

    init(manager: BrowserManager, paneID: UUID) {
        self.manager = manager
        self.paneID = paneID
    }

    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String, completionHandler: @escaping @MainActor @Sendable (URL?) -> Void) {
        let directory = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let destination = uniqueDestination(in: directory, suggestedFilename: suggestedFilename)
        completionHandler(destination)
        manager?.session(for: paneID).lastDownloadMessage = "Downloading \(suggestedFilename)…"
    }

    func downloadDidFinish(_ download: WKDownload) {
        manager?.session(for: paneID).lastDownloadMessage = "Download finished"
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        manager?.session(for: paneID).lastDownloadMessage = error.localizedDescription
    }

    private func uniqueDestination(in directory: URL, suggestedFilename: String) -> URL {
        let baseName = (suggestedFilename as NSString).deletingPathExtension
        let ext = (suggestedFilename as NSString).pathExtension
        var candidate = directory.appendingPathComponent(suggestedFilename)
        var suffix = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            let nextName = ext.isEmpty ? "\(baseName) \(suffix)" : "\(baseName) \(suffix).\(ext)"
            candidate = directory.appendingPathComponent(nextName)
            suffix += 1
        }
        return candidate
    }
}

struct BrowserPaneSnapshotStore {
    private let fileManager: FileManager
    private let directoryURL: URL
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    init(fileManager: FileManager = .default, directoryURL: URL? = nil) {
        self.fileManager = fileManager
        self.directoryURL = directoryURL ?? Self.defaultDirectory(fileManager: fileManager)
    }

    func snapshot(for paneID: UUID) -> BrowserPaneSnapshot? {
        guard let data = try? Data(contentsOf: fileURL(for: paneID)),
              let snapshot = try? decoder.decode(BrowserPaneSnapshot.self, from: data) else {
            return nil
        }
        return snapshot
    }

    func save(_ snapshot: BrowserPaneSnapshot) {
        do {
            try ensureDirectoryExists()
            let data = try encoder.encode(snapshot)
            try data.write(to: fileURL(for: snapshot.paneID), options: .atomic)
        } catch {
            Log.app.error("Failed to persist browser pane snapshot: \(error.localizedDescription)")
        }
    }

    func removeSnapshot(for paneID: UUID) {
        try? fileManager.removeItem(at: fileURL(for: paneID))
    }

    private func ensureDirectoryExists() throws {
        guard !fileManager.fileExists(atPath: directoryURL.path) else { return }
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }

    private func fileURL(for paneID: UUID) -> URL {
        directoryURL.appendingPathComponent("\(paneID.uuidString).json")
    }

    private static func defaultDirectory(fileManager: FileManager) -> URL {
        let baseDirectory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return baseDirectory
            .appendingPathComponent("Bugbook", isDirectory: true)
            .appendingPathComponent("BrowserPanes", isDirectory: true)
    }
}
