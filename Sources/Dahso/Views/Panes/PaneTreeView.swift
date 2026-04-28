import SwiftUI

struct PaneActions {
    var createPaneTab: (PaneNode.Leaf) -> Void
    var closePaneTab: (PaneNode.Leaf, UUID) -> Void
    var closePane: (PaneNode.Leaf) -> Void
    var closeOtherPanes: (PaneNode.Leaf) -> Void
}

/// Recursively renders a PaneNode tree as a tiling layout.
/// Splits become nested HStack/VStack with draggable dividers.
/// Leaves render PaneContentView.
///
/// IMPORTANT: This view must NOT read focus state (focusedPaneId) from
/// workspaceManager. Focus observation is handled by PaneContentView's
/// internal overlay to avoid re-rendering the entire tree on focus change.
struct PaneTreeView: View {
    let node: PaneNode
    let workspaceManager: WorkspaceManager
    let hasMultiplePanes: Bool
    var fileTree: [FileEntry] = []

    let documentContentBuilder: (PaneNode.Leaf, OpenFile) -> AnyView
    let terminalContentBuilder: (PaneNode.Leaf, Bool) -> AnyView
    var breadcrumbProvider: ((OpenFile) -> [BreadcrumbItem])? = nil
    var onBreadcrumbNavigate: ((BreadcrumbItem) -> Void)? = nil
    var blockDocumentLookup: ((UUID) -> BlockDocument?)? = nil
    let paneActions: PaneActions

    var body: some View {
        switch node {
        case .leaf(let leaf):
            PaneContentView(
                leaf: leaf,
                workspaceManager: workspaceManager,
                showFocusBorder: hasMultiplePanes,
                fileTree: fileTree,
                documentContentBuilder: documentContentBuilder,
                terminalContentBuilder: terminalContentBuilder,
                breadcrumbProvider: breadcrumbProvider,
                onBreadcrumbNavigate: onBreadcrumbNavigate,
                blockDocumentLookup: blockDocumentLookup,
                paneActions: paneActions
            )
        case .split(let split):
            splitView(split)
        }
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
                    childTree(split.first)
                    .frame(width: firstSize(total: totalSize, ratio: split.ratio))

                    SplitDividerView(axis: split.axis, ratio: ratioBinding, totalSize: totalSize)

                    childTree(split.second)
                }
            } else {
                VStack(spacing: 0) {
                    childTree(split.first)
                    .frame(height: firstSize(total: totalSize, ratio: split.ratio))

                    SplitDividerView(axis: split.axis, ratio: ratioBinding, totalSize: totalSize)

                    childTree(split.second)
                }
            }
        }
    }

    private func childTree(_ child: PaneNode) -> PaneTreeView {
        PaneTreeView(
            node: child,
            workspaceManager: workspaceManager,
            hasMultiplePanes: hasMultiplePanes,
            fileTree: fileTree,
            documentContentBuilder: documentContentBuilder,
            terminalContentBuilder: terminalContentBuilder,
            breadcrumbProvider: breadcrumbProvider,
            onBreadcrumbNavigate: onBreadcrumbNavigate,
            blockDocumentLookup: blockDocumentLookup,
            paneActions: paneActions
        )
    }

    private func firstSize(total: CGFloat, ratio: Double) -> CGFloat {
        max(total * CGFloat(ratio) - 4, 0)
    }
}
