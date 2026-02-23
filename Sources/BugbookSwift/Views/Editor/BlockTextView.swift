import SwiftUI
import AppKit

/// NSViewRepresentable wrapping NSTextView for per-block text editing.
/// Handles keyboard intercepts for block splitting, merging, and navigation.
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

        let coordinator = context.coordinator
        textView.onBecomeFirstResponder = { [weak coordinator] in
            coordinator?.handleBecomeFirstResponder()
        }
        context.coordinator.textView = textView

        DispatchQueue.main.async {
            self.recalculateHeight(textView)
        }

        return textView
    }

    func updateNSView(_ textView: BlockNSTextView, context: Context) {
        context.coordinator.parent = self

        // Update font/color
        if textView.font != font {
            textView.font = font
        }
        if textView.textColor != textColor {
            textView.textColor = textColor
        }

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
            DispatchQueue.main.async {
                textView.window?.makeFirstResponder(textView)
                let pos = min(self.document.cursorPosition, textView.string.count)
                textView.setSelectedRange(NSRange(location: pos, length: 0))
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
        let newHeight = max(ceil(rect.height) + textView.textContainerInset.height * 2, 24)
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

        func handleBecomeFirstResponder() {
            if parent.document.focusedBlockId != parent.blockId {
                parent.document.focusedBlockId = parent.blockId
                lastFocusedSelf = true
            }
        }

        func textDidChange(_ notification: Notification) {
            guard !suppressChanges else { return }
            guard let textView = notification.object as? NSTextView else { return }
            isEditing = true
            defer { isEditing = false }

            if let idx = parent.document.index(for: parent.blockId) {
                parent.document.blocks[idx].text = textView.string
            }

            // Slash command detection
            if textView.string.hasPrefix("/") {
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
            guard let idx = parent.document.index(for: parent.blockId) else { return }
            let newText = String(textView.string.dropFirst(prefixLen))

            parent.document.blocks[idx].type = type
            parent.document.blocks[idx].text = newText
            if type == .heading {
                parent.document.blocks[idx].headingLevel = headingLevel
            }
            if type == .taskItem {
                parent.document.blocks[idx].isChecked = checked
            }

            suppressChanges = true
            textView.string = newText
            textView.setSelectedRange(NSRange(location: newText.count, length: 0))
            suppressChanges = false
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
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
                    if let idx = parent.document.index(for: parent.blockId), idx > 0 {
                        let prev = parent.document.blocks[idx - 1]
                        parent.document.focusedBlockId = prev.id
                        parent.document.cursorPosition = prev.text.count
                        return true
                    }
                }
                return false
            }

            // Arrow down — move to next block if on last line
            if commandSelector == #selector(NSResponder.moveDown(_:)) {
                if isOnLastLine(textView) {
                    if let idx = parent.document.index(for: parent.blockId),
                       idx < parent.document.blocks.count - 1 {
                        let next = parent.document.blocks[idx + 1]
                        parent.document.focusedBlockId = next.id
                        parent.document.cursorPosition = 0
                        return true
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

// MARK: - Custom NSTextView for focus tracking

class BlockNSTextView: NSTextView {
    var onBecomeFirstResponder: (() -> Void)?
    var placeholderString: String?
    var placeholderFont: NSFont?

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

    // Reject all external drops to prevent UUID string insertion from drag-and-drop
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        return false
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        return []
    }
}
