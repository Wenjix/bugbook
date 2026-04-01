import Foundation

enum MailPriority: String, Codable, CaseIterable, Identifiable {
    case high
    case medium
    case low
    case skip

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .high: return "High"
        case .medium: return "Medium"
        case .low: return "Low"
        case .skip: return "Skip"
        }
    }
}

enum MailThreadFlag: String, Codable, CaseIterable, Identifiable {
    case needsReply = "needs_reply"
    case waiting
    case archiveReady = "archive_ready"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .needsReply: return "Needs Reply"
        case .waiting: return "Waiting"
        case .archiveReady: return "Archive Ready"
        }
    }
}

enum MailAnalysisStatus: String, Codable, Equatable {
    case idle
    case pending
    case complete
    case failed
}

enum MailDraftSuggestionStatus: String, Codable, Equatable {
    case none
    case suggested
    case accepted
    case edited
}

struct MailThreadAnnotation: Codable, Equatable {
    var analysisStatus: MailAnalysisStatus = .idle
    var analysisUpdatedAt: Date?
    var suggestedPriority: MailPriority?
    var statusFlags: [MailThreadFlag] = []
    var draftStatus: MailDraftSuggestionStatus = .none
    var hasSenderContext = false
}

struct MailThreadAnalysis: Codable, Equatable {
    var priority: MailPriority
    var reason: String
    var suggestedAction: String
    var flags: [MailThreadFlag]
    var shouldGenerateDraft: Bool
    var prefersReplyAll: Bool
    var analyzedAt: Date
}

struct MailDraftRefinement: Codable, Equatable, Identifiable {
    var id: String
    var instruction: String
    var body: String
    var createdAt: Date

    init(id: String = UUID().uuidString, instruction: String, body: String, createdAt: Date = Date()) {
        self.id = id
        self.instruction = instruction
        self.body = body
        self.createdAt = createdAt
    }
}

struct MailDraftSuggestion: Codable, Equatable, Identifiable {
    var id: String
    var threadID: String
    var subject: String
    var body: String
    var rationale: String
    var generatedAt: Date
    var status: MailDraftSuggestionStatus
    var refinementHistory: [MailDraftRefinement]

    init(
        id: String = UUID().uuidString,
        threadID: String,
        subject: String,
        body: String,
        rationale: String,
        generatedAt: Date = Date(),
        status: MailDraftSuggestionStatus = .suggested,
        refinementHistory: [MailDraftRefinement] = []
    ) {
        self.id = id
        self.threadID = threadID
        self.subject = subject
        self.body = body
        self.rationale = rationale
        self.generatedAt = generatedAt
        self.status = status
        self.refinementHistory = refinementHistory
    }
}

struct MailSenderContextReference: Codable, Equatable, Identifiable {
    var id: String
    var path: String
    var excerpt: String

    init(id: String = UUID().uuidString, path: String, excerpt: String) {
        self.id = id
        self.path = path
        self.excerpt = excerpt
    }
}

struct MailSenderContext: Codable, Equatable {
    var threadID: String
    var senderName: String
    var senderEmail: String
    var summary: String
    var references: [MailSenderContextReference]
    var generatedAt: Date
}

enum MailMemoryKind: String, Codable, CaseIterable, Identifiable {
    case writingStyle = "writing_style"
    case priorityPreference = "priority_preference"
    case manualNote = "manual_note"
    case senderInsight = "sender_insight"

    var id: String { rawValue }
}

struct MailMemory: Codable, Equatable, Identifiable {
    var id: String
    var kind: MailMemoryKind
    var title: String
    var detail: String
    var senderEmail: String?
    var senderDomain: String?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: String = UUID().uuidString,
        kind: MailMemoryKind,
        title: String,
        detail: String,
        senderEmail: String? = nil,
        senderDomain: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.detail = detail
        self.senderEmail = senderEmail
        self.senderDomain = senderDomain
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

struct MailPriorityOverride: Codable, Equatable, Identifiable {
    var id: String
    var senderEmail: String?
    var senderDomain: String?
    var subjectContains: String?
    var priority: MailPriority
    var note: String
    var createdAt: Date
    var updatedAt: Date

    init(
        id: String = UUID().uuidString,
        senderEmail: String? = nil,
        senderDomain: String? = nil,
        subjectContains: String? = nil,
        priority: MailPriority,
        note: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.senderEmail = senderEmail
        self.senderDomain = senderDomain
        self.subjectContains = subjectContains
        self.priority = priority
        self.note = note
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

enum MailAgentActionKind: String, Codable, CaseIterable, Identifiable {
    case draftReply = "draft_reply"
    case createTask = "create_task"
    case createNote = "create_note"
    case createCalendarEvent = "create_calendar_event"
    case summarizeToNote = "summarize_to_note"
    case gatherContext = "gather_context"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .draftReply: return "Draft Reply"
        case .createTask: return "Create Bugbook Task"
        case .createNote: return "Create Bugbook Note"
        case .createCalendarEvent: return "Create Calendar Event"
        case .summarizeToNote: return "Summarize To Note"
        case .gatherContext: return "Gather Context"
        }
    }
}

struct MailAgentActionProposal: Codable, Equatable, Identifiable {
    var id: String
    var kind: MailAgentActionKind
    var title: String
    var detail: String

    init(id: String = UUID().uuidString, kind: MailAgentActionKind, title: String, detail: String) {
        self.id = id
        self.kind = kind
        self.title = title
        self.detail = detail
    }
}

enum MailAgentSessionRole: String, Codable {
    case system
    case assistant
    case user
    case action
}

struct MailAgentSessionEntry: Codable, Equatable, Identifiable {
    var id: String
    var role: MailAgentSessionRole
    var content: String
    var createdAt: Date

    init(id: String = UUID().uuidString, role: MailAgentSessionRole, content: String, createdAt: Date = Date()) {
        self.id = id
        self.role = role
        self.content = content
        self.createdAt = createdAt
    }
}

struct MailAgentSession: Codable, Equatable, Identifiable {
    var id: String
    var threadID: String
    var proposals: [MailAgentActionProposal]
    var entries: [MailAgentSessionEntry]
    var createdAt: Date
    var updatedAt: Date

    init(
        id: String = UUID().uuidString,
        threadID: String,
        proposals: [MailAgentActionProposal] = [],
        entries: [MailAgentSessionEntry] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.threadID = threadID
        self.proposals = proposals
        self.entries = entries
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

struct MailThreadIntelligenceRecord: Codable, Equatable {
    var threadID: String
    var sourceSignature: String?
    var annotation: MailThreadAnnotation
    var analysis: MailThreadAnalysis?
    var draftSuggestion: MailDraftSuggestion?
    var senderContext: MailSenderContext?
    var acceptedDraftBody: String?
    var editedDraftBody: String?
    var updatedAt: Date

    init(
        threadID: String,
        sourceSignature: String? = nil,
        annotation: MailThreadAnnotation = MailThreadAnnotation(),
        analysis: MailThreadAnalysis? = nil,
        draftSuggestion: MailDraftSuggestion? = nil,
        senderContext: MailSenderContext? = nil,
        acceptedDraftBody: String? = nil,
        editedDraftBody: String? = nil,
        updatedAt: Date = Date()
    ) {
        self.threadID = threadID
        self.sourceSignature = sourceSignature
        self.annotation = annotation
        self.analysis = analysis
        self.draftSuggestion = draftSuggestion
        self.senderContext = senderContext
        self.acceptedDraftBody = acceptedDraftBody
        self.editedDraftBody = editedDraftBody
        self.updatedAt = updatedAt
    }
}

enum MailInboxSplit: String, CaseIterable, Identifiable {
    case priority = "Priority"
    case other = "Other"
    case all = "All"

    var id: String { rawValue }
}

enum MailDetailTab: String, CaseIterable, Identifiable {
    case thread = "Thread"
    case draft = "Draft"
    case context = "Context"
    case agent = "Agent"

    var id: String { rawValue }
}
