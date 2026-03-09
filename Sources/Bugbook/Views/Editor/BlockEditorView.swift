import SwiftUI

/// Main block editor — scroll view containing all block cells.
struct BlockEditorView: View {
    @ObservedObject var document: BlockDocument
    var onTextChange: (() -> Void)?
    var onTyping: (() -> Void)?
    @State private var activeDropIndex: Int?
    @State private var columnDropTargetId: UUID?

    var body: some View {
        // Skip the title block (first heading-1) — it's rendered separately above
        let startIndex = document.titleBlock != nil ? 1 : 0

        LazyVStack(alignment: .leading, spacing: 0) {
            // Drop zone before first visible block
            DropZoneView(isActive: activeDropIndex == startIndex) { droppedId in
                handleDrop(droppedId: droppedId, targetIndex: startIndex)
            } onTargetChanged: { targeted in
                activeDropIndex = targeted ? startIndex : (activeDropIndex == startIndex ? nil : activeDropIndex)
            }

            ForEach(Array(document.blocks.enumerated()).dropFirst(startIndex), id: \.element.id) { index, block in
                BlockCellView(document: document, block: block, onTyping: onTyping)
                    .padding(.vertical, 1)
                    .overlay(alignment: .trailing) {
                        // Right-side drop zone for column creation.
                        // Skip for database embeds — the 40px hittable overlay intercepts
                        // clicks on controls (settings, search, etc.) at the right edge.
                        if block.type != .databaseEmbed {
                            ColumnDropZoneView(
                                isActive: columnDropTargetId == block.id,
                                onDrop: { droppedId in
                                    handleColumnDrop(droppedId: droppedId, targetId: block.id)
                                },
                                onTargetChanged: { targeted in
                                    columnDropTargetId = targeted ? block.id : (columnDropTargetId == block.id ? nil : columnDropTargetId)
                                }
                            )
                        }
                    }

                // Drop zone after each block (also clickable to focus nearby block)
                // Use a taller drop zone after database embeds so users can easily click below them.
                DropZoneView(isActive: activeDropIndex == index + 1, height: block.type == .databaseEmbed ? 12 : 4) { droppedId in
                    handleDrop(droppedId: droppedId, targetIndex: index + 1)
                } onTargetChanged: { targeted in
                    let idx = index + 1
                    activeDropIndex = targeted ? idx : (activeDropIndex == idx ? nil : activeDropIndex)
                }
                .onTapGesture {
                    if document.consumePendingEditorTapAfterBlockSelection() {
                        return
                    }
                    // Click between blocks: focus the block below if it exists, otherwise the one above
                    if index + 1 < document.blocks.count {
                        let next = document.blocks[index + 1]
                        document.focusedBlockId = next.id
                        document.cursorPosition = 0
                    } else {
                        document.focusedBlockId = block.id
                        document.cursorPosition = block.text.count
                    }
                }
            }

            // Click target after last block — always visible, creates new block
            Rectangle()
                .fill(Color.white.opacity(0.001))
                .frame(maxWidth: .infinity)
                .frame(minHeight: 300)
                .contentShape(Rectangle())
                .onTapGesture {
                    if document.consumePendingEditorTapAfterBlockSelection() {
                        return
                    }
                    if let lastBlock = document.blocks.last,
                       lastBlock.text.isEmpty,
                       lastBlock.type != .databaseEmbed {
                        document.focusedBlockId = lastBlock.id
                        document.cursorPosition = 0
                    } else {
                        document.appendEmptyBlock()
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
        document.moveBlockById(droppedId, toIndex: targetIndex)
        activeDropIndex = nil
    }

    private func handleColumnDrop(droppedId: UUID, targetId: UUID) {
        document.createColumnFromDrop(droppedId: droppedId, targetId: targetId)
        columnDropTargetId = nil
    }
}

/// Thin drop zone between blocks that shows a blue line when a drag hovers over it.
/// Height is constant to prevent layout shifts that cause flickering.
struct DropZoneView: View {
    let isActive: Bool
    var height: CGFloat = 4
    let onDrop: (UUID) -> Void
    let onTargetChanged: (Bool) -> Void

    var body: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(height: height)
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

/// Right-edge drop zone that shows a vertical blue line for column creation.
struct ColumnDropZoneView: View {
    let isActive: Bool
    let onDrop: (UUID) -> Void
    let onTargetChanged: (Bool) -> Void

    var body: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(width: 40)
            .frame(maxHeight: .infinity)
            .overlay(alignment: .trailing) {
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(width: 2)
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
