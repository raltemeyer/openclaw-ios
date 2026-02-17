import Foundation

enum MessageRole: String, Codable {
    case user
    case assistant
    case system
}

struct Message: Identifiable, Codable {
    let id: UUID
    let role: MessageRole
    var content: String
    let agentId: String
    let timestamp: Date
    var isStreaming: Bool

    init(
        id: UUID = UUID(),
        role: MessageRole,
        content: String,
        agentId: String,
        timestamp: Date = Date(),
        isStreaming: Bool = false
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.agentId = agentId
        self.timestamp = timestamp
        self.isStreaming = isStreaming
    }
}

struct Conversation: Identifiable, Codable {
    let id: UUID
    let agentId: String
    var messages: [Message]
    let createdAt: Date
    var updatedAt: Date

    init(agentId: String) {
        self.id = UUID()
        self.agentId = agentId
        self.messages = []
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    var lastMessage: Message? {
        messages.last
    }

    var displayMessages: [Message] {
        messages.filter { $0.role != .system }
    }
}
