import Foundation

/// A single chat message with a stable identity and an explicit sender.
///
/// Modeling the sender explicitly (rather than inferring it from a message's
/// index parity) keeps bubble alignment correct even when the bot posts an
/// off-cadence message such as an automatic check-in.
struct ChatMessage: Identifiable, Hashable {
    let id = UUID()
    var text: String
    var isUser: Bool
}
