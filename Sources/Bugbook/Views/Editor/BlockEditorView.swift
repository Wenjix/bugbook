import SwiftUI
import UniformTypeIdentifiers
import AppKit

/// Supported image file extensions for drag-drop and paste handling.
let supportedImageExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "webp", "heic", "tiff", "bmp"]
let blockEditorCoordinateSpace = "block-editor-coordinate-space"

/// Main block editor — scroll view containing all block cells.
struct BlockEditorView: View {
    private enum ColumnEdge {
        case leading
        case trailing
    }

    private struct LocalColumnDropTarget: Equatable {
        let blockId: UUID
        let edge: ColumnEdge
    }

    var document: BlockDocument
    var onTextChange: (() -> Void)?
    var onTyping: (() -> Void)?
    var contentColumnMaxWidth: CGFloat? = nil
    var horizontalPadding: CGFloat = 48
    @State private var activeDropIndex: Int?
    @State private var columnDropTargetId: UUID?
    @State private var localColumnDropTarget: LocalColumnDropTarget?
    @State private var editorFrameInWindow: CGRect = .zero
    @State private var editorWindow: NSWindow?
    @State private var marqueeSelectionRect: CGRect?
    @State private var marqueeDragState: MarqueeDragState?
    @State private var blockMoveDragState: BlockMoveDragState?
    @State private var autoScrollTimer: Timer?
    @State private var autoScrollSpeed: CGFloat = 0

    var body: some View {
        // Skip the title block (first heading-1) — it's rendered separately above
        let startIndex = document.titleBlock != nil ? 1 : 0

        ZStack(alignment: .topLeading) {
            editorSurface(startIndex: startIndex)

            if let marqueeSelectionRect {
                MarqueeSelectionOverlay(rect: marqueeSelectionRect)
            }

            if let dragState = blockMoveDragState {
                BlockMovePreviewOverlay(
                    blocks: dragPreviewBlocks(for: dragState.draggedIds),
                    location: dragState.currentLocalPoint
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .coordinateSpace(name: blockEditorCoordinateSpace)
        .contentShape(Rectangle())
        .background(
            EditorFrameReporter(frameInWindow: $editorFrameInWindow, window: $editorWindow)
        )
        .simultaneousGesture(marqueeSelectionGesture)
        .editorTextCursor()
        .dropDestination(for: URL.self) { urls, _ in
            handleImageFileDrop(urls)
        } isTargeted: { _ in }
        .onDisappear { stopAutoScroll() }
        .onChange(of: document.contentVersion) { _, _ in
            onTextChange?()
        }
    }

    @ViewBuilder
    private func editorSurface(startIndex: Int) -> some View {
        editorContent(startIndex: startIndex)
    }

    private func editorContent(startIndex: Int) -> some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            // Drop zone before first visible block
            DropZoneView(isActive: activeDropIndex == startIndex) { droppedIds in
                handleDrop(droppedIds: droppedIds, targetIndex: startIndex)
            } onTargetChanged: { targeted in
                activeDropIndex = targeted ? startIndex : (activeDropIndex == startIndex ? nil : activeDropIndex)
            } onImageDrop: { urls in
                handleImageDrop(urls, at: startIndex)
            }

            ForEach(Array(document.blocks.enumerated()).dropFirst(startIndex), id: \.element.id) { index, block in
                let nextBlock = index + 1 < document.blocks.count ? document.blocks[index + 1] : nil
                let useTallDropZone = block.type == .databaseEmbed
                    || block.type == .pageLink
                    || nextBlock?.type == .image
                    || nextBlock?.type == .pageLink
                // After an image block use a slimmer drop zone since ImageBlockView
                // already provides a generous 44pt tap region internally.
                let dropZoneAfterImage = block.type == .image
                let dropZoneHeight: CGFloat = dropZoneAfterImage ? 4 : (useTallDropZone ? 24 : 6)

                BlockCellView(
                    document: document,
                    block: block,
                    isBeingDragged: blockMoveDragState?.draggedIds.contains(block.id) == true,
                    onTyping: onTyping,
                    onHandleDragStart: startBlockMoveDrag,
                    onHandleDragChange: updateBlockMoveDrag,
                    onHandleDragEnd: endBlockMoveDrag
                )
                    .padding(.vertical, 1)
                    .overlay(alignment: .trailing) {
                        // Right-side drop zone for column creation.
                        // Skip for database embeds — the 40px hittable overlay intercepts
                        // clicks on controls (settings, search, etc.) at the right edge.
                        if block.type != .databaseEmbed {
                            ColumnDropZoneView(
                                isActive: columnDropTargetId == block.id,
                                onDrop: { droppedIds in
                                    handleColumnDrop(droppedIds: droppedIds, targetId: block.id)
                                },
                                onTargetChanged: { targeted in
                                    columnDropTargetId = targeted ? block.id : (columnDropTargetId == block.id ? nil : columnDropTargetId)
                                }
                            )
                        }
                    }

                // Drop zone after each block (also clickable to focus nearby block).
                // Taller after database embeds; slimmer after images (which have their own 44pt tap zone).
                DropZoneView(isActive: activeDropIndex == index + 1, height: dropZoneHeight) { droppedIds in
                    handleDrop(droppedIds: droppedIds, targetIndex: index + 1)
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
                        document.clearMultiBlockTextSelection()
                        // After an image block, always focus or insert an empty paragraph
                        if block.type == .image {
                            document.focusOrInsertParagraphAfter(blockId: block.id)
                        } else if index + 1 < document.blocks.count {
                            let next = document.blocks[index + 1]
                            // If next block is non-editable (image, etc.), insert a paragraph between
                            if next.type == .image || next.type == .databaseEmbed {
                                document.focusOrInsertParagraphAfter(blockId: block.id)
                            } else {
                                document.focusedBlockId = next.id
                                document.cursorPosition = 0
                            }
                        } else {
                            document.focusedBlockId = block.id
                            document.cursorPosition = block.text.count
                        }
                    } label: {
                        Color.clear
                    }
                    .buttonStyle(.plain)
                    .editorTextCursor()
                }
            }

            // Click target after last block — always visible, creates new block
            Button {
                if document.consumePendingEditorTapAfterBlockSelection() {
                    return
                }
                document.clearMultiBlockTextSelection()
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
            .editorTextCursor()
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var outerPaddingSelectionSurface: some View {
        Color.clear
            .contentShape(Rectangle())
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onTapGesture {
                clearEditorSelections()
            }
    }

    private func handleDrop(droppedIds: [UUID], targetIndex: Int) {
        document.moveBlocksById(droppedIds, toIndex: targetIndex)
        activeDropIndex = nil
        localColumnDropTarget = nil
    }

    private func handleColumnDrop(droppedIds: [UUID], targetId: UUID) {
        guard droppedIds.count == 1, let droppedId = droppedIds.first else { return }
        document.createColumnFromDrop(droppedId: droppedId, targetId: targetId)
        columnDropTargetId = nil
        localColumnDropTarget = nil
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

    private var marqueeSelectionGesture: some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .local)
            .onChanged(handleMarqueeDragChanged)
            .onEnded { _ in
                endSurfaceSelectionDrag()
            }
    }

    private func handleMarqueeDragChanged(_ value: DragGesture.Value) {
        guard editorFrameInWindow != .zero,
              blockMoveDragState == nil else { return }
        if marqueeDragState == nil {
            document.requestBlockFrameRefresh()
            let sv = editorWindow.flatMap { findScrollView(in: $0.contentView) }
            let initialY = sv?.contentView.bounds.origin.y ?? 0
            marqueeDragState = MarqueeDragState(
                startLocalPoint: value.startLocation,
                canStart: shouldStartMarqueeSelection(at: windowPoint(for: value.startLocation)),
                initialScrollY: initialY,
                scrollView: sv
            )
        }

        guard var dragState = marqueeDragState, dragState.canStart else { return }

        // Adjust start point by scroll delta so selection grows with scrolling
        let currentScrollY = dragState.scrollView?.contentView.bounds.origin.y ?? dragState.initialScrollY
        let scrollDelta = currentScrollY - dragState.initialScrollY
        let adjustedStartY = dragState.startLocalPoint.y - scrollDelta

        let dragRect = CGRect(
            x: min(adjustedStartY < value.location.y ? dragState.startLocalPoint.x : value.location.x,
                   adjustedStartY < value.location.y ? value.location.x : dragState.startLocalPoint.x),
            y: min(adjustedStartY, value.location.y),
            width: abs(value.location.x - dragState.startLocalPoint.x),
            height: abs(value.location.y - adjustedStartY)
        ).standardized

        if !dragState.isActive {
            let dragDistance = max(dragRect.width, dragRect.height)
            guard dragDistance >= 6 else { return }
            dragState.isActive = true
            document.beginMarqueeBlockSelection()
        }

        marqueeDragState = dragState
        marqueeSelectionRect = dragRect

        // Refresh block frames when scroll has changed (blocks have moved)
        if abs(scrollDelta) > 1 {
            document.requestBlockFrameRefresh()
        }

        document.updateMarqueeBlockSelection(
            in: windowRect(for: dragRect),
            within: editorFrameInWindow
        )

        // Auto-scroll near edges
        updateAutoScroll(dragLocalY: value.location.y)
    }

    private func endSurfaceSelectionDrag() {
        stopAutoScroll()
        defer {
            marqueeSelectionRect = nil
            marqueeDragState = nil
        }

        if marqueeDragState?.isActive == true {
            document.endMarqueeBlockSelection()
        }
    }

    private func updateAutoScroll(dragLocalY: CGFloat) {
        guard let sv = marqueeDragState?.scrollView else { return }
        let edgeZone: CGFloat = 40
        let visibleHeight = sv.contentView.bounds.height

        // Convert local Y to scroll view visible area Y
        let scrollViewY = dragLocalY

        if scrollViewY < edgeZone {
            let proximity = max(0, edgeZone - scrollViewY) / edgeZone
            startAutoScroll(speed: -(proximity * 12 + 2))
        } else if scrollViewY > visibleHeight - edgeZone {
            let proximity = max(0, scrollViewY - (visibleHeight - edgeZone)) / edgeZone
            startAutoScroll(speed: proximity * 12 + 2)
        } else {
            stopAutoScroll()
        }
    }

    private func startAutoScroll(speed: CGFloat) {
        autoScrollSpeed = speed
        // If timer is already running, speed update above is sufficient
        guard autoScrollTimer == nil else { return }
        autoScrollTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [self] _ in
            guard let sv = marqueeDragState?.scrollView,
                  let docView = sv.documentView else { return }
            let clipView = sv.contentView
            var origin = clipView.bounds.origin
            origin.y += autoScrollSpeed
            origin.y = max(0, min(origin.y, docView.frame.height - clipView.bounds.height))
            clipView.setBoundsOrigin(origin)
            sv.reflectScrolledClipView(clipView)
        }
    }

    private func stopAutoScroll() {
        autoScrollTimer?.invalidate()
        autoScrollTimer = nil
    }


    private func windowPoint(for localPoint: CGPoint) -> CGPoint {
        CGPoint(
            x: editorFrameInWindow.minX + localPoint.x,
            y: editorFrameInWindow.maxY - localPoint.y
        )
    }

    private func localRect(for windowRect: CGRect) -> CGRect {
        CGRect(
            x: windowRect.minX - editorFrameInWindow.minX,
            y: editorFrameInWindow.maxY - windowRect.maxY,
            width: windowRect.width,
            height: windowRect.height
        )
    }

    private func windowRect(for localRect: CGRect) -> CGRect {
        CGRect(
            x: editorFrameInWindow.minX + localRect.minX,
            y: editorFrameInWindow.maxY - localRect.maxY,
            width: localRect.width,
            height: localRect.height
        ).standardized
    }

    private func shouldStartMarqueeSelection(at windowPoint: CGPoint) -> Bool {
        guard let editorWindow else { return false }

        let nsWindowPoint = NSPoint(x: windowPoint.x, y: windowPoint.y)
        if BlockNSTextView.blockId(atWindowPoint: nsWindowPoint, in: editorWindow) != nil {
            return false
        }

        guard let hitBlockId = document.blockId(atWindowPoint: windowPoint),
              let hitBlock = document.block(for: hitBlockId) else {
            return true
        }

        if let blockFrame = document.registeredBlockFrames[hitBlockId],
           windowPoint.x <= blockFrame.minX + 28 {
            return false
        }

        switch hitBlock.type {
        case .image, .databaseEmbed:
            return false
        default:
            return true
        }
    }

    private func startBlockMoveDrag(blockId: UUID, localPoint: CGPoint) {
        guard blockMoveDragState == nil else { return }
        document.requestBlockFrameRefresh()
        let draggedIds = document.dragSelectionBlockIds(startingWith: blockId)
        clearEditorSelections()
        blockMoveDragState = BlockMoveDragState(
            draggedIds: draggedIds,
            currentLocalPoint: localPoint
        )
        updateBlockMoveDrag(blockId: blockId, localPoint: localPoint)
    }

    private func updateBlockMoveDrag(blockId: UUID, localPoint: CGPoint) {
        guard var dragState = blockMoveDragState else { return }
        dragState.currentLocalPoint = localPoint
        blockMoveDragState = dragState
        if let localColumnDropTarget = localColumnDropTarget(for: localPoint, excluding: Set(dragState.draggedIds)) {
            self.localColumnDropTarget = localColumnDropTarget
            columnDropTargetId = localColumnDropTarget.edge == .trailing ? localColumnDropTarget.blockId : nil
            activeDropIndex = nil
            return
        }
        self.localColumnDropTarget = nil
        columnDropTargetId = nil
        activeDropIndex = blockInsertionIndex(for: localPoint, excluding: Set(dragState.draggedIds))
    }

    private func endBlockMoveDrag(blockId: UUID, localPoint: CGPoint) {
        defer {
            activeDropIndex = nil
            blockMoveDragState = nil
            localColumnDropTarget = nil
            columnDropTargetId = nil
        }

        guard let dragState = blockMoveDragState else {
            return
        }

        if dragState.draggedIds.count == 1,
           let localColumnDropTarget {
            document.createColumnFromDrop(
                droppedId: dragState.draggedIds[0],
                targetId: localColumnDropTarget.blockId,
                onLeadingEdge: localColumnDropTarget.edge == .leading
            )
            return
        }

        guard let targetIndex = blockInsertionIndex(for: localPoint, excluding: Set(dragState.draggedIds)) else {
            return
        }

        document.moveBlocksById(dragState.draggedIds, toIndex: targetIndex)
    }

    private func dragPreviewBlocks(for draggedIds: [UUID]) -> [Block] {
        draggedIds.compactMap { document.block(for: $0) }
    }

    private func clearEditorSelections() {
        document.clearBlockSelection()
        document.clearMultiBlockTextSelection()
        document.selectionRect = nil
        document.selectionBlockId = nil
        document.focusedBlockId = nil
    }

    private func localColumnDropTarget(for localPoint: CGPoint, excluding excludedIds: Set<UUID>) -> LocalColumnDropTarget? {
        guard let draggedId = blockMoveDragState?.draggedIds.first,
              blockMoveDragState?.draggedIds.count == 1 else {
            return nil
        }

        let startIndex = document.titleBlock != nil ? 1 : 0
        let visibleBlocks = Array(document.blocks.enumerated().dropFirst(startIndex))
            .map(\.element)
            .filter { !excludedIds.contains($0.id) && $0.type != .databaseEmbed }

        for block in visibleBlocks {
            guard let frame = document.registeredBlockFrames[block.id] else { continue }
            let localFrame = localRect(for: frame)
            guard localFrame.insetBy(dx: 0, dy: -8).contains(localPoint) else { continue }

            let edgeWidth = min(44.0, max(24.0, localFrame.width * 0.12))
            if localPoint.x <= localFrame.minX + edgeWidth {
                if block.id != draggedId {
                    return LocalColumnDropTarget(blockId: block.id, edge: .leading)
                }
                return nil
            }
            if localPoint.x >= localFrame.maxX - edgeWidth {
                if block.id != draggedId {
                    return LocalColumnDropTarget(blockId: block.id, edge: .trailing)
                }
                return nil
            }
        }

        return nil
    }

    private func blockInsertionIndex(for localPoint: CGPoint, excluding excludedIds: Set<UUID>) -> Int? {
        let startIndex = document.titleBlock != nil ? 1 : 0
        let visibleBlocks = Array(document.blocks.enumerated().dropFirst(startIndex))
            .filter { !excludedIds.contains($0.element.id) }

        guard !visibleBlocks.isEmpty else { return document.blocks.count }

        for (index, block) in visibleBlocks {
            guard let frame = document.registeredBlockFrames[block.id] else { continue }
            let localFrame = localRect(for: frame)
            if localPoint.y < localFrame.midY {
                return index
            }
        }

        if let lastIndex = visibleBlocks.last?.0 {
            return lastIndex + 1
        }
        return document.blocks.count
    }

}

private struct MarqueeDragState {
    let startLocalPoint: CGPoint
    let canStart: Bool
    var isActive = false
    var initialScrollY: CGFloat = 0
    var scrollView: NSScrollView?
}

private func findScrollView(in view: NSView?) -> NSScrollView? {
    guard let view else { return nil }
    if let sv = view as? NSScrollView { return sv }
    for sub in view.subviews {
        if let found = findScrollView(in: sub) { return found }
    }
    return nil
}

private struct BlockMoveDragState {
    let draggedIds: [UUID]
    var currentLocalPoint: CGPoint
}

private struct MarqueeSelectionOverlay: View {
    let rect: CGRect

    var body: some View {
        Rectangle()
            .fill(Color.accentColor.opacity(0.14))
            .overlay {
                Rectangle()
                    .stroke(Color.accentColor.opacity(0.9), lineWidth: 1)
            }
            .frame(width: max(rect.width, 1), height: max(rect.height, 1))
            .offset(x: rect.minX, y: rect.minY)
            .allowsHitTesting(false)
    }
}

private struct BlockMovePreviewOverlay: View {
    let blocks: [Block]
    let location: CGPoint

    private var previewBlocks: [Block] {
        Array(blocks.prefix(8))
    }

    var body: some View {
        if !previewBlocks.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(previewBlocks) { block in
                    BlockMovePreviewRow(block: block)
                }

                if blocks.count > previewBlocks.count {
                    Text("+\(blocks.count - previewBlocks.count) more")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 2)
            .padding(.vertical, 2)
            .frame(width: min(520, max(260, previewWidthEstimate)), alignment: .leading)
            .shadow(color: .black.opacity(0.08), radius: 10, y: 6)
            .opacity(0.58)
            .offset(x: location.x + 18, y: location.y + 14)
            .allowsHitTesting(false)
        }
    }

    private var previewWidthEstimate: CGFloat {
        let longest = previewBlocks
            .map(\.previewDragText)
            .map { min($0.count, 48) }
            .max() ?? 24
        return CGFloat(longest) * 8.2
    }
}

private struct BlockMovePreviewRow: View {
    let block: Block

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            previewMarker
                .frame(width: 14, alignment: .center)

            Text(block.previewDragText)
                .font(.system(size: 14))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 1)
    }

    @ViewBuilder
    private var previewMarker: some View {
        switch block.type {
        case .bulletListItem:
            Circle()
                .fill(Color.secondary)
                .frame(width: 5, height: 5)
        case .numberedListItem:
            Text("1.")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
        case .taskItem:
            Image(systemName: block.isChecked ? "checkmark.square.fill" : "square")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
        default:
            Image(systemName: block.previewDragIcon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
        }
    }
}

private extension Block {
    var previewDragText: String {
        switch type {
        case .pageLink:
            return pageLinkName.isEmpty ? "Page link" : pageLinkName
        case .image:
            return "Image"
        case .databaseEmbed:
            return "Database"
        case .horizontalRule:
            return "Divider"
        case .column:
            return "Column"
        default:
            let plainText = AttributedStringConverter.plainText(from: text).trimmingCharacters(in: .whitespacesAndNewlines)
            return plainText.isEmpty ? "Empty block" : plainText
        }
    }

    var previewDragIcon: String {
        switch type {
        case .bulletListItem, .numberedListItem:
            return "circle.fill"
        case .taskItem:
            return isChecked ? "checkmark.square.fill" : "square"
        case .heading:
            return "textformat.size"
        case .blockquote:
            return "quote.opening"
        case .codeBlock:
            return "chevron.left.forwardslash.chevron.right"
        case .pageLink:
            return "doc.text"
        case .image:
            return "photo"
        case .databaseEmbed:
            return "tablecells"
        case .toggle:
            return "chevron.right"
        case .horizontalRule:
            return "minus"
        case .column:
            return "rectangle.split.2x1"
        default:
            return "line.3.horizontal"
        }
    }
}

private struct EditorFrameReporter: NSViewRepresentable {
    @Binding var frameInWindow: CGRect
    @Binding var window: NSWindow?

    func makeNSView(context: Context) -> EditorFrameReporterView {
        let view = EditorFrameReporterView()
        view.onFrameChange = { frame, window in
            self.frameInWindow = frame
            self.window = window
        }
        return view
    }

    func updateNSView(_ nsView: EditorFrameReporterView, context: Context) {
        nsView.onFrameChange = { frame, window in
            self.frameInWindow = frame
            self.window = window
        }
    }
}

final class EditorFrameReporterView: NSView {
    var onFrameChange: ((CGRect, NSWindow?) -> Void)?
    private weak var observedClipView: NSClipView?
    private var clipViewObserver: NSObjectProtocol?
    private var frameReportScheduled = false

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateClipViewObservation()
        reportFrame()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        scheduleFrameReport()
    }

    override func setFrameOrigin(_ newOrigin: NSPoint) {
        super.setFrameOrigin(newOrigin)
        scheduleFrameReport()
    }

    private func updateClipViewObservation() {
        let clipView = enclosingScrollView?.contentView
        guard clipView !== observedClipView else { return }

        if let clipViewObserver {
            NotificationCenter.default.removeObserver(clipViewObserver)
            self.clipViewObserver = nil
        }

        observedClipView = clipView
        clipView?.postsBoundsChangedNotifications = true

        if let clipView {
            clipViewObserver = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: clipView,
                queue: .main
            ) { [weak self] _ in
                self?.scheduleFrameReport()
            }
        }
    }

    private func scheduleFrameReport() {
        guard !frameReportScheduled else { return }
        frameReportScheduled = true
        DispatchQueue.main.async { [weak self] in
            self?.frameReportScheduled = false
            self?.reportFrame()
        }
    }

    private func reportFrame() {
        guard window != nil else { return }
        onFrameChange?(convert(bounds, to: nil), window)
    }
}

/// Thin drop zone between blocks that shows a blue line when a drag hovers over it.
/// Height is constant to prevent layout shifts that cause flickering.
/// Accepts both block UUID drops (reorder) and image URL drops (insert image).
struct DropZoneView: View {
    let isActive: Bool
    var height: CGFloat = 4
    let onDrop: ([UUID]) -> Void
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
                guard let payload = items.first else { return false }
                let droppedIds = BlockDocument.draggedBlockIds(from: payload)
                guard !droppedIds.isEmpty else { return false }
                onDrop(droppedIds)
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
            .editorTextCursor()
    }
}

/// Right-edge drop zone that shows a vertical blue line for column creation.
struct ColumnDropZoneView: View {
    let isActive: Bool
    let onDrop: ([UUID]) -> Void
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
                guard let payload = items.first else { return false }
                let droppedIds = BlockDocument.draggedBlockIds(from: payload)
                guard droppedIds.count == 1 else { return false }
                onDrop(droppedIds)
                return true
            } isTargeted: { targeted in
                onTargetChanged(targeted)
            }
    }
}
