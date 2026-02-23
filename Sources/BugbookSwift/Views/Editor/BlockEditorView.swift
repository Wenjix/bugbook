import SwiftUI

/// Main block editor — scroll view containing all block cells.
struct BlockEditorView: View {
    @ObservedObject var document: BlockDocument
    var onTextChange: (() -> Void)?
    @State private var activeDropIndex: Int?

    var body: some View {
        // Skip the title block (first heading-1) — it's rendered separately above
        let startIndex = document.titleBlock != nil ? 1 : 0

        VStack(alignment: .leading, spacing: 0) {
            // Drop zone before first visible block
            DropZoneView(isActive: activeDropIndex == startIndex) { droppedId in
                handleDrop(droppedId: droppedId, targetIndex: startIndex)
            } onTargetChanged: { targeted in
                activeDropIndex = targeted ? startIndex : (activeDropIndex == startIndex ? nil : activeDropIndex)
            }

            ForEach(Array(document.blocks.enumerated()).dropFirst(startIndex), id: \.element.id) { index, block in
                BlockCellView(document: document, block: block)
                    .padding(.vertical, 1)

                // Drop zone after each block
                DropZoneView(isActive: activeDropIndex == index + 1) { droppedId in
                    handleDrop(droppedId: droppedId, targetIndex: index + 1)
                } onTargetChanged: { targeted in
                    let idx = index + 1
                    activeDropIndex = targeted ? idx : (activeDropIndex == idx ? nil : activeDropIndex)
                }
            }
        }
        .padding(.horizontal, 48)
        .padding(.vertical, 20)
        .onChange(of: document.blocks) { _, _ in
            onTextChange?()
        }
    }

    private func handleDrop(droppedId: UUID, targetIndex: Int) {
        guard let fromIndex = document.index(for: droppedId) else { return }
        document.moveBlock(from: fromIndex, to: targetIndex)
        activeDropIndex = nil
    }
}

/// Thin drop zone between blocks that shows a blue line when a drag hovers over it.
/// Height is constant to prevent layout shifts that cause flickering.
struct DropZoneView: View {
    let isActive: Bool
    let onDrop: (UUID) -> Void
    let onTargetChanged: (Bool) -> Void

    var body: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(height: 8)
            .frame(maxWidth: .infinity)
            .overlay {
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(height: 2)
                    .opacity(isActive ? 1 : 0)
            }
            .contentShape(Rectangle())
            .dropDestination(for: String.self) { items, _ in
                guard let idStr = items.first,
                      let droppedId = UUID(uuidString: idStr) else { return false }
                onDrop(droppedId)
                return true
            } isTargeted: { targeted in
                onTargetChanged(targeted)
            }
    }
}
