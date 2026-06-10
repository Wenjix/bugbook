import Foundation

enum TabKind: Equatable, Hashable, Codable, Sendable {
    case page
    case database
    case mail
    case calendar
    case meetings
    case browser
    case graphView
    case skill
    case gateway
    case chat
    case databaseRow(dbPath: String, rowId: String)
    /// Self-contained HTML artifact rendered in a locked-down WKWebView (Level 1).
    case artifact

    var isDatabase: Bool { self == .database }
    var isMail: Bool { self == .mail }
    var isCalendar: Bool { self == .calendar }
    var isMeetings: Bool { self == .meetings }
    var isBrowser: Bool { self == .browser }
    var isGraphView: Bool { self == .graphView }
    var isSkill: Bool { self == .skill }
    var isGateway: Bool { self == .gateway }
    var isChat: Bool { self == .chat }
    var isDatabaseRow: Bool { if case .databaseRow = self { return true }; return false }
    var isArtifact: Bool { self == .artifact }
    var databasePath: String? { if case .databaseRow(let p, _) = self { return p }; return nil }
    var databaseRowId: String? { if case .databaseRow(_, let r) = self { return r }; return nil }
}

struct FileEntry: Identifiable, Hashable, Sendable {
    let id: String
    var name: String
    var path: String
    var isDirectory: Bool
    var kind: TabKind
    var icon: String?
    var children: [FileEntry]?
    var isSidebarReference: Bool

    // Shims forwarding to kind for incremental migration
    var isDatabase: Bool { kind.isDatabase }
    var isMail: Bool { kind.isMail }
    var isCalendar: Bool { kind.isCalendar }
    var isMeetings: Bool { kind.isMeetings }
    var isBrowser: Bool { kind.isBrowser }
    var isGraphView: Bool { kind.isGraphView }
    var isSkill: Bool { kind.isSkill }
    var isGateway: Bool { kind.isGateway }
    var isChat: Bool { kind.isChat }
    var isDatabaseRow: Bool { kind.isDatabaseRow }
    var isArtifact: Bool { kind.isArtifact }
    var databasePath: String? { kind.databasePath }
    var databaseRowId: String? { kind.databaseRowId }

    init(
        id: String,
        name: String,
        path: String,
        isDirectory: Bool,
        kind: TabKind = .page,
        icon: String? = nil,
        children: [FileEntry]? = nil,
        isSidebarReference: Bool = false
    ) {
        self.id = id
        self.name = name
        self.path = path
        self.isDirectory = isDirectory
        self.kind = kind
        self.icon = icon
        self.children = children
        self.isSidebarReference = isSidebarReference
    }
}

extension String {
    /// File name with a known document extension removed (".md" pages, ".html" artifacts).
    var removingPageExtension: String {
        if hasSuffix(".md") { return String(dropLast(3)) }
        if hasSuffix(".html") { return String(dropLast(5)) }
        return self
    }
}
