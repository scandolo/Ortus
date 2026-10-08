import Foundation

enum ChatRole: String, Codable {
    case user
    case assistant
    case system
}

enum ChatMessageKind: Equatable {
    case text
    case toolUse(toolName: String)
    case error
    /// Claude was refused this tool; the row offers to allow it.
    case permissionRequest(toolName: String)
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
