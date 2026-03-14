import Foundation

struct ChatMessage: Identifiable {
    let id = UUID()
    let role: Role
    let content: String
    let timestamp: Date
    var isReverted: Bool = false

    enum Role {
        case user
        case assistant
        case error
        case applied
    }
}
