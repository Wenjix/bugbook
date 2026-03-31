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
        VStack(spacing: 0) {
            // Compact toolbar
            HStack(spacing: ShellZoomMetrics.size(6)) {
                Image(systemName: "terminal")
                    .font(ShellZoomMetrics.font(Typography.caption))
                    .foregroundStyle(.secondary)

                Text(session.title)
                    .font(ShellZoomMetrics.font(Typography.caption))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer()

                if !session.isAlive {
                    Text("exited")
                        .font(ShellZoomMetrics.font(Typography.caption2))
                        .foregroundStyle(StatusColor.cancelled)
                }
            }
            .padding(.horizontal, ShellZoomMetrics.size(10))
            .padding(.vertical, ShellZoomMetrics.size(4))
            .background(Color.fallbackBgSecondary)

            Divider()

            // Terminal surface
            GhosttyTerminalView(session: session, isFocused: isFocused)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
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
