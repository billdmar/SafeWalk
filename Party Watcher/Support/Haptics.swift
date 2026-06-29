import UIKit

/// Centralized haptic feedback so taps and escalations feel consistent across
/// the app, and so the call sites read intent ("success", "escalation") rather
/// than raw generator types.
enum Haptics {
    /// A light tap for routine confirmations (sending a reply, quick replies).
    static func light() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    /// A medium tap for deliberate actions (mark safe, start/arrive a walk).
    static func medium() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    /// A distinct error notification so an escalation is *felt*, not only seen —
    /// important when the phone is in a pocket during a walk.
    static func escalation() {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }
}
