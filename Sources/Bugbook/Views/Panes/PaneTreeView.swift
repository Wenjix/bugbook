import SwiftUI

/// Recursively renders a PaneNode tree as a tiling layout.
/// Splits become nested HStack/VStack with draggable dividers.
/// Leaves render PaneContentView.
struct PaneTreeView: View {
    let node: PaneNode
    let workspaceManager: WorkspaceManager
    let hasMultiplePanes: Bool

    /// Called when a pane leaf needs to render its document content.
    let documentContentBuilder: (PaneNode.Leaf, OpenFile) -> AnyView

    /// Called when a pane leaf needs to render its terminal content.
    let terminalContentBuilder: (PaneNode.Leaf, Bool) -> AnyView

    var body: some View {
        switch node {
        case .leaf(let leaf):
            leafView(leaf)
        case .split(let split):
            splitView(split)
        }
    }

    @ViewBuilder
    private func leafView(_ leaf: PaneNode.Leaf) -> some View {
        let isFocused = leaf.id == workspaceManager.activeWorkspace?.focusedPaneId

        PaneContentView(
            leaf: leaf,
            isFocused: isFocused,
            showFocusBorder: hasMultiplePanes,
            documentContentBuilder: documentContentBuilder,
            terminalContentBuilder: terminalContentBuilder,
            onFocus: { workspaceManager.setFocusedPane(id: leaf.id) }
        )
    }

    @ViewBuilder
    private func splitView(_ split: PaneNode.Split) -> some View {
        GeometryReader { geo in
            let totalSize = split.axis == .horizontal ? geo.size.width : geo.size.height

            let ratioBinding = Binding<Double>(
                get: { split.ratio },
                set: { workspaceManager.updateSplitRatio(splitId: split.id, ratio: $0) }
            )

            if split.axis == .horizontal {
                HStack(spacing: 0) {
                    PaneTreeView(
                        node: split.first,
                        workspaceManager: workspaceManager,
                        hasMultiplePanes: hasMultiplePanes,
                        documentContentBuilder: documentContentBuilder,
                        terminalContentBuilder: terminalContentBuilder
                    )
                    .frame(width: firstSize(total: totalSize, ratio: split.ratio))

                    SplitDividerView(axis: split.axis, ratio: ratioBinding, totalSize: totalSize)

                    PaneTreeView(
                        node: split.second,
                        workspaceManager: workspaceManager,
                        hasMultiplePanes: hasMultiplePanes,
                        documentContentBuilder: documentContentBuilder,
                        terminalContentBuilder: terminalContentBuilder
                    )
                }
            } else {
                VStack(spacing: 0) {
                    PaneTreeView(
                        node: split.first,
                        workspaceManager: workspaceManager,
                        hasMultiplePanes: hasMultiplePanes,
                        documentContentBuilder: documentContentBuilder,
                        terminalContentBuilder: terminalContentBuilder
                    )
                    .frame(height: firstSize(total: totalSize, ratio: split.ratio))

                    SplitDividerView(axis: split.axis, ratio: ratioBinding, totalSize: totalSize)

                    PaneTreeView(
                        node: split.second,
                        workspaceManager: workspaceManager,
                        hasMultiplePanes: hasMultiplePanes,
                        documentContentBuilder: documentContentBuilder,
                        terminalContentBuilder: terminalContentBuilder
                    )
                }
            }
        }
    }

    private func firstSize(total: CGFloat, ratio: Double) -> CGFloat {
        max(total * CGFloat(ratio) - 4, 0) // 4 = half the divider hit area
    }
}
