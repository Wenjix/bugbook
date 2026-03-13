import SwiftUI
import AppKit

/// Per-block wrapper with drag handle on hover.
struct BlockCellView: View {
    var document: BlockDocument
    let block: Block
    var isBeingDragged: Bool = false
    var onTyping: (() -> Void)? = nil
    var onHandleDragStart: ((UUID, CGPoint) -> Void)? = nil
    var onHandleDragChange: ((UUID, CGPoint) -> Void)? = nil
    var onHandleDragEnd: ((UUID, CGPoint) -> Void)? = nil
    @State private var isRowHovering = false
    @State private var isHandleHovering = false
    @State private var isHandleDragging = false
    @State private var showSlashMenu = false
    @State private var showBlockMenu = false
    @State private var showPagePicker = false

    var body: some View {
        // Database embed blocks need their own interactive controls to work, so we
        // skip the block-level tap gesture entirely for them.
        blockBase
            .modifier(PopoverSyncModifier(
                document: document,
                block: block,
                showSlashMenu: $showSlashMenu,
                showBlockMenu: $showBlockMenu,
                showPagePicker: $showPagePicker
            ))
    }

    private var blockBase: some View {
        blockShell
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.accentColor.opacity(
                    isBlockHighlighted ? 0.15 : 0
                ))
                .allowsHitTesting(false)
        )
    }

    private var blockShell: some View {
        HStack(alignment: .top, spacing: 4) {
            // Drag handle — click to open block menu
            handleView

            interactiveBlockContent
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, block.type == .horizontalRule ? 1 : 2)
        .background(
            block.backgroundColor != .default
                ? block.backgroundColor.backgroundColor
                : Color.clear
        )
        .opacity(isBeingDragged ? 0.22 : 1)
        .background(BlockFrameReporter(document: document, blockId: block.id))
        .clipShape(.rect(cornerRadius: block.backgroundColor != .default ? 4 : 0))
        .onHover { inside in
            isRowHovering = inside
        }
    }

    private var blockUsesOwnInteractions: Bool {
        switch block.type {
        case .databaseEmbed, .image:
            true
        default:
            false
        }
    }

    private var handleIsVisible: Bool {
        isRowHovering
            || isHandleHovering
            || isHandleDragging
            || document.blockMenuBlockId == block.id
    }

    private var isBlockHighlighted: Bool {
        document.selectedBlockIds.contains(block.id)
    }

    private var blockInteractionCursor: NSCursor {
        switch block.type {
        case .paragraph, .heading, .bulletListItem, .numberedListItem, .taskItem, .blockquote, .codeBlock, .toggle:
            return .iBeam
        default:
            return .arrow
        }
    }

    @ViewBuilder
    private var handleView: some View {
        let baseHandle = GripDotsView()
            .frame(width: 20, height: 24)
            .opacity(handleIsVisible ? 1 : 0)
            .contentShape(Rectangle())
            .onHover { inside in
                isHandleHovering = inside
            }
            .appCursor(isHandleDragging ? .closedHand : .openHand)
            .highPriorityGesture(
                TapGesture().onEnded {
                    guard !isHandleDragging else { return }
                    if document.blockMenuBlockId == block.id {
                        document.dismissBlockMenu()
                    } else {
                        document.blockMenuBlockId = block.id
                    }
                }
            )

        if let onHandleDragStart, let onHandleDragChange, let onHandleDragEnd {
            baseHandle.gesture(
                DragGesture(minimumDistance: 2, coordinateSpace: .named(blockEditorCoordinateSpace))
                    .onChanged { value in
                        if !isHandleDragging {
                            isHandleDragging = true
                            onHandleDragStart(block.id, value.startLocation)
                        }
                        onHandleDragChange(block.id, value.location)
                    }
                    .onEnded { value in
                        onHandleDragEnd(block.id, value.location)
                        isHandleDragging = false
                    }
            )
        } else {
            baseHandle.draggable(document.dragPayload(for: block.id))
        }
    }

    private func findPageIcon(named name: String) -> String? {
        func search(in entries: [FileEntry]) -> String? {
            for entry in entries {
                let entryName = entry.name.replacingOccurrences(of: ".md", with: "")
                if entryName.localizedCaseInsensitiveCompare(name) == .orderedSame {
                    return entry.icon
                }
                if let children = entry.children, let found = search(in: children) {
                    return found
                }
            }
            return nil
        }
        return search(in: document.availablePages)
    }

    @ViewBuilder
    private var interactiveBlockContent: some View {
        if blockUsesOwnInteractions {
            blockContent
        } else {
            blockContent
                .contentShape(Rectangle())
                .overlay {
                    blockInteractionOverlay
                }
        }
    }

    @ViewBuilder
    private var blockInteractionOverlay: some View {
        Button(action: handleBlockTap) {
            Color.clear
        }
        .buttonStyle(.plain)
        .appCursor(blockInteractionCursor)
    }

    private func handleBlockTap() {
        if document.consumePendingEditorTapAfterBlockSelection() {
            return
        }
        if NSEvent.modifierFlags.contains(.shift),
           let anchor = document.focusedBlockId {
            document.selectBlockRange(from: anchor, to: block.id)
        } else {
            document.clearBlockSelection()
            document.clearMultiBlockTextSelection()
            document.focusedBlockId = block.id
        }
    }

    @ViewBuilder
    private var blockContent: some View {
        switch block.type {
        case .paragraph, .heading, .bulletListItem, .numberedListItem, .taskItem, .blockquote:
            TextBlockView(document: document, block: block, onTyping: onTyping)

        case .codeBlock:
            CodeBlockView(document: document, block: block, onTyping: onTyping)

        case .horizontalRule:
            HorizontalRuleView()

        case .image:
            ImageBlockView(document: document, block: block)

        case .databaseEmbed:
            DatabaseEmbedBlockView(block: block, onOpenDatabaseTab: document.onOpenDatabaseTab)

        case .pageLink:
            WikiLinkView(
                pageName: block.pageLinkName,
                icon: findPageIcon(named: block.pageLinkName),
                onNavigate: { document.onNavigateToPage?(block.pageLinkName) }
            )

        case .toggle:
            ToggleBlockView(document: document, block: block, onTyping: onTyping)

        case .column:
            ColumnBlockView(document: document, block: block, onTyping: onTyping)
        }
    }
}

private struct PopoverSyncModifier: ViewModifier {
    var document: BlockDocument
    let block: Block
    @Binding var showSlashMenu: Bool
    @Binding var showBlockMenu: Bool
    @Binding var showPagePicker: Bool

    func body(content: Content) -> some View {
        content
            .floatingPopover(isPresented: $showSlashMenu, arrowEdge: .bottom) {
                SlashCommandMenu(document: document)
            }
            .floatingPopover(isPresented: $showBlockMenu, arrowEdge: .leading, onDelete: {
                document.dismissBlockMenu()
                document.deleteBlock(id: block.id)
            }) {
                BlockMenuView(document: document, blockId: block.id)
            }
            .floatingPopover(isPresented: $showPagePicker, arrowEdge: .bottom) {
                PagePickerView(document: document)
            }
            .onAppear {
                showSlashMenu = (document.slashMenuBlockId == block.id)
                showBlockMenu = (document.blockMenuBlockId == block.id)
                showPagePicker = document.showPagePicker && document.pagePickerBlockId == block.id
            }
            .onChange(of: document.slashMenuBlockId) { _, newVal in
                let shouldShow = (newVal == block.id)
                if showSlashMenu != shouldShow { showSlashMenu = shouldShow }
            }
            .onChange(of: showSlashMenu) { _, show in
                if !show && document.slashMenuBlockId == block.id {
                    document.dismissSlashMenu()
                }
            }
            .onChange(of: document.blockMenuBlockId) { _, newVal in
                let shouldShow = (newVal == block.id)
                if showBlockMenu != shouldShow { showBlockMenu = shouldShow }
            }
            .onChange(of: showBlockMenu) { _, show in
                if !show && document.blockMenuBlockId == block.id {
                    document.dismissBlockMenu()
                }
            }
            .onChange(of: document.showPagePicker) { _, _ in
                let shouldShow = document.showPagePicker && document.pagePickerBlockId == block.id
                if showPagePicker != shouldShow { showPagePicker = shouldShow }
            }
            .onChange(of: document.pagePickerBlockId) { _, _ in
                let shouldShow = document.showPagePicker && document.pagePickerBlockId == block.id
                if showPagePicker != shouldShow { showPagePicker = shouldShow }
            }
            .onChange(of: showPagePicker) { _, show in
                if !show && document.showPagePicker && document.pagePickerBlockId == block.id {
                    document.dismissPagePicker()
                }
            }
    }
}

private struct BlockFrameReporter: NSViewRepresentable {
    var document: BlockDocument
    let blockId: UUID

    func makeNSView(context: Context) -> BlockFrameReporterView {
        let view = BlockFrameReporterView()
        view.syncRegistration(document: document, blockId: blockId)
        return view
    }

    func updateNSView(_ nsView: BlockFrameReporterView, context: Context) {
        if nsView.document !== document || nsView.blockId != blockId {
            nsView.syncRegistration(document: document, blockId: blockId)
        }
    }
}

final class BlockFrameReporterView: NSView {
    weak var document: BlockDocument?
    var blockId: UUID?
    private weak var observedClipView: NSClipView?
    private var clipViewObserver: NSObjectProtocol?
    private var frameReportScheduled = false

    func syncRegistration(document: BlockDocument, blockId: UUID) {
        if let currentDocument = self.document,
           let currentBlockId = self.blockId,
           (currentDocument !== document || currentBlockId != blockId) {
            Task { @MainActor [weak currentDocument] in
                currentDocument?.unregisterBlockFrame(for: currentBlockId)
            }
        }

        self.document = document
        self.blockId = blockId
        updateClipViewObservation()
        reportFrame()
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil, let document, let blockId {
            Task { @MainActor [weak document] in
                document?.unregisterBlockFrame(for: blockId)
            }
        }
        super.viewWillMove(toWindow: newWindow)
    }

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

    func reportFrame() {
        guard let document, let blockId, window != nil else { return }
        let frameInWindow = convert(bounds, to: nil)
        document.registerBlockFrame(frameInWindow, for: blockId)
    }

    deinit {
        if let clipViewObserver {
            NotificationCenter.default.removeObserver(clipViewObserver)
        }
    }
}
