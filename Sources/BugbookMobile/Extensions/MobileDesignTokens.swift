import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Corner Radius

enum MobileRadius {
    static let sm: CGFloat = 6
    static let md: CGFloat = 10
    static let lg: CGFloat = 12
}

// MARK: - Theme Colors

extension Color {
    #if os(iOS)
    static var mobileBgPrimary: Color {
        Color(UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.098, green: 0.098, blue: 0.098, alpha: 1)
                : UIColor(red: 0.992, green: 0.988, blue: 0.980, alpha: 1)
        })
    }
    static var mobileBgSecondary: Color {
        Color(UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.125, green: 0.125, blue: 0.125, alpha: 1)
                : UIColor(red: 0.976, green: 0.969, blue: 0.953, alpha: 1)
        })
    }
    static var mobileBgTertiary: Color {
        Color(UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.184, green: 0.184, blue: 0.184, alpha: 1)
                : UIColor(red: 0.961, green: 0.953, blue: 0.933, alpha: 1)
        })
    }
    static var mobileTextPrimary: Color {
        Color(UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.941, green: 0.937, blue: 0.925, alpha: 1)
                : UIColor(red: 0.102, green: 0.102, blue: 0.102, alpha: 1)
        })
    }
    static var mobileTextSecondary: Color {
        Color(UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.608, green: 0.608, blue: 0.608, alpha: 1)
                : UIColor(red: 0.533, green: 0.533, blue: 0.533, alpha: 1)
        })
    }
    static var mobileTextMuted: Color {
        Color(UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.216, green: 0.216, blue: 0.216, alpha: 1)
                : UIColor(red: 0.600, green: 0.600, blue: 0.600, alpha: 1)
        })
    }
    static var mobileBorder: Color {
        Color(UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.18, green: 0.18, blue: 0.18, alpha: 1)
                : UIColor(red: 0.898, green: 0.898, blue: 0.898, alpha: 1)
        })
    }
    static var mobileDivider: Color {
        Color(UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.18, green: 0.18, blue: 0.18, alpha: 1)
                : UIColor(red: 0.898, green: 0.898, blue: 0.898, alpha: 1)
        })
    }
    static var mobileCardBg: Color {
        Color(UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.145, green: 0.145, blue: 0.145, alpha: 1)
                : UIColor(red: 0.961, green: 0.953, blue: 0.933, alpha: 1)
        })
    }
    static var mobileWarmAccent: Color {
        Color(UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.525, green: 0.404, blue: 0.259, alpha: 1)
                : UIColor(red: 0.749, green: 0.573, blue: 0.357, alpha: 1)
        })
    }
    static var mobileUtilityIcon: Color {
        Color(UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.670, green: 0.670, blue: 0.670, alpha: 1)
                : UIColor(red: 0.667, green: 0.667, blue: 0.667, alpha: 1)
        })
    }
    static var mobileFloatingActionBg: Color {
        Color(UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.208, green: 0.208, blue: 0.208, alpha: 1)
                : UIColor(red: 0.220, green: 0.220, blue: 0.220, alpha: 1)
        })
    }
    static var mobileActionBlue: Color {
        Color(UIColor { _ in
            UIColor(red: 0.0, green: 0.478, blue: 1.0, alpha: 1)
        })
    }
    #else
    static var mobileBgPrimary: Color { Color(red: 0.992, green: 0.988, blue: 0.980) }
    static var mobileBgSecondary: Color { Color(red: 0.976, green: 0.969, blue: 0.953) }
    static var mobileBgTertiary: Color { Color(red: 0.961, green: 0.953, blue: 0.933) }
    static var mobileTextPrimary: Color { Color(red: 0.102, green: 0.102, blue: 0.102) }
    static var mobileTextSecondary: Color { Color(red: 0.533, green: 0.533, blue: 0.533) }
    static var mobileTextMuted: Color { Color(red: 0.600, green: 0.600, blue: 0.600) }
    static var mobileBorder: Color { Color(red: 0.898, green: 0.898, blue: 0.898) }
    static var mobileDivider: Color { Color(red: 0.898, green: 0.898, blue: 0.898) }
    static var mobileCardBg: Color { Color(red: 0.961, green: 0.953, blue: 0.933) }
    static var mobileWarmAccent: Color { Color(red: 0.749, green: 0.573, blue: 0.357) }
    static var mobileUtilityIcon: Color { Color(red: 0.667, green: 0.667, blue: 0.667) }
    static var mobileFloatingActionBg: Color { Color(red: 0.220, green: 0.220, blue: 0.220) }
    static var mobileActionBlue: Color { Color(red: 0.0, green: 0.478, blue: 1.0) }
    #endif
}

// MARK: - Card Style Modifier

struct MobileCardStyle: ViewModifier {
    var padding: CGFloat = 14

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(Color.mobileCardBg)
            .clipShape(RoundedRectangle(cornerRadius: MobileRadius.lg))
            .overlay(
                RoundedRectangle(cornerRadius: MobileRadius.lg)
                    .stroke(Color.mobileBorder, lineWidth: 0.5)
            )
    }
}

extension View {
    func mobileCard(padding: CGFloat = 14) -> some View {
        modifier(MobileCardStyle(padding: padding))
    }
}
