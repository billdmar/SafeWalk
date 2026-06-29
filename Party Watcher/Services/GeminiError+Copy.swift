import Foundation

extension GeminiManager.GeminiError {
    /// A short, reassuring, user-facing line for a failed companion reply.
    ///
    /// Keyed off the specific failure so the user gets a useful hint ("no
    /// connection" vs "service busy") instead of one opaque apology — and so a
    /// configuration problem in a demo build is obvious. Every variant keeps the
    /// safety framing: SafeWalk is still watching the walk.
    var companionMessage: String {
        switch self {
        case .missingKey:
            return "🤖 My AI companion isn't configured, but I'm still watching your walk. Use the quick replies or the “I'm safe” button to check in."
        case .network:
            return "🤖 I can't reach the network right now — I'm still watching your walk. Tap “I'm safe” so I know you're okay."
        case .timeout:
            return "🤖 That took too long to come back. I'm still here — tap “I'm safe” to check in."
        case .server:
            return "🤖 The companion service is busy. Try again in a moment — I'm still watching your walk."
        case .decoding, .noCandidate, .invalidRequest:
            return "🤖 Sorry, I couldn't get a response right now — but I'm still watching your walk."
        }
    }
}
