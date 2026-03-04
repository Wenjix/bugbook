import Foundation
import SwiftUI

@MainActor
class BlockDocument: ObservableObject {
    @Published var blocks: [Block]
    @Published var focusedBlockId: UUID?
    @Published var cursorPosition: Int = 0
    @Published var slashMenuBlockId: UUID?
    @Published var slashMenuSelectedIndex: Int = 0
    @Published var slashMenuFilter: String = ""
    @Published var blockMenuBlockId: UUID?
    @Published var icon: String?
    @Published var coverUrl: String?
    @Published var coverPosition: Double = 50
    @Published var fullWidth: Bool = false
    @Published var showPagePicker: Bool = false
    @Published var pagePickerBlockId: UUID?
    @Published var showTemplatePicker: Bool = false
    @Published var selectedBlockIds: Set<UUID> = []
    @Published var selectionRect: CGRect?
    @Published var selectionBlockId: UUID?
    var blockSelectionAnchor: UUID?

    var titleBlock: Block? {
        guard let first = blocks.first,
              first.type == .heading, first.headingLevel == 1 else { return nil }
        return first
    }

    var onCreateDatabase: ((String) -> String?)?
    var onCreateSubPage: ((String) -> String?)?
    var onNavigateToPage: ((String) -> Void)?
    var onOpenDatabaseTab: ((String) -> Void)?
    var availablePages: [FileEntry] = []

    private var undoStack: [[Block]] = []
    private var redoStack: [[Block]] = []

    var markdown: String {
        let metadata = MarkdownBlockParser.Metadata(
            icon: icon,
            coverUrl: coverUrl,
            coverPosition: coverPosition,
            fullWidth: fullWidth
        )
        let metaStr = MarkdownBlockParser.serializeMetadata(metadata)
        let blockStr = MarkdownBlockParser.serialize(blocks)
        if metaStr.isEmpty {
            return blockStr
        }
        return metaStr + "\n" + blockStr
    }

    init(markdown: String) {
        let (metadata, content) = MarkdownBlockParser.parseMetadata(markdown)
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
        if undoStack.count > 200 { undoStack.removeFirst() }
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
        updateBlockProperty(id: id) { block in
            block.type = type
            if type == .heading { block.headingLevel = 1 }
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

        if let childIdx = loc.child {
            saveUndo()
            blocks[loc.topLevel].children.remove(at: childIdx)
            dissolveColumnIfNeeded(at: loc.topLevel)
            guard !blocks.isEmpty else {
                let placeholder = Block(type: .paragraph)
                blocks.append(placeholder)
                focusedBlockId = placeholder.id
                cursorPosition = 0
                return
            }
            let focusIdx = min(max(0, loc.topLevel), blocks.count - 1)
            focusedBlockId = blocks[focusIdx].id
            cursorPosition = 0
            return
        }

        let idx = loc.topLevel
        guard blocks.count > 1 else {
            blocks[idx] = Block(type: .paragraph)
            return
        }
        saveUndo()
        blocks.remove(at: idx)
        let focusIdx = min(idx, blocks.count - 1)
        focusedBlockId = blocks[focusIdx].id
        cursorPosition = 0
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
        SlashCommand(name: "Database", icon: "tablecells", action: .blockType(.databaseEmbed, headingLevel: 0)),
        SlashCommand(name: "Template", icon: "doc.on.doc", action: .template),
    ]

    var filteredSlashCommands: [SlashCommand] {
        if slashMenuFilter.isEmpty { return Self.slashCommands }
        return Self.slashCommands.filter { $0.name.localizedCaseInsensitiveContains(slashMenuFilter) }
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

    // MARK: - Block Selection

    func selectAllBlocks() {
        selectedBlockIds = Set(selectionOrder())
    }

    func clearBlockSelection() {
        selectedBlockIds.removeAll()
        blockSelectionAnchor = nil
    }

    func selectBlockRange(from anchorId: UUID, to currentId: UUID) {
        let ordered = selectionOrder()
        guard let anchorIdx = ordered.firstIndex(of: anchorId),
              let currentIdx = ordered.firstIndex(of: currentId) else { return }
        let range = min(anchorIdx, currentIdx)...max(anchorIdx, currentIdx)
        selectedBlockIds = Set(range.map { ordered[$0] })
    }

    func deleteSelectedBlocks() {
        guard !selectedBlockIds.isEmpty else { return }
        saveUndo()
        let ordered = selectionOrder()
        for blockId in ordered.reversed() where selectedBlockIds.contains(blockId) {
            guard let loc = blockLocation(for: blockId) else { continue }
            if let childIdx = loc.child {
                blocks[loc.topLevel].children.remove(at: childIdx)
                dissolveColumnIfNeeded(at: loc.topLevel)
            } else {
                blocks.remove(at: loc.topLevel)
            }
        }
        if blocks.isEmpty {
            let titleBlock = Block(type: .heading, headingLevel: 1)
            blocks.append(titleBlock)
            focusedBlockId = titleBlock.id
        } else {
            focusedBlockId = blocks.first?.id
        }
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
}
