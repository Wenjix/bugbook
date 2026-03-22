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
<<<<<<< HEAD
<<<<<<< HEAD
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
>>>>>>> worktree-agent-af1aa33e
=======
    case meeting
>>>>>>> worktree-agent-a04c7e97
=======
    case meeting
>>>>>>> worktree-agent-a6f82bb5
=======
    case meeting
>>>>>>> worktree-agent-aedc8a07
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
<<<<<<< HEAD
<<<<<<< HEAD
    var meetingNotes: String  // user-typed notes during a meeting block
<<<<<<< HEAD

    // Meeting block properties
    var meetingState: MeetingBlockState
    var meetingTranscript: String
    var meetingSummary: String
    var meetingActionItems: String
    var meetingTitle: String
    var meetingNotes: String
=======
>>>>>>> worktree-agent-a04c7e97
=======
    var meetingNotes: String  // user-typed notes during meeting recording
>>>>>>> worktree-agent-a6f82bb5
=======
    var meetingNotes: String
>>>>>>> worktree-agent-aedc8a07

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
<<<<<<< HEAD
<<<<<<< HEAD
<<<<<<< HEAD
        meetingState: MeetingBlockState = .complete,
        meetingTranscript: String = "",
        meetingSummary: String = "",
        meetingActionItems: String = "",
        meetingTitle: String = "",
=======
>>>>>>> worktree-agent-af1aa33e
=======
>>>>>>> worktree-agent-a04c7e97
=======
>>>>>>> worktree-agent-a6f82bb5
=======
>>>>>>> worktree-agent-aedc8a07
        meetingNotes: String = ""
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
<<<<<<< HEAD
<<<<<<< HEAD
<<<<<<< HEAD
<<<<<<< HEAD
        self.meetingState = meetingState
        self.meetingTranscript = meetingTranscript
        self.meetingSummary = meetingSummary
        self.meetingActionItems = meetingActionItems
        self.meetingTitle = meetingTitle
=======
>>>>>>> worktree-agent-af1aa33e
=======
>>>>>>> worktree-agent-a04c7e97
=======
>>>>>>> worktree-agent-a6f82bb5
=======
>>>>>>> worktree-agent-aedc8a07
        self.meetingNotes = meetingNotes
    }
}
