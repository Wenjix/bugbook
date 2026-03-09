import SwiftUI
import AppKit

/// Tracks whether cursor should be overridden to I-beam.
/// Grip dots, resize handles, and other special areas call `setOverride` to show their own cursor.
enum EditorCursorState {
    enum Override: Equatable {
        case openHand
        case resizeLeftRight

        var cursor: NSCursor {
            switch self {
            case .openHand:
                return .openHand
            case .resizeLeftRight:
                return .resizeLeftRight
            }
        }
    }

    @MainActor private static var isInsideEditor = false
    @MainActor private static var activeOverride: Override?

    @MainActor static func setEditorHover(_ isHovering: Bool) {
        isInsideEditor = isHovering
        applyCursor()
    }

    @MainActor static func setOverride(_ override: Override?) {
        activeOverride = override
        applyCursor()
    }

    @MainActor private static func applyCursor() {
        if let activeOverride {
            activeOverride.cursor.set()
        } else if isInsideEditor {
            NSCursor.iBeam.set()
        } else {
            NSCursor.arrow.set()
        }
    }
}

/// Tracks hover inside the editor and keeps the cursor on I-beam unless a
/// specific child interaction overrides it.
struct EditorIBeamCursor: ViewModifier {
    func body(content: Content) -> some View {
        content
            .onContinuousHover { phase in
                switch phase {
                case .active(_):
                    EditorCursorState.setEditorHover(true)
                case .ended:
                    EditorCursorState.setEditorHover(false)
                }
            }
            .onDisappear {
                EditorCursorState.setEditorHover(false)
                EditorCursorState.setOverride(nil)
            }
    }
}

extension View {
    func editorIBeamCursor() -> some View {
        modifier(EditorIBeamCursor())
    }
}
