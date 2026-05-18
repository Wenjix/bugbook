import SwiftUI

enum BlockColor: String, CaseIterable, Equatable, Sendable {
    case `default`
    case gray
    case brown
    case orange
    case yellow
    case green
    case blue
    case purple
    case pink
    case red

    var displayName: String {
        rawValue.capitalized
    }

    var textColor: Color {
        switch self {
        case .default: return Color(light: Color(hex: "1a1a1a"), dark: Color(hex: "e0e0e0"))
        case .gray: return Color(light: Color(hex: "787774"), dark: Color(hex: "979a9b"))
        case .brown: return Color(light: Color(hex: "64473a"), dark: Color(hex: "b4876e"))
        case .orange: return Color(light: Color(hex: "d9730d"), dark: Color(hex: "ffa344"))
        case .yellow: return Color(light: Color(hex: "cb9c09"), dark: Color(hex: "ffdc49"))
        case .green: return Color(light: Color(hex: "448361"), dark: Color(hex: "4dab9a"))
        case .blue: return Color(light: Color(hex: "337ea9"), dark: Color(hex: "529cca"))
        case .purple: return Color(light: Color(hex: "9065b0"), dark: Color(hex: "a475c5"))
        case .pink: return Color(light: Color(hex: "c14c8a"), dark: Color(hex: "d15796"))
        case .red: return Color(light: Color(hex: "d44c47"), dark: Color(hex: "e55b5b"))
        }
    }

    var nsTextColor: NSColor {
        NSColor(textColor)
    }

    var backgroundColor: Color {
        switch self {
        case .default: return .clear
        case .gray: return Color(light: Color(hex: "f1f1ef"), dark: Color(hex: "373737"))
        case .brown: return Color(light: Color(hex: "f4eeee"), dark: Color(hex: "434040"))
        case .orange: return Color(light: Color(hex: "fbecdd"), dark: Color(hex: "5c3b23"))
        case .yellow: return Color(light: Color(hex: "fbf3db"), dark: Color(hex: "564328"))
        case .green: return Color(light: Color(hex: "edf3ec"), dark: Color(hex: "2b4539"))
        case .blue: return Color(light: Color(hex: "e7f3f8"), dark: Color(hex: "28456c"))
        case .purple: return Color(light: Color(hex: "f4f0f7"), dark: Color(hex: "443757"))
        case .pink: return Color(light: Color(hex: "f9f0f5"), dark: Color(hex: "4e2d3f"))
        case .red: return Color(light: Color(hex: "fdebec"), dark: Color(hex: "5c2b2e"))
        }
    }
}
