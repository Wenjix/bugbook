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
                    .padding(6)
                    .transition(.opacity)
            }
        }
        .clipShape(Rectangle())
        .onHover { isHovered = $0 }
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

// MARK: - Pane Action Bar

/// Hover-reveal action buttons: split-right, split-down, pop-out, close.
/// Split buttons show a type picker via floatingPopover.
/// When `isOnlyPane` is true, hides close and pop-out (only splits are useful).
private struct PaneActionBar: View {
    let leaf: PaneNode.Leaf
    let workspaceManager: WorkspaceManager
    var isOnlyPane: Bool = false

    @State private var splitRightPicker = false
    @State private var splitDownPicker = false
    @State private var mergePicker = false

    var body: some View {
        HStack(spacing: 0) {
            // Split right — click shows type picker
            actionButton(help: "Split right") {
                splitRightPicker = true
            } label: {
                SplitIcon(direction: .right)
            }
            .floatingPopover(isPresented: $splitRightPicker) {
                TypePickerPopover { content in
                    splitRightPicker = false
                    workspaceManager.setFocusedPane(id: leaf.id)
                    _ = workspaceManager.splitFocusedPane(axis: .horizontal, newContent: content)
                }
                .popoverSurface()
            }

            // Split down — click shows type picker
            actionButton(help: "Split down") {
                splitDownPicker = true
            } label: {
                SplitIcon(direction: .down)
            }
            .floatingPopover(isPresented: $splitDownPicker) {
                TypePickerPopover { content in
                    splitDownPicker = false
                    workspaceManager.setFocusedPane(id: leaf.id)
                    _ = workspaceManager.splitFocusedPane(axis: .vertical, newContent: content)
                }
                .popoverSurface()
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
            if otherTabs.count > 0 {
                divider

                actionButton(icon: "arrow.down.left.square", help: "Pull tab in here") {
                    mergePicker = true
                }
                .floatingPopover(isPresented: $mergePicker) {
                    MergeTabPopover(
                        workspaceManager: workspaceManager,
                        targetPaneId: leaf.id,
                        otherTabs: otherTabs,
                        dismiss: { mergePicker = false }
                    )
                    .popoverSurface()
                }
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

// MARK: - Type Picker Popover

/// Compact list of content types for split/replace operations.
private struct TypePickerPopover: View {
    let onPick: (PaneContent) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            typeRow(icon: "terminal", label: "Terminal") { onPick(.terminal) }
            typeRow(icon: "doc.text", label: "Page") { onPick(.emptyDocument()) }
            typeRow(icon: "calendar", label: "Calendar") { onPick(.calendarDocument()) }
            typeRow(icon: "person.2", label: "Meetings") { onPick(.meetingsDocument()) }
            typeRow(icon: "point.3.connected.trianglepath.dotted", label: "Graph") { onPick(.graphDocument()) }
        }
        .padding(.vertical, 4)
        .frame(width: 140)
    }

    private func typeRow(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                    .frame(width: 14)
                    .foregroundStyle(.secondary)
                Text(label)
                    .font(.system(size: 12))
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Merge Tab Popover

/// Lists other open tabs that can be pulled into the current pane's layout as a split.
private struct MergeTabPopover: View {
    let workspaceManager: WorkspaceManager
    let targetPaneId: UUID
    let otherTabs: [(index: Int, workspace: Workspace)]
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Pull into split")
                .font(.system(size: Typography.caption2, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.top, 8)
                .padding(.bottom, 4)

            ForEach(otherTabs, id: \.workspace.id) { index, ws in
                Button {
                    workspaceManager.mergeTab(at: index, intoPane: targetPaneId, axis: .horizontal)
                    dismiss()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: tabIcon(for: ws))
                            .font(.system(size: 11))
                            .frame(width: 14)
                            .foregroundStyle(.secondary)
                        Text(tabLabel(for: ws))
                            .font(.system(size: 12))
                            .lineLimit(1)
                        Spacer()
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.bottom, 6)
        .frame(width: 160)
    }

    private func tabLabel(for ws: Workspace) -> String {
        guard let leaf = ws.root.firstLeaf else { return ws.name }
        switch leaf.content {
        case .document(let file):
            if let name = file.displayName, !name.isEmpty { return name }
            if file.isEmptyTab { return "New Tab" }
            return (file.path as NSString).lastPathComponent
        case .terminal: return "Terminal"
        }
    }

    private func tabIcon(for ws: Workspace) -> String {
        guard let leaf = ws.root.firstLeaf else { return "doc" }
        switch leaf.content {
        case .document(let file):
            if file.isCalendar { return "calendar" }
            if file.isMeetings { return "person.2" }
            if file.isGraphView { return "point.3.connected.trianglepath.dotted" }
            return "doc.text"
        case .terminal: return "terminal"
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
