import Foundation

/// The content type displayed in a single pane leaf.
enum PaneContent: Codable, Equatable {
    /// A document pane — routes through OpenFile.kind for all existing content types.
    case document(openFile: OpenFile)

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

    var id: UUID {
        switch self {
        case .document(let file):
            return file.id
        }
    }

    var openFile: OpenFile? {
        guard case .document(let file) = self else { return nil }
        return file
    }

    var supportsPaneTabs: Bool {
        true
    }

    func reidentified(as id: UUID) -> PaneContent {
        switch self {
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
                isExternal: file.isExternal
            )
            return .document(openFile: file)
        }
    }

    func defaultNewPaneTab() -> PaneContent? {
        switch self {
        case .document:
            return .emptyDocument()
        }
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case openFile
        case sessionID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "document":
            let file = try container.decode(OpenFile.self, forKey: .openFile)
            self = .document(openFile: file)
        default:
            // Removed pane types from older layouts (e.g. "terminal") decode as
            // a sentinel the workspace sanitizer prunes — the pane collapses to
            // its surviving sibling instead of lingering as a blank pane.
            let sessionID = try container.decodeIfPresent(UUID.self, forKey: .sessionID) ?? UUID()
            self = .document(openFile: OpenFile(
                id: sessionID,
                path: "",
                content: "",
                isDirty: false,
                isEmptyTab: false,
                kind: .removed
            ))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .document(let file):
            try container.encode("document", forKey: .type)
            try container.encode(file, forKey: .openFile)
        }
    }
}

extension PaneContent {
    var paneItemTitle: String {
        switch self {
        case .document(let file):
            return file.paneItemTitle
        }
    }

    var paneItemIcon: String {
        switch self {
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
        if isMeetings { return "sf:person.2" }
        if isChat { return "sf:bubble.left.and.bubble.right" }
        if isGraphView { return "sf:point.3.connected.trianglepath.dotted" }

        if let icon, !icon.isEmpty {
            return OpenFile.normalizedPaneIcon(icon)
        }
        return isDatabase ? "sf:tablecells" : "sf:doc.text"
    }

    private static func normalizedPaneIcon(_ icon: String) -> String {
        // Any icon PageIcon can decode (sf:/emoji/custom:/absolute path)
        // passes through unchanged; only bare SF symbol names get prefixed.
        PageIcon.parse(icon) != nil ? icon : "sf:\(icon)"
    }
}
