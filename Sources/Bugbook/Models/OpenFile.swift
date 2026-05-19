import Foundation

struct OpenFile: Identifiable, Equatable, Codable {
    let id: UUID
    var path: String
    var content: String
    var isDirty: Bool
    var isEmptyTab: Bool
    var kind: TabKind
    var displayName: String?
    var openerPagePath: String?
    var icon: String?
    var navigationHistory: [String] = []
    var navigationHistoryIndex: Int = -1
    var browserSavedRecordID: UUID?
    var browserPageZoom: Double
    /// True when this tab points at a markdown file outside the workspace folder
    /// (opened via the system "Open With" handler). External tabs are not autosaved;
    /// saving moves the file into the workspace and clears this flag.
    var isExternal: Bool = false

    private enum CodingKeys: String, CodingKey {
        case id
        case path
        case content
        case isDirty
        case isEmptyTab
        case kind
        case displayName
        case openerPagePath
        case icon
        case navigationHistory
        case navigationHistoryIndex
        case browserSavedRecordID
        case browserPageZoom
        case isExternal
    }

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
    var databasePath: String? { kind.databasePath }
    var databaseRowId: String? { kind.databaseRowId }
    var browserURLString: String {
        guard isBrowser, path == "bugbook://browser" else { return path }
        return ""
    }
    var browserURL: URL? {
        guard !browserURLString.isEmpty else { return nil }
        return URL(string: browserURLString)
    }

    init(
        id: UUID,
        path: String,
        content: String,
        isDirty: Bool,
        isEmptyTab: Bool,
        kind: TabKind = .page,
        displayName: String? = nil,
        openerPagePath: String? = nil,
        icon: String? = nil,
        navigationHistory: [String] = [],
        navigationHistoryIndex: Int = -1,
        browserSavedRecordID: UUID? = nil,
        browserPageZoom: Double = 0.85,
        isExternal: Bool = false
    ) {
        self.id = id
        self.path = path
        self.content = content
        self.isDirty = isDirty
        self.isEmptyTab = isEmptyTab
        self.kind = kind
        self.displayName = displayName
        self.openerPagePath = openerPagePath
        self.icon = icon
        self.navigationHistory = navigationHistory
        self.navigationHistoryIndex = navigationHistoryIndex
        self.browserSavedRecordID = browserSavedRecordID
        self.browserPageZoom = browserPageZoom
        self.isExternal = isExternal
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.path = try container.decode(String.self, forKey: .path)
        self.content = try container.decode(String.self, forKey: .content)
        self.isDirty = try container.decode(Bool.self, forKey: .isDirty)
        self.isEmptyTab = try container.decode(Bool.self, forKey: .isEmptyTab)
        self.kind = try container.decodeIfPresent(TabKind.self, forKey: .kind) ?? .page
        self.displayName = try container.decodeIfPresent(String.self, forKey: .displayName)
        self.openerPagePath = try container.decodeIfPresent(String.self, forKey: .openerPagePath)
        self.icon = try container.decodeIfPresent(String.self, forKey: .icon)
        self.navigationHistory = try container.decodeIfPresent([String].self, forKey: .navigationHistory) ?? []
        self.navigationHistoryIndex = try container.decodeIfPresent(Int.self, forKey: .navigationHistoryIndex) ?? -1
        self.browserSavedRecordID = try container.decodeIfPresent(UUID.self, forKey: .browserSavedRecordID)
        self.browserPageZoom = try container.decodeIfPresent(Double.self, forKey: .browserPageZoom) ?? 0.85
        self.isExternal = try container.decodeIfPresent(Bool.self, forKey: .isExternal) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(path, forKey: .path)
        try container.encode(content, forKey: .content)
        try container.encode(isDirty, forKey: .isDirty)
        try container.encode(isEmptyTab, forKey: .isEmptyTab)
        try container.encode(kind, forKey: .kind)
        try container.encodeIfPresent(displayName, forKey: .displayName)
        try container.encodeIfPresent(openerPagePath, forKey: .openerPagePath)
        try container.encodeIfPresent(icon, forKey: .icon)
        try container.encode(navigationHistory, forKey: .navigationHistory)
        try container.encode(navigationHistoryIndex, forKey: .navigationHistoryIndex)
        try container.encodeIfPresent(browserSavedRecordID, forKey: .browserSavedRecordID)
        try container.encode(browserPageZoom, forKey: .browserPageZoom)
        try container.encode(isExternal, forKey: .isExternal)
    }
}
