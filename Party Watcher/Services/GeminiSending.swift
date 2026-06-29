import Foundation

/// The Gemini behavior `SafetyWatcherViewModel` depends on, so the chat path can
/// be unit-tested with a stub that returns canned results instead of making a
/// real network call.
protocol GeminiSending {
    func send(messages: [GeminiManager.GeminiMessage],
              completion: @escaping (Result<String, GeminiManager.GeminiError>) -> Void)
}

extension GeminiManager: GeminiSending {}
