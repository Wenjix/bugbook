import Foundation

/// The content type displayed in a single pane leaf.
enum PaneContent: Codable, Equatable {
    /// A document pane — routes through OpenFile.kind for all existing content types.
    case document(openFile: OpenFile)

    /// A terminal pane (shell session). Ephemeral; only the type is persisted.
    case terminal(sessionID: UUID)

    // MARK: - Factories

    /// An empty document pane (new tab / welcome view).
    static func emptyDocument(id: UUID = UUID()) -> PaneContent {
        .document(openFile: OpenFile(id: id, path: "", content: "", isDirty: false, isEmptyTab: true))
    }

    /// A mail pane.
    static func mailDocument(id: UUID = UUID()) -> PaneContent {
        return .document(openFile: OpenFile(
            id: id, path: "bugbook://mail", content: "", isDirty: false, isEmptyTab: false,
            kind: .mail, displayName: "Mail", icon: "envelope"
        ))
    }

    /// A calendar pane.
    static func calendarDocument(id: UUID = UUID()) -> PaneContent {
        return .document(openFile: OpenFile(
            id: id, path: "bugbook://calendar", content: "", isDirty: false, isEmptyTab: false,
            kind: .calendar, displayName: "Calendar", icon: "calendar.badge.clock"
        ))
    }

    /// A graph view pane.
    static func graphDocument(id: UUID = UUID()) -> PaneContent {
        return .document(openFile: OpenFile(
            id: id, path: "bugbook://graph", content: "", isDirty: false, isEmptyTab: false,
            kind: .graphView, displayName: "Graph View", icon: "sf:point.3.connected.trianglepath.dotted"
        ))
    }

    /// A gateway dashboard pane.
    static func gatewayDocument(id: UUID = UUID()) -> PaneContent {
        return .document(openFile: OpenFile(
            id: id, path: "bugbook://gateway", content: "", isDirty: false, isEmptyTab: false,
            kind: .gateway, displayName: "Home", icon: "square.grid.2x2"
        ))
    }

    /// A full-page chat pane.
    static func chatDocument(id: UUID = UUID()) -> PaneContent {
        return .document(openFile: OpenFile(
            id: id, path: "bugbook://chat", content: "", isDirty: false, isEmptyTab: false,
            kind: .chat, displayName: "Chat", icon: "bubble.left.and.bubble.right"
        ))
    }

    /// A meetings pane.
    static func meetingsDocument(id: UUID = UUID()) -> PaneContent {
        return .document(openFile: OpenFile(
            id: id, path: "bugbook://meetings", content: "", isDirty: false, isEmptyTab: false,
            kind: .meetings, displayName: "Meetings", icon: "person.2"
        ))
    }

    /// A browser pane.
    static func browserDocument(
        id: UUID = UUID(),
        urlString: String = "bugbook://browser",
        title: String = "Browser",
        savedRecordID: UUID? = nil,
        pageZoom: Double = 0.85
    ) -> PaneContent {
        return .document(openFile: OpenFile(
            id: id,
            path: urlString,
            content: "",
            isDirty: false,
            isEmptyTab: false,
            kind: .browser,
            displayName: title,
            icon: "globe",
            browserSavedRecordID: savedRecordID,
            browserPageZoom: pageZoom
        ))
    }

    static func terminal(id: UUID = UUID()) -> PaneContent {
        .terminal(sessionID: id)
    }

    var id: UUID {
        switch self {
        case .document(let file):
            return file.id
        case .terminal(let sessionID):
            return sessionID
        }
    }

    var openFile: OpenFile? {
        guard case .document(let file) = self else { return nil }
        return file
    }

    var supportsPaneTabs: Bool {
        true
    }

    var isBrowser: Bool {
        guard case .document(let file) = self else { return false }
        return file.isBrowser
    }

    var isTerminal: Bool {
        if case .terminal = self { return true }
        return false
    }

    func reidentified(as id: UUID) -> PaneContent {
        switch self {
        case .terminal:
            return .terminal(id: id)
        case .document(var file):
            file = OpenFile(
                id: id,
                path: file.path,
                content: file.content,
                isDirty: file.isDirty,
                isEmptyTab: file.isEmptyTab,
                kind: file.kind,
                displayName: file.displayName,
                openerPagePath: file.openerPagePath,
                icon: file.icon,
                navigationHistory: file.navigationHistory,
                navigationHistoryIndex: file.navigationHistoryIndex,
                browserSavedRecordID: file.browserSavedRecordID,
                browserPageZoom: file.browserPageZoom,
                isExternal: file.isExternal
            )
            return .document(openFile: file)
        }
    }

    func defaultNewPaneTab() -> PaneContent? {
        switch self {
        case .terminal:
            return .terminal()
        case .document(let file):
            if file.isBrowser {
                return .browserDocument(urlString: "bugbook://browser", title: "Browser")
            }
            return .emptyDocument()
        }
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case openFile
        case sessionID
    }

    private enum ContentType: String, Codable {
        case document
        case terminal
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(ContentType.self, forKey: .type)
        switch type {
        case .document:
            let file = try container.decode(OpenFile.self, forKey: .openFile)
            self = .document(openFile: file)
        case .terminal:
            let sessionID = try container.decodeIfPresent(UUID.self, forKey: .sessionID) ?? UUID()
            self = .terminal(sessionID: sessionID)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .document(let file):
            try container.encode(ContentType.document, forKey: .type)
            try container.encode(file, forKey: .openFile)
        case .terminal(let sessionID):
            try container.encode(ContentType.terminal, forKey: .type)
            try container.encode(sessionID, forKey: .sessionID)
        }
    }
}

extension PaneContent {
    var paneItemTitle: String {
        switch self {
        case .terminal:
            return "Terminal"
        case .document(let file):
            return file.paneItemTitle
        }
    }

    var paneItemIcon: String {
        switch self {
        case .terminal:
            return "sf:terminal"
        case .document(let file):
            return file.paneItemIcon
        }
    }
}

extension OpenFile {
    var paneItemTitle: String {
        if isEmptyTab { return "Home" }
        if isGateway { return "Home" }
        if isMail { return "Mail" }
        if isCalendar { return "Calendar" }
        if isBrowser { return browserPaneItemTitle }
        if isMeetings { return "Meetings" }
        if isChat { return "Chat" }
        if isGraphView { return "Graph View" }

        if let displayName, !displayName.isEmpty {
            return displayName
        }

        let filename = (path as NSString).lastPathComponent
        if filename.hasSuffix(".md") {
            return String(filename.dropLast(3))
        }
        return filename.isEmpty ? "Untitled" : filename
    }

    var paneItemIcon: String {
        if isEmptyTab { return "sf:house" }
        if isGateway { return "sf:house" }
        if isMail { return "sf:envelope" }
        if isCalendar { return "sf:calendar.badge.clock" }
        if isBrowser { return "sf:globe" }
        if isMeetings { return "sf:person.2" }
        if isChat { return "sf:bubble.left.and.bubble.right" }
        if isGraphView { return "sf:point.3.connected.trianglepath.dotted" }

        if let icon, !icon.isEmpty {
            return OpenFile.normalizedPaneIcon(icon)
        }
        return isDatabase ? "sf:tablecells" : "sf:doc.text"
    }

    private var browserPaneItemTitle: String {
        if path == "bugbook://browser" {
            let trimmed = displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return trimmed.isEmpty || trimmed == "New Tab" ? "Browser" : trimmed
        }
        if let displayName, !displayName.isEmpty {
            return displayName
        }
        if let host = URL(string: path)?.host, !host.isEmpty {
            return host
        }
        return "Browser"
    }

    private static func normalizedPaneIcon(_ icon: String) -> String {
        if icon.hasPrefix("sf:") || icon.unicodeScalars.first?.properties.isEmoji == true {
            return icon
        }
        return "sf:\(icon)"
    }
}
