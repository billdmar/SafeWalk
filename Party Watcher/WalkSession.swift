//
//  WalkSession.swift
//  Party Watcher
//
//  The "walk timer" / ETA feature: the user names where they're headed and how
//  long they expect the walk to take; SafeWalk counts down and, if the walk
//  runs past its expected arrival without the user marking themselves safe,
//  auto-escalates — the same fail-safe used by the inactivity watcher, but
//  anchored to a concrete destination and deadline.
//
//  As with `SafetyEngine`, the decision logic here is pure and side-effect free
//  so the overrun rule — the safety-critical part — is unit-tested in isolation,
//  separately from the timers and SwiftUI state that drive it.
//

import Foundation

/// An in-progress timed walk to a destination.
///
/// A session is a value type: a destination label, when it started, and the
/// expected duration. "Are we overdue?" is derived from those plus the current
/// time, never stored, so the same inputs always yield the same decision.
struct WalkSession: Equatable {
    /// Where the user said they're walking to (e.g. "Jester dorm").
    var destination: String
    /// When the walk began.
    var startDate: Date
    /// How long the user expected the walk to take.
    var expectedDuration: TimeInterval

    /// The moment the walk is expected to be complete.
    var expectedArrival: Date {
        startDate.addingTimeInterval(expectedDuration)
    }

    /// Seconds remaining until the expected arrival at `now` (negative once
    /// overdue). Callers typically format this with `SafetyEngine.countdownString`.
    func secondsRemaining(at now: Date) -> TimeInterval {
        expectedArrival.timeIntervalSince(now)
    }

    /// `true` once the walk has run past its expected arrival time.
    func isOverdue(at now: Date) -> Bool {
        now >= expectedArrival
    }
}

/// Pure decisions for an active walk session.
enum WalkTimer {
    /// What the walk-timer poll should do, given a session and the current time.
    enum Decision: Equatable {
        /// On schedule — keep counting down.
        case onTrack
        /// Past the expected arrival without the user marking safe — escalate.
        case escalateOverdue
    }

    /// Decides whether an active walk should escalate.
    ///
    /// Escalation fires once the walk is overdue (`now >= expectedArrival`). A
    /// `nil` session (no active walk) is always `.onTrack` — the feature is
    /// opt-in and never escalates on its own when unused.
    ///
    /// - Parameters:
    ///   - session: The active walk, or `nil` if no walk is in progress.
    ///   - now: The current time.
    static func decide(session: WalkSession?, now: Date) -> Decision {
        guard let session else { return .onTrack }
        return session.isOverdue(at: now) ? .escalateOverdue : .onTrack
    }

    /// Sensible preset durations (in minutes) offered in the UI, kept here so
    /// the list is testable and has a single definition.
    static let presetMinutes: [Int] = [5, 10, 15, 20, 30]
}
