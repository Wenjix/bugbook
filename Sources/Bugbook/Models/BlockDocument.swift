import Foundation
import SwiftUI

@MainActor
@Observable
class BlockDocument {
    var blocks: [Block] {
        didSet { contentVersion += 1 }
    }
    /// Lightweight counter incremented on every `blocks` mutation. Use this
    /// in `onChange` instead of comparing the full `[Block]` array.
    var contentVersion: Int = 0
    var focusedBlockId: UUID?
    var cursorPosition: Int = 0
    var slashMenuBlockId: UUID?
    var slashMenuSelectedIndex: Int = 0
    var slashMenuFilter: String = ""
    var blockMenuBlockId: UUID?
    var icon: String?
    var coverUrl: String?
    var coverPosition: Double = 50
    var fullWidth: Bool = false
    var showPagePicker: Bool = false
    var pagePickerBlockId: UUID?
    var showTemplatePicker: Bool = false
    var selectedBlockIds: Set<UUID> = []
    var moveBlockId: UUID?
    var selectionRect: CGRect?
    var selectionBlockId: UUID?
    @ObservationIgnored var blockSelectionAnchor: UUID?
    @ObservationIgnored private var suppressNextEditorTapAfterBlockSelection = false
    @ObservationIgnored var registeredBlockFrames: [UUID: CGRect] = [:]

    var titleBlock: Block? {
        guard let first = blocks.first,
              first.type == .heading, first.headingLevel == 1 else { return nil }
        return first
    }

    @ObservationIgnored var onCreateDatabase: ((String) -> String?)?
    @ObservationIgnored var onCreateSubPage: ((String) -> String?)?
    @ObservationIgnored var onDeleteSubPage: ((String) -> Void)?
    @ObservationIgnored var onNavigateToPage: ((String) -> Void)?
    @ObservationIgnored var onOpenDatabaseTab: ((String) -> Void)?
    @ObservationIgnored var onMoveBlock: ((UUID, String) -> Void)?
    @ObservationIgnored var availablePages: [FileEntry] = []
    @ObservationIgnored var filePath: String?
    @ObservationIgnored var workspacePath: String?

    @ObservationIgnored private var undoStack: [[Block]] = []
    @ObservationIgnored private var redoStack: [[Block]] = []
    @ObservationIgnored private var persistsBlockIDs: Bool = false

    var markdown: String {
        let metadata = MarkdownBlockParser.Metadata(
            icon: icon,
            coverUrl: coverUrl,
            coverPosition: coverPosition,
            fullWidth: fullWidth
        )
        let metaStr = MarkdownBlockParser.serializeMetadata(metadata)
        let blockStr = MarkdownBlockParser.serialize(blocks, includeBlockIDComments: persistsBlockIDs)
        if metaStr.isEmpty {
            return blockStr
        }
        return metaStr + "\n" + blockStr
    }

    init(markdown: String) {
        let (metadata, content) = MarkdownBlockParser.parseMetadata(markdown)
        self.persistsBlockIDs = content.contains("<!-- block-id:")
        self.icon = metadata.icon
        self.coverUrl = metadata.coverUrl
        self.coverPosition = metadata.coverPosition
        self.fullWidth = metadata.fullWidth
        self.blocks = MarkdownBlockParser.parse(content)
    }

    func block(for id: UUID) -> Block? {
        for block in blocks {
            if block.id == id { return block }
            if block.type == .column || block.type == .toggle {
                if let child = block.children.first(where: { $0.id == id }) {
                    return child
                }
            }
        }
        return nil
    }

    func index(for id: UUID) -> Int? {
        blocks.firstIndex { $0.id == id }
    }

    /// Locates a block in the hierarchy. Returns (topLevelIndex, childIndex).
    /// childIndex is nil for top-level blocks, or the index within a column's children.
    func blockLocation(for id: UUID) -> (topLevel: Int, child: Int?)? {
        for (i, block) in blocks.enumerated() {
            if block.id == id { return (i, nil) }
            if block.type == .column || block.type == .toggle {
                if let childIdx = block.children.firstIndex(where: { $0.id == id }) {
                    return (i, childIdx)
                }
            }
        }
        return nil
    }

    /// Safely update a block's text whether it's top-level or inside a column.
    func updateBlockText(id: UUID, text: String) {
        guard let loc = blockLocation(for: id) else { return }
        if let childIdx = loc.child {
            blocks[loc.topLevel].children[childIdx].text = text
        } else {
            blocks[loc.topLevel].text = text
        }
    }

    /// Safely update a block's properties whether it's top-level or inside a column.
    func updateBlockProperty(id: UUID, _ mutate: (inout Block) -> Void) {
        guard let loc = blockLocation(for: id) else { return }
        if let childIdx = loc.child {
            mutate(&blocks[loc.topLevel].children[childIdx])
        } else {
            mutate(&blocks[loc.topLevel])
        }
    }

    /// Remove a block from wherever it lives (top-level or column child).
    /// Returns the extracted block with columnIndex reset. Auto-dissolves columns.
    private func extractBlock(id: UUID) -> Block? {
        guard let loc = blockLocation(for: id) else { return nil }
        if let childIdx = loc.child {
            var extracted = blocks[loc.topLevel].children.remove(at: childIdx)
            extracted.columnIndex = 0
            dissolveColumnIfNeeded(at: loc.topLevel)
            return extracted
        } else {
            return blocks.remove(at: loc.topLevel)
        }
    }

    /// If a column block has only one column of content left, unwrap all its children back to top level.
    private func dissolveColumnIfNeeded(at index: Int) {
        guard index < blocks.count, blocks[index].type == .column else { return }
        if blocks[index].children.isEmpty {
            blocks.remove(at: index)
            return
        }
        let uniqueColumns = Set(blocks[index].children.map(\.columnIndex))
        if uniqueColumns.count <= 1 {
            // Only one column left — promote all children back to top level
            let children = blocks[index].children.map { block -> Block in
                var b = block
                b.columnIndex = 0
                return b
            }
            blocks.remove(at: index)
            for (i, child) in children.enumerated() {
                blocks.insert(child, at: index + i)
            }
        }
    }

    // MARK: - Column Creation (Drag-to-Right)

    static let maxColumns = 5

    /// Number of distinct columns in a column block.
    private func columnCount(at index: Int) -> Int {
        Set(blocks[index].children.map(\.columnIndex)).count
    }

    /// Creates or extends a column layout by dropping a block to the right of a target.
    func createColumnFromDrop(droppedId: UUID, targetId: UUID) {
        guard droppedId != targetId,
              blockLocation(for: droppedId) != nil,
              let targetLoc = blockLocation(for: targetId) else { return }

        // Don't allow dropping column blocks or nested columns
        guard let droppedBlock = block(for: droppedId) else { return }
        if droppedBlock.type == .column { return }

        // If target is inside a column, add as a new column to that column block
        if targetLoc.child != nil {
            let columnIdx = targetLoc.topLevel
            guard columnCount(at: columnIdx) < Self.maxColumns else { return }
            saveUndo()
            let columnBlockId = blocks[columnIdx].id
            guard var extracted = extractBlock(id: droppedId) else { return }
            // Re-find column (indices may have shifted after extraction)
            if let newIdx = index(for: columnBlockId) {
                let newColIndex = (blocks[newIdx].children.map(\.columnIndex).max() ?? -1) + 1
                extracted.columnIndex = newColIndex
                blocks[newIdx].children.append(extracted)
            }
            return
        }

        // Target is top-level
        let targetBlock = blocks[targetLoc.topLevel]

        if targetBlock.type == .column {
            // Target IS a column block — add a new column to it
            guard columnCount(at: targetLoc.topLevel) < Self.maxColumns else { return }
            saveUndo()
            guard var extracted = extractBlock(id: droppedId) else { return }
            if let newIdx = index(for: targetBlock.id) {
                let newColIndex = (blocks[newIdx].children.map(\.columnIndex).max() ?? -1) + 1
                extracted.columnIndex = newColIndex
                blocks[newIdx].children.append(extracted)
            }
        } else {
            // Target is a regular block — wrap both in a new column
            saveUndo()
            guard var extracted = extractBlock(id: droppedId) else { return }
            guard let newTargetIdx = index(for: targetId) else { return }
            var target = blocks[newTargetIdx]
            target.columnIndex = 0
            extracted.columnIndex = 1
            let columnBlock = Block(
                type: .column,
                children: [target, extracted]
            )
            blocks[newTargetIdx] = columnBlock
        }
    }

    /// Adds a block into a specific column at a specific position within a column block.
    func addBlockToColumn(blockId: UUID, columnBlockId: UUID, columnIndex: Int, position: Int) {
        guard blockId != columnBlockId,
              let colTopIdx = index(for: columnBlockId),
              blocks[colTopIdx].type == .column else { return }

        saveUndo()
        guard var extracted = extractBlock(id: blockId) else { return }
        extracted.columnIndex = columnIndex

        // Re-find the column block (may have shifted)
        guard let newColIdx = index(for: columnBlockId) else { return }

        // Find insertion point: get children in this column, find the one at `position`
        let sameColIndices = blocks[newColIdx].children.enumerated()
            .filter { $0.element.columnIndex == columnIndex }
            .map(\.offset)

        let insertAt: Int
        if position >= sameColIndices.count {
            // Insert after the last block in this column
            insertAt = (sameColIndices.last ?? blocks[newColIdx].children.count - 1) + 1
        } else {
            // Insert before the block at this position
            insertAt = sameColIndices[position]
        }
        blocks[newColIdx].children.insert(extracted, at: min(insertAt, blocks[newColIdx].children.count))
    }

    // MARK: - Mutations

    private func saveUndo() {
        undoStack.append(blocks)
        if undoStack.count > 30 { undoStack.removeFirst() }
        redoStack.removeAll()
    }

    @discardableResult
    func splitBlock(id: UUID, atOffset offset: Int) -> UUID {
        guard let loc = blockLocation(for: id) else { return UUID() }

        // If inside a column or toggle, split creates a new block in the same parent
        if let childIdx = loc.child {
            let parentBlock = blocks[loc.topLevel]
            let block = parentBlock.children[childIdx]
            let clamped = min(offset, block.text.count)
            let splitAt = block.text.index(block.text.startIndex, offsetBy: clamped)
            let before = String(block.text[..<splitAt])
            let after = String(block.text[splitAt...])

            // Empty child in toggle → exit toggle
            if parentBlock.type == .toggle, before.isEmpty, after.isEmpty {
                saveUndo()
                blocks[loc.topLevel].children.remove(at: childIdx)
                let newBlock = Block(type: .paragraph)
                blocks.insert(newBlock, at: loc.topLevel + 1)
                focusedBlockId = newBlock.id
                cursorPosition = 0
                return newBlock.id
            }

            saveUndo()
            blocks[loc.topLevel].children[childIdx].text = before
            let newBlock = Block(type: .paragraph, text: after, columnIndex: block.columnIndex)
            blocks[loc.topLevel].children.insert(newBlock, at: childIdx + 1)
            focusedBlockId = newBlock.id
            cursorPosition = 0
            return newBlock.id
        }

        let idx = loc.topLevel
        let block = blocks[idx]
        let clamped = min(offset, block.text.count)
        let splitAt = block.text.index(block.text.startIndex, offsetBy: clamped)
        let before = String(block.text[..<splitAt])
        let after = String(block.text[splitAt...])

        // Toggle title → Enter creates child inside toggle
        if block.type == .toggle {
            saveUndo()
            blocks[idx].text = before
            blocks[idx].isExpanded = true
            let newChild = Block(type: .paragraph, text: after)
            blocks[idx].children.insert(newChild, at: 0)
            focusedBlockId = newChild.id
            cursorPosition = 0
            return newChild.id
        }

        saveUndo()

        let continuableTypes: [BlockType] = [.bulletListItem, .numberedListItem, .taskItem, .blockquote]

        // Enter on empty list/quote item → convert to paragraph (exit list)
        if before.isEmpty, after.isEmpty, continuableTypes.contains(block.type) {
            blocks[idx].type = .paragraph
            blocks[idx].listDepth = 0
            focusedBlockId = block.id
            cursorPosition = 0
            return block.id
        }

        blocks[idx].text = before

        // New block inherits list type from parent
        let newBlock: Block
        if continuableTypes.contains(block.type) {
            newBlock = Block(type: block.type, text: after, listDepth: block.listDepth)
        } else {
            newBlock = Block(type: .paragraph, text: after)
        }
        blocks.insert(newBlock, at: idx + 1)

        focusedBlockId = newBlock.id
        cursorPosition = 0
        return newBlock.id
    }

    @discardableResult
    func mergeWithPrevious(id: UUID) -> Int? {
        guard let loc = blockLocation(for: id) else { return nil }

        if let childIdx = loc.child {
            let block = blocks[loc.topLevel].children[childIdx]
            let colIndex = block.columnIndex

            // Find previous block in same column
            let prevInCol = blocks[loc.topLevel].children[..<childIdx]
                .enumerated()
                .filter { $0.element.columnIndex == colIndex }
                .last

            if let prev = prevInCol {
                // Merge with previous block in same column
                saveUndo()
                let prevText = blocks[loc.topLevel].children[prev.offset].text
                let curText = blocks[loc.topLevel].children[childIdx].text
                let joinPoint = prevText.count
                let prevId = blocks[loc.topLevel].children[prev.offset].id
                blocks[loc.topLevel].children[prev.offset].text = prevText + curText
                blocks[loc.topLevel].children.remove(at: childIdx)
                focusedBlockId = prevId
                cursorPosition = joinPoint
                return joinPoint
            } else if blocks[loc.topLevel].type == .toggle {
                // First child in toggle — merge into toggle title
                saveUndo()
                let childText = blocks[loc.topLevel].children[childIdx].text
                let joinPoint = blocks[loc.topLevel].text.count
                blocks[loc.topLevel].text += childText
                blocks[loc.topLevel].children.remove(at: childIdx)
                focusedBlockId = blocks[loc.topLevel].id
                cursorPosition = joinPoint
                return joinPoint
            } else {
                // First block in this column — extract from column
                saveUndo()
                var extracted = blocks[loc.topLevel].children.remove(at: childIdx)
                extracted.columnIndex = 0
                dissolveColumnIfNeeded(at: loc.topLevel)
                let insertIdx = loc.topLevel
                blocks.insert(extracted, at: insertIdx)
                focusedBlockId = extracted.id
                cursorPosition = 0
                return 0
            }
        }

        let idx = loc.topLevel
        guard idx > 0 else { return nil }
        saveUndo()

        let prevText = blocks[idx - 1].text
        let curText = blocks[idx].text
        let joinPoint = prevText.count
        let prevId = blocks[idx - 1].id

        blocks[idx - 1].text = prevText + curText
        blocks.remove(at: idx)

        focusedBlockId = prevId
        cursorPosition = joinPoint
        return joinPoint
    }

    func moveBlock(from: Int, to: Int) {
        guard from != to, from >= 0, from < blocks.count,
              to >= 0, to <= blocks.count else { return }
        saveUndo()
        let block = blocks.remove(at: from)
        let adjusted = to > from ? to - 1 : to
        blocks.insert(block, at: adjusted)
    }

    /// Move a block by ID to a target index, handling extraction from columns.
    func moveBlockById(_ id: UUID, toIndex: Int) {
        guard let loc = blockLocation(for: id) else { return }
        saveUndo()
        var extracted: Block
        if let childIdx = loc.child {
            extracted = blocks[loc.topLevel].children.remove(at: childIdx)
            extracted.columnIndex = 0
            dissolveColumnIfNeeded(at: loc.topLevel)
        } else {
            extracted = blocks.remove(at: loc.topLevel)
        }
        let adjustedIdx = min(toIndex, blocks.count)
        blocks.insert(extracted, at: adjustedIdx)
    }

    func changeBlockType(id: UUID, to type: BlockType) {
        guard blockLocation(for: id) != nil else { return }
        saveUndo()
        // Rescue pageLinkName into text when converting from pageLink
        if let current = block(for: id), current.type == .pageLink, type != .pageLink {
            updateBlockProperty(id: id) { block in
                if block.text.isEmpty, !block.pageLinkName.isEmpty {
                    block.text = block.pageLinkName
                }
            }
        }
        updateBlockProperty(id: id) { block in
            block.type = type
            if type == .heading {
                block.headingLevel = 1
            } else {
                block.headingLevel = 0
            }
        }
    }

    func setHeadingLevel(id: UUID, level: Int) {
        updateBlockProperty(id: id) { block in
            block.type = .heading
            block.headingLevel = level
        }
    }

    func toggleCheck(id: UUID) {
        updateBlockProperty(id: id) { block in
            block.isChecked.toggle()
        }
    }

    func indent(id: UUID) {
        updateBlockProperty(id: id) { block in
            block.listDepth += 1
        }
    }

    func outdent(id: UUID) {
        updateBlockProperty(id: id) { block in
            if block.listDepth > 0 { block.listDepth -= 1 }
        }
    }

    func deleteBlock(id: UUID) {
        guard let loc = blockLocation(for: id) else { return }

        // Capture pageLink name before removing so we can trash the child file
        let deletedBlock = block(for: id)
        let deletedPageName = (deletedBlock?.type == .pageLink) ? deletedBlock?.pageLinkName : nil

        if let childIdx = loc.child {
            saveUndo()
            unregisterFramesRecursively(for: blocks[loc.topLevel].children[childIdx])
            blocks[loc.topLevel].children.remove(at: childIdx)
            dissolveColumnIfNeeded(at: loc.topLevel)
            guard !blocks.isEmpty else {
                let placeholder = Block(type: .paragraph)
                blocks.append(placeholder)
                focusedBlockId = placeholder.id
                cursorPosition = 0
                if let name = deletedPageName, !name.isEmpty { onDeleteSubPage?(name) }
                return
            }
            let focusIdx = min(max(0, loc.topLevel), blocks.count - 1)
            focusedBlockId = blocks[focusIdx].id
            cursorPosition = 0
            if let name = deletedPageName, !name.isEmpty { onDeleteSubPage?(name) }
            return
        }

        let idx = loc.topLevel
        guard blocks.count > 1 else {
            let wasPageLink = blocks[idx].type == .pageLink
            let pageName = blocks[idx].pageLinkName
            unregisterFramesRecursively(for: blocks[idx])
            blocks[idx] = Block(type: .paragraph)
            if wasPageLink, !pageName.isEmpty { onDeleteSubPage?(pageName) }
            return
        }
        saveUndo()
        unregisterFramesRecursively(for: blocks[idx])
        blocks.remove(at: idx)
        ensureTrailingParagraph()
        let focusIdx = min(idx, blocks.count - 1)
        focusedBlockId = blocks[focusIdx].id
        cursorPosition = 0
        if let name = deletedPageName, !name.isEmpty { onDeleteSubPage?(name) }
    }

    func appendEmptyBlock() {
        let newBlock = Block(type: .paragraph)
        blocks.append(newBlock)
        focusedBlockId = newBlock.id
        cursorPosition = 0
    }

    func ensureTrailingParagraph() {
        guard let last = blocks.last else { return }
        if last.type != .paragraph || !last.text.isEmpty {
            blocks.append(Block(type: .paragraph))
        }
    }

    func duplicateBlock(id: UUID) {
        guard let loc = blockLocation(for: id) else { return }
        guard let original = block(for: id) else { return }
        saveUndo()
        let copy = Block(
            type: original.type,
            text: original.text,
            headingLevel: original.headingLevel,
            listDepth: original.listDepth,
            isChecked: original.isChecked,
            language: original.language,
            imageSource: original.imageSource,
            imageAlt: original.imageAlt,
            imageWidth: original.imageWidth,
            databasePath: original.databasePath,
            pageLinkName: original.pageLinkName,
            textColor: original.textColor,
            backgroundColor: original.backgroundColor,
            children: original.children,
            columnIndex: original.columnIndex,
            isExpanded: original.isExpanded
        )
        if let childIdx = loc.child {
            blocks[loc.topLevel].children.insert(copy, at: childIdx + 1)
        } else {
            blocks.insert(copy, at: loc.topLevel + 1)
        }
        focusedBlockId = copy.id
        cursorPosition = 0
    }

    func setTextColor(id: UUID, color: BlockColor) {
        guard blockLocation(for: id) != nil else { return }
        saveUndo()
        updateBlockProperty(id: id) { $0.textColor = color }
    }

    func setBackgroundColor(id: UUID, color: BlockColor) {
        guard blockLocation(for: id) != nil else { return }
        saveUndo()
        updateBlockProperty(id: id) { $0.backgroundColor = color }
    }

    func dismissBlockMenu() {
        blockMenuBlockId = nil
    }

    func undo() {
        guard let prev = undoStack.popLast() else { return }
        redoStack.append(blocks)
        blocks = prev
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(blocks)
        blocks = next
    }

    // MARK: - Slash Commands

    enum SlashCommandAction {
        case blockType(BlockType, headingLevel: Int)
        case linkToPage
        case createPage
        case template
        case imagePicker
    }

    struct SlashCommand {
        let name: String
        let icon: String
        let action: SlashCommandAction
    }

    static let slashCommands: [SlashCommand] = [
        SlashCommand(name: "Text", icon: "text.alignleft", action: .blockType(.paragraph, headingLevel: 0)),
        SlashCommand(name: "Heading 1", icon: "textformat.size.larger", action: .blockType(.heading, headingLevel: 1)),
        SlashCommand(name: "Heading 2", icon: "textformat.size", action: .blockType(.heading, headingLevel: 2)),
        SlashCommand(name: "Heading 3", icon: "textformat.size.smaller", action: .blockType(.heading, headingLevel: 3)),
        SlashCommand(name: "Bullet List", icon: "list.bullet", action: .blockType(.bulletListItem, headingLevel: 0)),
        SlashCommand(name: "Numbered List", icon: "list.number", action: .blockType(.numberedListItem, headingLevel: 0)),
        SlashCommand(name: "To-do", icon: "checkmark.square", action: .blockType(.taskItem, headingLevel: 0)),
        SlashCommand(name: "Quote", icon: "text.quote", action: .blockType(.blockquote, headingLevel: 0)),
        SlashCommand(name: "Code", icon: "chevron.left.forwardslash.chevron.right", action: .blockType(.codeBlock, headingLevel: 0)),
        SlashCommand(name: "Divider", icon: "minus", action: .blockType(.horizontalRule, headingLevel: 0)),
        SlashCommand(name: "Toggle", icon: "chevron.right", action: .blockType(.toggle, headingLevel: 0)),
        SlashCommand(name: "Page", icon: "doc.text", action: .createPage),
        SlashCommand(name: "Link to Page", icon: "link", action: .linkToPage),
        SlashCommand(name: "Image", icon: "photo", action: .imagePicker),
        SlashCommand(name: "Database", icon: "tablecells", action: .blockType(.databaseEmbed, headingLevel: 0)),
        SlashCommand(name: "Template", icon: "doc.on.doc", action: .template),
    ]

    var filteredSlashCommands: [SlashCommand] {
        if slashMenuFilter.isEmpty { return Self.slashCommands }
        return Self.slashCommands.filter { $0.name.localizedStandardContains(slashMenuFilter) }
    }

    func executeSlashCommand() {
        guard let blockId = slashMenuBlockId else { return }
        let commands = filteredSlashCommands
        let idx = min(slashMenuSelectedIndex, commands.count - 1)
        guard idx >= 0, idx < commands.count else {
            dismissSlashMenu()
            return
        }
        let command = commands[idx]

        updateBlockProperty(id: blockId) { $0.text = "" }

        switch command.action {
        case .createPage:
            if let createPage = onCreateSubPage,
               let pagePath = createPage("Untitled") {
                let pageName = (pagePath as NSString).lastPathComponent.replacingOccurrences(of: ".md", with: "")
                saveUndo()
                updateBlockProperty(id: blockId) { block in
                    block.type = .pageLink
                    block.pageLinkName = pageName
                }
            }
            dismissSlashMenu()
            return

        case .linkToPage:
            pagePickerBlockId = blockId
            showPagePicker = true
            dismissSlashMenu()
            return

        case .template:
            showTemplatePicker = true
            dismissSlashMenu()
            return

        case .imagePicker:
            dismissSlashMenu()
            pickAndInsertImage(blockId: blockId)
            return

        case let .blockType(type, headingLevel):
            // Database command needs special handling — creates files via callback
            if type == .databaseEmbed {
                if blockLocation(for: blockId) != nil,
                   let createDb = onCreateDatabase,
                   let dbPath = createDb("Untitled Database") {
                    updateBlockProperty(id: blockId) { block in
                        block.type = .databaseEmbed
                        block.databasePath = dbPath
                    }
                }
                dismissSlashMenu()
                return
            }

            changeBlockType(id: blockId, to: type)
            if type == .heading {
                setHeadingLevel(id: blockId, level: headingLevel)
            }
        }

        dismissSlashMenu()
    }

    func insertPageLink(name: String) {
        guard let blockId = pagePickerBlockId,
              blockLocation(for: blockId) != nil else {
            dismissPagePicker()
            return
        }
        saveUndo()
        updateBlockProperty(id: blockId) { block in
            block.type = .pageLink
            block.pageLinkName = name
            block.text = ""
        }
        dismissPagePicker()
    }

    func dismissPagePicker() {
        showPagePicker = false
        pagePickerBlockId = nil
    }

    func dismissSlashMenu() {
        slashMenuBlockId = nil
        slashMenuFilter = ""
        slashMenuSelectedIndex = 0
    }

    // MARK: - Image Insertion

    /// Copies an image file into the workspace `_assets/` directory and returns the relative path.
    func copyImageToAssets(_ sourceURL: URL) -> String? {
        guard let workspace = workspacePath else { return nil }
        let assetsDir = (workspace as NSString).appendingPathComponent("_assets")
        let fm = FileManager.default
        if !fm.fileExists(atPath: assetsDir) {
            try? fm.createDirectory(atPath: assetsDir, withIntermediateDirectories: true)
        }
        let fileName = sourceURL.lastPathComponent
        var destPath = (assetsDir as NSString).appendingPathComponent(fileName)
        // Avoid overwrites by appending a suffix
        var counter = 1
        let baseName = (fileName as NSString).deletingPathExtension
        let ext = (fileName as NSString).pathExtension
        while fm.fileExists(atPath: destPath) {
            let newName = "\(baseName)_\(counter).\(ext)"
            destPath = (assetsDir as NSString).appendingPathComponent(newName)
            counter += 1
        }
        do {
            try fm.copyItem(at: sourceURL, to: URL(fileURLWithPath: destPath))
            return destPath
        } catch {
            return nil
        }
    }

    /// Inserts an image block at the given index, or converts an existing block.
    func insertImageAtBlock(blockId: UUID, imagePath: String) {
        saveUndo()
        updateBlockProperty(id: blockId) { block in
            block.type = .image
            block.imageSource = imagePath
            block.text = ""
        }
    }

    /// Inserts a new image block after the given index.
    func insertImageBlock(at index: Int, imagePath: String) {
        saveUndo()
        var imageBlock = Block(type: .image)
        imageBlock.imageSource = imagePath
        let clampedIndex = min(index, blocks.count)
        blocks.insert(imageBlock, at: clampedIndex)
        focusedBlockId = imageBlock.id
    }

    /// Saves raw image data to the workspace `_assets/` directory and returns the absolute path.
    func saveImageDataToAssets(_ data: Data, fileExtension: String = "png") -> String? {
        guard let workspace = workspacePath else { return nil }
        let assetsDir = (workspace as NSString).appendingPathComponent("_assets")
        let fm = FileManager.default
        if !fm.fileExists(atPath: assetsDir) {
            try? fm.createDirectory(atPath: assetsDir, withIntermediateDirectories: true)
        }
        let fileName = "\(UUID().uuidString).\(fileExtension)"
        let destPath = (assetsDir as NSString).appendingPathComponent(fileName)
        do {
            try data.write(to: URL(fileURLWithPath: destPath), options: .atomic)
            return destPath
        } catch {
            return nil
        }
    }

    #if os(macOS)
    /// Opens a file picker for images and inserts the selected image at the given block.
    func pickAndInsertImage(blockId: UUID) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url, let self else { return }
            if let path = self.copyImageToAssets(url) {
                self.insertImageAtBlock(blockId: blockId, imagePath: path)
            }
        }
    }
    #endif

    // MARK: - Block Selection

    func selectAllBlocks() {
        selectedBlockIds = Set(selectionOrder())
        selectionRect = nil
        selectionBlockId = nil
        suppressNextEditorTapAfterBlockSelection = false
    }

    func clearBlockSelection() {
        selectedBlockIds.removeAll()
        blockSelectionAnchor = nil
        suppressNextEditorTapAfterBlockSelection = false
    }

    func selectBlockRange(from anchorId: UUID, to currentId: UUID) {
        let ordered = selectionOrder()
        guard let anchorIdx = ordered.firstIndex(of: anchorId),
              let currentIdx = ordered.firstIndex(of: currentId) else { return }
        let range = min(anchorIdx, currentIdx)...max(anchorIdx, currentIdx)
        selectedBlockIds = Set(range.map { ordered[$0] })
        selectionRect = nil
        selectionBlockId = nil
    }

    func beginBlockSelectionDrag(from anchorId: UUID) {
        blockSelectionAnchor = anchorId
        selectedBlockIds = [anchorId]
        selectionRect = nil
        selectionBlockId = nil
        suppressNextEditorTapAfterBlockSelection = false
    }

    func endBlockSelectionDrag() {
        blockSelectionAnchor = nil
        suppressNextEditorTapAfterBlockSelection = !selectedBlockIds.isEmpty
    }

    func consumePendingEditorTapAfterBlockSelection() -> Bool {
        guard suppressNextEditorTapAfterBlockSelection else { return false }
        suppressNextEditorTapAfterBlockSelection = false
        return true
    }

    func deleteSelectedBlocks() {
        guard !selectedBlockIds.isEmpty else { return }
        saveUndo()
        // Collect pageLink names before removing blocks
        var deletedPageNames: [String] = []
        for blockId in selectedBlockIds {
            if let b = block(for: blockId), b.type == .pageLink, !b.pageLinkName.isEmpty {
                deletedPageNames.append(b.pageLinkName)
            }
        }
        let ordered = selectionOrder()
        for blockId in ordered.reversed() where selectedBlockIds.contains(blockId) {
            guard let loc = blockLocation(for: blockId) else { continue }
            if let childIdx = loc.child {
                unregisterFramesRecursively(for: blocks[loc.topLevel].children[childIdx])
                blocks[loc.topLevel].children.remove(at: childIdx)
                dissolveColumnIfNeeded(at: loc.topLevel)
            } else {
                unregisterFramesRecursively(for: blocks[loc.topLevel])
                blocks.remove(at: loc.topLevel)
            }
        }
        for name in deletedPageNames { onDeleteSubPage?(name) }
        if blocks.isEmpty {
            let titleBlock = Block(type: .heading, headingLevel: 1)
            blocks.append(titleBlock)
            focusedBlockId = titleBlock.id
        } else {
            focusedBlockId = blocks.first?.id
        }
        ensureTrailingParagraph()
        cursorPosition = 0
        clearBlockSelection()
    }

    private func selectionOrder() -> [UUID] {
        var ordered: [UUID] = []
        for block in blocks {
            ordered.append(block.id)
            if block.type == .column {
                ordered.append(contentsOf: block.children.map(\.id))
            } else if block.type == .toggle, block.isExpanded {
                ordered.append(contentsOf: block.children.map(\.id))
            }
        }
        return ordered
    }

    private func unregisterFramesRecursively(for block: Block) {
        unregisterBlockFrame(for: block.id)
        for child in block.children {
            unregisterFramesRecursively(for: child)
        }
    }

    func registerBlockFrame(_ frame: CGRect, for blockId: UUID) {
        registeredBlockFrames[blockId] = frame
    }

    func unregisterBlockFrame(for blockId: UUID) {
        registeredBlockFrames.removeValue(forKey: blockId)
    }

    func blockId(atWindowPoint point: CGPoint) -> UUID? {
        registeredBlockFrames
            .filter { $0.value.contains(point) }
            .min(by: { $0.value.width * $0.value.height < $1.value.width * $1.value.height })?
            .key
    }
}
