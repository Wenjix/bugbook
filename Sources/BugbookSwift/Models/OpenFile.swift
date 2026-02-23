import Foundation

struct OpenFile: Identifiable, Equatable {
    let id: UUID
    var path: String
    var content: String
    var isDirty: Bool
    var isEmptyTab: Bool
    var isDatabase: Bool
    var displayName: String?
    var openerPagePath: String?
}
