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

    var titleBlock: Block? {
        guard let first = blocks.first,
              first.type == .heading, first.headingLevel == 1 else { return nil }
        return first
    }

    var onCreateDatabase: ((String) -> String?)?
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
        blocks.first { $0.id == id }
    }

    func index(for id: UUID) -> Int? {
        blocks.firstIndex { $0.id == id }
    }

    // MARK: - Mutations

    private func saveUndo() {
        undoStack.append(blocks)
        redoStack.removeAll()
    }

    @discardableResult
    func splitBlock(id: UUID, atOffset offset: Int) -> UUID {
        guard let idx = index(for: id) else { return UUID() }
        saveUndo()

        let block = blocks[idx]
        let clamped = min(offset, block.text.count)
        let splitAt = block.text.index(block.text.startIndex, offsetBy: clamped)
        let before = String(block.text[..<splitAt])
        let after = String(block.text[splitAt...])

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
        guard let idx = index(for: id), idx > 0 else { return nil }
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

    func changeBlockType(id: UUID, to type: BlockType) {
        guard let idx = index(for: id) else { return }
        saveUndo()
        blocks[idx].type = type
        if type == .heading {
            blocks[idx].headingLevel = 1
        }
    }

    func setHeadingLevel(id: UUID, level: Int) {
        guard let idx = index(for: id) else { return }
        blocks[idx].type = .heading
        blocks[idx].headingLevel = level
    }

    func toggleCheck(id: UUID) {
        guard let idx = index(for: id) else { return }
        blocks[idx].isChecked.toggle()
    }

    func indent(id: UUID) {
        guard let idx = index(for: id) else { return }
        blocks[idx].listDepth += 1
    }

    func outdent(id: UUID) {
        guard let idx = index(for: id) else { return }
        if blocks[idx].listDepth > 0 {
            blocks[idx].listDepth -= 1
        }
    }

    func deleteBlock(id: UUID) {
        guard let idx = index(for: id) else { return }
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
        guard let idx = index(for: id) else { return }
        saveUndo()
        var copy = blocks[idx]
        copy = Block(
            type: copy.type,
            text: copy.text,
            headingLevel: copy.headingLevel,
            listDepth: copy.listDepth,
            isChecked: copy.isChecked,
            language: copy.language,
            imageSource: copy.imageSource,
            imageAlt: copy.imageAlt,
            imageWidth: copy.imageWidth,
            databasePath: copy.databasePath,
            pageLinkName: copy.pageLinkName,
            textColor: copy.textColor,
            backgroundColor: copy.backgroundColor,
            children: copy.children
        )
        blocks.insert(copy, at: idx + 1)
        focusedBlockId = copy.id
        cursorPosition = 0
    }

    func setTextColor(id: UUID, color: BlockColor) {
        guard let idx = index(for: id) else { return }
        saveUndo()
        blocks[idx].textColor = color
    }

    func setBackgroundColor(id: UUID, color: BlockColor) {
        guard let idx = index(for: id) else { return }
        saveUndo()
        blocks[idx].backgroundColor = color
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
        SlashCommand(name: "Link to Page", icon: "link", action: .linkToPage),
        SlashCommand(name: "Database", icon: "tablecells", action: .blockType(.databaseEmbed, headingLevel: 0)),
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

        if let blockIdx = index(for: blockId) {
            blocks[blockIdx].text = ""
        }

        switch command.action {
        case .linkToPage:
            pagePickerBlockId = blockId
            showPagePicker = true
            dismissSlashMenu()
            return

        case let .blockType(type, headingLevel):
            // Database command needs special handling — creates files via callback
            if type == .databaseEmbed {
                if let blockIdx = index(for: blockId),
                   let createDb = onCreateDatabase,
                   let dbPath = createDb("Untitled Database") {
                    blocks[blockIdx].type = .databaseEmbed
                    blocks[blockIdx].databasePath = dbPath
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
              let blockIdx = index(for: blockId) else {
            dismissPagePicker()
            return
        }
        saveUndo()
        blocks[blockIdx].type = .pageLink
        blocks[blockIdx].pageLinkName = name
        blocks[blockIdx].text = ""
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
}
