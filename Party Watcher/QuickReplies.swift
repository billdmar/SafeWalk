//
//  QuickReplies.swift
//  Party Watcher
//
//  "Quick reply" buttons for the check-in chat. Tapping one posts the reply as
//  the user's message and sends it to the Gemini AI companion for a real,
//  context-aware response — `botResponse` is the instant offline fallback used
//  only when the network/AI is unavailable. Each reply also carries a safety
//  effect so a tap does the right thing (confirm safety, or escalate) in
//  addition to talking. The "I need help" reply escalates instantly and does
//  NOT wait on the AI, since a safety action must never depend on the network.
//
//  Like `SafetyEngine` / `Escalation`, the catalog and the label→reply mapping
//  are pure and side-effect free, so the labels, fallback wording, and the
//  effect of every button are unit-tested. The view is responsible for sending
//  the AI request, applying the effect (markSafe / escalate), and appending the
//  messages.
//

import Foundation

/// A tappable quick reply in the check-in chat.
struct QuickReply: Identifiable, Hashable {
    /// What the button shows and what gets posted as the user's chat bubble
    /// (and sent to the AI companion as the prompt).
    let label: String
    /// The offline fallback response, used only when the AI request fails.
    let botResponse: String
    /// The safety action the tap performs, in addition to the exchange.
    let effect: Effect

    /// Stable identity derived from the label (labels are unique in the catalog).
    var id: String { label }

    /// The safety side-effect a quick reply triggers when tapped.
    enum Effect: Equatable {
        /// Reassuring reply — confirm safety, reset the check-in clock.
        case reassure
        /// Neutral chit-chat — no safety state change. (Named `neutral` rather
        /// than `none` to avoid colliding with `Optional.none` at call sites.)
        case neutral
        /// The user signaled distress — escalate immediately.
        case escalate
    }
}

/// The catalog of quick replies and the label→reply lookup.
enum QuickReplies {
    /// The buttons offered under the chat input, in display order. Kept small so
    /// they fit the row and cover the common cases: "I'm fine", small talk, and
    /// a fast distress signal.
    static let all: [QuickReply] = [
        QuickReply(label: "I'm okay 👍",
                   botResponse: "Great — glad you're safe! I'll keep watching. 💛",
                   effect: .reassure),
        QuickReply(label: "Almost home",
                   botResponse: "Nice work. Stay aware of your surroundings — I'm still here with you.",
                   effect: .reassure),
        QuickReply(label: "Just walking",
                   botResponse: "Sounds good. Keep moving and I'll check back in shortly. 🚶",
                   effect: .neutral),
        QuickReply(label: "Feeling nervous",
                   botResponse: "I hear you. Head for a lit, busy area if you can. Tap “I need help” and I'll escalate the moment you want me to.",
                   effect: .neutral),
        QuickReply(label: "I need help 🚨",
                   botResponse: "Got it — escalating now. Hang tight, help is being contacted.",
                   effect: .escalate),
    ]

    /// The deterministic companion response for a given button label, or `nil`
    /// if the label isn't a known quick reply. Extracted so the mapping is
    /// testable independently of the catalog ordering.
    static func response(for label: String) -> QuickReply? {
        all.first { $0.label == label }
    }
}
