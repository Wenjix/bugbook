import Foundation

enum TabKind: Equatable, Hashable, Codable, Sendable {
    case page
    case database
    case mail
    case calendar
    case meetings
    case graphView
    case skill
    case gateway
    case chat
    /// Sentinel for tab kinds that no longer exist (e.g. persisted "browser"
    /// tabs from older layouts). Never allowed by the feature gate, so the
    /// workspace sanitizer strips these on restore.
    case removed
    case databaseRow(dbPath: String, rowId: String)

    var isDatabase: Bool { self == .database }
    var isMail: Bool { self == .mail }
    var isCalendar: Bool { self == .calendar }
    var isMeetings: Bool { self == .meetings }
    var isGraphView: Bool { self == .graphView }
    var isSkill: Bool { self == .skill }
    var isGateway: Bool { self == .gateway }
    var isChat: Bool { self == .chat }
    var isDatabaseRow: Bool { if case .databaseRow = self { return true }; return false }
    var databasePath: String? { if case .databaseRow(let p, _) = self { return p }; return nil }
    var databaseRowId: String? { if case .databaseRow(_, let r) = self { return r }; return nil }

    private struct RawCodingKey: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }
        init(_ stringValue: String) { self.stringValue = stringValue }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    /// Discriminator-aware decoding: live kinds decode normally (and rethrow
    /// real payload errors, e.g. a corrupt databaseRow), while removed or
    /// unknown discriminators (e.g. "browser") decode as `.removed` so the
    /// sanitizer drops the tab instead of the whole layout failing to restore.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: RawCodingKey.self)
        switch container.allKeys.first?.stringValue {
        case "page": self = .page
        case "database": self = .database
        case "mail": self = .mail
        case "calendar": self = .calendar
        case "meetings": self = .meetings
        case "graphView": self = .graphView
        case "skill": self = .skill
        case "gateway": self = .gateway
        case "chat": self = .chat
        case "databaseRow":
            let payload = try container.nestedContainer(
                keyedBy: RawCodingKey.self,
                forKey: RawCodingKey("databaseRow")
            )
            self = .databaseRow(
                dbPath: try payload.decode(String.self, forKey: RawCodingKey("dbPath")),
                rowId: try payload.decode(String.self, forKey: RawCodingKey("rowId"))
            )
        default:
            self = .removed
        }
    }
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
    var isGraphView: Bool { kind.isGraphView }
    var isSkill: Bool { kind.isSkill }
    var isGateway: Bool { kind.isGateway }
    var isChat: Bool { kind.isChat }
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
