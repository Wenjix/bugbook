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

    /// Decode a raw icon string as stored in page metadata (`<!-- icon:... -->`)
    /// and `FileEntry.icon`. This is the single place that knows the format:
    /// - `custom:<path>` — uploaded image file
    /// - `sf:<name>` — SF Symbol
    /// - leading emoji scalar — emoji icon
    /// - bare absolute path — legacy custom image file
    /// - anything else — nil (callers render their default icon)
    static func parse(_ raw: String?) -> PageIcon? {
        guard let raw, !raw.isEmpty else { return nil }
        if raw.hasPrefix("custom:") {
            return .custom(String(raw.dropFirst(7)))
        }
        if raw.hasPrefix("sf:") {
            return .symbol(String(raw.dropFirst(3)))
        }
        if raw.unicodeScalars.first?.properties.isEmoji == true {
            return .emoji(raw)
        }
        if raw.hasPrefix("/") {
            return .custom(raw)
        }
        return nil
    }
}
