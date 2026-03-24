import Foundation

struct ChatMessage: Identifiable {
    let id = UUID()
    let role: Role
    let content: String
    let timestamp: Date
    var isReverted: Bool = false
    var changeSummary: String?

    enum Role {
        case user
        case assistant
        case error
        case applied
    }
}
