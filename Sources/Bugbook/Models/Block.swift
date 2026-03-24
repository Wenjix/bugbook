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
<<<<<<< HEAD
    case headingToggle
    case canvas
    case meeting
}

/// The lifecycle state of a meeting recording block.
enum MeetingBlockState: Equatable {
    case recording
    case processing
    case complete
=======
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
>>>>>>> worktree-agent-af890d65
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
<<<<<<< HEAD
    var meetingState: MeetingBlockState
    var meetingTranscript: String
    var meetingSummary: String
    var meetingActionItems: String
    var meetingTitle: String
    var meetingNotes: String
=======
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
>>>>>>> worktree-agent-af890d65

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
<<<<<<< HEAD
        meetingState: MeetingBlockState = .complete,
        meetingTranscript: String = "",
        meetingSummary: String = "",
        meetingActionItems: String = "",
        meetingTitle: String = "",
        meetingNotes: String = ""
=======
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
>>>>>>> worktree-agent-af890d65
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
<<<<<<< HEAD
        self.meetingTranscript = meetingTranscript
        self.meetingSummary = meetingSummary
        self.meetingActionItems = meetingActionItems
        self.meetingTitle = meetingTitle
        self.meetingNotes = meetingNotes
=======
        self.meetingTitle = meetingTitle
        self.meetingNotes = meetingNotes
        self.meetingTranscript = meetingTranscript
        self.meetingSummary = meetingSummary
        self.meetingKeyDecisions = meetingKeyDecisions
        self.meetingActionItems = meetingActionItems
        self.meetingDiscussionNotes = meetingDiscussionNotes
        self.meetingStartDate = meetingStartDate
        self.meetingDuration = meetingDuration
>>>>>>> worktree-agent-af890d65
    }
}
