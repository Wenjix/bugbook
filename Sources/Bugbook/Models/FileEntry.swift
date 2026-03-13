import Foundation

enum TabKind: Equatable, Hashable {
    case page
    case database
    case canvas
    case databaseRow(dbPath: String, rowId: String)

    var isDatabase: Bool { self == .database }
    var isCanvas: Bool { self == .canvas }
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
    var isCanvas: Bool { kind.isCanvas }
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
