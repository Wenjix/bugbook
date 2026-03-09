import SwiftUI
import AppKit

/// Per-block wrapper with drag handle on hover.
struct BlockCellView: View {
    @ObservedObject var document: BlockDocument
    let block: Block
    var onTyping: (() -> Void)? = nil
    @State private var isHandleHovering = false

    var body: some View {
        // Database embed blocks need their own interactive controls to work, so we
        // skip the block-level tap gesture entirely for them.
        Group {
            if block.type == .databaseEmbed {
                blockShell
            } else {
                blockShell
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if document.consumePendingEditorTapAfterBlockSelection() {
                            return
                        }
                        if NSEvent.modifierFlags.contains(.shift),
                           let anchor = document.focusedBlockId {
                            document.selectBlockRange(from: anchor, to: block.id)
                        } else {
                            document.clearBlockSelection()
                            document.focusedBlockId = block.id
                        }
                    }
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.accentColor.opacity(
                    document.selectedBlockIds.contains(block.id) ? 0.15 : 0
                ))
                .allowsHitTesting(false)
        )
        .popover(
            isPresented: Binding(
                get: { document.slashMenuBlockId == block.id },
                set: { if !$0 { document.dismissSlashMenu() } }
            ),
            arrowEdge: .bottom
        ) {
            SlashCommandMenu(document: document)
        }
        .popover(
            isPresented: Binding(
                get: { document.blockMenuBlockId == block.id },
                set: { if !$0 { document.dismissBlockMenu() } }
            ),
            arrowEdge: .leading
        ) {
            BlockMenuView(document: document, blockId: block.id)
        }
        .popover(
            isPresented: Binding(
                get: { document.showPagePicker && document.pagePickerBlockId == block.id },
                set: { if !$0 { document.dismissPagePicker() } }
            ),
            arrowEdge: .bottom
        ) {
            PagePickerView(document: document)
        }
    }

    private var blockShell: some View {
        HStack(alignment: .top, spacing: 4) {
            // Drag handle — click to open block menu
            GripDotsView()
                .frame(width: 20, height: 24)
                .opacity(handleIsVisible ? 1 : 0)
                .contentShape(Rectangle())
                .onHover { inside in
                    isHandleHovering = inside
                    EditorCursorState.setOverride(inside ? .openHand : nil)
                }
                .highPriorityGesture(
                    TapGesture().onEnded {
                        document.blockMenuBlockId = block.id
                    }
                )
                .draggable(block.id.uuidString)

            blockContent
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, block.type == .horizontalRule ? 1 : 2)
        .background(
            block.backgroundColor != .default
                ? block.backgroundColor.backgroundColor
                : Color.clear
        )
        .background(BlockFrameReporter(document: document, blockId: block.id))
        .cornerRadius(block.backgroundColor != .default ? 4 : 0)
    }

    private var handleIsVisible: Bool {
        isHandleHovering
            || document.blockMenuBlockId == block.id
            || document.selectedBlockIds.contains(block.id)
            || document.focusedBlockId == block.id
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
    private var blockContent: some View {
        switch block.type {
        case .paragraph, .heading, .bulletListItem, .numberedListItem, .taskItem, .blockquote:
            TextBlockView(document: document, block: block, onTyping: onTyping)

        case .codeBlock:
            CodeBlockView(document: document, block: block, onTyping: onTyping)

        case .horizontalRule:
            HorizontalRuleView()

        case .image:
            ImageBlockView(block: block)

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

private struct BlockFrameReporter: NSViewRepresentable {
    @ObservedObject var document: BlockDocument
    let blockId: UUID

    func makeNSView(context: Context) -> BlockFrameReporterView {
        let view = BlockFrameReporterView()
        view.syncRegistration(document: document, blockId: blockId)
        return view
    }

    func updateNSView(_ nsView: BlockFrameReporterView, context: Context) {
        nsView.syncRegistration(document: document, blockId: blockId)
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
