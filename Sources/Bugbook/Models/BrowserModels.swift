import Foundation
import SwiftUI

struct BrowserRecentVisit: Codable, Equatable, Identifiable {
    var id: UUID
    var title: String
    var urlString: String
    var visitedAt: Date

    init(id: UUID = UUID(), title: String, urlString: String, visitedAt: Date = Date()) {
        self.id = id
        self.title = title
        self.urlString = urlString
        self.visitedAt = visitedAt
    }

    var url: URL? { URL(string: urlString) }
    var host: String { url?.host ?? urlString }
}

struct BrowserTabSnapshot: Codable, Equatable, Identifiable {
    var id: UUID
    var title: String
    var urlString: String
    var savedRecordID: UUID?
    var pageZoom: Double

    init(
        id: UUID = UUID(),
        title: String = "New Tab",
        urlString: String = "",
        savedRecordID: UUID? = nil,
        pageZoom: Double = BrowserPageState.defaultPageZoom
    ) {
        self.id = id
        self.title = title
        self.urlString = urlString
        self.savedRecordID = savedRecordID
        self.pageZoom = pageZoom
    }
}

struct BrowserPaneSnapshot: Codable, Equatable {
    var paneID: UUID
    var tabs: [BrowserTabSnapshot]
    var selectedTabID: UUID?
    var recentVisits: [BrowserRecentVisit]
    var isReadLaterDrawerOpen: Bool

    init(
        paneID: UUID,
        tabs: [BrowserTabSnapshot] = [BrowserTabSnapshot()],
        selectedTabID: UUID? = nil,
        recentVisits: [BrowserRecentVisit] = [],
        isReadLaterDrawerOpen: Bool = false
    ) {
        self.paneID = paneID
        self.tabs = tabs.isEmpty ? [BrowserTabSnapshot()] : tabs
        self.selectedTabID = selectedTabID ?? self.tabs.first?.id
        self.recentVisits = recentVisits
        self.isReadLaterDrawerOpen = isReadLaterDrawerOpen
    }
}

struct BrowserTabState: Identifiable, Equatable {
    var id: UUID
    var title: String
    var urlString: String
    var isLoading: Bool
    var estimatedProgress: Double
    var hoverURLString: String?
    var savedRecordID: UUID?
    var pageZoom: Double
    var canGoBack: Bool
    var canGoForward: Bool
    var securityIconName: String

    init(
        id: UUID = UUID(),
        title: String = "New Tab",
        urlString: String = "",
        isLoading: Bool = false,
        estimatedProgress: Double = 0,
        hoverURLString: String? = nil,
        savedRecordID: UUID? = nil,
        pageZoom: Double = BrowserPageState.defaultPageZoom,
        canGoBack: Bool = false,
        canGoForward: Bool = false,
        securityIconName: String = "magnifyingglass"
    ) {
        self.id = id
        self.title = title
        self.urlString = urlString
        self.isLoading = isLoading
        self.estimatedProgress = estimatedProgress
        self.hoverURLString = hoverURLString
        self.savedRecordID = savedRecordID
        self.pageZoom = pageZoom
        self.canGoBack = canGoBack
        self.canGoForward = canGoForward
        self.securityIconName = securityIconName
    }

    var url: URL? { URL(string: urlString) }
    var host: String {
        guard let url else { return "" }
        return url.host ?? url.absoluteString
    }

    var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        if !host.isEmpty { return host }
        return "New Tab"
    }

    var displayURL: String {
        if !host.isEmpty { return host }
        return urlString
    }
}

enum SavedWebPageStatus: String, Codable, CaseIterable {
    case unread
    case read
}

struct SavedWebPageRecord: Codable, Equatable, Identifiable {
    var id: UUID
    var title: String
    var urlString: String
    var savedAt: Date
    var folderPath: String
    var notePath: String
    var status: SavedWebPageStatus
    var summary: String

    init(
        id: UUID = UUID(),
        title: String,
        urlString: String,
        savedAt: Date = Date(),
        folderPath: String,
        notePath: String,
        status: SavedWebPageStatus = .unread,
        summary: String = ""
    ) {
        self.id = id
        self.title = title
        self.urlString = urlString
        self.savedAt = savedAt
        self.folderPath = folderPath
        self.notePath = notePath
        self.status = status
        self.summary = summary
    }

    var url: URL? { URL(string: urlString) }
    var host: String { url?.host ?? urlString }
}

enum BrowserCleanupDecision: String, Codable, CaseIterable {
    case save
    case readLater
    case close
    case keep
}

struct BrowserCleanupProposal: Codable, Equatable, Identifiable {
    var id: UUID
    var tabID: UUID
    var title: String
    var urlString: String
    var decision: BrowserCleanupDecision
    var reason: String

    init(
        id: UUID = UUID(),
        tabID: UUID,
        title: String,
        urlString: String,
        decision: BrowserCleanupDecision,
        reason: String
    ) {
        self.id = id
        self.tabID = tabID
        self.title = title
        self.urlString = urlString
        self.decision = decision
        self.reason = reason
    }
}

enum BrowserOmnibarDestination {
    case directURL(URL)
    case webSearch(URL)
    case bugbookEntry(FileEntry)
}

protocol ContextualSidebarProviding {
    func makeContextualSidebar() -> AnyView
}

protocol PaneDropdownProviding {
    func makePaneDropdown() -> AnyView
}

