//
//  WalkSessionTests.swift
//  Party WatcherTests
//
//  Regression guards for the walk-timer / ETA feature: the overdue rule that
//  decides whether a timed walk escalates. Time is injected (`at:`/`now:`) so
//  these run deterministically without waiting on a real clock.
//

import Testing
import Foundation
@testable import Party_Watcher

struct WalkSessionTests {

    private let start = Date(timeIntervalSince1970: 1_000_000)

    private func session(minutes: Int) -> WalkSession {
        WalkSession(destination: "Jester dorm",
                    startDate: start,
                    expectedDuration: TimeInterval(minutes * 60))
    }

    // MARK: - WalkSession

    @Test func expectedArrivalIsStartPlusDuration() {
        let s = session(minutes: 15)
        #expect(s.expectedArrival == start.addingTimeInterval(900))
    }

    @Test func secondsRemainingCountsDownAndGoesNegativeWhenOverdue() {
        let s = session(minutes: 10) // 600 s
        #expect(s.secondsRemaining(at: start.addingTimeInterval(60)) == 540)
        #expect(s.secondsRemaining(at: start.addingTimeInterval(700)) == -100)
    }

    @Test func isOverdueOnlyAtOrAfterExpectedArrival() {
        let s = session(minutes: 10)
        #expect(s.isOverdue(at: start.addingTimeInterval(599)) == false)
        #expect(s.isOverdue(at: start.addingTimeInterval(600)) == true) // boundary: inclusive
        #expect(s.isOverdue(at: start.addingTimeInterval(601)) == true)
    }

    // MARK: - WalkTimer decision

    @Test func noSessionNeverEscalates() {
        #expect(WalkTimer.decide(session: nil, now: start.addingTimeInterval(100_000)) == .onTrack)
    }

    @Test func onTrackBeforeETA() {
        let s = session(minutes: 20)
        #expect(WalkTimer.decide(session: s, now: start.addingTimeInterval(300)) == .onTrack)
    }

    @Test func escalatesOnceOverdue() {
        let s = session(minutes: 20) // 1200 s
        #expect(WalkTimer.decide(session: s, now: start.addingTimeInterval(1200)) == .escalateOverdue)
        #expect(WalkTimer.decide(session: s, now: start.addingTimeInterval(5000)) == .escalateOverdue)
    }

    @Test func presetMinutesAreOfferedAndSorted() {
        #expect(WalkTimer.presetMinutes == [5, 10, 15, 20, 30])
    }
}
