import SwiftUI
import AppKit

/// Tracks whether cursor should be overridden to I-beam.
/// Grip dots, resize handles, and other special areas set `suppressIBeam` to show their own cursor.
enum EditorCursorState {
    @MainActor static var suppressIBeam = false
}

/// A ViewModifier that uses a local event monitor to enforce I-beam cursor
/// within the modified view's bounds. Overrides SwiftUI's default arrow cursor
/// on buttons, tap gesture areas, etc.
struct EditorIBeamCursor: ViewModifier {
    @State private var isHovering = false
    @State private var monitor: Any?

    func body(content: Content) -> some View {
        content
            .onHover { hovering in
                if hovering && !isHovering {
                    isHovering = true
                    startMonitor()
                } else if !hovering && isHovering {
                    isHovering = false
                    stopMonitor()
                }
            }
    }

    private func startMonitor() {
        stopMonitor()
        NSCursor.iBeam.push()
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .mouseEntered, .cursorUpdate]) { event in
            if !EditorCursorState.suppressIBeam && NSCursor.current != .iBeam {
                NSCursor.iBeam.set()
            }
            return event
        }
    }

    private func stopMonitor() {
        if let monitor = monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        NSCursor.pop()
    }
}

extension View {
    func editorIBeamCursor() -> some View {
        modifier(EditorIBeamCursor())
    }
}
