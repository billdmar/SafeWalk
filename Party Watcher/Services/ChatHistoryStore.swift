import Foundation

/// Persistence for the check-in chat, so the transcript and the Gemini
/// conversation survive an app relaunch. Abstracted so the view model can be
/// tested with an in-memory store.
protocol ChatHistoryStoring {
    func load() -> ChatHistory?
    func save(_ history: ChatHistory)
    func clear()
}

/// The persisted chat state: what the user sees (`messages`) and what's sent to
/// Gemini for context (`conversation`).
struct ChatHistory: Codable {
    var messages: [PersistedMessage]
    var conversation: [PersistedTurn]

    /// A view message, flattened for `Codable` (ChatMessage's `id` is generated).
    struct PersistedMessage: Codable {
        var text: String
        var isUser: Bool
    }

    /// A Gemini turn, flattened to role + text (the API shape is parts-based but
    /// SafeWalk only ever sends a single text part per turn).
    struct PersistedTurn: Codable {
        var role: String
        var text: String
    }
}

/// The production store, JSON-encoding the chat into `UserDefaults`.
struct ChatHistoryStore: ChatHistoryStoring {
    private let defaults: UserDefaults
    private let key = "chatHistory"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> ChatHistory? {
        guard let data = defaults.data(forKey: key),
              let history = try? JSONDecoder().decode(ChatHistory.self, from: data) else {
            return nil
        }
        return history
    }

    func save(_ history: ChatHistory) {
        if let data = try? JSONEncoder().encode(history) {
            defaults.set(data, forKey: key)
        }
    }

    func clear() {
        defaults.removeObject(forKey: key)
    }
}
