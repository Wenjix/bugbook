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
    @ObservationIgnored private let fallbackWorkspaceManager: WorkspaceManager
    @ObservationIgnored private var boundWorkspaceManager: WorkspaceManager?

    fileprivate var workspaceManager: WorkspaceManager {
        boundWorkspaceManager ?? fallbackWorkspaceManager
    }

    init(
        engine: (any BrowserEngine)? = nil,
        snapshotStore: BrowserPaneSnapshotStore = BrowserPaneSnapshotStore(),
        historyStore: BrowserHistoryStore = BrowserHistoryStore()
    ) {
        let fallbackWorkspaceManager = WorkspaceManager()
        fallbackWorkspaceManager.layoutPersistenceEnabled = false
        self.engine = engine ?? BrowserEngineFactory.makeDefault()
        self.snapshotStore = snapshotStore
        self.historyStore = historyStore
        self.fallbackWorkspaceManager = fallbackWorkspaceManager
        self.browsingHistory = historyStore.load()
    }

    func bind(workspaceManager: WorkspaceManager) {
        boundWorkspaceManager = workspaceManager
        for paneID in sessions.keys {
            if workspaceManager.leaf(id: paneID) == nil,
               let fallbackLeaf = fallbackWorkspaceManager.leaf(id: paneID) {
                workspaceManager.setPaneTabs(
                    paneId: paneID,
                    tabs: fallbackLeaf.tabs,
                    selectedTabID: fallbackLeaf.activeTabID
                )
            } else {
                ensurePaneExists(
                    for: paneID,
                    snapshot: snapshotStore.snapshot(for: paneID) ?? BrowserPaneSnapshot(paneID: paneID)
                )
            }
        }
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
        ensurePaneExists(for: paneID, snapshot: snapshot)
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

        let file = workspaceManager.openFile(tabId: tabID)
        let initialURL = file?.browserURL
        let page = engine.makePage(for: paneID, tabID: tabID, initialURL: initialURL) { [weak self] event in
            self?.handlePageEvent(event, paneID: paneID, tabID: tabID)
        }
        if let pageZoom = file?.browserPageZoom, pageZoom > 0 {
            page.setPageZoom(pageZoom)
        }
        session.pages[tabID] = page
        session.updatePageState(tabID: tabID, from: page.state)
        return page
    }

    func activePage(for paneID: UUID) -> (any BrowserPage)? {
        guard let tabID = activeBrowserTabID(in: paneID) else { return nil }
        return ensurePage(for: paneID, tabID: tabID)
    }

    func activeHostView(for paneID: UUID) -> NSView? {
        activePage(for: paneID)?.hostView
    }

    func openURL(_ url: URL, in paneID: UUID, newTab: Bool = false) {
        let tabID: UUID
        if newTab || activeBrowserTabID(in: paneID) == nil {
            let content = PaneContent.browserDocument(
                urlString: url.absoluteString,
                title: url.host ?? "New Tab"
            )
            tabID = content.id
            _ = workspaceManager.addPaneTab(to: paneID, content: content)
        } else if let selectedTabID = activeBrowserTabID(in: paneID) {
            tabID = selectedTabID
            workspaceManager.updateOpenFile(tabId: tabID, persist: false) { file in
                file.path = url.absoluteString
                file.displayName = url.host ?? "New Tab"
                file.browserSavedRecordID = nil
            }
        } else {
            return
        }

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
        guard let tabID = activeBrowserTabID(in: paneID),
              let page = activePage(for: paneID) else { return }
        page.setPageZoom(zoom)
        workspaceManager.updateOpenFile(tabId: tabID) { file in
            file.browserPageZoom = zoom
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
        session.updateHoverURL(tabID: tabID, urlString: urlString)
    }

    fileprivate func updateTabState(_ state: BrowserPageState, paneID: UUID, tabID: UUID) {
        let session = session(for: paneID)
        session.updatePageState(tabID: tabID, from: state)
        workspaceManager.updateOpenFile(tabId: tabID, persist: !state.isLoading) { file in
            let trimmedTitle = state.title?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let trimmedTitle, !trimmedTitle.isEmpty {
                file.displayName = trimmedTitle
            }
            if let url = state.url {
                file.path = url.absoluteString
            }
            if state.pageZoom > 0 {
                file.browserPageZoom = state.pageZoom
            }
        }
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

    func tabs(in paneID: UUID) -> [BrowserTabState] {
        ensurePaneExists(for: paneID, snapshot: snapshotStore.snapshot(for: paneID) ?? BrowserPaneSnapshot(paneID: paneID))
        guard let leaf = workspaceManager.leaf(id: paneID) else { return [] }
        return session(for: paneID).tabStates(for: browserFiles(in: leaf))
    }

    func activeTab(in paneID: UUID) -> BrowserTabState? {
        ensurePaneExists(for: paneID, snapshot: snapshotStore.snapshot(for: paneID) ?? BrowserPaneSnapshot(paneID: paneID))
        guard let leaf = workspaceManager.leaf(id: paneID) else { return nil }
        return session(for: paneID).activeTab(for: browserFiles(in: leaf), selectedTabID: activeBrowserTabID(in: paneID))
    }

    func closeTab(_ tabID: UUID, in paneID: UUID) {
        session(for: paneID).closeTab(tabID)
    }

    func discardTabResources(_ tabID: UUID, in paneID: UUID) {
        guard let session = sessions[paneID] else { return }
        session.discardResources(for: tabID)
        persistSession(paneID)
    }

    private func makeSession(for paneID: UUID) -> BrowserPaneSession {
        let snapshot = snapshotStore.snapshot(for: paneID) ?? BrowserPaneSnapshot(paneID: paneID)
        ensurePaneExists(for: paneID, snapshot: snapshot)
        let session = BrowserPaneSession(paneID: paneID, snapshot: snapshot)
        session.manager = self
        return session
    }

    private func activeBrowserTabID(in paneID: UUID) -> UUID? {
        guard let file = workspaceManager.leaf(id: paneID)?.activeOpenFile,
              file.isBrowser else { return nil }
        return file.id
    }

    private func browserFiles(in leaf: PaneNode.Leaf) -> [OpenFile] {
        leaf.tabs.compactMap(\.openFile).filter(\.isBrowser)
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

    fileprivate func replaceTabs(_ tabs: [BrowserTabState], selectedTabID: UUID?, in paneID: UUID) {
        let contents = tabs.map { tab in
            PaneContent.browserDocument(
                id: tab.id,
                urlString: tab.urlString.isEmpty ? "dahso://browser" : tab.urlString,
                title: tab.title,
                savedRecordID: tab.savedRecordID,
                pageZoom: tab.pageZoom
            )
        }
        workspaceManager.setPaneTabs(paneId: paneID, tabs: contents, selectedTabID: selectedTabID)
        let session = session(for: paneID)
        let validTabIDs = Set(tabs.map(\.id))
        for tabID in Set(session.pages.keys).subtracting(validTabIDs) {
            session.discardResources(for: tabID)
        }
        for tab in tabs {
            session.hoverURLStrings[tab.id] = tab.hoverURLString
            session.pageStates[tab.id] = BrowserPageState(
                title: tab.title,
                url: tab.url,
                isLoading: tab.isLoading,
                estimatedProgress: tab.estimatedProgress,
                canGoBack: tab.canGoBack,
                canGoForward: tab.canGoForward,
                pageZoom: tab.pageZoom
            )
        }
        persistSession(paneID)
    }

    private func ensurePaneExists(for paneID: UUID, snapshot: BrowserPaneSnapshot) {
        guard workspaceManager.leaf(id: paneID) == nil else { return }

        let contents = snapshot.tabs.map { tab in
            PaneContent.browserDocument(
                id: tab.id,
                urlString: tab.urlString.isEmpty ? "dahso://browser" : tab.urlString,
                title: tab.title,
                savedRecordID: tab.savedRecordID,
                pageZoom: tab.pageZoom
            )
        }
        let initialTabs = contents.isEmpty ? [PaneContent.browserDocument(id: paneID)] : contents
        let selectedTabID = snapshot.selectedTabID ?? initialTabs.first?.id
        workspaceManager.setPaneTabs(paneId: paneID, tabs: initialTabs, selectedTabID: selectedTabID)
    }
}

@MainActor
@Observable
final class BrowserPaneSession {
    let paneID: UUID
    var recentVisits: [BrowserRecentVisit]
    var isReadLaterDrawerOpen: Bool
    var lastDownloadMessage: String?

    @ObservationIgnored weak var manager: BrowserManager?
    @ObservationIgnored fileprivate var pages: [UUID: any BrowserPage] = [:]
    @ObservationIgnored fileprivate var pageStates: [UUID: BrowserPageState] = [:]
    @ObservationIgnored fileprivate var hoverURLStrings: [UUID: String?] = [:]

    init(paneID: UUID, snapshot: BrowserPaneSnapshot) {
        self.paneID = paneID
        self.recentVisits = snapshot.recentVisits
        self.isReadLaterDrawerOpen = snapshot.isReadLaterDrawerOpen
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

    var tabs: [BrowserTabState] {
        get { manager?.tabs(in: paneID) ?? [] }
        set { manager?.replaceTabs(newValue, selectedTabID: selectedTabID, in: paneID) }
    }

    var selectedTabID: UUID? {
        get { manager?.workspaceManager.leaf(id: paneID)?.activeTabID }
        set {
            guard let newValue else { return }
            selectTab(newValue)
        }
    }

    var activeTab: BrowserTabState? {
        manager?.activeTab(in: paneID)
    }

    func tabStates(for files: [OpenFile]) -> [BrowserTabState] {
        files.map(browserTabState(for:))
    }

    func activeTab(for files: [OpenFile], selectedTabID: UUID?) -> BrowserTabState? {
        let states = tabStates(for: files)
        guard let selectedTabID else { return states.first }
        return states.first { $0.id == selectedTabID }
    }

    func closeTab(_ tabID: UUID) {
        pages[tabID]?.dispose()
        pages.removeValue(forKey: tabID)
        pageStates.removeValue(forKey: tabID)
        hoverURLStrings.removeValue(forKey: tabID)

        if manager?.workspaceManager.closePaneTab(paneId: paneID, tabId: tabID) == nil {
            manager?.workspaceManager.updatePaneContent(
                paneId: paneID,
                content: .browserDocument(id: tabID)
            )
        }
        manager?.persistSession(paneID)
    }

    func moveTab(from sourceIndex: Int, to destinationIndex: Int) {
        manager?.workspaceManager.movePaneTab(paneId: paneID, from: sourceIndex, to: destinationIndex)
        manager?.persistSession(paneID)
    }

    func selectTab(_ tabID: UUID) {
        manager?.workspaceManager.selectPaneTab(paneId: paneID, tabId: tabID)
        syncPageZoom(for: tabID)
        manager?.persistSession(paneID)
    }

    @discardableResult
    func openNewTab(url: URL? = nil, select: Bool = true) -> UUID {
        let content = PaneContent.browserDocument(
            urlString: url?.absoluteString ?? "dahso://browser",
            title: url?.host ?? "New Tab"
        )
        manager?.workspaceManager.addPaneTab(to: paneID, content: content, select: select)
        if let manager, let url {
            manager.ensurePage(for: paneID, tabID: content.id).load(URLRequest(url: url))
        } else if let manager {
            _ = manager.ensurePage(for: paneID, tabID: content.id)
        }
        manager?.persistSession(paneID)
        return content.id
    }

    func updateSavedRecordID(_ recordID: UUID?, for tabID: UUID) {
        manager?.workspaceManager.updateOpenFile(tabId: tabID) { file in
            file.browserSavedRecordID = recordID
        }
        manager?.persistSession(paneID)
    }

    func updatePageState(tabID: UUID, from state: BrowserPageState) {
        pageStates[tabID] = state
    }

    func updateHoverURL(tabID: UUID, urlString: String?) {
        hoverURLStrings[tabID] = urlString
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
        pageStates.removeAll()
        hoverURLStrings.removeAll()
    }

    func discardResources(for tabID: UUID) {
        pages[tabID]?.dispose()
        pages.removeValue(forKey: tabID)
        pageStates.removeValue(forKey: tabID)
        hoverURLStrings.removeValue(forKey: tabID)
    }

    private func browserTabState(for file: OpenFile) -> BrowserTabState {
        let state = pageStates[file.id] ?? pages[file.id]?.state ?? .empty
        let title = file.displayName ?? state.title ?? "New Tab"
        let urlString = state.url?.absoluteString ?? file.browserURLString
        let securityURL = state.url ?? URL(string: urlString)
        return BrowserTabState(
            id: file.id,
            title: title,
            urlString: urlString,
            isLoading: state.isLoading,
            estimatedProgress: state.estimatedProgress,
            hoverURLString: hoverURLStrings[file.id] ?? nil,
            savedRecordID: file.browserSavedRecordID,
            pageZoom: state.pageZoom > 0 ? state.pageZoom : file.browserPageZoom,
            canGoBack: state.canGoBack,
            canGoForward: state.canGoForward,
            securityIconName: BrowserManager.securityIcon(for: securityURL)
        )
    }

    private func syncPageZoom(for tabID: UUID) {
        guard let manager,
              let file = manager.workspaceManager.openFile(tabId: tabID) else { return }
        let page = manager.ensurePage(for: paneID, tabID: tabID)
        if abs(file.browserPageZoom - page.state.pageZoom) > 0.001 {
            page.setPageZoom(file.browserPageZoom)
        }
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
