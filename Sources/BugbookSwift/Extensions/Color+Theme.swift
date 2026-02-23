import SwiftUI

extension Color {
    // MARK: - Backgrounds
    static let bgPrimary = Color("bgPrimary", bundle: nil)
    static let bgSecondary = Color("bgSecondary", bundle: nil)
    static let bgTertiary = Color("bgTertiary", bundle: nil)

    // MARK: - Text
    static let textPrimary = Color("textPrimary", bundle: nil)
    static let textSecondary = Color("textSecondary", bundle: nil)
    static let textMuted = Color("textMuted", bundle: nil)

    // MARK: - Accent
    static let appAccent = Color("appAccent", bundle: nil)
    static let accentLight = Color("accentLight", bundle: nil)

    // MARK: - Borders
    static let borderColor = Color("borderColor", bundle: nil)
    static let dividerColor = Color("dividerColor", bundle: nil)

    // MARK: - Surfaces
    static let sidebarBg = Color("sidebarBg", bundle: nil)
    static let editorBg = Color("editorBg", bundle: nil)
}

// MARK: - Fallback colors for use without asset catalog

extension Color {
    static let fallbackBgPrimary = Color(light: .white, dark: Color(hex: "1e1e1e"))
    static let fallbackBgSecondary = Color(light: Color(hex: "f5f5f5"), dark: Color(hex: "252525"))
    static let fallbackBgTertiary = Color(light: Color(hex: "e8e8e8"), dark: Color(hex: "2d2d2d"))
    static let fallbackTextPrimary = Color(light: Color(hex: "1a1a1a"), dark: Color(hex: "e0e0e0"))
    static let fallbackTextSecondary = Color(light: Color(hex: "555555"), dark: Color(hex: "a0a0a0"))
    static let fallbackTextMuted = Color(light: Color(hex: "999999"), dark: Color(hex: "666666"))
    static let fallbackAccent = Color(light: Color(hex: "2563eb"), dark: Color(hex: "3b82f6"))
    static let fallbackAccentLight = Color(light: Color(hex: "dbeafe"), dark: Color(hex: "1e3a5f"))
    static let fallbackBorderColor = Color(light: Color(hex: "e0e0e0"), dark: Color(hex: "3a3a3a"))
    static let fallbackDividerColor = Color(light: Color(hex: "eeeeee"), dark: Color(hex: "333333"))
    static let fallbackSidebarBg = Color(light: Color(hex: "f7f7f7"), dark: Color(hex: "1a1a1a"))
    static let fallbackEditorBg = Color(light: .white, dark: Color(hex: "1e1e1e"))
}

// MARK: - Helpers

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r, g, b: UInt64
        (r, g, b) = (int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: 1
        )
    }

    init(light: Color, dark: Color) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
                return NSColor(dark)
            } else {
                return NSColor(light)
            }
        })
    }
}
