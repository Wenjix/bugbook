import SwiftUI

/// Renders a single pane leaf's content with focus tracking and hover action bar.
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
    @State private var isDropTarget = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            contentForLeaf
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            PaneFocusOverlay(
                paneId: leaf.id,
                workspaceManager: workspaceManager,
                showBorder: showFocusBorder
            )

            if isHovered {
                PaneActionBar(leaf: leaf, workspaceManager: workspaceManager, isOnlyPane: !showFocusBorder)
                    .padding(.top, 38)
                    .padding([.trailing, .bottom], 6)
                    .transition(.opacity)
            }

            // Drop target highlight for pane swap
            if isDropTarget {
                RoundedRectangle(cornerRadius: 0)
                    .strokeBorder(Color.fallbackAccent.opacity(Opacity.strong), lineWidth: 2)
                    .allowsHitTesting(false)
            }
        }
        .clipShape(Rectangle())
        .onHover { isHovered = $0 }
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

// MARK: - Pane Action Bar

/// Hover-reveal action buttons: split-right, split-down, pop-out, close.
/// Split/merge buttons use native Menu to avoid floatingPopover dismiss conflicts.
/// When `isOnlyPane` is true, hides close and pop-out (only splits are useful).
private struct PaneActionBar: View {
    let leaf: PaneNode.Leaf
    let workspaceManager: WorkspaceManager
    var isOnlyPane: Bool = false

    var body: some View {
        HStack(spacing: 0) {
            // Drag handle for pane swap
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
                .onDrag {
                    NSItemProvider(object: leaf.id.uuidString as NSString)
                }
                .help("Drag to swap panes")

            divider

            // Split right
            splitMenu(direction: .right, help: "Split right") { content in
                workspaceManager.setFocusedPane(id: leaf.id)
                _ = workspaceManager.splitFocusedPane(axis: .horizontal, newContent: content)
            }

            // Split down
            splitMenu(direction: .down, help: "Split down") { content in
                workspaceManager.setFocusedPane(id: leaf.id)
                _ = workspaceManager.splitFocusedPane(axis: .vertical, newContent: content)
            }

            if !isOnlyPane {
                divider

                // Pop out to own tab
                actionButton(icon: "arrow.up.right.square", help: "Pop out to tab") {
                    workspaceManager.popOutPane(id: leaf.id)
                }

                // Close
                actionButton(icon: "xmark", help: "Close pane", isDestructive: true) {
                    workspaceManager.closePane(id: leaf.id)
                }
            }

            // Merge another tab into this pane (show when other tabs exist)
            if !otherTabs.isEmpty {
                divider

                mergeMenu
            }
        }
        .padding(.horizontal, 2)
        .padding(.vertical, 1)
        .background(
            RoundedRectangle(cornerRadius: Radius.sm)
                .fill(Color.fallbackEditorBg)
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.sm)
                        .strokeBorder(Color.fallbackBorderColor, lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
        )
    }

    // MARK: - Helpers

    /// Other tabs that could be merged into this pane's layout.
    private var otherTabs: [(index: Int, workspace: Workspace)] {
        workspaceManager.workspaces.enumerated().compactMap { index, ws in
            index == workspaceManager.activeWorkspaceIndex ? nil : (index, ws)
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.fallbackDividerColor)
            .frame(width: 1, height: 14)
            .padding(.horizontal, 1)
    }

    private func splitMenu(direction: SplitIcon.Direction, help: String, action: @escaping (PaneContent) -> Void) -> some View {
        Menu {
            Button("Terminal") { action(.terminal) }
            Button("Empty Page") { action(.emptyDocument()) }
            Button("Mail") { action(.mailDocument()) }
            Button("Calendar") { action(.calendarDocument()) }
            Button("Meetings") { action(.meetingsDocument()) }
            Button("Graph View") { action(.graphDocument()) }
        } label: {
            SplitIcon(direction: direction)
                .foregroundStyle(.secondary)
                .frame(width: 22, height: 20)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(help)
    }

    private var mergeMenu: some View {
        Menu {
            ForEach(otherTabs, id: \.workspace.id) { index, ws in
                Button(mergeLabel(for: ws)) {
                    workspaceManager.mergeTab(at: index, intoPane: leaf.id, axis: .horizontal)
                }
            }
        } label: {
            Image(systemName: "arrow.down.left.square")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 22, height: 20)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Pull tab in here")
    }

    private func mergeLabel(for ws: Workspace) -> String {
        guard let leaf = ws.root.firstLeaf else { return ws.name }
        switch leaf.content {
        case .document(let file):
            if let name = file.displayName, !name.isEmpty { return name }
            if file.isEmptyTab { return "New Tab" }
            return (file.path as NSString).lastPathComponent
        case .terminal: return "Terminal"
        }
    }

    private func actionButton(icon: String? = nil, help: String, isDestructive: Bool = false, action: @escaping () -> Void, @ViewBuilder label: () -> some View = { EmptyView() }) -> some View {
        Button(action: action) {
            Group {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 10, weight: .medium))
                } else {
                    label()
                }
            }
            .foregroundStyle(.secondary)
            .frame(width: 22, height: 20)
            .contentShape(Rectangle())
        }
        .buttonStyle(PaneActionButtonStyle(isDestructive: isDestructive))
        .help(help)
    }
}

// MARK: - Split Direction Icon

/// Correctly oriented split icon: a rectangle with a divider line.
/// `.right` = vertical divider (splits left|right). `.down` = horizontal divider (splits top/bottom).
private struct SplitIcon: View {
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

private struct PaneActionButtonStyle: ButtonStyle {
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
