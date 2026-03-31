import SwiftUI

/// Renders a single pane leaf's content with focus tracking and border.
///
/// Focus state is observed internally by a lightweight overlay — the document/terminal
/// content is NOT re-rendered when focus changes. This prevents the editor NSTextView
/// from being destroyed mid-click.
struct PaneContentView: View {
    let leaf: PaneNode.Leaf
    let workspaceManager: WorkspaceManager
    let showFocusBorder: Bool

    let documentContentBuilder: (PaneNode.Leaf, OpenFile) -> AnyView
    let terminalContentBuilder: (PaneNode.Leaf, Bool) -> AnyView

    var body: some View {
        ZStack {
            // Content layer — does NOT depend on focus state
            contentForLeaf
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Focus tracking + indicator — observes focus independently
            PaneFocusOverlay(
                paneId: leaf.id,
                workspaceManager: workspaceManager,
                showBorder: showFocusBorder
            )
        }
        .clipShape(Rectangle())
        .contextMenu {
            Menu("Split Right") {
                paneTypeOptions { content in
                    workspaceManager.setFocusedPane(id: leaf.id)
                    _ = workspaceManager.splitFocusedPane(axis: .horizontal, newContent: content)
                }
            }
            Menu("Split Down") {
                paneTypeOptions { content in
                    workspaceManager.setFocusedPane(id: leaf.id)
                    _ = workspaceManager.splitFocusedPane(axis: .vertical, newContent: content)
                }
            }
            Divider()
            Menu("Replace With") {
                paneTypeOptions { content in
                    workspaceManager.updatePaneContent(paneId: leaf.id, content: content)
                }
            }
            Divider()
            Button("Close Pane") {
                workspaceManager.closePane(id: leaf.id)
            }
        }
    }

    @ViewBuilder
    private func paneTypeOptions(action: @escaping (PaneContent) -> Void) -> some View {
        Button("Terminal") { action(.terminal) }
        Button("Empty Page") { action(.emptyDocument()) }
        Button("Calendar") { action(.calendarDocument()) }
        Button("Meetings") { action(.meetingsDocument()) }
        Button("Graph View") { action(.graphDocument()) }
    }

    @ViewBuilder
    private var contentForLeaf: some View {
        switch leaf.content {
        case .document(let file):
            documentContentBuilder(leaf, file)
        case .terminal:
            // Terminal needs focus state for first responder — observe it in TerminalPaneView directly
            terminalContentBuilder(leaf, false)
        }
    }
}

// MARK: - Focus Overlay

/// Lightweight view that observes focus state and renders the focus indicator.
/// Isolated from document content so focus changes don't trigger content re-renders.
private struct PaneFocusOverlay: View {
    let paneId: UUID
    let workspaceManager: WorkspaceManager
    let showBorder: Bool

    private var isFocused: Bool {
        workspaceManager.activeWorkspace?.focusedPaneId == paneId
    }

    var body: some View {
        ZStack {
            // Click-to-focus tracker
            #if os(macOS)
            PaneFocusTracker(paneId: paneId) { id in
                workspaceManager.setFocusedPane(id: id)
            }
            #endif

            // Focus border
            if isFocused && showBorder {
                RoundedRectangle(cornerRadius: ShellZoomMetrics.size(Radius.xs))
                    .strokeBorder(Color.fallbackAccent.opacity(Opacity.medium), lineWidth: 2)
                    .allowsHitTesting(false)
            }
        }
    }
}
