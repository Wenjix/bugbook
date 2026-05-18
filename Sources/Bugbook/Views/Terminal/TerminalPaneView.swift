import SwiftUI
import AppKit

/// SwiftUI view for a terminal pane. Wraps a ghostty Metal surface via NSViewRepresentable.
struct TerminalPaneView: View {
    let session: TerminalSession
    let paneId: UUID
    let workspaceManager: WorkspaceManager

    private var isFocused: Bool {
        workspaceManager.activeWorkspace?.focusedPaneId == paneId
    }

    var body: some View {
        // Terminal surface — chrome bar handles the title/icon
        GhosttyTerminalView(session: session, isFocused: isFocused)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - NSViewRepresentable

private struct GhosttyTerminalView: NSViewRepresentable {
    let session: TerminalSession
    let isFocused: Bool

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        guard let surfaceView = session.surfaceView else {
            return NSView()
        }
        surfaceView.translatesAutoresizingMaskIntoConstraints = false
        context.coordinator.wasFocused = isFocused
        return surfaceView
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        let wasFocused = context.coordinator.wasFocused
        context.coordinator.wasFocused = isFocused

        // Only act on focus transitions to avoid re-stealing focus on unrelated renders
        guard wasFocused != isFocused else { return }

        DispatchQueue.main.async {
            guard let window = nsView.window else { return }
            if isFocused {
                if window.firstResponder !== nsView {
                    window.makeFirstResponder(nsView)
                }
            } else {
                if window.firstResponder === nsView {
                    window.makeFirstResponder(nil)
                }
            }
        }
    }

    class Coordinator {
        var wasFocused = false
    }
}
