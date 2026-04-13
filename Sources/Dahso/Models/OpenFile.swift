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
        guard isBrowser, path == "dahso://browser" else { return path }
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
        browserPageZoom: Double = 0.85
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
    }
}
