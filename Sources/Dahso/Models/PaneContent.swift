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
            id: id, path: "dahso://mail", content: "", isDirty: false, isEmptyTab: false,
            kind: .mail, displayName: "Mail", icon: "envelope"
        ))
    }

    /// A calendar pane.
    static func calendarDocument(id: UUID = UUID()) -> PaneContent {
        return .document(openFile: OpenFile(
            id: id, path: "dahso://calendar", content: "", isDirty: false, isEmptyTab: false,
            kind: .calendar, displayName: "Calendar", icon: "calendar.badge.clock"
        ))
    }

    /// A graph view pane.
    static func graphDocument(id: UUID = UUID()) -> PaneContent {
        return .document(openFile: OpenFile(
            id: id, path: "dahso://graph", content: "", isDirty: false, isEmptyTab: false,
            kind: .graphView, displayName: "Graph View", icon: "sf:point.3.connected.trianglepath.dotted"
        ))
    }

    /// A gateway dashboard pane.
    static func gatewayDocument(id: UUID = UUID()) -> PaneContent {
        return .document(openFile: OpenFile(
            id: id, path: "dahso://gateway", content: "", isDirty: false, isEmptyTab: false,
            kind: .gateway, displayName: "Home", icon: "square.grid.2x2"
        ))
    }

    /// A full-page chat pane.
    static func chatDocument(id: UUID = UUID()) -> PaneContent {
        return .document(openFile: OpenFile(
            id: id, path: "dahso://chat", content: "", isDirty: false, isEmptyTab: false,
            kind: .chat, displayName: "Chat", icon: "bubble.left.and.bubble.right"
        ))
    }

    /// A meetings pane.
    static func meetingsDocument(id: UUID = UUID()) -> PaneContent {
        return .document(openFile: OpenFile(
            id: id, path: "dahso://meetings", content: "", isDirty: false, isEmptyTab: false,
            kind: .meetings, displayName: "Meetings", icon: "person.2"
        ))
    }

    /// A browser pane.
    static func browserDocument(
        id: UUID = UUID(),
        urlString: String = "dahso://browser",
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
        switch self {
        case .terminal:
            return true
        case .document(let file):
            return !(file.isMail || file.isCalendar)
        }
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
                browserPageZoom: file.browserPageZoom
            )
            return .document(openFile: file)
        }
    }

    func defaultNewPaneTab() -> PaneContent? {
        switch self {
        case .terminal:
            return .terminal()
        case .document(let file):
            if file.isMail || file.isCalendar {
                return nil
            }
            if file.isBrowser {
                return .browserDocument(urlString: "dahso://browser", title: "New Tab")
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
