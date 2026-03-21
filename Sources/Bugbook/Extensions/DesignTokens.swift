import SwiftUI
#if os(macOS)
import AppKit
#endif

// MARK: - Typography

enum Typography {
    /// Editor body text (markdown content)
    static let content: CGFloat = 17

    /// Primary UI text (navigation, card titles, buttons)
    static let body: CGFloat = 14

    /// Compact/secondary UI text (sidebar items, metadata)
    static let bodySmall: CGFloat = 13

    /// Small labels, tabs, compact controls
    static let caption: CGFloat = 12

    /// Tiny indicators, badges, fine print
    static let caption2: CGFloat = 11

    /// Section titles, dialog headings
    static let title3: CGFloat = 18

    /// Major section headings
    static let title2: CGFloat = 22

    /// Page/display titles
    static let title: CGFloat = 28
}

// MARK: - Corner Radii

enum Radius {
    /// Controls, small chips, inline tags
    static let xs: CGFloat = 4

    /// Buttons, cards, list items
    static let sm: CGFloat = 6

    /// Popovers, panels, menus
    static let md: CGFloat = 8

    /// Modals, sheets, large containers
    static let lg: CGFloat = 10

    /// Chat bubbles, pills, full-round elements
    static let xl: CGFloat = 16
}

// MARK: - Opacity Scale

enum Opacity {
    /// Hover backgrounds, barely-there tints
    static let subtle: Double = 0.04

    /// Surface tints, light overlays
    static let light: Double = 0.08

    /// Selection highlights, accent backgrounds
    static let medium: Double = 0.15

    /// Secondary overlays, muted fills
    static let strong: Double = 0.3

    /// Disabled foreground, faded elements
    static let heavy: Double = 0.5

    /// Borders, strong secondary text
    static let solid: Double = 0.7
}

// MARK: - Status Colors (blue-anchored palette)
//
// Designed to sit next to each other without clashing.
// Cool tones dominate; warm colors reserved for warnings/attention.

enum StatusColor {
    /// Neutral, inactive, not started
    static let neutral = Color(light: Color(hex: "787774"), dark: Color(hex: "979a9b"))

    /// Queued, ready, informational
    static let info = Color(light: Color(hex: "787774"), dark: Color(hex: "979a9b"))

    /// Active, in progress, running
    static let active = Color(light: Color(hex: "d9730d"), dark: Color(hex: "e8993f"))

    /// Blocked, needs attention (indigo, not red)
    static let blocked = Color(light: Color(hex: "6c5ce7"), dark: Color(hex: "9b8ce8"))

    /// Success, complete, resolved
    static let success = Color(light: Color(hex: "448361"), dark: Color(hex: "4dab9a"))

    /// Cancelled, archived, removed
    static let cancelled = Color(light: Color(hex: "9b9b9b"), dark: Color(hex: "636363"))

    /// Warning (amber, not red)
    static let warning = Color(light: Color(hex: "cb9c09"), dark: Color(hex: "e8b930"))

    /// Error, failure, destructive
    static let error = Color(light: Color(hex: "d44c47"), dark: Color(hex: "e55b5b"))
}

// MARK: - Elevation (Popovers, Menus, Floating Surfaces)
//
// Clean white surfaces with warm, soft shadows.
// Replaces .regularMaterial (frosted gray) across all popovers.

enum Elevation {
    /// Popover/menu background — clean white, not frosted gray
    static let popoverBg = Color(light: .white, dark: Color(hex: "2a2a2a"))

    /// Popover border — visible edge definition
    static let popoverBorder = Color(light: Color(hex: "d4d4d0"), dark: Color(hex: "454545"))

    /// Warm shadow color — slightly tinted, not cold black
    static let shadowColor = Color(light: Color(hex: "1a1a1a"), dark: Color(hex: "000000"))

    /// Standard shadow for floating surfaces
    static let shadowRadius: CGFloat = 12
    static let shadowY: CGFloat = 4
    static let shadowOpacity: Double = 0.12
}


// MARK: - Tag/Label Colors
//
// Shared palette for select options, kanban columns, canvas nodes.
// Replaces the duplicated colorForName() functions.

enum TagColor {
    static func color(for name: String) -> Color {
        switch name {
        case "blue":   return Color(light: Color(hex: "337ea9"), dark: Color(hex: "529cca"))
        case "green":  return Color(light: Color(hex: "448361"), dark: Color(hex: "4dab9a"))
        case "red":    return Color(light: Color(hex: "d44c47"), dark: Color(hex: "e55b5b"))
        case "yellow": return Color(light: Color(hex: "cb9c09"), dark: Color(hex: "e8b930"))
        case "purple": return Color(light: Color(hex: "9065b0"), dark: Color(hex: "a475c5"))
        case "pink":   return Color(light: Color(hex: "c14c8a"), dark: Color(hex: "d15796"))
        case "orange": return Color(light: Color(hex: "d9730d"), dark: Color(hex: "e8993f"))
        case "teal":   return Color(light: Color(hex: "337ea9"), dark: Color(hex: "4dab9a"))
        case "gray":   return Color(light: Color(hex: "787774"), dark: Color(hex: "979a9b"))
        default:       return Color(light: Color(hex: "787774"), dark: Color(hex: "979a9b"))
        }
    }

    /// Light background tint for tags/badges (use with tag text color as foreground)
    static func background(for name: String) -> Color {
        color(for: name).opacity(Opacity.medium)
    }
}

// MARK: - Popover Surface Modifier
//
// Replaces the repeated .background(.regularMaterial) + .clipShape + .shadow pattern.
// Use with .floatingPopover() for full visual control (no native chrome).

struct PopoverSurface: ViewModifier {
    var cornerRadius: CGFloat = Radius.md

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Elevation.popoverBg)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .strokeBorder(Elevation.popoverBorder, lineWidth: 1)
                    )
                    .shadow(
                        color: Elevation.shadowColor.opacity(Elevation.shadowOpacity),
                        radius: Elevation.shadowRadius,
                        y: Elevation.shadowY
                    )
            )
    }
}

extension View {
    func popoverSurface(cornerRadius: CGFloat = Radius.md) -> some View {
        modifier(PopoverSurface(cornerRadius: cornerRadius))
    }

    /// Attach a right-click (secondary click) action to a view.
    func onNSRightClick(perform action: @escaping () -> Void) -> some View {
        overlay(RightClickOverlay(action: action))
    }
}

#if os(macOS)
/// Invisible NSView overlay that intercepts right-click events.
private struct RightClickOverlay: NSViewRepresentable {
    let action: () -> Void

    func makeNSView(context: Context) -> RightClickView {
        let v = RightClickView()
        v.action = action
        return v
    }

    func updateNSView(_ nsView: RightClickView, context: Context) {
        nsView.action = action
    }

    class RightClickView: NSView {
        var action: (() -> Void)?
        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window != nil && monitor == nil {
                monitor = NSEvent.addLocalMonitorForEvents(matching: .rightMouseDown) { [weak self] event in
                    guard let self, let window = self.window else { return event }
                    let locationInWindow = event.locationInWindow
                    let locationInView = self.convert(locationInWindow, from: nil)
                    if self.bounds.contains(locationInView) && event.window === window {
                        self.action?()
                    }
                    return event
                }
            } else if window == nil, let m = monitor {
                NSEvent.removeMonitor(m)
                monitor = nil
            }
        }

        override func removeFromSuperview() {
            if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
            super.removeFromSuperview()
        }

        // Invisible to hit testing — left clicks pass through
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}
#endif

