import SwiftUI

/// The high-level safety state surfaced by the status hero.
enum SafetyStatus {
    case safe
    case checking
    case alert

    var title: String {
        switch self {
        case .safe: return "You're safe"
        case .checking: return "Checking in…"
        case .alert: return "Alert sent"
        }
    }

    var subtitle: String {
        switch self {
        case .safe: return "SafeWalk is watching your walk."
        case .checking: return "Reply or keep moving so I know you're okay."
        case .alert: return "No response detected — escalation triggered."
        }
    }

    var color: Color {
        switch self {
        case .safe: return Theme.safe
        case .checking: return Theme.checking
        case .alert: return Theme.alert
        }
    }

    var symbol: String {
        switch self {
        case .safe: return "checkmark.shield.fill"
        case .checking: return "clock.badge.questionmark.fill"
        case .alert: return "exclamationmark.shield.fill"
        }
    }
}
