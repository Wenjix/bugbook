import Foundation

struct MobileNoteFile: Identifiable, Hashable {
    var id: String { path }
    let path: String
    let name: String
}
