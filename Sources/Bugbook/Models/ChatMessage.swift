import Foundation

struct ChatMessage: Identifiable, Codable {
    let id: UUID
    let role: Role
    let content: String
    let timestamp: Date
    var isReverted: Bool = false
    var changeSummary: String?

    enum Role: String, Codable {
        case user
        case assistant
        case error
        case applied
    }

    init(id: UUID = UUID(), role: Role, content: String, timestamp: Date, isReverted: Bool = false, changeSummary: String? = nil) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.isReverted = isReverted
        self.changeSummary = changeSummary
    }
}
