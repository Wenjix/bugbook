import SwiftUI

/// Renders a single pane leaf's content with focus tracking, action buttons, and border.
///
/// Focus state is observed internally by a lightweight overlay — the document/terminal
/// content is NOT re-rendered when focus changes.
struct PaneContentView: View {
    let leaf: PaneNode.Leaf
    let workspaceManager: WorkspaceManager
    let showFocusBorder: Bool

    let documentContentBuilder: (PaneNode.Leaf, OpenFile) -> AnyView
    let terminalContentBuilder: (PaneNode.Leaf, Bool) -> AnyView

    @State private var isHovered = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // Content layer — does NOT depend on focus state
            contentForLeaf
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Focus tracking + indicator
            PaneFocusOverlay(
                paneId: leaf.id,
                workspaceManager: workspaceManager,
                showBorder: showFocusBorder
            )

            // Hover-reveal action buttons (top-right corner)
            if isHovered && showFocusBorder {
                PaneActionButtons(leaf: leaf, workspaceManager: workspaceManager)
                    .padding(6)
                    .transition(.opacity)
            }
        }
        .clipShape(Rectangle())
        .onHover { isHovered = $0 }
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
            terminalContentBuilder(leaf, false)
        }
    }
}

// MARK: - Pane Action Buttons

/// Small hover-reveal buttons in the top-right corner of a pane.
private struct PaneActionButtons: View {
    let leaf: PaneNode.Leaf
    let workspaceManager: WorkspaceManager

    var body: some View {
        HStack(spacing: 2) {
            actionButton(icon: "rectangle.split.1x2", help: "Split Right") {
                workspaceManager.setFocusedPane(id: leaf.id)
                _ = workspaceManager.splitFocusedPane(axis: .horizontal, newContent: .terminal)
            }
            actionButton(icon: "rectangle.split.2x1", help: "Split Down") {
                workspaceManager.setFocusedPane(id: leaf.id)
                _ = workspaceManager.splitFocusedPane(axis: .vertical, newContent: .terminal)
            }
            actionButton(icon: "xmark", help: "Close Pane") {
                workspaceManager.closePane(id: leaf.id)
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: Radius.sm)
                .fill(Color.fallbackEditorBg.opacity(0.9))
                .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
        )
    }

    private func actionButton(icon: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
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
            #if os(macOS)
            PaneFocusTracker(paneId: paneId) { id in
                workspaceManager.setFocusedPane(id: id)
            }
            #endif

            if isFocused && showBorder {
                RoundedRectangle(cornerRadius: ShellZoomMetrics.size(Radius.xs))
                    .strokeBorder(Color.fallbackAccent.opacity(Opacity.medium), lineWidth: 2)
                    .allowsHitTesting(false)
            }
        }
    }
}
