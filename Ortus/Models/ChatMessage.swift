import Foundation
import OrtusCore

enum ChatRole: String, Codable {
    case user
    case assistant
    case system
}

enum ChatMessageKind: Equatable {
    case text
    /// What Claude is doing or did for this answer; updated in place while it works.
    case activity(ChatActivity)
    case error
}

struct ChatMessage: Identifiable, Equatable {
    let id: UUID
    let role: ChatRole
    var content: String
    let timestamp: Date
    var kind: ChatMessageKind

    init(
        id: UUID = UUID(),
        role: ChatRole,
        content: String,
        timestamp: Date = Date(),
        kind: ChatMessageKind = .text
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.kind = kind
    }
}
