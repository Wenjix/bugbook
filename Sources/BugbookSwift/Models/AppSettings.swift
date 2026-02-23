import Foundation

enum ThemeMode: String, Codable {
    case light
    case dark
    case system
}

struct AppSettings: Codable {
    var theme: ThemeMode
    var focusModeOnType: Bool

    static let `default` = AppSettings(theme: .system, focusModeOnType: false)
}
