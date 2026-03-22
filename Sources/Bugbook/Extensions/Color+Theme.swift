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

// MARK: - Notion-inspired palette
//
// Two core tones:
//   Chrome (#202020 dark / #f7f7f5 light) — sidebar, tab bar, breadcrumbs
//   Canvas (#191919 dark / #ffffff light) — main page, active tab

extension Color {
    // Canvas — the main page background
    static let fallbackBgPrimary   = Color(light: .white,               dark: Color(hex: "191919"))
    // Chrome — sidebar, tab bar, breadcrumbs
    static let fallbackBgSecondary = Color(light: Color(hex: "f8f8f7"), dark: Color(hex: "202020"))
    // Elevated — cards, code blocks, hover states
    static let fallbackBgTertiary  = Color(light: Color(hex: "eeeeec"), dark: Color(hex: "2f2f2f"))

    // Text (Notion values)
    static let fallbackTextPrimary   = Color(light: Color(hex: "1f1f1f"), dark: Color(hex: "F0EFEC"))
    static let fallbackTextSecondary = Color(light: Color(hex: "6b6b6b"), dark: Color(hex: "9b9b9b"))
    static let fallbackTextMuted     = Color(light: Color(hex: "9b9b9b"), dark: Color(hex: "373737"))

    // Accent — neutral charcoal (light) / soft gray (dark)
    static let fallbackAccent      = Color(light: Color(hex: "2d2d2d"), dark: Color(hex: "b0b0b0"))
    static let fallbackAccentLight = Color(light: Color(hex: "e8e8e8"), dark: Color(hex: "3a3a3a"))
    // Text on accent fill — white on charcoal (light), dark on gray (dark)
    static let fallbackAccentFg    = Color(light: .white, dark: Color(hex: "1f1f1f"))

    // Borders & dividers
    static let fallbackBorderColor  = Color(light: Color(hex: "e8e8e5"), dark: Color(hex: "2e2e2e"))
    static let fallbackDividerColor = Color(light: Color(hex: "eeeeec"), dark: Color(hex: "2e2e2e"))
    static let fallbackChromeBorder = Color(light: Color(hex: "e0e0e0"), dark: Color(hex: "2e2e2e"))

    // Chrome — sidebar, tab bar, breadcrumbs
    static let fallbackSidebarBg = Color(light: Color(hex: "f8f8f7"), dark: Color(hex: "202020"))
    static let fallbackTabBarBg  = Color(light: Color(hex: "f8f8f7"), dark: Color(hex: "202020"))
    // Canvas — editor, active tab
    static let fallbackEditorBg  = Color(light: .white, dark: Color(hex: "191919"))

    // Semantic surfaces
    static let fallbackCardBg        = Color(light: .white,               dark: Color(hex: "202020"))
    static let fallbackSurfaceHover  = Color(light: Color(hex: "0000000A"), dark: Color(hex: "ffffff0A"))
    static let fallbackSurfaceSubtle = Color(light: Color(hex: "00000008"), dark: Color(hex: "ffffff08"))
    static let fallbackBadgeBg       = Color(light: Color(hex: "0000001A"), dark: Color(hex: "ffffff1A"))

    // Selection / highlight
    static let selectionHighlight = Color(light: Color(hex: "B4D7FF").opacity(0.45), dark: Color(hex: "B4D7FF").opacity(0.2))
}

// MARK: - Helpers

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)

        let r, g, b, a: UInt64
        switch hex.count {
        case 6:
            (r, g, b, a) = (int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF, 255)
        case 8:
            (r, g, b, a) = (int >> 24 & 0xFF, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (r, g, b, a) = (0, 0, 0, 255)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
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
