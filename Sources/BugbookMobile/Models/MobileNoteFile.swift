import Foundation

struct MobileNoteFile: Identifiable, Hashable {
    var id: String { path }
    let path: String
    let name: String
    var isDirectory: Bool = false
    var isDatabase: Bool = false
    var isCanvas: Bool = false
    var children: [MobileNoteFile]? = nil
    var icon: String? = nil
    var modifiedAt: Date? = nil
}
