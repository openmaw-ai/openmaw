import Foundation

final class ConversationManager {
    static let shared = ConversationManager()

    private var conversations: [String: ConversationState] = [:]
    private let defaultTimeout: TimeInterval = 600  // 10 minutes

    private struct ConversationState {
        var messages: [ChatMessage]
        var lastActivity: Date
    }

    private init() {}

    // MARK: - Public API

    func messages(for pluginID: String) -> [ChatMessage] {
        guard let state = conversations[pluginID],
              !isExpired(state) else {
            return []
        }
        return state.messages
    }

    func append(message: ChatMessage, for pluginID: String) {
        if conversations[pluginID] == nil || isExpired(conversations[pluginID]!) {
            conversations[pluginID] = ConversationState(messages: [], lastActivity: Date())
        }
        conversations[pluginID]?.messages.append(message)
        conversations[pluginID]?.lastActivity = Date()
    }

    func clear(for pluginID: String) {
        conversations.removeValue(forKey: pluginID)
    }

    func hasActiveConversation(for pluginID: String) -> Bool {
        guard let state = conversations[pluginID] else { return false }
        return !isExpired(state) && !state.messages.isEmpty
    }

    // MARK: - Expiry

    private func isExpired(_ state: ConversationState) -> Bool {
        Date().timeIntervalSince(state.lastActivity) > defaultTimeout
    }

    func cleanupExpired() {
        let expired = conversations.filter { isExpired($0.value) }.map { $0.key }
        for key in expired {
            conversations.removeValue(forKey: key)
        }
    }
}
