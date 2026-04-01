import Foundation

enum MailMailbox: String, CaseIterable, Codable, Identifiable {
    case inbox
    case sent
    case drafts
    case starred
    case trash

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .inbox: return "Inbox"
        case .sent: return "Sent"
        case .drafts: return "Drafts"
        case .starred: return "Starred"
        case .trash: return "Trash"
        }
    }

    var systemImage: String {
        switch self {
        case .inbox: return "tray.full"
        case .sent: return "paperplane"
        case .drafts: return "square.and.pencil"
        case .starred: return "star"
        case .trash: return "trash"
        }
    }

    var gmailLabelIDs: [String] {
        switch self {
        case .inbox: return ["INBOX"]
        case .sent: return ["SENT"]
        case .drafts: return ["DRAFT"]
        case .starred: return ["STARRED"]
        case .trash: return ["TRASH"]
        }
    }
}

struct MailMessageRecipient: Codable, Equatable, Hashable, Identifiable {
    var name: String?
    var email: String

    var id: String { "\(email.lowercased())|\(name ?? "")" }

    var displayName: String {
        let trimmedName = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmedName.isEmpty ? email : "\(trimmedName) <\(email)>"
    }
}

enum MailComposerMode: String, Codable, Equatable {
    case newMessage
    case reply
    case replyAll
}

struct MailDraft: Codable, Equatable {
    var mode: MailComposerMode = .newMessage
    var to: String = ""
    var cc: String = ""
    var bcc: String = ""
    var subject: String = ""
    var body: String = ""
    var threadId: String?
    var replyToMessageID: String?
    var referencesHeader: String?

    var isEmpty: Bool {
        to.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            cc.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            bcc.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            subject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

struct MailSearchState: Codable, Equatable {
    var query: String = ""

    var isActive: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

struct MailMessage: Identifiable, Codable, Equatable {
    let id: String
    var threadId: String
    var subject: String
    var snippet: String
    var labelIds: [String]
    var from: MailMessageRecipient?
    var to: [MailMessageRecipient]
    var cc: [MailMessageRecipient]
    var bcc: [MailMessageRecipient]
    var date: Date?
    var plainBody: String
    var htmlBody: String?
    var messageIDHeader: String?
    var referencesHeader: String?

    var isUnread: Bool { labelIds.contains("UNREAD") }
    var isDraft: Bool { labelIds.contains("DRAFT") }

    var bodyText: String {
        if !plainBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return plainBody
        }
        return htmlBody ?? ""
    }
}

struct MailThreadSummary: Identifiable, Codable, Equatable {
    let id: String
    var mailbox: MailMailbox?
    var subject: String
    var snippet: String
    var participants: [String]
    var date: Date?
    var messageCount: Int
    var labelIds: [String]

    var isUnread: Bool { labelIds.contains("UNREAD") }
    var isStarred: Bool { labelIds.contains("STARRED") }
}

struct MailThreadDetail: Identifiable, Codable, Equatable {
    let id: String
    var mailbox: MailMailbox?
    var subject: String
    var snippet: String
    var participants: [String]
    var messages: [MailMessage]
    var labelIds: [String]
    var historyId: String?

    var isUnread: Bool { labelIds.contains("UNREAD") }
    var isStarred: Bool { labelIds.contains("STARRED") }

    var lastDate: Date? {
        messages.compactMap(\.date).max()
    }
}

struct MailCacheSnapshot: Codable, Equatable {
    var mailboxThreads: [MailMailbox: [MailThreadSummary]]
    var threadDetails: [String: MailThreadDetail]
    var savedAt: Date
}

enum MailThreadAction: Equatable {
    case archive
    case trash
    case untrash
    case setStarred(Bool)
    case setUnread(Bool)
}
