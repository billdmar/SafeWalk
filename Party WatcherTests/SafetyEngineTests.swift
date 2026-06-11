//
//  SafetyEngineTests.swift
//  Party WatcherTests
//
//  Regression guards around SafeWalk's safety-critical pure logic: the
//  escalation decision, movement threshold, and countdown formatting that were
//  lifted out of `SafetyWatcherView` into `SafetyEngine`. These are the rules
//  that decide whether help is summoned, so they get explicit edge-case tests.
//

import Testing
import Foundation
import CoreLocation
@testable import Party_Watcher

struct SafetyEngineTests {

    // MARK: - Escalation decision

    /// Within both thresholds, nothing happens.
    @Test func noDecisionWhenWithinThresholds() {
        let d = SafetyEngine.decide(timeSinceLastResponse: 10,
                                    timeSinceLastMovement: 10,
                                    checkInInterval: 60,
                                    inactivityThreshold: 120)
        #expect(d == .none)
    }

    /// Past the check-in interval but under the inactivity threshold → checking.
    @Test func checkingWhenCheckInOverdueButNotInactive() {
        let d = SafetyEngine.decide(timeSinceLastResponse: 75,
                                    timeSinceLastMovement: 5,
                                    checkInInterval: 60,
                                    inactivityThreshold: 120)
        #expect(d == .checking)
    }

    /// No response past the inactivity threshold → escalate.
    @Test func escalateOnNoResponse() {
        let d = SafetyEngine.decide(timeSinceLastResponse: 121,
                                    timeSinceLastMovement: 0,
                                    checkInInterval: 60,
                                    inactivityThreshold: 120)
        #expect(d == .escalate)
    }

    /// No movement past the threshold escalates even if the user just replied —
    /// the original "either condition" rule is preserved.
    @Test func escalateOnNoMovementEvenIfRecentlyResponded() {
        let d = SafetyEngine.decide(timeSinceLastResponse: 1,
                                    timeSinceLastMovement: 200,
                                    checkInInterval: 60,
                                    inactivityThreshold: 120)
        #expect(d == .escalate)
    }

    /// Escalation takes precedence over checking when both would apply.
    @Test func escalateWinsOverChecking() {
        let d = SafetyEngine.decide(timeSinceLastResponse: 300,
                                    timeSinceLastMovement: 300,
                                    checkInInterval: 60,
                                    inactivityThreshold: 120)
        #expect(d == .escalate)
    }

    /// Exactly at the threshold is *not* past it (strict `>`), matching the
    /// original inline comparison.
    @Test func thresholdBoundaryIsExclusive() {
        let d = SafetyEngine.decide(timeSinceLastResponse: 120,
                                    timeSinceLastMovement: 120,
                                    checkInInterval: 60,
                                    inactivityThreshold: 120)
        #expect(d == .checking) // past 60 (check-in), not past 120 (escalate)
    }

    // MARK: - Movement

    @Test func movementThresholdIsExclusiveAtFiveMetres() {
        #expect(SafetyEngine.isSignificantMovement(distance: 5) == false)
        #expect(SafetyEngine.isSignificantMovement(distance: 5.01) == true)
        #expect(SafetyEngine.isSignificantMovement(distance: 0) == false)
    }

    // MARK: - Countdown formatting

    @Test func countdownFormatsAsMinutesSeconds() {
        #expect(SafetyEngine.countdownString(secondsRemaining: 65) == "01:05")
        #expect(SafetyEngine.countdownString(secondsRemaining: 9) == "00:09")
        #expect(SafetyEngine.countdownString(secondsRemaining: 600) == "10:00")
    }

    /// A passed deadline clamps to zero rather than showing a negative time.
    @Test func countdownClampsNegativeToZero() {
        #expect(SafetyEngine.countdownString(secondsRemaining: -42) == "00:00")
    }
}
