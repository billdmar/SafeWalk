//
//  QuickReplies.swift
//  Party Watcher
//
//  Deterministic "quick reply" buttons for the check-in chat. Tapping one posts
//  a canned user message and a fixed companion response — so the chat feels
//  conversational without depending on the network or the Gemini API. Each reply
//  also carries a safety effect so a tap can do the right thing (confirm safety,
//  or escalate) in addition to talking.
//
//  Like `SafetyEngine` / `Escalation`, the catalog and the label→response
//  mapping are pure and side-effect free, so the wording and the effect of every
//  button are unit-tested. The view is responsible only for *applying* the
//  effect (markSafe / escalate) and appending the messages.
//

import Foundation

/// A tappable canned reply in the check-in chat.
struct QuickReply: Identifiable, Hashable {
    /// What the button shows and what gets posted as the user's chat bubble.
    let label: String
    /// The companion's deterministic reply to this tap.
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

/// The fixed catalog of quick replies and the deterministic responder.
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
