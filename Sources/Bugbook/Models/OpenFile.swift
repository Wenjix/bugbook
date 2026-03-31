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

    // Shims forwarding to kind for incremental migration
    var isDatabase: Bool { kind.isDatabase }
    var isCalendar: Bool { kind.isCalendar }
    var isMeetings: Bool { kind.isMeetings }
    var isDatabaseRow: Bool { kind.isDatabaseRow }
    var databasePath: String? { kind.databasePath }
    var databaseRowId: String? { kind.databaseRowId }

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
        navigationHistoryIndex: Int = -1
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
    }
}
