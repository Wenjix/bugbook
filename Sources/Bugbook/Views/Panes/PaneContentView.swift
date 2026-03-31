import SwiftUI

/// Renders a single pane leaf's content with focus tracking and border.
struct PaneContentView: View {
    let leaf: PaneNode.Leaf
    let isFocused: Bool
    let showFocusBorder: Bool

    /// Builds the document content view for a given leaf and its OpenFile.
    let documentContentBuilder: (PaneNode.Leaf, OpenFile) -> AnyView

    /// Builds the terminal content view for a given leaf.
    let terminalContentBuilder: (PaneNode.Leaf, Bool) -> AnyView

    let onFocus: () -> Void

    var body: some View {
        ZStack {
            contentForLeaf
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            #if os(macOS)
            PaneFocusTracker(paneId: leaf.id) { _ in onFocus() }
            #endif
        }
        .modifier(PaneFocusIndicator(isFocused: isFocused, showBorder: showFocusBorder))
        .clipShape(Rectangle())
    }

    @ViewBuilder
    private var contentForLeaf: some View {
        switch leaf.content {
        case .document(let file):
            documentContentBuilder(leaf, file)
        case .terminal:
            terminalContentBuilder(leaf, isFocused)
        }
    }
}
