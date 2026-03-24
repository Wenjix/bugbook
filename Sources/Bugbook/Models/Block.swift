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
    case pageLink
    case column
    case toggle
    case meeting
}

// MARK: - Meeting Block State

enum MeetingState: Equatable {
    case before
    case during
    case after
}

struct TranscriptEntry: Identifiable, Equatable {
    let id: UUID
    var text: String
    var isUser: Bool
    var timestamp: Date

    init(id: UUID = UUID(), text: String, isUser: Bool = false, timestamp: Date = Date()) {
        self.id = id
        self.text = text
        self.isUser = isUser
        self.timestamp = timestamp
    }
}

struct ActionItem: Identifiable, Equatable {
    let id: UUID
    var text: String
    var isChecked: Bool

    init(id: UUID = UUID(), text: String, isChecked: Bool = false) {
        self.id = id
        self.text = text
        self.isChecked = isChecked
    }
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
    var pageLinkName: String
    var textColor: BlockColor
    var backgroundColor: BlockColor
    var children: [Block]
    var columnIndex: Int  // which column this belongs to (only meaningful inside .column parent)
    var isExpanded: Bool

    // Meeting block properties
    var meetingState: MeetingState
    var meetingTitle: String
    var meetingNotes: String
    var meetingTranscript: [TranscriptEntry]
    var meetingSummary: String
    var meetingKeyDecisions: [String]
    var meetingActionItems: [ActionItem]
    var meetingDiscussionNotes: String
    var meetingStartDate: Date?
    var meetingDuration: TimeInterval

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
        meetingState: MeetingState = .before,
        meetingTitle: String = "",
        meetingNotes: String = "",
        meetingTranscript: [TranscriptEntry] = [],
        meetingSummary: String = "",
        meetingKeyDecisions: [String] = [],
        meetingActionItems: [ActionItem] = [],
        meetingDiscussionNotes: String = "",
        meetingStartDate: Date? = nil,
        meetingDuration: TimeInterval = 0
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
        self.meetingTitle = meetingTitle
        self.meetingNotes = meetingNotes
        self.meetingTranscript = meetingTranscript
        self.meetingSummary = meetingSummary
        self.meetingKeyDecisions = meetingKeyDecisions
        self.meetingActionItems = meetingActionItems
        self.meetingDiscussionNotes = meetingDiscussionNotes
        self.meetingStartDate = meetingStartDate
        self.meetingDuration = meetingDuration
    }
}
