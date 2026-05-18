import Foundation

enum BlockType: Equatable, Sendable {
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
    case pageLink
    case column
    case toggle
    case headingToggle
    case meeting
    case table
    case outline
    case callout
    case footnote

    /// Whether this block type is a list item (bullet, numbered, or task).
    var isListItem: Bool {
        switch self {
        case .bulletListItem, .numberedListItem, .taskItem: true
        default: false
        }
    }
}

/// The lifecycle state of a meeting recording block.
enum MeetingBlockState: Equatable, Sendable {
    case ready
    case recording
    case processing
    case complete
}

struct Block: Identifiable, Equatable, Sendable {
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
    var pageLinkName: String
    var textColor: BlockColor
    var backgroundColor: BlockColor
    var children: [Block]
    var columnIndex: Int  // which column this belongs to (only meaningful inside .column parent)
    var isExpanded: Bool

    // Meeting block properties
    var meetingState: MeetingBlockState
    var meetingTranscript: String
    var meetingSummary: String
    var meetingActionItems: String
    var meetingTitle: String
    var meetingNotes: String
    var transcriptEntries: [String] = []

    // Table block properties
    var tableData: [[String]] = []
    var hasHeaderRow: Bool = false

    // Callout block properties
    var calloutIcon: String = "lightbulb"
    var calloutColor: String = "default"

    // Footnote block properties
    var footnoteLabel: String = ""

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
        pageLinkName: String = "",
        textColor: BlockColor = .default,
        backgroundColor: BlockColor = .default,
        children: [Block] = [],
        columnIndex: Int = 0,
        isExpanded: Bool = true,
        meetingState: MeetingBlockState = .complete,
        meetingTranscript: String = "",
        meetingSummary: String = "",
        meetingActionItems: String = "",
        meetingTitle: String = "",
        meetingNotes: String = "",
        tableData: [[String]] = [],
        hasHeaderRow: Bool = false,
        calloutIcon: String = "lightbulb",
        calloutColor: String = "default",
        footnoteLabel: String = ""
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
        self.pageLinkName = pageLinkName
        self.textColor = textColor
        self.backgroundColor = backgroundColor
        self.children = children
        self.columnIndex = columnIndex
        self.isExpanded = isExpanded
        self.meetingState = meetingState
        self.meetingTranscript = meetingTranscript
        self.meetingSummary = meetingSummary
        self.meetingActionItems = meetingActionItems
        self.meetingTitle = meetingTitle
        self.meetingNotes = meetingNotes
        self.tableData = tableData
        self.hasHeaderRow = hasHeaderRow
        self.calloutIcon = calloutIcon
        self.calloutColor = calloutColor
        self.footnoteLabel = footnoteLabel
    }
}
