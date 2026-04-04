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

    func makeNSView(context: Context) -> NSView {
        guard let surfaceView = session.surfaceView else {
            return NSView()
        }
        surfaceView.translatesAutoresizingMaskIntoConstraints = false
        return surfaceView
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if isFocused {
            DispatchQueue.main.async {
                if let window = nsView.window, window.firstResponder !== nsView {
                    window.makeFirstResponder(nsView)
                }
            }
        }
    }
}
