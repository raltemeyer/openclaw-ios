import Foundation
import Combine

@MainActor
class ConversationStore: ObservableObject {
    @Published var conversations: [String: Conversation] = [:]

    private let saveURL: URL = {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("conversations.json")
    }()

    init() {
        load()
        // Ensure every agent has a conversation
        for agent in Agent.all {
            if conversations[agent.id] == nil {
                conversations[agent.id] = Conversation(agentId: agent.id)
            }
        }
    }

    func conversation(for agentId: String) -> Conversation {
        conversations[agentId] ?? Conversation(agentId: agentId)
    }

    func addMessage(_ message: Message, to agentId: String) {
        if conversations[agentId] == nil {
            conversations[agentId] = Conversation(agentId: agentId)
        }
        conversations[agentId]?.messages.append(message)
        conversations[agentId]?.updatedAt = Date()
        save()
    }

    func updateLastMessage(in agentId: String, content: String, isStreaming: Bool) {
        guard let idx = conversations[agentId]?.messages.indices.last else { return }
        conversations[agentId]?.messages[idx].content = content
        conversations[agentId]?.messages[idx].isStreaming = isStreaming
        if !isStreaming { save() }
    }

    func clearConversation(for agentId: String) {
        conversations[agentId] = Conversation(agentId: agentId)
        save()
    }

    // MARK: - Persistence

    private func save() {
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(conversations) {
            try? data.write(to: saveURL)
        }
    }

    private func load() {
        let decoder = JSONDecoder()
        if let data = try? Data(contentsOf: saveURL),
           let loaded = try? decoder.decode([String: Conversation].self, from: data) {
            conversations = loaded
        }
    }
}
