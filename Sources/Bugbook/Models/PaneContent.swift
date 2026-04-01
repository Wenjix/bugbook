import Foundation

/// The content type displayed in a single pane leaf.
enum PaneContent: Codable, Equatable {
    /// A document pane — routes through OpenFile.kind for all existing content types.
    case document(openFile: OpenFile)

    /// A terminal pane (shell session). Ephemeral; only the type is persisted.
    case terminal

    // MARK: - Factories

    /// An empty document pane (new tab / welcome view).
    static func emptyDocument() -> PaneContent {
        let id = UUID()
        return .document(openFile: OpenFile(id: id, path: "", content: "", isDirty: false, isEmptyTab: true))
    }

    /// A mail pane.
    static func mailDocument() -> PaneContent {
        let id = UUID()
        return .document(openFile: OpenFile(
            id: id, path: "bugbook://mail", content: "", isDirty: false, isEmptyTab: false,
            kind: .mail, displayName: "Mail", icon: "envelope"
        ))
    }

    /// A calendar pane.
    static func calendarDocument() -> PaneContent {
        let id = UUID()
        return .document(openFile: OpenFile(
            id: id, path: "bugbook://calendar", content: "", isDirty: false, isEmptyTab: false,
            kind: .calendar, displayName: "Calendar", icon: "calendar.badge.clock"
        ))
    }

    /// A graph view pane.
    static func graphDocument() -> PaneContent {
        let id = UUID()
        return .document(openFile: OpenFile(
            id: id, path: "bugbook://graph", content: "", isDirty: false, isEmptyTab: false,
            kind: .graphView, displayName: "Graph View", icon: "sf:point.3.connected.trianglepath.dotted"
        ))
    }

    /// A gateway dashboard pane.
    static func gatewayDocument() -> PaneContent {
        let id = UUID()
        return .document(openFile: OpenFile(
            id: id, path: "bugbook://gateway", content: "", isDirty: false, isEmptyTab: false,
            kind: .gateway, displayName: "Gateway", icon: "square.grid.2x2"
        ))
    }

    /// A meetings pane.
    static func meetingsDocument() -> PaneContent {
        let id = UUID()
        return .document(openFile: OpenFile(
            id: id, path: "bugbook://meetings", content: "", isDirty: false, isEmptyTab: false,
            kind: .meetings, displayName: "Meetings", icon: "person.2"
        ))
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case openFile
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
            self = .terminal
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .document(let file):
            try container.encode(ContentType.document, forKey: .type)
            try container.encode(file, forKey: .openFile)
        case .terminal:
            try container.encode(ContentType.terminal, forKey: .type)
        }
    }
}
