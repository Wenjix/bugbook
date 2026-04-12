import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class BrowserManager {
    private(set) var sessions: [UUID: BrowserPaneSession] = [:]
    private(set) var browsingHistory: [BrowserRecentVisit]
    var isHistoryEnabled = true

    @ObservationIgnored private let engine: any BrowserEngine
    @ObservationIgnored private let snapshotStore: BrowserPaneSnapshotStore
    @ObservationIgnored private let historyStore: BrowserHistoryStore

    init(
        engine: (any BrowserEngine)? = nil,
        snapshotStore: BrowserPaneSnapshotStore = BrowserPaneSnapshotStore(),
        historyStore: BrowserHistoryStore = BrowserHistoryStore()
    ) {
        self.engine = engine ?? BrowserEngineFactory.makeDefault()
        self.snapshotStore = snapshotStore
        self.historyStore = historyStore
        self.browsingHistory = historyStore.load()
    }

    func session(for paneID: UUID) -> BrowserPaneSession {
        if let session = sessions[paneID] {
            return session
        }

        let session = makeSession(for: paneID)
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

    func clearHistory() {
        browsingHistory.removeAll()
        historyStore.clear()
        snapshotStore.clearHistory()
        for paneID in sessions.keys {
            sessions[paneID]?.recentVisits.removeAll()
            persistSession(paneID)
        }
    }

    func clearCookies() async throws {
        try await engine.clearCookies()
    }

    func configureExtensions(_ extensionPaths: [String]) {
        engine.configureExtensions(extensionPaths)
    }

    func setHistoryEnabled(_ enabled: Bool) {
        isHistoryEnabled = enabled
    }

    func restoreSessionSnapshot(_ snapshot: BrowserPaneSnapshot, for paneID: UUID) {
        let session = BrowserPaneSession(paneID: paneID, snapshot: snapshot)
        session.manager = self
        sessions[paneID] = session
    }

    func snapshot(for paneID: UUID) -> BrowserPaneSnapshot? {
        if let session = sessions[paneID] {
            return session.snapshot
        }
        return snapshotStore.snapshot(for: paneID)
    }

    func ensurePage(for paneID: UUID, tabID: UUID) -> any BrowserPage {
        let session = session(for: paneID)
        if let existing = session.pages[tabID] {
            return existing
        }

        let tab = session.tabs.first(where: { $0.id == tabID })
        let initialURL = tab?.url
        let page = engine.makePage(for: paneID, tabID: tabID, initialURL: initialURL) { [weak self] event in
            self?.handlePageEvent(event, paneID: paneID, tabID: tabID)
        }
        if let pageZoom = tab?.pageZoom, pageZoom > 0 {
            page.setPageZoom(pageZoom)
        }
        session.pages[tabID] = page
        session.sync(tabID: tabID, from: page.state)
        return page
    }

    func activePage(for paneID: UUID) -> (any BrowserPage)? {
        guard let session = sessions[paneID],
              let tabID = session.selectedTabID else { return nil }
        return ensurePage(for: paneID, tabID: tabID)
    }

    func activeHostView(for paneID: UUID) -> NSView? {
        activePage(for: paneID)?.hostView
    }

    func openURL(_ url: URL, in paneID: UUID, newTab: Bool = false) {
        let session = session(for: paneID)
        let tabID = tabIDForOpenURL(url, in: session, newTab: newTab)

        let page = ensurePage(for: paneID, tabID: tabID)
        page.load(URLRequest(url: url))
        persistSession(paneID)
    }

    func goBack(in paneID: UUID) {
        activePage(for: paneID)?.goBack()
    }

    func goForward(in paneID: UUID) {
        activePage(for: paneID)?.goForward()
    }

    func reload(in paneID: UUID) {
        activePage(for: paneID)?.reload()
    }

    func stopLoading(in paneID: UUID) {
        activePage(for: paneID)?.stopLoading()
    }

    func setPageZoom(_ zoom: Double, in paneID: UUID) {
        guard let session = sessions[paneID],
              let tabID = session.selectedTabID,
              let page = activePage(for: paneID) else { return }
        page.setPageZoom(zoom)
        session.updateTab(tabID: tabID) { tab in
            tab.pageZoom = zoom
        }
        persistSession(paneID)
    }

    func printActiveTab(in paneID: UUID) {
        activePage(for: paneID)?.printPage()
    }

    func find(_ query: String, in paneID: UUID, forward: Bool = true) {
        activePage(for: paneID)?.find(query, forward: forward)
    }

    func evaluateJavaScript(_ script: String, in paneID: UUID, tabID: UUID) async throws -> String {
        let page = ensurePage(for: paneID, tabID: tabID)
        return try await page.evaluateJavaScript(script)
    }

    fileprivate func recordVisit(title: String, url: URL, paneID: UUID) {
        guard isHistoryEnabled else { return }
        let session = session(for: paneID)
        let visit = BrowserRecentVisit(title: title, urlString: url.absoluteString)
        session.recordVisit(visit)
        recordGlobalVisit(visit)
        persistSession(paneID)
    }

    fileprivate func updateHoverURL(_ urlString: String?, paneID: UUID, tabID: UUID) {
        guard let session = sessions[paneID] else { return }
        session.updateTab(tabID: tabID) { tab in
            tab.hoverURLString = urlString
        }
    }

    fileprivate func updateTabState(_ state: BrowserPageState, paneID: UUID, tabID: UUID) {
        let session = session(for: paneID)
        session.sync(tabID: tabID, from: state)
        persistSession(paneID)
    }

    fileprivate func updateDownloadStatus(_ message: String, paneID: UUID) {
        session(for: paneID).lastDownloadMessage = message
    }

    private func recordGlobalVisit(_ visit: BrowserRecentVisit) {
        browsingHistory.removeAll { $0.urlString == visit.urlString }
        browsingHistory.insert(visit, at: 0)
        if browsingHistory.count > 200 {
            browsingHistory = Array(browsingHistory.prefix(200))
        }
        historyStore.save(browsingHistory)
    }

    private func makeSession(for paneID: UUID) -> BrowserPaneSession {
        let snapshot = snapshotStore.snapshot(for: paneID) ?? BrowserPaneSnapshot(paneID: paneID)
        let session = BrowserPaneSession(paneID: paneID, snapshot: snapshot)
        session.manager = self
        return session
    }

    private func tabIDForOpenURL(_ url: URL, in session: BrowserPaneSession, newTab: Bool) -> UUID {
        if newTab {
            return session.openNewTab(url: url)
        }

        let tabID = session.selectedTabID ?? session.openNewTab(url: url)
        session.updateTab(tabID: tabID) { tab in
            tab.urlString = url.absoluteString
            tab.securityIconName = Self.securityIcon(for: url)
        }
        return tabID
    }

    fileprivate func handlePageEvent(_ event: BrowserPageEvent, paneID: UUID, tabID: UUID) {
        switch event {
        case .stateChanged(let state):
            updateTabState(state, paneID: paneID, tabID: tabID)
        case .hoverURLChanged(let urlString):
            updateHoverURL(urlString, paneID: paneID, tabID: tabID)
        case .didFinishNavigation(let title, let url):
            recordVisit(title: title, url: url, paneID: paneID)
            updateTabState(ensurePage(for: paneID, tabID: tabID).state, paneID: paneID, tabID: tabID)
        case .openInNewTab(let url):
            openURL(url, in: paneID, newTab: true)
        case .downloadStatusChanged(let message):
            updateDownloadStatus(message, paneID: paneID)
        }
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
    @ObservationIgnored fileprivate var pages: [UUID: any BrowserPage] = [:]

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
        if shouldCreateBlankPage(for: url) {
            _ = manager?.ensurePage(for: paneID, tabID: tab.id)
        }
        return tab.id
    }

    func closeTab(_ tabID: UUID) {
        tabs.removeAll { $0.id == tabID }
        pages[tabID]?.dispose()
        pages.removeValue(forKey: tabID)
        if tabs.isEmpty {
            tabs = [BrowserTabState()]
        }
        if selectedTabID == tabID {
            selectedTabID = tabs.first?.id
        }
        manager?.persistSession(paneID)
    }

    func moveTab(from sourceIndex: Int, to destinationIndex: Int) {
        guard sourceIndex != destinationIndex,
              sourceIndex >= 0, sourceIndex < tabs.count,
              destinationIndex >= 0, destinationIndex <= tabs.count else { return }

        let selectedTabID = self.selectedTabID
        let tab = tabs.remove(at: sourceIndex)
        let adjustedDestination = destinationIndex > sourceIndex ? destinationIndex - 1 : destinationIndex
        tabs.insert(tab, at: adjustedDestination)

        if let selectedTabID,
           let updatedIndex = tabs.firstIndex(where: { $0.id == selectedTabID }) {
            self.selectedTabID = tabs[updatedIndex].id
        }

        manager?.persistSession(paneID)
    }

    func selectTab(_ tabID: UUID) {
        selectedTabID = tabID
        if let activeTab,
           let manager {
            let page = manager.ensurePage(for: paneID, tabID: activeTab.id)
            if abs(activeTab.pageZoom - page.state.pageZoom) > 0.001 {
                page.setPageZoom(activeTab.pageZoom)
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

    func sync(tabID: UUID, from state: BrowserPageState) {
        updateTab(tabID: tabID) { tab in
            let trimmedTitle = state.title?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let trimmedTitle, !trimmedTitle.isEmpty {
                tab.title = trimmedTitle
            }
            tab.urlString = state.url?.absoluteString ?? tab.urlString
            tab.isLoading = state.isLoading
            tab.estimatedProgress = state.estimatedProgress
            tab.canGoBack = state.canGoBack
            tab.canGoForward = state.canGoForward
            tab.securityIconName = BrowserManager.securityIcon(for: state.url)
            tab.pageZoom = state.pageZoom > 0 ? state.pageZoom : tab.pageZoom
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
        for (_, page) in pages {
            page.dispose()
        }
        pages.removeAll()
    }

    private func shouldCreateBlankPage(for url: URL?) -> Bool {
        url == nil
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

    func clearHistory() {
        guard let enumerator = fileManager.enumerator(at: directoryURL, includingPropertiesForKeys: nil) else {
            return
        }

        for case let url as URL in enumerator where url.pathExtension == "json" {
            guard let data = try? Data(contentsOf: url),
                  var snapshot = try? decoder.decode(BrowserPaneSnapshot.self, from: data) else {
                continue
            }
            snapshot.recentVisits.removeAll()
            guard let encoded = try? encoder.encode(snapshot) else { continue }
            try? encoded.write(to: url, options: .atomic)
        }
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
            .appendingPathComponent("Dahso", isDirectory: true)
            .appendingPathComponent("BrowserPanes", isDirectory: true)
    }
}

struct BrowserHistoryStore {
    private let fileManager: FileManager
    private let fileURL: URL
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

    init(fileManager: FileManager = .default, fileURL: URL? = nil) {
        self.fileManager = fileManager
        self.fileURL = fileURL ?? Self.defaultFileURL(fileManager: fileManager)
    }

    func load() -> [BrowserRecentVisit] {
        guard let data = try? Data(contentsOf: fileURL),
              let visits = try? decoder.decode([BrowserRecentVisit].self, from: data) else {
            return []
        }
        return visits
    }

    func save(_ visits: [BrowserRecentVisit]) {
        do {
            try ensureDirectoryExists()
            let data = try encoder.encode(visits)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            Log.app.error("Failed to persist browser history: \(error.localizedDescription)")
        }
    }

    func clear() {
        try? fileManager.removeItem(at: fileURL)
    }

    private func ensureDirectoryExists() throws {
        let directoryURL = fileURL.deletingLastPathComponent()
        guard !fileManager.fileExists(atPath: directoryURL.path) else { return }
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }

    private static func defaultFileURL(fileManager: FileManager) -> URL {
        let baseDirectory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return baseDirectory
            .appendingPathComponent("Dahso", isDirectory: true)
            .appendingPathComponent("BrowserHistory", isDirectory: true)
            .appendingPathComponent("history.json")
    }
}
