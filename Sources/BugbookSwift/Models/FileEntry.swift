import Foundation

struct FileEntry: Identifiable, Hashable {
    let id: String
    var name: String
    var path: String
    var isDirectory: Bool
    var isDatabase: Bool
    var icon: String?
    var children: [FileEntry]?
}
