import Foundation

enum PageIconType: String, Codable {
    case emoji
    case symbol  // SF Symbol
    case custom  // Uploaded image file
}

struct PageIcon: Codable, Equatable {
    var type: PageIconType
    var value: String  // emoji character, SF Symbol name, or file path

    static func emoji(_ value: String) -> PageIcon {
        PageIcon(type: .emoji, value: value)
    }

    static func symbol(_ name: String) -> PageIcon {
        PageIcon(type: .symbol, value: name)
    }

    static func custom(_ path: String) -> PageIcon {
        PageIcon(type: .custom, value: path)
    }
}
