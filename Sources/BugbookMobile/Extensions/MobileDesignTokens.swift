import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Corner Radius

enum MobileRadius {
    static let sm: CGFloat = 6
    static let md: CGFloat = 8
    static let lg: CGFloat = 10
}

// MARK: - Theme Colors

extension Color {
    #if os(iOS)
    static var mobileBgPrimary: Color {
        Color(UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(red: 0.098, green: 0.098, blue: 0.098, alpha: 1) : .white
        })
    }
    static var mobileBgSecondary: Color {
        Color(UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.125, green: 0.125, blue: 0.125, alpha: 1)
                : UIColor(red: 0.973, green: 0.973, blue: 0.965, alpha: 1)
        })
    }
    static var mobileBgTertiary: Color {
        Color(UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.184, green: 0.184, blue: 0.184, alpha: 1)
                : UIColor(red: 0.933, green: 0.933, blue: 0.925, alpha: 1)
        })
    }
    static var mobileTextPrimary: Color {
        Color(UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.941, green: 0.937, blue: 0.925, alpha: 1)
                : UIColor(red: 0.122, green: 0.122, blue: 0.122, alpha: 1)
        })
    }
    static var mobileTextSecondary: Color {
        Color(UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.608, green: 0.608, blue: 0.608, alpha: 1)
                : UIColor(red: 0.42, green: 0.42, blue: 0.42, alpha: 1)
        })
    }
    static var mobileTextMuted: Color {
        Color(UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.216, green: 0.216, blue: 0.216, alpha: 1)
                : UIColor(red: 0.608, green: 0.608, blue: 0.608, alpha: 1)
        })
    }
    static var mobileBorder: Color {
        Color(UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.18, green: 0.18, blue: 0.18, alpha: 1)
                : UIColor(red: 0.91, green: 0.91, blue: 0.898, alpha: 1)
        })
    }
    static var mobileDivider: Color {
        Color(UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.18, green: 0.18, blue: 0.18, alpha: 1)
                : UIColor(red: 0.933, green: 0.933, blue: 0.925, alpha: 1)
        })
    }
    static var mobileCardBg: Color {
        Color(UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.145, green: 0.145, blue: 0.145, alpha: 1)
                : UIColor(red: 0.973, green: 0.973, blue: 0.965, alpha: 1)
        })
    }
    #else
    static var mobileBgPrimary: Color { .white }
    static var mobileBgSecondary: Color { Color(red: 0.973, green: 0.973, blue: 0.965) }
    static var mobileBgTertiary: Color { Color(red: 0.933, green: 0.933, blue: 0.925) }
    static var mobileTextPrimary: Color { Color(red: 0.122, green: 0.122, blue: 0.122) }
    static var mobileTextSecondary: Color { Color(red: 0.42, green: 0.42, blue: 0.42) }
    static var mobileTextMuted: Color { Color(red: 0.608, green: 0.608, blue: 0.608) }
    static var mobileBorder: Color { Color(red: 0.91, green: 0.91, blue: 0.898) }
    static var mobileDivider: Color { Color(red: 0.933, green: 0.933, blue: 0.925) }
    static var mobileCardBg: Color { Color(red: 0.973, green: 0.973, blue: 0.965) }
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
