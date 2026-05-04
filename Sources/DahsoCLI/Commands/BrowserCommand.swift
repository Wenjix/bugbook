import ArgumentParser
import Foundation

struct Browser: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "browser",
        abstract: "Inspect Dahso browser tabs, history, saved pages, and persisted content",
        subcommands: [Tabs.self, History.self, Saved.self, Content.self]
    )

    struct StoreOptions: ParsableArguments {
        @Option(name: .long, help: "Dahso app support directory. Defaults to ~/Library/Application Support/Dahso.")
        var appSupport: String?

        var appSupportURL: URL {
            if let appSupport, !appSupport.isEmpty {
                return URL(fileURLWithPath: (appSupport as NSString).expandingTildeInPath)
            }
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory
            return base.appendingPathComponent("Dahso", isDirectory: true)
        }
    }

    struct Tabs: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "tabs",
            abstract: "List Dahso browser tabs from persisted workspace layouts and pane snapshots"
        )

        @OptionGroup var options: Dahso.Options
        @OptionGroup var storeOptions: StoreOptions

        func run() throws {
            let reader = BrowserStateReader(
                workspacePath: options.resolvedWorkspace,
                appSupportURL: storeOptions.appSupportURL
            )
            let tabs = reader.tabs().map(\.json)
            try outputJSON([
                "tabs": tabs,
                "total_count": tabs.count,
            ])
        }
    }

    struct History: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "history",
            abstract: "List recent Dahso browser history entries"
        )

        @OptionGroup var options: Dahso.Options
        @OptionGroup var storeOptions: StoreOptions

        @Option(help: "Maximum number of history entries to print")
        var limit: Int = 50

        func run() throws {
            let reader = BrowserStateReader(
                workspacePath: options.resolvedWorkspace,
                appSupportURL: storeOptions.appSupportURL
            )
            let history = Array(reader.history().prefix(max(0, limit))).map(\.json)
            try outputJSON([
                "history": history,
                "total_count": history.count,
            ])
        }
    }

    struct Saved: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "saved",
            abstract: "List saved/read-later web pages for the workspace"
        )

        @OptionGroup var options: Dahso.Options
        @OptionGroup var storeOptions: StoreOptions

        func run() throws {
            let reader = BrowserStateReader(
                workspacePath: options.resolvedWorkspace,
                appSupportURL: storeOptions.appSupportURL
            )
            let records = reader.savedRecords().map(\.json)
            try outputJSON([
                "saved": records,
                "total_count": records.count,
                "workspace": options.resolvedWorkspace,
            ])
        }
    }

    struct Content: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "content",
            abstract: "Print persisted saved-page content for a saved page, tab ID, URL, or title"
        )

        @OptionGroup var options: Dahso.Options
        @OptionGroup var storeOptions: StoreOptions

        @Argument(help: "Saved page ID, browser tab ID, URL, title, or note path")
        var idOrURL: String

        func run() throws {
            let reader = BrowserStateReader(
                workspacePath: options.resolvedWorkspace,
                appSupportURL: storeOptions.appSupportURL
            )
            try outputJSON(reader.contentResult(for: idOrURL))
        }
    }
}

private struct BrowserStateReader {
    let workspacePath: String
    let appSupportURL: URL
    var fileManager: FileManager = .default

    func tabs() -> [BrowserTabRecord] {
        let layoutState = layoutState()
        var records: [BrowserTabRecord] = []
        for record in layoutState.tabs + snapshotTabs(paneContexts: layoutState.paneContexts) {
            merge(record, into: &records)
        }
        return records
    }

    func history() -> [BrowserHistoryRecord] {
        let url = appSupportURL
            .appendingPathComponent("BrowserHistory", isDirectory: true)
            .appendingPathComponent("history.json")
        guard let items = readJSONArray(at: url) else { return [] }
        return items.compactMap { item in
            guard let id = item.string("id"),
                  let title = item.string("title"),
                  let urlString = item.string("urlString") else {
                return nil
            }
            return BrowserHistoryRecord(
                id: id,
                title: title,
                urlString: urlString,
                visitedAt: item.string("visitedAt") ?? ""
            )
        }
    }

    func savedRecords() -> [SavedBrowserPageRecord] {
        let url = appSupportURL
            .appendingPathComponent("SavedWebPages", isDirectory: true)
            .appendingPathComponent(Self.encodedWorkspacePath(workspacePath) + ".json")
        guard let items = readJSONArray(at: url) else { return [] }
        return items.compactMap(SavedBrowserPageRecord.init(json:))
            .sorted { $0.savedAt > $1.savedAt }
    }

    func contentResult(for query: String) -> [String: Any] {
        let records = savedRecords()
        if let record = matchingSavedRecord(query, records: records) {
            return contentResult(for: record)
        }

        if let tab = matchingTab(query) {
            if let savedRecordID = tab.savedRecordID,
               let record = records.first(where: { $0.matches(savedRecordID) }) {
                return contentResult(for: record)
            }
            if let record = records.first(where: { $0.urlString == tab.urlString }) {
                return contentResult(for: record)
            }
            return structuredError(
                code: "live_content_unavailable",
                message: "No saved page note exists for this browser tab. Live DOM text requires the running app bridge.",
                query: query,
                requiresRunningAppBridge: true,
                tab: tab.json
            )
        }

        return structuredError(
            code: "not_found",
            message: "No saved page or browser tab matched '\(query)'.",
            query: query,
            requiresRunningAppBridge: false
        )
    }

    private func layoutState() -> LayoutBrowserState {
        let url = appSupportURL
            .appendingPathComponent("WorkspaceLayouts", isDirectory: true)
            .appendingPathComponent("layouts.json")
        guard let root = readJSONDictionary(at: url),
              let workspaces = root["workspaces"] as? [[String: Any]] else {
            return LayoutBrowserState()
        }
        let activeWorkspaceIndex = root["activeWorkspaceIndex"] as? Int
        var state = LayoutBrowserState()
        for (index, workspace) in workspaces.enumerated() {
            guard let node = workspace["root"] as? [String: Any] else { continue }
            state.merge(layoutState(
                in: node,
                workspaceID: workspace.string("id"),
                workspaceName: workspace.string("name"),
                focusedPaneID: workspace.string("focusedPaneId"),
                isActiveWorkspace: index == activeWorkspaceIndex
            ))
        }
        return state
    }

    private func layoutState(
        in node: [String: Any],
        workspaceID: String?,
        workspaceName: String?,
        focusedPaneID: String?,
        isActiveWorkspace: Bool
    ) -> LayoutBrowserState {
        switch node.string("type") {
        case "leaf":
            guard let leaf = node["leaf"] as? [String: Any] else { return LayoutBrowserState() }
            let paneID = leaf.string("id")
            let isFocusedPane = paneID == focusedPaneID
            let selectedTabIndex = leaf["selectedTabIndex"] as? Int ?? 0
            let tabs = leaf["tabs"] as? [[String: Any]] ?? []
            var state = LayoutBrowserState()
            if let paneID {
                state.paneContexts[paneID] = BrowserPaneContext(
                    workspaceID: workspaceID,
                    workspaceName: workspaceName,
                    isFocusedPane: isFocusedPane,
                    isActiveWorkspace: isActiveWorkspace
                )
            }
            state.tabs = tabs.enumerated().compactMap { index, tabJSON in
                guard let openFile = tabJSON["openFile"] as? [String: Any],
                      openFile.isBrowserOpenFile else {
                    return nil
                }
                let isSelected = index == selectedTabIndex
                return BrowserTabRecord(
                    id: openFile.string("id"),
                    title: openFile.string("displayName") ?? "Browser",
                    urlString: openFile.browserURLString,
                    savedRecordID: openFile.string("browserSavedRecordID"),
                    pageZoom: openFile["browserPageZoom"] as? Double,
                    paneID: paneID,
                    workspaceID: workspaceID,
                    workspaceName: workspaceName,
                    isSelected: isSelected,
                    isFocusedPane: isFocusedPane,
                    isActiveWorkspace: isActiveWorkspace,
                    isActiveTab: isActiveWorkspace && isFocusedPane && isSelected,
                    sources: ["workspace-layout"]
                )
            }
            return state
        case "split":
            guard let split = node["split"] as? [String: Any] else { return LayoutBrowserState() }
            var state = LayoutBrowserState()
            if let first = split["first"] as? [String: Any] {
                state.merge(layoutState(
                    in: first,
                    workspaceID: workspaceID,
                    workspaceName: workspaceName,
                    focusedPaneID: focusedPaneID,
                    isActiveWorkspace: isActiveWorkspace
                ))
            }
            if let second = split["second"] as? [String: Any] {
                state.merge(layoutState(
                    in: second,
                    workspaceID: workspaceID,
                    workspaceName: workspaceName,
                    focusedPaneID: focusedPaneID,
                    isActiveWorkspace: isActiveWorkspace
                ))
            }
            return state
        default:
            return LayoutBrowserState()
        }
    }

    private func snapshotTabs(paneContexts: [String: BrowserPaneContext]) -> [BrowserTabRecord] {
        let directory = appSupportURL.appendingPathComponent("BrowserPanes", isDirectory: true)
        guard let files = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return files
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .flatMap { snapshotTabs(at: $0, paneContexts: paneContexts) }
    }

    private func snapshotTabs(at url: URL, paneContexts: [String: BrowserPaneContext]) -> [BrowserTabRecord] {
        guard let snapshot = readJSONDictionary(at: url),
              let paneID = snapshot.string("paneID"),
              let tabs = snapshot["tabs"] as? [[String: Any]] else {
            return []
        }
        let context = paneContexts[paneID]
        let selectedTabID = snapshot.string("selectedTabID")
        return tabs.compactMap { tab in
            guard let id = tab.string("id") else { return nil }
            let isSelected = id == selectedTabID
            return BrowserTabRecord(
                id: id,
                title: tab.string("title") ?? "Browser",
                urlString: tab.string("urlString") ?? "",
                savedRecordID: tab.string("savedRecordID"),
                pageZoom: tab["pageZoom"] as? Double,
                paneID: paneID,
                workspaceID: context?.workspaceID,
                workspaceName: context?.workspaceName,
                isSelected: isSelected,
                isFocusedPane: context?.isFocusedPane ?? false,
                isActiveWorkspace: context?.isActiveWorkspace ?? false,
                isActiveTab: (context?.isActiveWorkspace ?? false) && (context?.isFocusedPane ?? false) && isSelected,
                sources: ["browser-pane-snapshot"]
            )
        }
    }

    private func matchingSavedRecord(_ query: String, records: [SavedBrowserPageRecord]) -> SavedBrowserPageRecord? {
        let normalizedQuery = query.normalizedBrowserLookup
        return records.first { record in
            record.matches(query)
                || record.urlString.normalizedBrowserLookup == normalizedQuery
                || record.title.normalizedBrowserLookup == normalizedQuery
                || record.notePath.normalizedBrowserLookup == normalizedQuery
                || URL(fileURLWithPath: record.notePath).lastPathComponent.normalizedBrowserLookup == normalizedQuery
        }
    }

    private func matchingTab(_ query: String) -> BrowserTabRecord? {
        let normalizedQuery = query.normalizedBrowserLookup
        return tabs().first { tab in
            tab.id?.normalizedBrowserLookup == normalizedQuery
                || tab.urlString.normalizedBrowserLookup == normalizedQuery
                || tab.title.normalizedBrowserLookup == normalizedQuery
        }
    }

    private func contentResult(for record: SavedBrowserPageRecord) -> [String: Any] {
        let noteURL = resolvedNoteURL(record.notePath)
        guard fileManager.fileExists(atPath: noteURL.path),
              let content = try? String(contentsOf: noteURL, encoding: .utf8) else {
            return structuredError(
                code: "saved_note_missing",
                message: "Saved page record exists, but the note file could not be read.",
                query: record.id,
                requiresRunningAppBridge: false,
                record: record.json
            )
        }
        var output = record.json
        output["content"] = content
        output["source"] = "saved-page-note"
        return output
    }

    private func resolvedNoteURL(_ notePath: String) -> URL {
        let expanded = (notePath as NSString).expandingTildeInPath
        if expanded.hasPrefix("/") {
            return URL(fileURLWithPath: expanded)
        }
        return URL(fileURLWithPath: workspacePath).appendingPathComponent(expanded)
    }

    private func merge(_ record: BrowserTabRecord, into records: inout [BrowserTabRecord]) {
        if let id = record.id,
           let index = records.firstIndex(where: { $0.id == id }) {
            records[index].merge(record)
            return
        }
        if !record.urlString.isEmpty,
           let index = records.firstIndex(where: { existing in
               guard existing.id == nil || record.id == nil else { return false }
               return !existing.urlString.isEmpty && existing.urlString == record.urlString
           }) {
            records[index].merge(record)
            return
        }
        records.append(record)
    }

    private func readJSONDictionary(at url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url),
              let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return value
    }

    private func readJSONArray(at url: URL) -> [[String: Any]]? {
        guard let data = try? Data(contentsOf: url),
              let value = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return nil
        }
        return value
    }

    private func structuredError(
        code: String,
        message: String,
        query: String,
        requiresRunningAppBridge: Bool,
        record: [String: Any]? = nil,
        tab: [String: Any]? = nil
    ) -> [String: Any] {
        var error: [String: Any] = [
            "code": code,
            "message": message,
            "requires_running_app_bridge": requiresRunningAppBridge,
        ]
        if let record { error["record"] = record }
        if let tab { error["tab"] = tab }
        return [
            "error": error,
            "query": query,
        ]
    }

    private static func encodedWorkspacePath(_ workspacePath: String) -> String {
        Data(workspacePath.utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")
    }
}

private struct LayoutBrowserState {
    var tabs: [BrowserTabRecord] = []
    var paneContexts: [String: BrowserPaneContext] = [:]

    mutating func merge(_ other: LayoutBrowserState) {
        tabs.append(contentsOf: other.tabs)
        paneContexts.merge(other.paneContexts) { current, _ in current }
    }
}

private struct BrowserPaneContext {
    var workspaceID: String?
    var workspaceName: String?
    var isFocusedPane: Bool
    var isActiveWorkspace: Bool
}

private struct BrowserTabRecord {
    var id: String?
    var title: String
    var urlString: String
    var savedRecordID: String?
    var pageZoom: Double?
    var paneID: String?
    var workspaceID: String?
    var workspaceName: String?
    var isSelected: Bool
    var isFocusedPane: Bool
    var isActiveWorkspace: Bool
    var isActiveTab: Bool
    var sources: Set<String>

    mutating func merge(_ other: BrowserTabRecord) {
        if title == "Browser", other.title != "Browser" {
            title = other.title
        }
        id = id ?? other.id
        if urlString.isEmpty {
            urlString = other.urlString
        }
        savedRecordID = savedRecordID ?? other.savedRecordID
        pageZoom = pageZoom ?? other.pageZoom
        paneID = paneID ?? other.paneID
        workspaceID = workspaceID ?? other.workspaceID
        workspaceName = workspaceName ?? other.workspaceName
        isSelected = isSelected || other.isSelected
        isFocusedPane = isFocusedPane || other.isFocusedPane
        isActiveWorkspace = isActiveWorkspace || other.isActiveWorkspace
        isActiveTab = isActiveTab || other.isActiveTab
        sources.formUnion(other.sources)
    }

    var json: [String: Any] {
        var output: [String: Any] = [
            "title": title,
            "url": urlString,
            "is_selected": isSelected,
            "is_focused_pane": isFocusedPane,
            "is_active_workspace": isActiveWorkspace,
            "is_active_tab": isActiveTab,
            "sources": sources.sorted(),
            "source": sources.sorted().joined(separator: ","),
        ]
        if let id { output["id"] = id }
        if let savedRecordID { output["saved_record_id"] = savedRecordID }
        if let pageZoom { output["page_zoom"] = pageZoom }
        if let paneID { output["pane_id"] = paneID }
        if let workspaceID { output["workspace_id"] = workspaceID }
        if let workspaceName { output["workspace_name"] = workspaceName }
        return output
    }
}

private struct BrowserHistoryRecord {
    let id: String
    let title: String
    let urlString: String
    let visitedAt: String

    var json: [String: Any] {
        [
            "id": id,
            "title": title,
            "url": urlString,
            "visited_at": visitedAt,
        ]
    }
}

private struct SavedBrowserPageRecord {
    let id: String
    let title: String
    let urlString: String
    let savedAt: String
    let folderPath: String
    let notePath: String
    let status: String
    let summary: String

    init?(json: [String: Any]) {
        guard let id = json.string("id"),
              let title = json.string("title"),
              let urlString = json.string("urlString"),
              let folderPath = json.string("folderPath"),
              let notePath = json.string("notePath") else {
            return nil
        }
        self.id = id
        self.title = title
        self.urlString = urlString
        self.savedAt = json.string("savedAt") ?? ""
        self.folderPath = folderPath
        self.notePath = notePath
        self.status = json.string("status") ?? "unread"
        self.summary = json.string("summary") ?? ""
    }

    func matches(_ query: String) -> Bool {
        id.normalizedBrowserLookup == query.normalizedBrowserLookup
    }

    var json: [String: Any] {
        [
            "id": id,
            "title": title,
            "url": urlString,
            "saved_at": savedAt,
            "folder_path": folderPath,
            "note_path": notePath,
            "status": status,
            "summary": summary,
        ]
    }
}

private extension Dictionary where Key == String, Value == Any {
    func string(_ key: String) -> String? {
        self[key] as? String
    }

    var isBrowserOpenFile: Bool {
        if let kind = self["kind"] as? [String: Any], kind["browser"] != nil {
            return true
        }
        return false
    }

    var browserURLString: String {
        guard let path = string("path"), path != "dahso://browser" else {
            return ""
        }
        return path
    }
}

private extension String {
    var normalizedBrowserLookup: String {
        trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
