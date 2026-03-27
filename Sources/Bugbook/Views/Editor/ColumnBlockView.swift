import SwiftUI

/// Renders a column block as a side-by-side horizontal layout with multiple blocks per column.
struct ColumnBlockView: View {
    var document: BlockDocument
    let block: Block
    var onTyping: (() -> Void)? = nil
    @State private var activeDropTarget: ColumnDropTarget?

    struct ColumnDropTarget: Equatable {
        let columnIndex: Int
        let position: Int
    }

    var body: some View {
        let groups = columnGroups()

        HStack(alignment: .top, spacing: 16) {
            ForEach(Array(groups.enumerated()), id: \.offset) { _, group in
                VStack(alignment: .leading, spacing: 0) {
                    // Drop zone at top of column
                    InColumnDropZone(
                        isActive: activeDropTarget == ColumnDropTarget(columnIndex: group.columnIndex, position: 0),
                        onDrop: { droppedId in
                            document.addBlockToColumn(blockId: droppedId, columnBlockId: block.id, columnIndex: group.columnIndex, position: 0)
                            activeDropTarget = nil
                        },
                        onTargetChanged: { targeted in
                            let target = ColumnDropTarget(columnIndex: group.columnIndex, position: 0)
                            activeDropTarget = targeted ? target : (activeDropTarget == target ? nil : activeDropTarget)
                        }
                    )

                    ForEach(Array(group.blocks.enumerated()), id: \.element.id) { blockIdx, child in
                        let prevType = blockIdx > 0 ? group.blocks[blockIdx - 1].type : nil
                        let nextType = blockIdx + 1 < group.blocks.count ? group.blocks[blockIdx + 1].type : nil
                        BlockCellView(document: document, block: child, previousBlockType: prevType, nextBlockType: nextType, onTyping: onTyping)
                            .padding(.vertical, 1)

                        // Drop zone after each block
                        InColumnDropZone(
                            isActive: activeDropTarget == ColumnDropTarget(columnIndex: group.columnIndex, position: blockIdx + 1),
                            onDrop: { droppedId in
                                document.addBlockToColumn(blockId: droppedId, columnBlockId: block.id, columnIndex: group.columnIndex, position: blockIdx + 1)
                                activeDropTarget = nil
                            },
                            onTargetChanged: { targeted in
                                let target = ColumnDropTarget(columnIndex: group.columnIndex, position: blockIdx + 1)
                                activeDropTarget = targeted ? target : (activeDropTarget == target ? nil : activeDropTarget)
                            }
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.vertical, 4)
    }

    /// Groups children by columnIndex, preserving order within each column.
    private func columnGroups() -> [(columnIndex: Int, blocks: [Block])] {
        var dict: [Int: [Block]] = [:]
        for child in block.children {
            dict[child.columnIndex, default: []].append(child)
        }
        return dict.sorted(by: { $0.key < $1.key })
            .map { (columnIndex: $0.key, blocks: $0.value) }
    }
}

/// Thin drop zone within a column that shows a horizontal line.
struct InColumnDropZone: View {
    let isActive: Bool
    let onDrop: (UUID) -> Void
    let onTargetChanged: (Bool) -> Void

    var body: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(height: 12)
            .frame(maxWidth: .infinity)
            .overlay {
                Rectangle()
                    .fill(Color.dragIndicator)
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
