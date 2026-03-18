import Foundation
import AppKit
import SwiftUI

extension Notification.Name {
    static let blockDocumentFrameRefreshRequested = Notification.Name("BlockDocumentFrameRefreshRequested")
}

struct BlockTextSelectionPoint: Equatable {
    let blockId: UUID
    let displayOffset: Int
}

struct MultiBlockTextSelection: Equatable {
    var anchor: BlockTextSelectionPoint
    var focus: BlockTextSelectionPoint
}

@MainActor
@Observable
class BlockDocument {
    var blocks: [Block] {
        didSet { contentVersion += 1 }
    }
    /// Lightweight counter incremented on every `blocks` mutation. Use this
    /// in `onChange` instead of comparing the full `[Block]` array.
    var contentVersion: Int = 0
    var selectionVersion: Int = 0
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
    var pagePickerSearch: String = ""
    var pagePickerSelectedIndex: Int = 0
    var showTemplatePicker: Bool = false
    var aiPromptBlockId: UUID?
    var aiPromptText: String = ""
    var isAiGenerating: Bool = false
    var selectedBlockIds: Set<UUID> = []
    var moveBlockId: UUID?
    var selectionRect: CGRect?
    var selectionBlockId: UUID?
    var multiBlockTextSelection: MultiBlockTextSelection?
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
    @ObservationIgnored var onSubmitAiPrompt: ((String) -> Void)?
    @ObservationIgnored var onCancelAiPrompt: (() -> Void)?
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
    func createColumnFromDrop(droppedId: UUID, targetId: UUID, onLeadingEdge: Bool = false) {
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
                if onLeadingEdge {
                    for childIndex in blocks[newIdx].children.indices {
                        blocks[newIdx].children[childIndex].columnIndex += 1
                    }
                }
                let newColIndex = onLeadingEdge ? 0 : (blocks[newIdx].children.map(\.columnIndex).max() ?? -1) + 1
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
                if onLeadingEdge {
                    for childIndex in blocks[newIdx].children.indices {
                        blocks[newIdx].children[childIndex].columnIndex += 1
                    }
                }
                let newColIndex = onLeadingEdge ? 0 : (blocks[newIdx].children.map(\.columnIndex).max() ?? -1) + 1
                extracted.columnIndex = newColIndex
                blocks[newIdx].children.append(extracted)
            }
        } else {
            // Target is a regular block — wrap both in a new column
            saveUndo()
            guard var extracted = extractBlock(id: droppedId) else { return }
            guard let newTargetIdx = index(for: targetId) else { return }
            var target = blocks[newTargetIdx]
            if onLeadingEdge {
                extracted.columnIndex = 0
                target.columnIndex = 1
            } else {
                target.columnIndex = 0
                extracted.columnIndex = 1
            }
            let columnBlock = Block(
                type: .column,
                children: onLeadingEdge ? [extracted, target] : [target, extracted]
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

            // Empty child in toggle → exit the container
            if parentBlock.type == .toggle,
               before.isEmpty,
               after.isEmpty {
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

        // Toggle title → Enter creates child inside the container
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
                // First child in toggle — merge into the parent text
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
        moveBlocksById([id], toIndex: toIndex)
    }

    func moveBlocksById(_ ids: [UUID], toIndex: Int) {
        let draggedIds = orderedDraggedBlockIds(ids)
        guard !draggedIds.isEmpty else { return }

        let draggedSet = Set(draggedIds)
        let topLevelIdsBefore = blocks.map(\.id)
        let clampedTarget = min(max(0, toIndex), topLevelIdsBefore.count)
        let remainingInsertionIndex = topLevelIdsBefore
            .prefix(clampedTarget)
            .filter { !draggedSet.contains($0) }
            .count
        let insertionAnchorId = topLevelIdsBefore
            .filter { !draggedSet.contains($0) }
            .dropFirst(remainingInsertionIndex)
            .first

        saveUndo()

        var extractedBlocks: [Block] = []
        for draggedId in draggedIds {
            guard let extracted = extractBlock(id: draggedId) else { continue }
            extractedBlocks.append(extracted)
        }
        guard !extractedBlocks.isEmpty else { return }

        let insertionIndex: Int
        if let insertionAnchorId,
           let anchorIndex = blocks.firstIndex(where: { $0.id == insertionAnchorId }) {
            insertionIndex = anchorIndex
        } else {
            insertionIndex = min(remainingInsertionIndex, blocks.count)
        }

        for (offset, block) in extractedBlocks.enumerated() {
            blocks.insert(block, at: min(insertionIndex + offset, blocks.count))
        }
    }

    var orderedSelectedBlockIds: [UUID] {
        selectionOrder().filter { selectedBlockIds.contains($0) }
    }

    var orderedMultiBlockSelectedTextBlockIds: [UUID] {
        guard let normalized = normalizedMultiBlockTextSelection() else { return [] }
        return selectionBlockIdsBetween(start: normalized.start.blockId, end: normalized.end.blockId)
    }

    func dragSelectionBlockIds(startingWith blockId: UUID) -> [UUID] {
        if selectedBlockIds.contains(blockId), selectedBlockIds.count > 1 {
            return orderedSelectedBlockIds
        }

        let multiBlockIds = orderedMultiBlockSelectedTextBlockIds
        if multiBlockIds.contains(blockId), multiBlockIds.count > 1 {
            return multiBlockIds
        }

        return orderedDraggedBlockIds([blockId])
    }

    func dragPayload(for blockId: UUID) -> String {
        let draggedIds = dragSelectionBlockIds(startingWith: blockId)
        if draggedIds.count == 1, let onlyId = draggedIds.first {
            return onlyId.uuidString
        }
        return "blocks:" + draggedIds.map(\.uuidString).joined(separator: ",")
    }

    static func draggedBlockIds(from payload: String) -> [UUID] {
        if let id = UUID(uuidString: payload) {
            return [id]
        }

        guard payload.hasPrefix("blocks:") else { return [] }
        let rawIds = payload.dropFirst("blocks:".count).split(separator: ",")
        return rawIds.compactMap { UUID(uuidString: String($0)) }
    }

    private func orderedDraggedBlockIds(_ ids: [UUID]) -> [UUID] {
        let requestedIds = Set(ids)
        let orderedSelection = selectionOrder().filter { requestedIds.contains($0) }
        if !orderedSelection.isEmpty {
            return orderedSelection
        }
        return ids.filter { blockLocation(for: $0) != nil }
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

    /// Focus the empty paragraph right after the given block, or insert one if needed.
    func focusOrInsertParagraphAfter(blockId: UUID) {
        guard let idx = blocks.firstIndex(where: { $0.id == blockId }) else { return }
        let nextIdx = idx + 1
        if nextIdx < blocks.count {
            let next = blocks[nextIdx]
            if next.type == .paragraph, next.text.isEmpty {
                focusedBlockId = next.id
                cursorPosition = 0
                return
            }
        }
        let newBlock = Block(type: .paragraph)
        blocks.insert(newBlock, at: nextIdx)
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

    func updateImageWidth(blockId: UUID, width: Double) {
        updateBlockProperty(id: blockId) { $0.imageWidth = Int(width) }
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
        case askAI
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
        SlashCommand(name: "Ask AI", icon: "ladybug", action: .askAI),
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
            pagePickerSearch = ""
            pagePickerSelectedIndex = 0
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

        case .askAI:
            showAiPrompt(blockId: blockId)
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

    @ObservationIgnored private var _pagePickerCache: (search: String, entries: [FileEntry])?

    var filteredPagePickerEntries: [FileEntry] {
        if let cache = _pagePickerCache, cache.search == pagePickerSearch {
            return cache.entries
        }
        let flat = flattenEntries(availablePages)
            .filter { !$0.isDirectory && ($0.name.hasSuffix(".md") || $0.isDatabase) }
        let result = pagePickerSearch.isEmpty
            ? flat
            : flat.filter { $0.name.localizedCaseInsensitiveContains(pagePickerSearch) }
        _pagePickerCache = (search: pagePickerSearch, entries: result)
        return result
    }

    func executePagePicker() {
        let items = filteredPagePickerEntries
        guard !items.isEmpty else { return }
        let idx = min(pagePickerSelectedIndex, items.count - 1)
        let name = items[idx].name.replacingOccurrences(of: ".md", with: "")
        insertPageLink(name: name)
    }

    private func flattenEntries(_ entries: [FileEntry]) -> [FileEntry] {
        var result: [FileEntry] = []
        for entry in entries {
            result.append(entry)
            if let children = entry.children {
                result.append(contentsOf: flattenEntries(children))
            }
        }
        return result
    }

    func dismissPagePicker() {
        showPagePicker = false
        pagePickerBlockId = nil
        pagePickerSearch = ""
        pagePickerSelectedIndex = 0
        _pagePickerCache = nil
    }

    func dismissSlashMenu() {
        slashMenuBlockId = nil
        slashMenuFilter = ""
        slashMenuSelectedIndex = 0
    }

    // MARK: - Inline AI Prompt

    func showAiPrompt(blockId: UUID) {
        aiPromptBlockId = blockId
        aiPromptText = ""
        isAiGenerating = false
    }

    func dismissAiPrompt() {
        aiPromptBlockId = nil
        aiPromptText = ""
        isAiGenerating = false
    }

    func submitAiPrompt() {
        let prompt = aiPromptText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, !isAiGenerating else { return }
        isAiGenerating = true
        onSubmitAiPrompt?(prompt)
    }

    func cancelAiGeneration() {
        onCancelAiPrompt?()
        isAiGenerating = false
    }

    /// Resolves the current selection into an ordered list of block indices.
    /// Priority: block selection > multi-block text selection > single-block selection.
    private func selectedBlockIndices() -> [Int]? {
        if !selectedBlockIds.isEmpty {
            let indices = blocks.enumerated()
                .filter { selectedBlockIds.contains($0.element.id) }
                .map(\.offset)
            return indices.isEmpty ? nil : indices
        }
        if let mbs = multiBlockTextSelection {
            guard let anchorIdx = index(for: mbs.anchor.blockId),
                  let focusIdx = index(for: mbs.focus.blockId) else { return nil }
            return Array(min(anchorIdx, focusIdx)...max(anchorIdx, focusIdx))
        }
        if let blockId = selectionBlockId {
            guard let idx = index(for: blockId) else { return nil }
            return [idx]
        }
        return nil
    }

    /// Returns the markdown for currently selected blocks (block selection or multi-block text selection).
    func selectedBlocksMarkdown() -> String? {
        guard let indices = selectedBlockIndices() else { return nil }
        let selectedBlocks = indices.map { blocks[$0] }
        return MarkdownBlockParser.serialize(selectedBlocks)
    }

    /// Replaces the selected blocks with AI-generated content.
    func replaceSelectedBlocks(markdown: String) {
        guard let indices = selectedBlockIndices(), !indices.isEmpty else { return }

        let newBlocks = MarkdownBlockParser.parse(markdown)
        guard !newBlocks.isEmpty else { return }

        saveUndo()

        let ids = Set(indices.map { blocks[$0].id })

        // Find the first selected block index
        guard let firstIdx = blocks.firstIndex(where: { ids.contains($0.id) }) else { return }

        // Remove all selected blocks
        blocks.removeAll { ids.contains($0.id) }

        // Insert new blocks at the position of the first removed block
        let insertIdx = min(firstIdx, blocks.count)
        for (i, block) in newBlocks.enumerated() {
            blocks.insert(block, at: insertIdx + i)
        }

        clearBlockSelection()
        clearMultiBlockTextSelection()
        ensureTrailingParagraph()
        focusedBlockId = newBlocks.first?.id
    }

    /// Returns the path selector range (first, last) for selected blocks.
    func selectedBlockPathRange() -> (first: String, last: String)? {
        guard let indices = selectedBlockIndices(),
              let first = indices.first, let last = indices.last else { return nil }
        return ("path:\(first)", "path:\(last)")
    }

    func applyAiResponse(markdown: String) {
        let newBlocks = MarkdownBlockParser.parse(markdown)
        guard !newBlocks.isEmpty else { return }
        saveUndo()
        blocks = newBlocks
        ensureTrailingParagraph()
        if let first = blocks.first {
            focusedBlockId = first.id
        }
    }

    func reloadFromDisk() {
        guard let path = filePath,
              let content = try? String(contentsOfFile: path, encoding: .utf8) else { return }
        saveUndo()
        let (_, body) = MarkdownBlockParser.parseMetadata(content)
        blocks = MarkdownBlockParser.parse(body)
        ensureTrailingParagraph()
        clearBlockSelection()
        clearMultiBlockTextSelection()
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

    /// Inserts a new page link block at the given index.
    func insertPageLinkBlock(at index: Int, name: String) {
        saveUndo()
        let block = Block(type: .pageLink, pageLinkName: name)
        let clampedIndex = min(index, blocks.count)
        blocks.insert(block, at: clampedIndex)
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
        clearMultiBlockTextSelection()
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
        clearMultiBlockTextSelection()
        let ordered = selectionOrder()
        guard let anchorIdx = ordered.firstIndex(of: anchorId),
              let currentIdx = ordered.firstIndex(of: currentId) else { return }
        let range = min(anchorIdx, currentIdx)...max(anchorIdx, currentIdx)
        selectedBlockIds = Set(range.map { ordered[$0] })
        selectionRect = nil
        selectionBlockId = nil
        selectionVersion += 1
    }

    func beginBlockSelectionDrag(from anchorId: UUID) {
        clearMultiBlockTextSelection()
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

    func beginMarqueeBlockSelection() {
        clearMultiBlockTextSelection()
        blockSelectionAnchor = nil
        selectedBlockIds.removeAll()
        selectionRect = nil
        selectionBlockId = nil
        suppressNextEditorTapAfterBlockSelection = false
    }

    func updateMarqueeBlockSelection(in windowRect: CGRect, within selectionSurfaceRect: CGRect) {
        let normalizedRect = windowRect.standardized
        let normalizedSurfaceRect = selectionSurfaceRect.standardized
        selectedBlockIds = Set(
            registeredBlockFrames.compactMap { blockId, frame in
                let marqueeRowFrame = CGRect(
                    x: normalizedSurfaceRect.minX,
                    y: frame.minY - 2,
                    width: normalizedSurfaceRect.width,
                    height: frame.height + 4
                )
                return marqueeRowFrame.intersects(normalizedRect) ? blockId : nil
            }
        )
    }

    /// Screen rect of the last selected block (for toolbar positioning near where user finished).
    /// Works for both block selection (selectedBlockIds) and multi-block text selection.
    var lastSelectedBlockRect: CGRect? {
        // Block selection — last selected block in document order
        if !selectedBlockIds.isEmpty {
            for block in blocks.reversed() where selectedBlockIds.contains(block.id) {
                if let frame = registeredBlockFrames[block.id] {
                    return frame
                }
                break
            }
        }
        // Multi-block text selection — use the focus (end) block
        if let mbs = multiBlockTextSelection {
            return registeredBlockFrames[mbs.focus.blockId]
        }
        return nil
    }

    func endMarqueeBlockSelection() {
        blockSelectionAnchor = nil
        suppressNextEditorTapAfterBlockSelection = !selectedBlockIds.isEmpty
        if !selectedBlockIds.isEmpty {
            selectionVersion += 1
        }
    }

    func consumePendingEditorTapAfterBlockSelection() -> Bool {
        guard suppressNextEditorTapAfterBlockSelection else { return false }
        suppressNextEditorTapAfterBlockSelection = false
        return true
    }

    var hasMultiBlockTextSelection: Bool {
        guard let normalized = normalizedMultiBlockTextSelection() else { return false }
        return normalized.start != normalized.end
    }

    func beginMultiBlockTextSelection(anchor: BlockTextSelectionPoint, focus: BlockTextSelectionPoint) {
        clearBlockSelection()
        selectionRect = nil
        selectionBlockId = nil
        multiBlockTextSelection = MultiBlockTextSelection(anchor: anchor, focus: focus)
        selectionVersion += 1
    }

    func updateMultiBlockTextSelection(focus: BlockTextSelectionPoint) {
        guard var selection = multiBlockTextSelection else {
            beginMultiBlockTextSelection(anchor: focus, focus: focus)
            return
        }
        selection.focus = focus
        multiBlockTextSelection = selection
        selectionRect = nil
        selectionBlockId = nil
        selectionVersion += 1
    }

    func clearMultiBlockTextSelection() {
        let hadSelection = multiBlockTextSelection != nil
        multiBlockTextSelection = nil
        selectionRect = nil
        selectionBlockId = nil
        if hadSelection {
            selectionVersion += 1
        }
    }

    func multiBlockSelectionRange(for blockId: UUID, visibleLength: Int) -> NSRange? {
        guard let normalized = normalizedMultiBlockTextSelection() else { return nil }
        let ordered = selectionOrder()
        guard let startIndex = ordered.firstIndex(of: normalized.start.blockId),
              let endIndex = ordered.firstIndex(of: normalized.end.blockId),
              let currentIndex = ordered.firstIndex(of: blockId),
              currentIndex >= startIndex, currentIndex <= endIndex else {
            return nil
        }

        let clampedLength = max(0, visibleLength)
        if normalized.start.blockId == normalized.end.blockId {
            let lower = min(normalized.start.displayOffset, normalized.end.displayOffset)
            let upper = max(normalized.start.displayOffset, normalized.end.displayOffset)
            let location = min(lower, clampedLength)
            let length = min(max(0, upper - lower), max(0, clampedLength - location))
            return NSRange(location: location, length: length)
        }

        if blockId == normalized.start.blockId {
            let location = min(normalized.start.displayOffset, clampedLength)
            return NSRange(location: location, length: max(0, clampedLength - location))
        }

        if blockId == normalized.end.blockId {
            let upper = min(normalized.end.displayOffset, clampedLength)
            return NSRange(location: 0, length: upper)
        }

        return NSRange(location: 0, length: clampedLength)
    }

    func copyMultiBlockSelectedText() -> Bool {
        guard let text = multiBlockSelectedText(), !text.isEmpty else { return false }
        writeTextToPasteboard(text)
        return true
    }

    func cutMultiBlockSelectedText() -> Bool {
        guard let text = multiBlockSelectedText(), !text.isEmpty else { return false }
        writeTextToPasteboard(text)
        deleteMultiBlockSelectedText()
        return true
    }

    func deleteMultiBlockSelectedText() {
        guard let normalized = normalizedMultiBlockTextSelection(),
              normalized.start.blockId != normalized.end.blockId,
              let startBlock = block(for: normalized.start.blockId),
              let endBlock = block(for: normalized.end.blockId) else { return }

        saveUndo()

        let startMarkdownOffset = AttributedStringConverter.markdownOffset(
            forDisplayOffset: normalized.start.displayOffset,
            in: startBlock.text
        )
        let endMarkdownOffset = AttributedStringConverter.markdownOffset(
            forDisplayOffset: normalized.end.displayOffset,
            in: endBlock.text
        )

        let startNSString = startBlock.text as NSString
        let endNSString = endBlock.text as NSString
        let preservedPrefix = startNSString.substring(to: min(startMarkdownOffset, startNSString.length))
        let preservedSuffix = endNSString.substring(from: min(endMarkdownOffset, endNSString.length))

        updateBlockText(id: normalized.start.blockId, text: preservedPrefix + preservedSuffix)

        let orderedIds = selectionBlockIdsBetween(start: normalized.start.blockId, end: normalized.end.blockId)
        for blockId in orderedIds.reversed() where blockId != normalized.start.blockId {
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

        focusedBlockId = normalized.start.blockId
        cursorPosition = startMarkdownOffset
        ensureTrailingParagraph()
        clearMultiBlockTextSelection()
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

    /// Refresh cached window-space block frames only when block hit-testing is needed.
    /// Recomputing every block's frame on every scroll tick is too expensive for long pages.
    func requestBlockFrameRefresh() {
        NotificationCenter.default.post(name: .blockDocumentFrameRefreshRequested, object: self)
    }

    func blockId(atWindowPoint point: CGPoint) -> UUID? {
        registeredBlockFrames
            .filter { $0.value.contains(point) }
            .min(by: { $0.value.width * $0.value.height < $1.value.width * $1.value.height })?
            .key
    }

    private func multiBlockSelectedText() -> String? {
        guard let normalized = normalizedMultiBlockTextSelection(),
              normalized.start.blockId != normalized.end.blockId else { return nil }

        let orderedIds = selectionBlockIdsBetween(start: normalized.start.blockId, end: normalized.end.blockId)
        var parts: [String] = []

        for blockId in orderedIds {
            guard let block = block(for: blockId) else { continue }
            let plainText = AttributedStringConverter.plainText(from: block.text)
            let visibleLength = (plainText as NSString).length
            guard let range = multiBlockSelectionRange(for: blockId, visibleLength: visibleLength),
                  range.length > 0 else {
                continue
            }
            parts.append((plainText as NSString).substring(with: range))
        }

        return parts.isEmpty ? nil : parts.joined(separator: "\n")
    }

    private func normalizedMultiBlockTextSelection() -> (start: BlockTextSelectionPoint, end: BlockTextSelectionPoint)? {
        guard let selection = multiBlockTextSelection else { return nil }
        let ordered = selectionOrder()
        guard let anchorIndex = ordered.firstIndex(of: selection.anchor.blockId),
              let focusIndex = ordered.firstIndex(of: selection.focus.blockId) else {
            return nil
        }

        if anchorIndex < focusIndex {
            return (selection.anchor, selection.focus)
        }

        if anchorIndex > focusIndex {
            return (selection.focus, selection.anchor)
        }

        if selection.anchor.displayOffset <= selection.focus.displayOffset {
            return (selection.anchor, selection.focus)
        }

        return (selection.focus, selection.anchor)
    }

    private func selectionBlockIdsBetween(start: UUID, end: UUID) -> [UUID] {
        let ordered = selectionOrder()
        guard let startIndex = ordered.firstIndex(of: start),
              let endIndex = ordered.firstIndex(of: end) else {
            return []
        }
        return Array(ordered[min(startIndex, endIndex)...max(startIndex, endIndex)])
    }

    var multiBlockSelectedBlockIds: Set<UUID> {
        guard let normalized = normalizedMultiBlockTextSelection() else { return [] }
        let orderedIds = selectionBlockIdsBetween(start: normalized.start.blockId, end: normalized.end.blockId)
        guard orderedIds.count > 2 else { return [] }
        return Set(orderedIds.dropFirst().dropLast())
    }

    private func writeTextToPasteboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
