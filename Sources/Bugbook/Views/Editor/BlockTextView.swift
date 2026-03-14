import SwiftUI
import AppKit
import UniformTypeIdentifiers

enum EditorTypography {
    static let zoomScaleKey = "editorZoomScale"
    static let minZoomScale: CGFloat = 0.8
    static let maxZoomScale: CGFloat = 2.4
    static let defaultZoomScale: CGFloat = 1.1

    static var zoomScale: CGFloat {
        let stored = UserDefaults.standard.double(forKey: zoomScaleKey)
        let resolved = stored == 0 ? defaultZoomScale : CGFloat(stored)
        return min(max(resolved, minZoomScale), maxZoomScale)
    }

    static var bodyFontSize: CGFloat {
        scaled(Typography.content)
    }

    static func scaled(_ baseSize: CGFloat) -> CGFloat {
        baseSize * zoomScale
    }
}

enum EditorSelectionStyle {
    static var backgroundColor: NSColor {
        NSColor.controlAccentColor.withAlphaComponent(0.28)
    }

    static var foregroundColor: NSColor {
        NSColor.labelColor
    }
}

/// NSViewRepresentable wrapping NSTextView for per-block text editing.
/// Handles keyboard intercepts for block splitting, merging, and navigation.
/// Supports rich text with WYSIWYG inline formatting (bold, italic, code, strikethrough, links).
struct BlockTextView: NSViewRepresentable {
    var document: BlockDocument
    let blockId: UUID
    var selectionVersion: Int = 0
    var isMultiline: Bool = false
    var font: NSFont = .systemFont(ofSize: EditorTypography.bodyFontSize)
    var textColor: NSColor = .labelColor
    var placeholder: String? = nil
    var onTextChange: (() -> Void)? = nil
    @Binding var textHeight: CGFloat

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> BlockNSTextView {
        let textView = BlockNSTextView()
        textView.delegate = context.coordinator
        textView.isRichText = true
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
            let attributed = AttributedStringConverter.attributedString(
                from: block.text,
                font: font,
                textColor: textColor
            )
            context.coordinator.suppressChanges = true
            textView.textStorage?.setAttributedString(attributed)
            context.coordinator.suppressChanges = false
        }

        textView.placeholderString = placeholder
        textView.placeholderFont = font
        textView.blockId = blockId
        textView.typingAttributes = [
            .font: font,
            .foregroundColor: textColor
        ]
        textView.selectedTextAttributes = [
            .backgroundColor: EditorSelectionStyle.backgroundColor,
            .foregroundColor: EditorSelectionStyle.foregroundColor
        ]

        let coordinator = context.coordinator
        textView.onBecomeFirstResponder = { [weak coordinator] in
            coordinator?.handleBecomeFirstResponder()
        }
        textView.onMouseDownAction = { [weak coordinator] in
            coordinator?.handleMouseDown()
        }
        textView.onResignFirstResponder = { [weak coordinator] in
            coordinator?.handleResignFirstResponder()
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
        textView.formatStrikethroughAction = { [weak coordinator] in
            coordinator?.toggleStrikethrough()
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
        textView.blockTypeShortcutAction = { [weak coordinator] action in
            coordinator?.handleBlockTypeShortcut(action)
        }
        textView.onDragOutOfBlock = { [weak coordinator] anchorOffset, windowPoint in
            coordinator?.startMultiBlockTextSelection(anchorOffset: anchorOffset, initialWindowPoint: windowPoint)
        }
        textView.onMultiBlockSelectionDrag = { [weak coordinator] windowPoint in
            coordinator?.updateMultiBlockTextSelection(windowPoint: windowPoint)
        }
        textView.onMultiBlockSelectionEnd = { [weak coordinator] in
            coordinator?.endMultiBlockTextSelection()
        }
        textView.onShiftClick = { [weak coordinator] in
            guard let coordinator = coordinator else { return }
            let doc = coordinator.parent.document
            if let anchor = doc.focusedBlockId {
                doc.selectBlockRange(from: anchor, to: coordinator.parent.blockId)
            }
        }
        textView.onPasteImage = { [weak coordinator] in
            guard let coordinator = coordinator else { return false }
            return coordinator.handleImagePaste()
        }
        textView.copySelectionAction = { [weak coordinator] in
            coordinator?.handleCopySelection() ?? false
        }
        textView.cutSelectionAction = { [weak coordinator] in
            coordinator?.handleCutSelection() ?? false
        }
        let heightRecalc = { [weak textView] in
            guard let textView else { return }
            self.recalculateHeight(textView)
        }
        textView.onFrameWidthChanged = {
            DispatchQueue.main.async { heightRecalc() }
        }
        context.coordinator.textView = textView

        DispatchQueue.main.async {
            self.recalculateHeight(textView)
        }

        return textView
    }

    func updateNSView(_ textView: BlockNSTextView, context: Context) {
        context.coordinator.parent = self

        // Update placeholder (safe — doesn't modify text storage)
        textView.placeholderString = placeholder
        textView.placeholderFont = font

        // Update typing attributes for new text (doesn't touch existing text storage)
        textView.typingAttributes = [
            .font: font,
            .foregroundColor: textColor
        ]
        textView.selectedTextAttributes = [
            .backgroundColor: EditorSelectionStyle.backgroundColor,
            .foregroundColor: EditorSelectionStyle.foregroundColor
        ]

        // Re-apply foreground color to existing text when textColor changes
        if textColor != context.coordinator.lastTextColor {
            context.coordinator.lastTextColor = textColor
            let fullRange = NSRange(location: 0, length: textView.textStorage?.length ?? 0)
            if fullRange.length > 0 {
                context.coordinator.withProgrammaticViewUpdate {
                    textView.textStorage?.addAttribute(.foregroundColor, value: textColor, range: fullRange)
                }
            }
        }

        // Re-apply font to existing text when block type changes (e.g., heading → paragraph)
        if font != context.coordinator.lastFont {
            context.coordinator.lastFont = font
            let fullRange = NSRange(location: 0, length: textView.textStorage?.length ?? 0)
            if fullRange.length > 0 {
                context.coordinator.withProgrammaticViewUpdate {
                    textView.textStorage?.addAttribute(.font, value: font, range: fullRange)
                }
            }
            DispatchQueue.main.async {
                self.recalculateHeight(textView)
            }
        }

        // Update text if changed externally (not from user editing)
        if let block = document.block(for: blockId),
           !context.coordinator.isEditing {
            let currentMarkdown = context.coordinator.markdownFromTextView(textView)
            if currentMarkdown != block.text {
                let selected = textView.selectedRange()
                let attributed = AttributedStringConverter.attributedString(
                    from: block.text,
                    font: font,
                    textColor: textColor
                )
                let textLength = (attributed.string as NSString).length
                let clampedLocation = min(selected.location, textLength)
                let clampedLength = min(selected.length, max(0, textLength - clampedLocation))
                let newSelection = NSRange(location: clampedLocation, length: clampedLength)

                context.coordinator.withProgrammaticViewUpdate {
                    textView.textStorage?.setAttributedString(attributed)
                    if textView.selectedRange() != newSelection {
                        textView.setSelectedRange(newSelection)
                    }
                    textView.typingAttributes = [
                        .font: font,
                        .foregroundColor: textColor
                    ]
                }
            }
            DispatchQueue.main.async {
                self.recalculateHeight(textView)
            }
        }

        let multiBlockRange = document.multiBlockSelectionRange(
            for: blockId,
            visibleLength: (textView.string as NSString).length
        )
        let isFirstResponder = textView.window?.firstResponder === textView
        let isActivelyDraggingMultiBlockSelection = textView.isInBlockSelection
        context.coordinator.updateTemporaryMultiBlockHighlight(on: textView, range: multiBlockRange)

        if let range = multiBlockRange, isFirstResponder, !isActivelyDraggingMultiBlockSelection {
            context.coordinator.withProgrammaticViewUpdate {
                if textView.selectedRange() != range {
                    textView.setSelectedRange(range)
                }
            }
        } else if multiBlockRange != nil, !isFirstResponder {
            let caret = NSRange(
                location: min(textView.selectedRange().location, (textView.string as NSString).length),
                length: 0
            )
            context.coordinator.withProgrammaticViewUpdate {
                if textView.selectedRange() != caret {
                    textView.setSelectedRange(caret)
                }
            }
        } else if document.multiBlockTextSelection == nil,
                  document.focusedBlockId != blockId,
                  textView.selectedRange().length > 0 {
            let caret = NSRange(
                location: min(textView.selectedRange().location, (textView.string as NSString).length),
                length: 0
            )
            context.coordinator.withProgrammaticViewUpdate {
                if textView.selectedRange() != caret {
                    textView.setSelectedRange(caret)
                }
            }
        }

        // Focus management: only when focus transitions to this block
        if document.multiBlockTextSelection == nil,
           document.focusedBlockId == blockId,
           context.coordinator.lastFocusedSelf != true {
            context.coordinator.lastFocusedSelf = true
            let cursorPos = self.document.cursorPosition
            // Retry with short delay — view may not have a window yet on first render
            func attemptFocus(retries: Int = 3) {
                guard retries > 0 else { return }
                if textView.window != nil {
                    let pos = min(cursorPos, textView.string.count)
                    let targetSelection = NSRange(location: pos, length: 0)
                    context.coordinator.withProgrammaticViewUpdate {
                        textView.window?.makeFirstResponder(textView)
                        if textView.selectedRange() != targetSelection {
                            textView.setSelectedRange(targetSelection)
                        }
                    }
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
        let fontSize = textView.font?.pointSize ?? EditorTypography.bodyFontSize
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
        var lastTextColor: NSColor?
        var lastFont: NSFont?
        var lastReplacementString: String?
        private var programmaticViewUpdateDepth: Int = 0

        init(_ parent: BlockTextView) {
            self.parent = parent
        }

        var isProgrammaticViewUpdateInFlight: Bool {
            programmaticViewUpdateDepth > 0
        }

        func withProgrammaticViewUpdate(_ updates: () -> Void) {
            programmaticViewUpdateDepth += 1
            suppressChanges = true
            updates()
            programmaticViewUpdateDepth = max(0, programmaticViewUpdateDepth - 1)
            if programmaticViewUpdateDepth == 0 {
                suppressChanges = false
            }
        }

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

        func handleMouseDown() {
            if parent.document.multiBlockTextSelection != nil {
                parent.document.clearMultiBlockTextSelection()
            }
            if !parent.document.selectedBlockIds.isEmpty {
                parent.document.clearBlockSelection()
            }
        }

        func handleResignFirstResponder() {
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard self.parent.document.selectionBlockId == self.parent.blockId else { return }
                self.parent.document.selectionRect = nil
                self.parent.document.selectionBlockId = nil
            }
        }

        // MARK: - Cross-Block Text Selection

        func startMultiBlockTextSelection(anchorOffset: Int, initialWindowPoint: NSPoint) {
            parent.document.beginMultiBlockTextSelection(
                anchor: BlockTextSelectionPoint(blockId: parent.blockId, displayOffset: anchorOffset),
                focus: BlockTextSelectionPoint(blockId: parent.blockId, displayOffset: anchorOffset)
            )
            updateMultiBlockTextSelection(windowPoint: initialWindowPoint)
        }

        func updateMultiBlockTextSelection(windowPoint: NSPoint) {
            guard let window = textView?.window else { return }
            guard let target = BlockNSTextView.textPosition(atWindowPoint: windowPoint, in: window) else {
                return
            }
            parent.document.updateMultiBlockTextSelection(
                focus: BlockTextSelectionPoint(blockId: target.blockId, displayOffset: target.offset)
            )
        }

        func endMultiBlockTextSelection() {
            if let tv = textView as? BlockNSTextView {
                tv.isInBlockSelection = false
            }
        }

        func handleCopySelection() -> Bool {
            parent.document.copyMultiBlockSelectedText()
        }

        func handleCutSelection() -> Bool {
            parent.document.cutMultiBlockSelectedText()
        }

        func updateTemporaryMultiBlockHighlight(on textView: NSTextView, range: NSRange?) {
            guard let layoutManager = textView.layoutManager else { return }

            let fullLength = (textView.string as NSString).length
            let fullRange = NSRange(location: 0, length: fullLength)
            if fullRange.length > 0 {
                layoutManager.removeTemporaryAttribute(.backgroundColor, forCharacterRange: fullRange)
                layoutManager.removeTemporaryAttribute(.foregroundColor, forCharacterRange: fullRange)
            }

            guard let range,
                  range.length > 0,
                  textView.window?.firstResponder !== textView else {
                return
            }

            let location = min(max(0, range.location), fullLength)
            let length = min(max(0, range.length), max(0, fullLength - location))
            guard length > 0 else { return }

            let highlightRange = NSRange(location: location, length: length)
            layoutManager.addTemporaryAttribute(
                .backgroundColor,
                value: EditorSelectionStyle.backgroundColor,
                forCharacterRange: highlightRange
            )
            layoutManager.addTemporaryAttribute(
                .foregroundColor,
                value: EditorSelectionStyle.foregroundColor,
                forCharacterRange: highlightRange
            )
        }

        // MARK: - Image Paste

        /// Handles pasting image data from the clipboard. Returns true if an image was handled.
        func handleImagePaste() -> Bool {
            let document = parent.document
            let blockId = parent.blockId
            let pb = NSPasteboard.general

            // 1. Check for image file URLs (e.g. copied files from Finder)
            if let urls = pb.readObjects(forClasses: [NSURL.self], options: [
                .urlReadingFileURLsOnly: true,
                .urlReadingContentsConformToTypes: ["public.image"]
            ]) as? [URL] {
                let imageURLs = urls.filter { supportedImageExtensions.contains($0.pathExtension.lowercased()) }
                if let url = imageURLs.first {
                    if let path = document.copyImageToAssets(url) {
                        insertImageAfterCurrentBlock(document: document, blockId: blockId, imagePath: path)
                        return true
                    }
                }
            }

            // 2. Check for any pasteboard payload AppKit can decode into an image.
            if let image = pastedImage(from: pb),
               let pngData = pngData(from: image),
               let path = document.saveImageDataToAssets(pngData, fileExtension: "png") {
                insertImageAfterCurrentBlock(document: document, blockId: blockId, imagePath: path)
                return true
            }

            return false
        }

        private func pastedImage(from pasteboard: NSPasteboard) -> NSImage? {
            if let image = (pasteboard.readObjects(forClasses: [NSImage.self]) as? [NSImage])?.first {
                return image
            }

            if let imageType = pasteboard.types?.first(where: Self.isImagePasteboardType),
               let data = pasteboard.data(forType: imageType),
               let image = NSImage(data: data) {
                return image
            }

            return NSImage(pasteboard: pasteboard)
        }

        private func pngData(from image: NSImage) -> Data? {
            guard let tiffData = image.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiffData) else {
                return nil
            }
            return bitmap.representation(using: .png, properties: [:])
        }

        private static func isImagePasteboardType(_ type: NSPasteboard.PasteboardType) -> Bool {
            UTType(type.rawValue)?.conforms(to: .image) == true
        }

        private func insertImageAfterCurrentBlock(document: BlockDocument, blockId: UUID, imagePath: String) {
            guard let loc = document.blockLocation(for: blockId) else { return }
            let currentBlock = document.block(for: blockId)
            let isEmptyParagraph = currentBlock?.type == .paragraph && (currentBlock?.text.isEmpty ?? true)

            if isEmptyParagraph {
                // Convert the current empty block into the image block
                document.insertImageAtBlock(blockId: blockId, imagePath: imagePath)
            } else {
                // Insert a new image block after the current one
                let insertIndex = loc.topLevel + 1
                document.insertImageBlock(at: insertIndex, imagePath: imagePath)
            }
        }

        // MARK: - Block Type Shortcuts

        func handleBlockTypeShortcut(_ action: String) {
            let doc = parent.document
            let blockId = parent.blockId

            if action == "createPage" {
                let currentText = doc.block(for: blockId)?.text ?? ""
                let pageName = currentText.isEmpty ? "Untitled" : currentText
                if let createPage = doc.onCreateSubPage,
                   let pagePath = createPage(pageName) {
                    let resolvedName = (pagePath as NSString).lastPathComponent.replacingOccurrences(of: ".md", with: "")
                    doc.updateBlockProperty(id: blockId) { block in
                        block.type = .pageLink
                        block.pageLinkName = resolvedName
                        block.text = ""
                    }
                }
                return
            }

            let mapping: [(String, BlockType, Int)] = [
                ("paragraph", .paragraph, 0),
                ("heading1", .heading, 1),
                ("heading2", .heading, 2),
                ("heading3", .heading, 3),
                ("taskItem", .taskItem, 0),
                ("bulletListItem", .bulletListItem, 0),
                ("numberedListItem", .numberedListItem, 0),
                ("toggle", .toggle, 0),
                ("codeBlock", .codeBlock, 0),
            ]
            guard let match = mapping.first(where: { $0.0 == action }) else { return }
            doc.changeBlockType(id: blockId, to: match.1)
            if match.1 == .heading {
                doc.setHeadingLevel(id: blockId, level: match.2)
            }
        }

        // MARK: - Formatting Actions

        func toggleBold() {
            guard let textView = textView else { return }
            AttributedStringConverter.toggleBold(in: textView, font: parent.font)
            textView.textStorage?.removeAttribute(
                AttributedStringConverter.markdownSourceKey,
                range: NSRange(location: 0, length: textView.string.count)
            )
            parent.document.updateBlockText(id: parent.blockId, text: markdownFromTextView(textView))
            parent.recalculateHeight(textView)
            parent.onTextChange?()
        }

        func toggleItalic() {
            guard let textView = textView else { return }
            AttributedStringConverter.toggleItalic(in: textView, font: parent.font)
            textView.textStorage?.removeAttribute(
                AttributedStringConverter.markdownSourceKey,
                range: NSRange(location: 0, length: textView.string.count)
            )
            parent.document.updateBlockText(id: parent.blockId, text: markdownFromTextView(textView))
            parent.recalculateHeight(textView)
            parent.onTextChange?()
        }

        func toggleCode() {
            guard let textView = textView else { return }
            AttributedStringConverter.toggleCode(in: textView, font: parent.font)
            textView.textStorage?.removeAttribute(
                AttributedStringConverter.markdownSourceKey,
                range: NSRange(location: 0, length: textView.string.count)
            )
            parent.document.updateBlockText(id: parent.blockId, text: markdownFromTextView(textView))
            parent.recalculateHeight(textView)
            parent.onTextChange?()
        }

        func toggleStrikethrough() {
            guard let textView = textView else { return }
            AttributedStringConverter.toggleStrikethrough(in: textView)
            textView.textStorage?.removeAttribute(
                AttributedStringConverter.markdownSourceKey,
                range: NSRange(location: 0, length: textView.string.count)
            )
            parent.document.updateBlockText(id: parent.blockId, text: markdownFromTextView(textView))
            parent.recalculateHeight(textView)
            parent.onTextChange?()
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
                    AttributedStringConverter.applyLink(in: textView, url: url)
                    textView.textStorage?.removeAttribute(
                        AttributedStringConverter.markdownSourceKey,
                        range: NSRange(location: 0, length: textView.string.count)
                    )
                    parent.document.updateBlockText(id: parent.blockId, text: markdownFromTextView(textView))
                    parent.recalculateHeight(textView)
                    parent.onTextChange?()
                }
            }
        }

        func textView(
            _ textView: NSTextView,
            shouldChangeTextIn affectedCharRange: NSRange,
            replacementString: String?
        ) -> Bool {
            // Redirect typing to page picker search when active
            if !suppressChanges,
               parent.document.pagePickerBlockId == parent.blockId,
               let text = replacementString, !text.isEmpty {
                parent.document.pagePickerSearch += text
                parent.document.pagePickerSelectedIndex = 0
                return false
            }
            lastReplacementString = replacementString
            return true
        }

        func textDidChange(_ notification: Notification) {
            guard !suppressChanges, !isProgrammaticViewUpdateInFlight else { return }
            guard let textView = notification.object as? NSTextView else { return }
            isEditing = true
            defer { isEditing = false }

            textView.textStorage?.removeAttribute(
                AttributedStringConverter.markdownSourceKey,
                range: NSRange(location: 0, length: textView.string.count)
            )

            normalizeInlineMarkdownIfNeeded(textView)

            // Clear multi-block selection when typing
            if !parent.document.selectedBlockIds.isEmpty {
                parent.document.clearBlockSelection()
            }
            if parent.document.multiBlockTextSelection != nil {
                parent.document.clearMultiBlockTextSelection()
            }

            // Persist block text in markdown form so inline styles round-trip to disk.
            parent.document.updateBlockText(id: parent.blockId, text: markdownFromTextView(textView))

            // Slash command detection (skip title block)
            let isTitleBlock = parent.document.titleBlock?.id == parent.blockId
            if !isTitleBlock, textView.string.hasPrefix("/") {
                if parent.document.slashMenuBlockId != parent.blockId {
                    parent.document.slashMenuBlockId = parent.blockId
                }
                parent.document.slashMenuFilter = String(textView.string.dropFirst(1))
                parent.document.slashMenuSelectedIndex = 0
            } else if parent.document.slashMenuBlockId == parent.blockId {
                parent.document.dismissSlashMenu()
            }

            // Auto-detect markdown prefixes (e.g. "## ", "- ", "- [ ] ", "> ")
            // Skip title block to avoid converting heading to other types
            if !isTitleBlock {
                autoDetectMarkdownPrefix(textView)
            }

            parent.recalculateHeight(textView)
            parent.onTextChange?()
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard !isProgrammaticViewUpdateInFlight else { return }
            guard let textView = notification.object as? NSTextView else { return }
            if parent.document.multiBlockTextSelection != nil {
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.parent.document.selectionRect = nil
                    self.parent.document.selectionBlockId = nil
                }
                return
            }
            let range = textView.selectedRange()
            if range.length > 0 {
                // firstRect returns screen coordinates (bottom-left origin),
                // which matches NSPanel.setFrame coordinate space.
                let screenRect = textView.firstRect(forCharacterRange: range, actualRange: nil)
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    guard !self.isProgrammaticViewUpdateInFlight else { return }
                    if self.parent.document.selectionRect != screenRect ||
                        self.parent.document.selectionBlockId != self.parent.blockId {
                        self.parent.document.selectionRect = screenRect
                        self.parent.document.selectionBlockId = self.parent.blockId
                    }
                }
            } else {
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    guard !self.isProgrammaticViewUpdateInFlight else { return }
                    if self.parent.document.selectionRect != nil ||
                        self.parent.document.selectionBlockId != nil {
                        self.parent.document.selectionRect = nil
                        self.parent.document.selectionBlockId = nil
                    }
                }
            }
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

            withProgrammaticViewUpdate {
                textView.textStorage?.setAttributedString(
                    AttributedStringConverter.attributedString(
                        from: newText,
                        font: parent.font,
                        textColor: parent.textColor
                    )
                )
                textView.setSelectedRange(NSRange(location: (newText as NSString).length, length: 0))
                textView.typingAttributes = [
                    .font: parent.font,
                    .foregroundColor: parent.textColor
                ]
            }
        }

        func markdownFromTextView(_ textView: NSTextView) -> String {
            guard let storage = textView.textStorage else { return textView.string }
            return AttributedStringConverter.markdown(from: storage)
        }

        private func normalizeInlineMarkdownIfNeeded(_ textView: NSTextView) {
            guard shouldNormalizeInlineMarkdown() else { return }
            guard let storage = textView.textStorage else { return }

            let currentSelection = textView.selectedRange()
            let markdownStart = markdownOffset(
                forDisplayOffset: currentSelection.location,
                in: storage
            )
            let markdownEnd = markdownOffset(
                forDisplayOffset: currentSelection.location + currentSelection.length,
                in: storage
            )
            let markdown = AttributedStringConverter.markdown(from: storage)
            let normalized = AttributedStringConverter.attributedString(
                from: markdown,
                font: parent.font,
                textColor: parent.textColor
            )
            let normalizedLength = (normalized.string as NSString).length
            let needsRewrite = storage.string != normalized.string
                || normalizedLength != (markdown as NSString).length
            guard needsRewrite else { return }

            let displayStart = displayOffset(forMarkdownOffset: markdownStart, markdown: markdown)
            let displayEnd = displayOffset(forMarkdownOffset: markdownEnd, markdown: markdown)
            let mappedLocation = min(displayStart, normalizedLength)
            let mappedLength = min(max(0, displayEnd - displayStart), max(0, normalizedLength - mappedLocation))

            withProgrammaticViewUpdate {
                storage.setAttributedString(normalized)
                textView.setSelectedRange(NSRange(location: mappedLocation, length: mappedLength))
                textView.typingAttributes = [
                    .font: parent.font,
                    .foregroundColor: parent.textColor
                ]
            }
        }

        private func shouldNormalizeInlineMarkdown() -> Bool {
            let replacement = lastReplacementString ?? ""
            defer { lastReplacementString = nil }

            if replacement.contains("*") || replacement.contains("`")
                || replacement.contains("~") || replacement.contains("[") {
                return true
            }
            // Handle paste operations where replacement string may be nil.
            if replacement.isEmpty {
                guard let textView = textView else { return false }
                let nsString = textView.string as NSString
                let cursor = textView.selectedRange().location
                let scanStart = max(0, cursor - 3)
                let scanLength = min(6, nsString.length - scanStart)
                if scanLength > 0 {
                    let neighborhood = nsString.substring(with: NSRange(location: scanStart, length: scanLength))
                    return neighborhood.contains("*") || neighborhood.contains("`")
                        || neighborhood.contains("~") || neighborhood.contains("[")
                }
            }
            return false
        }

        private func markdownOffset(forDisplayOffset displayOffset: Int, in attributed: NSAttributedString) -> Int {
            let clamped = max(0, min(displayOffset, attributed.length))
            let prefix = attributed.attributedSubstring(from: NSRange(location: 0, length: clamped))
            let markdownPrefix = AttributedStringConverter.markdown(from: prefix)
            return (markdownPrefix as NSString).length
        }

        private func displayOffset(forMarkdownOffset markdownOffset: Int, markdown: String) -> Int {
            let markdownNSString = markdown as NSString
            let clamped = max(0, min(markdownOffset, markdownNSString.length))
            let prefix = markdownNSString.substring(to: clamped)
            let renderedPrefix = AttributedStringConverter.attributedString(
                from: prefix,
                font: parent.font,
                textColor: parent.textColor
            )
            return renderedPrefix.length
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if parent.document.hasMultiBlockTextSelection,
               (commandSelector == #selector(NSResponder.deleteBackward(_:))
                || commandSelector == #selector(NSResponder.deleteForward(_:))) {
                parent.document.deleteMultiBlockSelectedText()
                return true
            }

            // Delete all selected blocks (e.g. Cmd+A then Backspace)
            if (commandSelector == #selector(NSResponder.deleteBackward(_:))
                || commandSelector == #selector(NSResponder.deleteForward(_:))),
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

            // Page picker intercepts (when active)
            if parent.document.pagePickerBlockId == parent.blockId {
                if commandSelector == #selector(NSResponder.moveUp(_:)) {
                    if parent.document.pagePickerSelectedIndex > 0 {
                        parent.document.pagePickerSelectedIndex -= 1
                    }
                    return true
                }
                if commandSelector == #selector(NSResponder.moveDown(_:)) {
                    let count = min(parent.document.filteredPagePickerEntries.count, 8)
                    if parent.document.pagePickerSelectedIndex < count - 1 {
                        parent.document.pagePickerSelectedIndex += 1
                    }
                    return true
                }
                if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                    parent.document.executePagePicker()
                    return true
                }
                if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                    parent.document.dismissPagePicker()
                    return true
                }
                if commandSelector == #selector(NSResponder.deleteBackward(_:)) {
                    if !parent.document.pagePickerSearch.isEmpty {
                        parent.document.pagePickerSearch.removeLast()
                        parent.document.pagePickerSelectedIndex = 0
                    } else {
                        parent.document.dismissPagePicker()
                    }
                    return true
                }
            }

            // Enter — split block
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                if parent.isMultiline { return false }
                let displayPos = textView.selectedRange().location
                let mdPos = markdownOffset(forDisplayOffset: displayPos, in: textView.attributedString())
                parent.document.splitBlock(id: parent.blockId, atOffset: mdPos)
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
    private static let liveTextViews = NSHashTable<BlockNSTextView>.weakObjects()

    var onBecomeFirstResponder: (() -> Void)?
    var onMouseDownAction: (() -> Void)?
    var onResignFirstResponder: (() -> Void)?
    var placeholderString: String?
    var placeholderFont: NSFont?

    // Formatting action closures
    var blockId: UUID?
    var formatBoldAction: (() -> Void)?
    var formatItalicAction: (() -> Void)?
    var formatCodeAction: (() -> Void)?
    var formatLinkAction: (() -> Void)?
    var formatStrikethroughAction: (() -> Void)?
    var undoAction: (() -> Void)?
    var redoAction: (() -> Void)?
    var selectAllBlocksAction: (() -> Void)?
    var blockTypeShortcutAction: ((String) -> Void)?
    var onDragOutOfBlock: ((Int, NSPoint) -> Void)?
    var onMultiBlockSelectionDrag: ((NSPoint) -> Void)?
    var onMultiBlockSelectionEnd: (() -> Void)?
    var onShiftClick: (() -> Void)?
    var onPasteImage: (() -> Bool)?
    var copySelectionAction: (() -> Bool)?
    var cutSelectionAction: (() -> Bool)?
    var onFrameWidthChanged: (() -> Void)?
    var isInBlockSelection = false
    private var lastKnownWidth: CGFloat = 0
    private var dragSelectionAnchorOffset = 0
    private var dragStartWindowPoint = NSPoint.zero
    private var selectionDragTimer: Timer?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            Self.liveTextViews.remove(self)
        } else {
            Self.liveTextViews.add(self)
        }
    }

    override func setFrameSize(_ newSize: NSSize) {
        let widthChanged = abs(newSize.width - lastKnownWidth) > 0.5
        super.setFrameSize(newSize)
        if widthChanged && newSize.width > 0 {
            lastKnownWidth = newSize.width
            onFrameWidthChanged?()
        }
    }

    deinit {
        finishSelectionDragMonitoring()
        Self.liveTextViews.remove(self)
    }

    override func didChangeText() {
        super.didChangeText()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        if string.isEmpty, let placeholder = placeholderString {
            let font = placeholderFont ?? .systemFont(ofSize: EditorTypography.bodyFontSize)
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

    override func resignFirstResponder() -> Bool {
        let result = super.resignFirstResponder()
        if result {
            onResignFirstResponder?()
        }
        return result
    }

    override func selectAll(_ sender: Any?) {
        if selectedRange().length < string.count && !string.isEmpty {
            // First Cmd+A: select all text within this block
            setSelectedRange(NSRange(location: 0, length: string.count))
        } else {
            // Second Cmd+A (or empty block): select all blocks
            selectAllBlocksAction?()
        }
    }

    // Reject all external drops to prevent UUID string insertion from drag-and-drop
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        return false
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        return []
    }

    override func paste(_ sender: Any?) {
        if let handler = onPasteImage,
           handler() {
            return // Image paste handled
        }

        super.paste(sender)
    }

    // MARK: - Cross-Block Selection

    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.shift) {
            onShiftClick?()
            return
        }
        let localPoint = convert(event.locationInWindow, from: nil)
        dragSelectionAnchorOffset = textOffset(for: localPoint)
        dragStartWindowPoint = event.locationInWindow
        beginSelectionDragMonitoring()
        onMouseDownAction?()
        super.mouseDown(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        if isInBlockSelection {
            handleSelectionDrag(at: event.locationInWindow)
            return
        }
        if shouldStartCrossBlockSelection(at: event.locationInWindow) {
            handleSelectionDrag(at: event.locationInWindow)
            return
        }
        super.mouseDragged(with: event)
        handleSelectionDrag(at: event.locationInWindow)
    }

    override func mouseUp(with event: NSEvent) {
        let wasInBlockSelection = isInBlockSelection
        finishSelectionDragMonitoring()
        if wasInBlockSelection { return }
        super.mouseUp(with: event)
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil {
            finishSelectionDragMonitoring()
        }
        super.viewWillMove(toWindow: newWindow)
    }

    // MARK: - Keyboard Shortcuts

    override func keyDown(with event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        if handleBlockTypeShortcut(event, flags: flags) {
            return
        }

        if flags == .command {
            switch event.charactersIgnoringModifiers {
            case "z":
                undoAction?()
                return
            case "v":
                paste(nil)
                return
            case "c":
                if copySelectionAction?() == true {
                    return
                }
            case "x":
                if cutSelectionAction?() == true {
                    return
                }
            case "b":
                formatBoldAction?()
                return
            case "i":
                formatItalicAction?()
                return
            case "e":
                formatCodeAction?()
                return
            case "k":
                if selectedRange().length > 0 {
                    formatLinkAction?()
                    return
                }
            default:
                break
            }
        }

        if flags.contains([.command, .shift]) && !flags.contains(.option) && !flags.contains(.control) {
            if let chars = event.charactersIgnoringModifiers?.lowercased() {
                if chars == "x" {
                    formatStrikethroughAction?()
                    return
                }
                if chars == "z" {
                    redoAction?()
                    return
                }
            }
        }

        super.keyDown(with: event)
    }

    override func copy(_ sender: Any?) {
        if copySelectionAction?() == true {
            return
        }
        super.copy(sender)
    }

    override func cut(_ sender: Any?) {
        if cutSelectionAction?() == true {
            return
        }
        super.cut(sender)
    }

    private func handleBlockTypeShortcut(_ event: NSEvent, flags: NSEvent.ModifierFlags) -> Bool {
        let isCommandOptionOnly = flags.contains([.command, .option])
            && !flags.contains(.shift)
            && !flags.contains(.control)
        guard isCommandOptionOnly else { return false }

        // Use keyCode exclusively — charactersIgnoringModifiers is unreliable
        // when Option is held (returns special characters on many layouts)
        let keyCodeToAction: [UInt16: String] = [
            29: "paragraph",        // 0
            18: "heading1",         // 1
            19: "heading2",         // 2
            20: "heading3",         // 3
            21: "taskItem",         // 4
            23: "bulletListItem",   // 5
            22: "numberedListItem", // 6
            26: "toggle",           // 7
            28: "codeBlock",        // 8
            25: "createPage",       // 9
        ]
        guard let action = keyCodeToAction[event.keyCode] else { return false }

        if let handler = blockTypeShortcutAction {
            handler(action)
        } else {
            NotificationCenter.default.post(name: .blockTypeShortcut, object: action)
        }
        return true
    }

    static func blockId(atWindowPoint point: NSPoint, in window: NSWindow) -> UUID? {
        for textView in liveTextViews.allObjects.reversed() {
            guard textView.window === window,
                  !textView.isHiddenOrHasHiddenAncestor,
                  let blockId = textView.blockId else { continue }
            let frameInWindow = textView.convert(textView.bounds, to: nil)
            if frameInWindow.contains(point) {
                return blockId
            }
        }
        return nil
    }

    static func textPosition(atWindowPoint point: NSPoint, in window: NSWindow) -> (blockId: UUID, offset: Int)? {
        let visibleTextViews = liveTextViews.allObjects.compactMap { textView -> (BlockNSTextView, NSRect, UUID)? in
            guard textView.window === window,
                  !textView.isHiddenOrHasHiddenAncestor,
                  let blockId = textView.blockId else {
                return nil
            }
            return (textView, textView.convert(textView.bounds, to: nil), blockId)
        }

        guard !visibleTextViews.isEmpty else { return nil }

        if let exactMatch = visibleTextViews.reversed().first(where: { $0.1.contains(point) }) {
            let localPoint = exactMatch.0.convert(point, from: nil)
            return (exactMatch.2, exactMatch.0.textOffset(for: localPoint))
        }

        guard let nearest = visibleTextViews.min(by: { distance(from: point, to: $0.1) < distance(from: point, to: $1.1) }) else {
            return nil
        }

        let clampedPoint = NSPoint(
            x: min(max(point.x, nearest.1.minX), nearest.1.maxX),
            y: min(max(point.y, nearest.1.minY), nearest.1.maxY)
        )
        let localPoint = nearest.0.convert(clampedPoint, from: nil)
        return (nearest.2, nearest.0.textOffset(for: localPoint))
    }

    static func textPosition(for blockId: UUID, atWindowPoint point: NSPoint, in window: NSWindow) -> (blockId: UUID, offset: Int)? {
        guard let textView = liveTextViews.allObjects.first(where: {
            $0.window === window && !$0.isHiddenOrHasHiddenAncestor && $0.blockId == blockId
        }) else {
            return nil
        }

        let frameInWindow = textView.convert(textView.bounds, to: nil)
        let clampedPoint = NSPoint(
            x: min(max(point.x, frameInWindow.minX), frameInWindow.maxX),
            y: min(max(point.y, frameInWindow.minY), frameInWindow.maxY)
        )
        let localPoint = textView.convert(clampedPoint, from: nil)
        return (blockId, textView.textOffset(for: localPoint))
    }

    private func textOffset(for localPoint: NSPoint) -> Int {
        guard let layoutManager = layoutManager,
              let textContainer = textContainer else {
            return (string as NSString).length
        }

        let adjustedPoint = NSPoint(
            x: max(0, localPoint.x - textContainerInset.width),
            y: max(0, localPoint.y - textContainerInset.height)
        )

        guard layoutManager.numberOfGlyphs > 0 else { return 0 }
        let glyphIndex = layoutManager.glyphIndex(for: adjustedPoint, in: textContainer)
        let characterIndex = layoutManager.characterIndexForGlyph(at: glyphIndex)
        return min(characterIndex, (string as NSString).length)
    }

    private static func distance(from point: NSPoint, to rect: NSRect) -> CGFloat {
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return hypot(dx, dy)
    }

    private func beginSelectionDragMonitoring() {
        finishSelectionDragMonitoring()
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.pollSelectionDrag()
        }
        selectionDragTimer = timer
        RunLoop.main.add(timer, forMode: .common)
        RunLoop.main.add(timer, forMode: .eventTracking)
    }

    private func pollSelectionDrag() {
        guard let window else {
            finishSelectionDragMonitoring()
            return
        }
        if (NSEvent.pressedMouseButtons & 1) == 0 {
            finishSelectionDragMonitoring()
            return
        }
        handleSelectionDrag(at: window.mouseLocationOutsideOfEventStream)
    }

    private func handleSelectionDrag(at point: NSPoint) {
        if isInBlockSelection {
            onMultiBlockSelectionDrag?(point)
            return
        }
        let dragDistance = hypot(point.x - dragStartWindowPoint.x, point.y - dragStartWindowPoint.y)
        guard dragDistance >= 3,
              shouldStartCrossBlockSelection(at: point) else { return }
        isInBlockSelection = true
        onDragOutOfBlock?(dragSelectionAnchorOffset, point)
    }

    private func shouldStartCrossBlockSelection(at point: NSPoint) -> Bool {
        guard let blockId else { return false }

        let localPoint = convert(point, from: nil)
        if !bounds.insetBy(dx: 0, dy: -2).contains(localPoint) {
            return true
        }

        guard let window else { return false }
        guard let target = Self.textPosition(atWindowPoint: point, in: window) else {
            return false
        }
        return target.blockId != blockId
    }

    private func finishSelectionDragMonitoring() {
        if let selectionDragTimer {
            selectionDragTimer.invalidate()
            self.selectionDragTimer = nil
        }

        let wasInBlockSelection = isInBlockSelection
        isInBlockSelection = false
        if wasInBlockSelection {
            onMultiBlockSelectionEnd?()
        }
    }
}
