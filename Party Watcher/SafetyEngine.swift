//
//  SafetyEngine.swift
//  Party Watcher
//
//  The pure decision core of SafeWalk's safety logic, lifted out of
//  `SafetyWatcherView` so it can be reasoned about and unit-tested in
//  isolation — without timers, Core Location, or the SwiftUI runtime.
//
//  These functions are deliberately side-effect free: they take elapsed
//  times and thresholds and return a decision. The view remains responsible
//  for *acting* on a decision (posting notifications, updating @State), but the
//  "should we escalate?" judgement — the safety-critical part — now lives in
//  one place with regression tests around it.
//

import Foundation
import CoreLocation

/// Pure safety decisions derived from elapsed time and movement.
///
/// Nothing here touches the UI or the system; every function is a deterministic
/// mapping from inputs to a decision, which is what makes the escalation logic
/// testable and hard to regress.
enum SafetyEngine {
    /// The action the inactivity poll should take, given how long it's been
    /// since the user last responded or moved.
    enum Decision: Equatable {
        /// Nothing to do — the user is within all thresholds.
        case none
        /// A check-in is outstanding (past the check-in interval but not yet
        /// past the inactivity threshold); surface the "checking in…" state.
        case checking
        /// Thresholds exceeded — escalate (alert + notification) now.
        case escalate
    }

    /// Decides what the inactivity poll should do.
    ///
    /// Escalation fires if *either* the time since the last response **or** the
    /// time since the last movement exceeds `inactivityThreshold` — matching the
    /// original inline logic, now centralized and tested. Otherwise, if a
    /// check-in is overdue (past `checkInInterval`) the state moves to
    /// `.checking`; below that, `.none`.
    ///
    /// - Parameters:
    ///   - timeSinceLastResponse: Seconds since the user last replied / tapped "I'm safe".
    ///   - timeSinceLastMovement: Seconds since the last significant movement.
    ///   - checkInInterval: The check-in cadence (e.g. 60 s).
    ///   - inactivityThreshold: The no-response/no-movement limit before escalation (e.g. 120 s).
    static func decide(timeSinceLastResponse: TimeInterval,
                       timeSinceLastMovement: TimeInterval,
                       checkInInterval: TimeInterval,
                       inactivityThreshold: TimeInterval) -> Decision {
        if timeSinceLastResponse > inactivityThreshold || timeSinceLastMovement > inactivityThreshold {
            return .escalate
        }
        if timeSinceLastResponse > checkInInterval {
            return .checking
        }
        return .none
    }

    /// Whether a position change counts as "movement" for the purpose of
    /// resetting the inactivity clock. Mirrors the 5 m threshold used by
    /// `LocationManager`, extracted so the rule is named and testable.
    static let movementThreshold: CLLocationDistance = 5

    /// `true` when the distance moved between two fixes clears the movement
    /// threshold and should reset the inactivity timer.
    static func isSignificantMovement(distance: CLLocationDistance) -> Bool {
        distance > movementThreshold
    }

    /// Formats a countdown (seconds remaining) as `mm:ss`, clamping negatives to
    /// zero so an elapsed deadline reads `00:00` rather than a negative value.
    ///
    /// Extracted from the view's `timerString` so the formatting — including the
    /// clamp — is verified independently of the display timer.
    static func countdownString(secondsRemaining: TimeInterval) -> String {
        let total = max(0, Int(secondsRemaining))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}
