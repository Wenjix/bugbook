import Foundation

enum BlockType: Equatable {
    case paragraph
    case heading
    case bulletListItem
    case numberedListItem
    case taskItem
    case codeBlock
    case blockquote
    case horizontalRule
    case image
    case databaseEmbed
    case column
}

struct Block: Identifiable, Equatable {
    let id: UUID
    var type: BlockType
    var text: String
    var headingLevel: Int
    var listDepth: Int
    var isChecked: Bool
    var language: String
    var imageSource: String
    var imageAlt: String
    var imageWidth: Int?
    var databasePath: String
    var textColor: BlockColor
    var backgroundColor: BlockColor
    var children: [Block]

    init(
        id: UUID = UUID(),
        type: BlockType = .paragraph,
        text: String = "",
        headingLevel: Int = 1,
        listDepth: Int = 0,
        isChecked: Bool = false,
        language: String = "",
        imageSource: String = "",
        imageAlt: String = "",
        imageWidth: Int? = nil,
        databasePath: String = "",
        textColor: BlockColor = .default,
        backgroundColor: BlockColor = .default,
        children: [Block] = []
    ) {
        self.id = id
        self.type = type
        self.text = text
        self.headingLevel = headingLevel
        self.listDepth = listDepth
        self.isChecked = isChecked
        self.language = language
        self.imageSource = imageSource
        self.imageAlt = imageAlt
        self.imageWidth = imageWidth
        self.databasePath = databasePath
        self.textColor = textColor
        self.backgroundColor = backgroundColor
        self.children = children
    }
}
