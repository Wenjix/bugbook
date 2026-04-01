import Foundation

enum TabKind: Equatable, Hashable, Codable {
    case page
    case database
    case mail
    case calendar
    case meetings
    case graphView
    case skill
    case gateway
    case databaseRow(dbPath: String, rowId: String)

    var isDatabase: Bool { self == .database }
    var isMail: Bool { self == .mail }
    var isCalendar: Bool { self == .calendar }
    var isMeetings: Bool { self == .meetings }
    var isGraphView: Bool { self == .graphView }
    var isSkill: Bool { self == .skill }
    var isGateway: Bool { self == .gateway }
    var isDatabaseRow: Bool { if case .databaseRow = self { return true }; return false }
    var databasePath: String? { if case .databaseRow(let p, _) = self { return p }; return nil }
    var databaseRowId: String? { if case .databaseRow(_, let r) = self { return r }; return nil }
}

struct FileEntry: Identifiable, Hashable {
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
    var isSkill: Bool { kind.isSkill }
    var isDatabaseRow: Bool { kind.isDatabaseRow }
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
