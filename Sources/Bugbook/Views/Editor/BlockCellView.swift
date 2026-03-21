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
    @State private var showAiPrompt = false

    var body: some View {
        // Database embed blocks need their own interactive controls to work, so we
        // skip the block-level tap gesture entirely for them.
        blockBase
            .modifier(PopoverSyncModifier(
                document: document,
                block: block,
                showSlashMenu: $showSlashMenu,
                showBlockMenu: $showBlockMenu,
                showPagePicker: $showPagePicker,
                showAiPrompt: $showAiPrompt
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
                .frame(maxWidth: .infinity, minHeight: isEmptyParagraph ? 28 : 0, alignment: .leading)
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

    private var isEmptyParagraph: Bool {
        block.type == .paragraph && block.text.isEmpty
    }

    private var blockUsesOwnInteractions: Bool {
        switch block.type {
        case .databaseEmbed, .image, .pageLink:
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
        findPageEntry(named: name)?.icon
    }

    private func findPageEntry(named name: String) -> FileEntry? {
        func search(in entries: [FileEntry]) -> FileEntry? {
            for entry in entries {
                let entryName = entry.name.replacingOccurrences(of: ".md", with: "")
                if entryName.localizedCaseInsensitiveCompare(name) == .orderedSame {
                    return entry
                }
                if let children = entry.children, let found = search(in: children) {
                    return found
                }
            }
            return nil
        }
        return search(in: document.availablePages)
    }

    private var pageLinkSidebarReferencePayload: SidebarReferenceDragPayload? {
        guard let entry = findPageEntry(named: block.pageLinkName) else { return nil }
        return SidebarReferenceDragPayload.page(path: entry.path)
    }

    private var resolvedDatabasePath: String? {
        guard !block.databasePath.isEmpty else { return nil }
        guard let pagePath = document.filePath else { return block.databasePath }
        return resolveDatabaseEmbedPath(
            block.databasePath,
            pagePath: pagePath,
            workspacePath: document.workspacePath
        ) ?? block.databasePath
    }

    private var databaseSidebarReferencePayload: SidebarReferenceDragPayload? {
        guard let resolvedDatabasePath else { return nil }
        return SidebarReferenceDragPayload.database(path: resolvedDatabasePath)
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
            DatabaseEmbedBlockView(
                dbPath: resolvedDatabasePath ?? block.databasePath,
                onOpenDatabaseTab: document.onOpenDatabaseTab,
                sidebarReferencePayload: databaseSidebarReferencePayload
            )

        case .pageLink:
            WikiLinkView(
                pageName: block.pageLinkName,
                icon: findPageIcon(named: block.pageLinkName),
                onNavigate: { document.onNavigateToPage?(block.pageLinkName) },
                sidebarReferencePayload: pageLinkSidebarReferencePayload
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
    @Binding var showAiPrompt: Bool

    func body(content: Content) -> some View {
        popoverLayer(content)
            .modifier(PopoverChangeTracker(
                document: document,
                block: block,
                showSlashMenu: $showSlashMenu,
                showBlockMenu: $showBlockMenu,
                showPagePicker: $showPagePicker,
                showAiPrompt: $showAiPrompt
            ))
    }

    @ViewBuilder
    private func popoverLayer(_ content: Content) -> some View {
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
            .floatingPopover(isPresented: $showAiPrompt, arrowEdge: .bottom) {
                AiPromptView(document: document)
            }
    }
}

private struct PopoverChangeTracker: ViewModifier {
    var document: BlockDocument
    let block: Block
    @Binding var showSlashMenu: Bool
    @Binding var showBlockMenu: Bool
    @Binding var showPagePicker: Bool
    @Binding var showAiPrompt: Bool

    func body(content: Content) -> some View {
        content
            .onAppear {
                showSlashMenu = (document.slashMenuBlockId == block.id)
                showBlockMenu = (document.blockMenuBlockId == block.id)
                showPagePicker = document.showPagePicker && document.pagePickerBlockId == block.id
                showAiPrompt = (document.aiPromptBlockId == block.id)
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
            .onChange(of: document.aiPromptBlockId) { _, newVal in
                let shouldShow = (newVal == block.id)
                if showAiPrompt != shouldShow { showAiPrompt = shouldShow }
            }
            .onChange(of: showAiPrompt) { _, show in
                if !show && document.aiPromptBlockId == block.id {
                    // Don't dismiss while generating — keep the popover alive
                    if document.isAiGenerating {
                        showAiPrompt = true
                    } else {
                        document.dismissAiPrompt()
                    }
                }
            }
    }
}

/// Inline AI prompt popover for generating content at the cursor position.
private struct AiPromptView: View {
    var document: BlockDocument
    @State private var promptText: String = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Input area with icon
            HStack(alignment: .top, spacing: 10) {
                Image("BugbookAI")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 20, height: 20)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .padding(.top, 4)

                TextField("Tell AI what to write...", text: $promptText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15))
                    .lineLimit(1...10)
                    .frame(minHeight: 24)
                    .fixedSize(horizontal: false, vertical: true)
                    .focused($isFocused)
                    .disabled(document.isAiGenerating)
                    .onSubmit {
                        document.aiPromptText = promptText
                        document.submitAiPrompt()
                    }
                    .onChange(of: promptText) { _, newVal in
                        document.aiPromptText = newVal
                    }
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 12)

            // Footer
            if document.isAiGenerating {
                aiGeneratingFooter
            } else {
                aiPromptHints
            }
        }
        .frame(width: 380)
        .popoverSurface()
        .onAppear {
            isFocused = true
        }
        .onKeyPress(.escape) {
            if document.isAiGenerating {
                document.cancelAiGeneration()
            } else {
                document.dismissAiPrompt()
            }
            return .handled
        }
    }

    private var aiGeneratingFooter: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text("Generating...")
                .font(.system(size: Typography.caption))
                .foregroundStyle(Color.fallbackTextSecondary)
            Spacer()
            Button {
                document.cancelAiGeneration()
            } label: {
                Text("Cancel")
                    .font(.system(size: Typography.caption, weight: .medium))
                    .foregroundStyle(Color.fallbackTextSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.primary.opacity(Opacity.light))
                    .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
            }
            .buttonStyle(.borderless)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Brand.subtle)
    }

    private var aiPromptHints: some View {
        HStack(spacing: 3) {
            kbdKey("Return")
            Text("generate")
                .font(.system(size: Typography.caption2))
                .foregroundStyle(Color.fallbackTextSecondary)
            Spacer()
            kbdKey("Esc")
            Text("cancel")
                .font(.system(size: Typography.caption2))
                .foregroundStyle(Color.fallbackTextSecondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(Opacity.subtle))
    }

    private func kbdKey(_ label: String) -> some View {
        Text(label)
            .font(.system(size: 10, weight: .medium, design: .rounded))
            .foregroundStyle(Color.fallbackTextSecondary)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Color.primary.opacity(Opacity.light))
            .clipShape(RoundedRectangle(cornerRadius: Radius.xs))
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
    private var refreshObserver: NSObjectProtocol?
    private var frameReportScheduled = false

    func syncRegistration(document: BlockDocument, blockId: UUID) {
        if let currentDocument = self.document,
           let currentBlockId = self.blockId,
           (currentDocument !== document || currentBlockId != blockId) {
            Task { @MainActor [weak currentDocument] in
                currentDocument?.unregisterBlockFrame(for: currentBlockId)
            }
        }

        let needsRefreshObserverUpdate = self.document !== document
        self.document = document
        self.blockId = blockId
        if needsRefreshObserverUpdate || refreshObserver == nil {
            updateRefreshObservation()
        }
        scheduleFrameReport()
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil { unregisterCurrentFrame() }
        super.viewWillMove(toWindow: newWindow)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        scheduleFrameReport()
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        if superview == nil {
            unregisterCurrentFrame()
        } else {
            scheduleFrameReport()
        }
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        // Only report on size changes (layout), not origin changes (scroll).
        scheduleFrameReport()
    }

    private func updateRefreshObservation() {
        if let refreshObserver {
            NotificationCenter.default.removeObserver(refreshObserver)
            self.refreshObserver = nil
        }

        guard let document else { return }
        refreshObserver = NotificationCenter.default.addObserver(
            forName: .blockDocumentFrameRefreshRequested,
            object: document,
            queue: nil
        ) { [weak self] _ in
            self?.reportFrame()
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

    private func unregisterCurrentFrame() {
        guard let document, let blockId else { return }
        Task { @MainActor [weak document] in
            document?.unregisterBlockFrame(for: blockId)
        }
    }

    deinit {
        if let refreshObserver {
            NotificationCenter.default.removeObserver(refreshObserver)
        }
        unregisterCurrentFrame()
    }
}
