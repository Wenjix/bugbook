import SwiftUI
import UniformTypeIdentifiers

/// Supported image file extensions for drag-drop and paste handling.
let supportedImageExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "webp", "heic", "tiff", "bmp"]

/// Main block editor — scroll view containing all block cells.
struct BlockEditorView: View {
    var document: BlockDocument
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
            } onImageDrop: { urls in
                handleImageDrop(urls, at: startIndex)
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
                } onImageDrop: { urls in
                    handleImageDrop(urls, at: index + 1)
                }
                .overlay {
                    Button {
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
                    } label: {
                        Color.clear
                    }
                    .buttonStyle(.plain)
                }
            }

            // Click target after last block — always visible, creates new block
            Button {
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
            } label: {
                Rectangle()
                    .fill(Color.white.opacity(0.001))
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 300)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 48)
        .padding(.vertical, 20)
        .dropDestination(for: URL.self) { urls, _ in
            handleImageFileDrop(urls)
        } isTargeted: { _ in }
        .onChange(of: document.contentVersion) { _, _ in
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

    private func handleImageDrop(_ urls: [URL], at index: Int) -> Bool {
        let imageURLs = urls.filter { supportedImageExtensions.contains($0.pathExtension.lowercased()) }
        guard !imageURLs.isEmpty else { return false }
        for (offset, url) in imageURLs.enumerated() {
            if let path = document.copyImageToAssets(url) {
                document.insertImageBlock(at: index + offset, imagePath: path)
            }
        }
        return true
    }

    /// Fallback for drops that land on blocks (not between them).
    private func handleImageFileDrop(_ urls: [URL]) -> Bool {
        var insertIndex = document.blocks.count
        if let focusedId = document.focusedBlockId,
           let idx = document.blocks.firstIndex(where: { $0.id == focusedId }) {
            insertIndex = idx + 1
        }
        return handleImageDrop(urls, at: insertIndex)
    }
}

/// Thin drop zone between blocks that shows a blue line when a drag hovers over it.
/// Height is constant to prevent layout shifts that cause flickering.
/// Accepts both block UUID drops (reorder) and image URL drops (insert image).
struct DropZoneView: View {
    let isActive: Bool
    var height: CGFloat = 4
    let onDrop: (UUID) -> Void
    let onTargetChanged: (Bool) -> Void
    var onImageDrop: (([URL]) -> Bool)?

    @State private var imageDropTargeted = false

    var body: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(height: height)
            .frame(maxWidth: .infinity)
            .overlay {
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(height: 2)
                    .opacity(isActive || imageDropTargeted ? 1 : 0)
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
            .overlay {
                if onImageDrop != nil {
                    Color.clear
                        .frame(maxWidth: .infinity)
                        .frame(height: 24)
                        .dropDestination(for: URL.self) { urls, _ in
                            onImageDrop?(urls) ?? false
                        } isTargeted: { targeted in
                            imageDropTargeted = targeted
                        }
                }
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
