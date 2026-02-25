import SwiftUI
import AppKit

/// NSViewRepresentable wrapping NSTextView for per-block text editing.
/// Handles keyboard intercepts for block splitting, merging, and navigation.
/// Supports rich text with WYSIWYG inline formatting (bold, italic, code, strikethrough, links).
struct BlockTextView: NSViewRepresentable {
    @ObservedObject var document: BlockDocument
    let blockId: UUID
    var isMultiline: Bool = false
    var font: NSFont = .systemFont(ofSize: 15)
    var textColor: NSColor = .labelColor
    var placeholder: String? = nil
    @Binding var textHeight: CGFloat

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> BlockNSTextView {
        let textView = BlockNSTextView()
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.isEditable = true
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainerInset = NSSize(width: 0, height: 2)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.font = font
        textView.textColor = textColor
        textView.allowsUndo = false // We handle undo at document level

        // Prevent NSTextView from accepting drag-and-drop (avoids UUID string insertion)
        textView.unregisterDraggedTypes()

        if let block = document.block(for: blockId) {
            textView.string = block.text
        }

        textView.placeholderString = placeholder
        textView.placeholderFont = font
        textView.blockId = blockId

        let coordinator = context.coordinator
        textView.onBecomeFirstResponder = { [weak coordinator] in
            coordinator?.handleBecomeFirstResponder()
        }
        textView.formatBoldAction = { [weak coordinator] in
            coordinator?.toggleBold()
        }
        textView.formatItalicAction = { [weak coordinator] in
            coordinator?.toggleItalic()
        }
        textView.formatCodeAction = { [weak coordinator] in
            coordinator?.toggleCode()
        }
        textView.formatLinkAction = { [weak coordinator] in
            coordinator?.promptLink()
        }
        textView.undoAction = { [weak coordinator] in
            coordinator?.parent.document.undo()
        }
        textView.redoAction = { [weak coordinator] in
            coordinator?.parent.document.redo()
        }
        textView.selectAllBlocksAction = { [weak coordinator] in
            coordinator?.parent.document.selectAllBlocks()
        }
        textView.onDragOutOfBlock = { [weak coordinator] in
            coordinator?.startBlockDragSelection()
        }
        textView.onShiftClick = { [weak coordinator] in
            guard let coordinator = coordinator else { return }
            let doc = coordinator.parent.document
            if let anchor = doc.focusedBlockId {
                doc.selectBlockRange(from: anchor, to: coordinator.parent.blockId)
            }
        }
        context.coordinator.textView = textView

        DispatchQueue.main.async {
            self.recalculateHeight(textView)
        }

        return textView
    }

    func updateNSView(_ textView: BlockNSTextView, context: Context) {
        context.coordinator.parent = self

        // Update font and color
        textView.font = font
        textView.textColor = textColor

        // Update placeholder
        textView.placeholderString = placeholder
        textView.placeholderFont = font

        // Update text if changed externally (not from user editing)
        if let block = document.block(for: blockId),
           !context.coordinator.isEditing,
           textView.string != block.text {
            textView.string = block.text
            DispatchQueue.main.async {
                self.recalculateHeight(textView)
            }
        }

        // Focus management: only when focus transitions to this block
        if document.focusedBlockId == blockId,
           context.coordinator.lastFocusedSelf != true {
            context.coordinator.lastFocusedSelf = true
            let cursorPos = self.document.cursorPosition
            // Retry with short delay — view may not have a window yet on first render
            func attemptFocus(retries: Int = 3) {
                guard retries > 0 else { return }
                if textView.window != nil {
                    textView.window?.makeFirstResponder(textView)
                    let pos = min(cursorPos, textView.string.count)
                    textView.setSelectedRange(NSRange(location: pos, length: 0))
                } else {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        attemptFocus(retries: retries - 1)
                    }
                }
            }
            DispatchQueue.main.async {
                attemptFocus()
            }
        } else if document.focusedBlockId != blockId {
            context.coordinator.lastFocusedSelf = false
        }
    }

    func recalculateHeight(_ textView: NSTextView) {
        guard let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else { return }
        layoutManager.ensureLayout(for: textContainer)
        let rect = layoutManager.usedRect(for: textContainer)
        let insets = textView.textContainerInset.height * 2
        // Use font-based minimum so empty headings aren't squished to 24px
        let fontSize = textView.font?.pointSize ?? 15
        let fontBasedMin = ceil(fontSize * 1.4) + insets
        let minHeight = max(24, fontBasedMin)
        let newHeight = max(ceil(rect.height) + insets, minHeight)
        if abs(newHeight - textHeight) > 0.5 {
            textHeight = newHeight
        }
    }

    // MARK: - Coordinator

    @MainActor
    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: BlockTextView
        weak var textView: NSTextView?
        var isEditing = false
        var suppressChanges = false
        var lastFocusedSelf: Bool?

        init(_ parent: BlockTextView) {
            self.parent = parent
        }

        private var dragMonitor: Any?

        func handleBecomeFirstResponder() {
            if parent.document.focusedBlockId != parent.blockId {
                parent.document.focusedBlockId = parent.blockId
                lastFocusedSelf = true
            }
            // Clear multi-block selection when a specific block gets focus
            if !parent.document.selectedBlockIds.isEmpty {
                parent.document.clearBlockSelection()
            }
        }

        // MARK: - Block Drag Selection

        func startBlockDragSelection() {
            let anchorId = parent.blockId
            parent.document.blockSelectionAnchor = anchorId
            parent.document.selectedBlockIds = [anchorId]

            dragMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDragged, .leftMouseUp]) { [weak self] event in
                guard let self = self else { return event }

                if event.type == .leftMouseUp {
                    self.endBlockDragSelection()
                    return event
                }

                // Hit test to find which block is under the mouse
                let point = event.locationInWindow
                if let contentView = event.window?.contentView {
                    let converted = contentView.convert(point, from: nil)
                    if let hitView = contentView.hitTest(converted) {
                        var view: NSView? = hitView
                        while let v = view {
                            if let blockTV = v as? BlockNSTextView,
                               let targetId = blockTV.blockId {
                                self.parent.document.selectBlockRange(from: anchorId, to: targetId)
                                break
                            }
                            view = v.superview
                        }
                    }
                }

                return event
            }
        }

        func endBlockDragSelection() {
            if let monitor = dragMonitor {
                NSEvent.removeMonitor(monitor)
                dragMonitor = nil
            }
            parent.document.blockSelectionAnchor = nil
            if let tv = textView as? BlockNSTextView {
                tv.isInBlockSelection = false
            }
        }

        // MARK: - Formatting Actions

        func toggleBold() {
            // TODO: WYSIWYG formatting disabled pending AttributedStringConverter fix
        }

        func toggleItalic() {
        }

        func toggleCode() {
        }

        func toggleStrikethrough() {
        }

        func promptLink() {
            guard let textView = textView, textView.selectedRange().length > 0 else { return }

            let alert = NSAlert()
            alert.messageText = "Insert Link"
            alert.informativeText = "Enter URL:"
            alert.addButton(withTitle: "OK")
            alert.addButton(withTitle: "Cancel")

            let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
            input.placeholderString = "https://"
            alert.accessoryView = input

            if alert.runModal() == .alertFirstButtonReturn {
                let url = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
                if !url.isEmpty {
                    let range = textView.selectedRange()
                    let linkText = (textView.string as NSString).substring(with: range)
                    textView.insertText("[\(linkText)](\(url))", replacementRange: range)
                }
            }
        }

        func textDidChange(_ notification: Notification) {
            guard !suppressChanges else { return }
            guard let textView = notification.object as? NSTextView else { return }
            isEditing = true
            defer { isEditing = false }

            // Clear multi-block selection when typing
            if !parent.document.selectedBlockIds.isEmpty {
                parent.document.clearBlockSelection()
            }

            // Store plain text directly (works for both top-level and column children)
            parent.document.updateBlockText(id: parent.blockId, text: textView.string)

            // Slash command detection (skip title block)
            let isTitleBlock = parent.document.titleBlock?.id == parent.blockId
            if !isTitleBlock, textView.string.hasPrefix("/") {
                if parent.document.slashMenuBlockId != parent.blockId {
                    parent.document.slashMenuBlockId = parent.blockId
                    parent.document.slashMenuSelectedIndex = 0
                }
                parent.document.slashMenuFilter = String(textView.string.dropFirst(1))
            } else if parent.document.slashMenuBlockId == parent.blockId {
                parent.document.dismissSlashMenu()
            }

            // Auto-detect markdown prefixes (e.g. "## ", "- ", "- [ ] ", "> ")
            autoDetectMarkdownPrefix(textView)

            parent.recalculateHeight(textView)
        }

        // MARK: - Markdown shortcut auto-detection

        /// Detects markdown prefixes typed at the start of a paragraph block
        /// and auto-converts the block type (like Notion does).
        private func autoDetectMarkdownPrefix(_ textView: NSTextView) {
            guard let block = parent.document.block(for: parent.blockId),
                  block.type == .paragraph else { return }
            let text = textView.string

            // Task item: "- [ ] " or "- [x] " or shorthand "[] " / "[ ] "
            if text.hasPrefix("- [ ] ") {
                convertBlock(textView, stripping: 6, to: .taskItem)
                return
            }
            if text.hasPrefix("- [x] ") || text.hasPrefix("- [X] ") {
                convertBlock(textView, stripping: 6, to: .taskItem, checked: true)
                return
            }
            if text.hasPrefix("[ ] ") {
                convertBlock(textView, stripping: 4, to: .taskItem)
                return
            }
            if text.hasPrefix("[x] ") || text.hasPrefix("[X] ") {
                convertBlock(textView, stripping: 4, to: .taskItem, checked: true)
                return
            }
            if text.hasPrefix("[] ") {
                convertBlock(textView, stripping: 3, to: .taskItem)
                return
            }

            // Heading: "# " through "###### "
            if text.hasPrefix("#") {
                for level in (1...6).reversed() {
                    let prefix = String(repeating: "#", count: level) + " "
                    if text.hasPrefix(prefix) {
                        convertBlock(textView, stripping: prefix.count, to: .heading, headingLevel: level)
                        return
                    }
                }
            }

            // Bullet: "- " or "* " or "+ "
            if text.hasPrefix("- ") || text.hasPrefix("* ") || text.hasPrefix("+ ") {
                convertBlock(textView, stripping: 2, to: .bulletListItem)
                return
            }

            // Numbered: digits followed by ". "
            if let dotIdx = text.firstIndex(of: "."),
               dotIdx > text.startIndex,
               text[..<dotIdx].allSatisfy(\.isNumber) {
                let afterDot = text.index(after: dotIdx)
                if afterDot < text.endIndex, text[afterDot] == " " {
                    let prefixLen = text.distance(from: text.startIndex, to: afterDot) + 1
                    convertBlock(textView, stripping: prefixLen, to: .numberedListItem)
                    return
                }
            }

            // Blockquote: "> "
            if text.hasPrefix("> ") {
                convertBlock(textView, stripping: 2, to: .blockquote)
                return
            }

            // Horizontal rule: exactly "---", "***", or "___" (3+ same char, nothing else)
            let trimmed = text.trimmingCharacters(in: .whitespaces)
            if trimmed.count >= 3 {
                let chars = Set(trimmed)
                if chars.count == 1, let ch = chars.first, "-*_".contains(ch) {
                    convertBlock(textView, stripping: text.count, to: .horizontalRule)
                    return
                }
            }
        }

        private func convertBlock(_ textView: NSTextView, stripping prefixLen: Int, to type: BlockType, headingLevel: Int = 1, checked: Bool = false) {
            guard parent.document.blockLocation(for: parent.blockId) != nil else { return }
            let newText = String(textView.string.dropFirst(prefixLen))

            parent.document.updateBlockProperty(id: parent.blockId) { block in
                block.type = type
                block.text = newText
                if type == .heading { block.headingLevel = headingLevel }
                if type == .taskItem { block.isChecked = checked }
            }

            suppressChanges = true
            textView.textStorage?.setAttributedString(
                NSAttributedString(string: newText, attributes: [
                    .font: parent.font,
                    .foregroundColor: parent.textColor
                ])
            )
            textView.setSelectedRange(NSRange(location: newText.count, length: 0))
            suppressChanges = false
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            // Delete all selected blocks (e.g. Cmd+A then Backspace)
            if commandSelector == #selector(NSResponder.deleteBackward(_:)),
               !parent.document.selectedBlockIds.isEmpty {
                parent.document.deleteSelectedBlocks()
                return true
            }

            // Slash menu intercepts (when active)
            if parent.document.slashMenuBlockId == parent.blockId {
                if commandSelector == #selector(NSResponder.moveUp(_:)) {
                    if parent.document.slashMenuSelectedIndex > 0 {
                        parent.document.slashMenuSelectedIndex -= 1
                    }
                    return true
                }
                if commandSelector == #selector(NSResponder.moveDown(_:)) {
                    let count = parent.document.filteredSlashCommands.count
                    if parent.document.slashMenuSelectedIndex < count - 1 {
                        parent.document.slashMenuSelectedIndex += 1
                    }
                    return true
                }
                if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                    parent.document.executeSlashCommand()
                    return true
                }
                if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                    parent.document.dismissSlashMenu()
                    return true
                }
            }

            // Enter — split block
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                if parent.isMultiline { return false }
                let pos = textView.selectedRange().location
                parent.document.splitBlock(id: parent.blockId, atOffset: pos)
                return true
            }

            // Backspace at position 0
            if commandSelector == #selector(NSResponder.deleteBackward(_:)) {
                let range = textView.selectedRange()
                if range.location == 0, range.length == 0 {
                    // Title block: don't convert type or merge
                    if parent.document.index(for: parent.blockId) == 0,
                       parent.document.titleBlock != nil {
                        return true
                    }
                    if let block = parent.document.block(for: parent.blockId),
                       block.type != .paragraph {
                        parent.document.changeBlockType(id: parent.blockId, to: .paragraph)
                        return true
                    }
                    parent.document.mergeWithPrevious(id: parent.blockId)
                    return true
                }
                return false
            }

            // Arrow up — move to previous block if on first line
            if commandSelector == #selector(NSResponder.moveUp(_:)) {
                if isOnFirstLine(textView) {
                    if let loc = parent.document.blockLocation(for: parent.blockId) {
                        if let childIdx = loc.child {
                            // Inside column — navigate to previous block in same column
                            let colBlock = parent.document.blocks[loc.topLevel]
                            let myColIndex = colBlock.children[childIdx].columnIndex
                            let prevInCol = colBlock.children[..<childIdx]
                                .filter { $0.columnIndex == myColIndex }
                                .last
                            if let prev = prevInCol {
                                parent.document.focusedBlockId = prev.id
                                parent.document.cursorPosition = prev.text.count
                                return true
                            }
                            return false
                        }
                        if loc.topLevel > 0 {
                            let prev = parent.document.blocks[loc.topLevel - 1]
                            parent.document.focusedBlockId = prev.id
                            parent.document.cursorPosition = prev.text.count
                            return true
                        }
                    }
                }
                return false
            }

            // Arrow down — move to next block if on last line
            if commandSelector == #selector(NSResponder.moveDown(_:)) {
                if isOnLastLine(textView) {
                    if let loc = parent.document.blockLocation(for: parent.blockId) {
                        if let childIdx = loc.child {
                            // Inside column — navigate to next block in same column
                            let colBlock = parent.document.blocks[loc.topLevel]
                            let myColIndex = colBlock.children[childIdx].columnIndex
                            let nextInCol = colBlock.children[(childIdx + 1)...]
                                .first { $0.columnIndex == myColIndex }
                            if let next = nextInCol {
                                parent.document.focusedBlockId = next.id
                                parent.document.cursorPosition = 0
                                return true
                            }
                            return false
                        }
                        if loc.topLevel < parent.document.blocks.count - 1 {
                            let next = parent.document.blocks[loc.topLevel + 1]
                            parent.document.focusedBlockId = next.id
                            parent.document.cursorPosition = 0
                            return true
                        }
                    }
                }
                return false
            }

            // Tab — indent list items
            if commandSelector == #selector(NSResponder.insertTab(_:)) {
                if let block = parent.document.block(for: parent.blockId),
                   [.bulletListItem, .numberedListItem, .taskItem].contains(block.type) {
                    parent.document.indent(id: parent.blockId)
                    return true
                }
                return false
            }

            // Shift+Tab — outdent list items
            if commandSelector == #selector(NSResponder.insertBacktab(_:)) {
                if let block = parent.document.block(for: parent.blockId),
                   [.bulletListItem, .numberedListItem, .taskItem].contains(block.type) {
                    parent.document.outdent(id: parent.blockId)
                    return true
                }
                return false
            }

            return false
        }

        // MARK: - Line position helpers

        private func isOnFirstLine(_ textView: NSTextView) -> Bool {
            guard let layoutManager = textView.layoutManager,
                  layoutManager.numberOfGlyphs > 0 else { return true }
            let cursorPos = textView.selectedRange().location
            let glyphIdx = layoutManager.glyphIndexForCharacter(
                at: min(cursorPos, max(0, layoutManager.numberOfGlyphs - 1))
            )
            var cursorLineRange = NSRange()
            layoutManager.lineFragmentRect(forGlyphAt: glyphIdx, effectiveRange: &cursorLineRange)
            var firstLineRange = NSRange()
            layoutManager.lineFragmentRect(forGlyphAt: 0, effectiveRange: &firstLineRange)
            return cursorLineRange.location == firstLineRange.location
        }

        private func isOnLastLine(_ textView: NSTextView) -> Bool {
            guard let layoutManager = textView.layoutManager,
                  layoutManager.numberOfGlyphs > 0 else { return true }
            let cursorPos = textView.selectedRange().location
            let glyphIdx = layoutManager.glyphIndexForCharacter(
                at: min(cursorPos, max(0, layoutManager.numberOfGlyphs - 1))
            )
            var cursorLineRange = NSRange()
            layoutManager.lineFragmentRect(forGlyphAt: glyphIdx, effectiveRange: &cursorLineRange)
            let lastGlyph = max(0, layoutManager.numberOfGlyphs - 1)
            var lastLineRange = NSRange()
            layoutManager.lineFragmentRect(forGlyphAt: lastGlyph, effectiveRange: &lastLineRange)
            return cursorLineRange.location == lastLineRange.location
        }
    }
}

// MARK: - Custom NSTextView for focus tracking and keyboard shortcuts

class BlockNSTextView: NSTextView {
    var onBecomeFirstResponder: (() -> Void)?
    var placeholderString: String?
    var placeholderFont: NSFont?

    // Formatting action closures
    var blockId: UUID?
    var formatBoldAction: (() -> Void)?
    var formatItalicAction: (() -> Void)?
    var formatCodeAction: (() -> Void)?
    var formatLinkAction: (() -> Void)?
    var undoAction: (() -> Void)?
    var redoAction: (() -> Void)?
    var selectAllBlocksAction: (() -> Void)?
    var onDragOutOfBlock: (() -> Void)?
    var onShiftClick: (() -> Void)?
    var isInBlockSelection = false

    override func didChangeText() {
        super.didChangeText()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        if string.isEmpty, let placeholder = placeholderString {
            let font = placeholderFont ?? .systemFont(ofSize: 15)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: NSColor.placeholderTextColor
            ]
            let inset = textContainerInset
            let padding = textContainer?.lineFragmentPadding ?? 0
            let point = NSPoint(x: inset.width + padding, y: inset.height)
            NSAttributedString(string: placeholder, attributes: attrs).draw(at: point)
        }
    }

    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        if result {
            onBecomeFirstResponder?()
        }
        return result
    }

    override func selectAll(_ sender: Any?) {
        // If all text already selected (or empty), escalate to select all blocks
        if string.isEmpty || selectedRange().length == string.count {
            selectAllBlocksAction?()
            return
        }
        super.selectAll(sender)
    }

    // Reject all external drops to prevent UUID string insertion from drag-and-drop
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        return false
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        return []
    }

    // MARK: - Cross-Block Selection

    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.shift) {
            onShiftClick?()
            return
        }
        super.mouseDown(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        if isInBlockSelection {
            return // Block selection is active — don't do text selection
        }
        let localPoint = convert(event.locationInWindow, from: nil)
        if !bounds.contains(localPoint) {
            isInBlockSelection = true
            onDragOutOfBlock?()
            return
        }
        super.mouseDragged(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        isInBlockSelection = false
        super.mouseUp(with: event)
    }

    // MARK: - Keyboard Shortcuts for Formatting

    override func keyDown(with event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        if flags == .command {
            switch event.charactersIgnoringModifiers {
            case "z":
                undoAction?()
                return
            case "b":
                formatBoldAction?()
                return
            case "i":
                formatItalicAction?()
                return
            case "e":
                formatCodeAction?()
                return
            default:
                break
            }
        }

        if flags == [.command, .shift] {
            switch event.charactersIgnoringModifiers {
            case "z":
                redoAction?()
                return
            default:
                break
            }
        }

        super.keyDown(with: event)
    }
}
