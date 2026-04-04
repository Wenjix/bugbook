import SwiftUI

/// Renders a single pane leaf: chrome bar (30px) + content below.
///
/// Focus state is observed by PaneChromeBar and PaneFocusOverlay internally —
/// the document/terminal content is NOT re-rendered when focus changes.
struct PaneContentView: View {
    let leaf: PaneNode.Leaf
    let workspaceManager: WorkspaceManager
    let showFocusBorder: Bool
    var fileTree: [FileEntry] = []

    let documentContentBuilder: (PaneNode.Leaf, OpenFile) -> AnyView
    let terminalContentBuilder: (PaneNode.Leaf, Bool) -> AnyView
    var breadcrumbProvider: ((OpenFile) -> [BreadcrumbItem])? = nil
    var onBreadcrumbNavigate: ((BreadcrumbItem) -> Void)? = nil

    @State private var isDropTarget = false

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                PaneChromeBar(
                    leaf: leaf,
                    workspaceManager: workspaceManager,
                    isOnlyPane: !showFocusBorder,
                    fileTree: fileTree,
                    breadcrumbs: chromeBreadcrumbs,
                    onBreadcrumbNavigate: onBreadcrumbNavigate
                )

                contentForLeaf
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            PaneFocusOverlay(
                paneId: leaf.id,
                workspaceManager: workspaceManager
            )

            // Drop target highlight for pane swap
            if isDropTarget {
                RoundedRectangle(cornerRadius: 0)
                    .strokeBorder(Color.fallbackAccent.opacity(Opacity.strong), lineWidth: 2)
                    .allowsHitTesting(false)
            }
        }
        .clipShape(Rectangle())
        .onDrop(of: [.text], isTargeted: $isDropTarget) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: NSString.self) { item, _ in
                guard let idString = item as? String,
                      let sourceId = UUID(uuidString: idString),
                      sourceId != leaf.id else { return }
                DispatchQueue.main.async {
                    workspaceManager.swapPaneContents(paneA: sourceId, paneB: leaf.id)
                }
            }
            return true
        }
        .contextMenu {
            Menu("Split Right") {
                paneTypeMenu { content in
                    workspaceManager.setFocusedPane(id: leaf.id)
                    _ = workspaceManager.splitFocusedPane(axis: .horizontal, newContent: content)
                }
            }
            Menu("Split Down") {
                paneTypeMenu { content in
                    workspaceManager.setFocusedPane(id: leaf.id)
                    _ = workspaceManager.splitFocusedPane(axis: .vertical, newContent: content)
                }
            }
            Divider()
            Menu("Replace With") {
                paneTypeMenu { content in
                    workspaceManager.updatePaneContent(paneId: leaf.id, content: content)
                }
            }
            if showFocusBorder {
                Button("Pop Out to Tab") {
                    workspaceManager.popOutPane(id: leaf.id)
                }
            }
            Divider()
            Button("Close Pane") {
                workspaceManager.closePane(id: leaf.id)
            }
        }
    }

    @ViewBuilder
    private func paneTypeMenu(action: @escaping (PaneContent) -> Void) -> some View {
        Button("Terminal") { action(.terminal) }
        Button("Empty Page") { action(.emptyDocument()) }
        Button("Mail") { action(.mailDocument()) }
        Button("Calendar") { action(.calendarDocument()) }
        Button("Meetings") { action(.meetingsDocument()) }
        Button("Graph View") { action(.graphDocument()) }
        Button("Home") { action(.gatewayDocument()) }
    }

    private var chromeBreadcrumbs: [BreadcrumbItem] {
        guard let provider = breadcrumbProvider else { return [] }
        switch leaf.content {
        case .document(let file):
            if file.isEmptyTab || file.isMail || file.isCalendar || file.isMeetings || file.isGateway || file.isChat || file.isGraphView { return [] }
            return provider(file)
        case .terminal:
            return []
        }
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

// MARK: - Split Direction Icon

/// Correctly oriented split icon: a rectangle with a divider line.
/// `.right` = vertical divider (splits left|right). `.down` = horizontal divider (splits top/bottom).
struct SplitIcon: View {
    enum Direction { case right, down }
    let direction: Direction

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 2)
                .strokeBorder(Color.secondary, lineWidth: 1.5)
                .frame(width: 12, height: 10)

            if direction == .right {
                // Vertical line = split left|right
                Rectangle().fill(Color.secondary).frame(width: 1.5, height: 10)
            } else {
                // Horizontal line = split top/bottom
                Rectangle().fill(Color.secondary).frame(width: 12, height: 1.5)
            }
        }
    }
}

// MARK: - Button Style

struct PaneActionButtonStyle: ButtonStyle {
    let isDestructive: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: Radius.xs)
                    .fill(backgroundColor(configuration.isPressed))
            )
    }

    private func backgroundColor(_ isPressed: Bool) -> Color {
        if isPressed {
            return isDestructive ? Color.red.opacity(0.12) : Color.primary.opacity(0.08)
        }
        return .clear
    }
}

// MARK: - Focus Overlay

private struct PaneFocusOverlay: View {
    let paneId: UUID
    let workspaceManager: WorkspaceManager

    var body: some View {
        // Focus tracking only — chrome bar handles focus visual indication.
        #if os(macOS)
        PaneFocusTracker(paneId: paneId) { id in
            workspaceManager.setFocusedPane(id: id)
        }
        #else
        EmptyView()
        #endif
    }
}
