//
//  SafetyWatcherViewModelTests.swift
//  Party WatcherTests
//
//  Exercises the safety controller end-to-end without a device, network, or
//  wall-clock waits. The view model's dependencies are injected as test doubles:
//  a `MockLocationProvider` that publishes synthetic locations and fires
//  movement on demand, a `ManualTimerScheduler` whose `advance(...)` fires timer
//  ticks deterministically, a `StubGemini` that returns canned results, an
//  in-memory contact store, and a controllable `now` clock. This is the seam the
//  MVVM refactor unlocked: the timer-driven escalation logic that used to be
//  buried in the view is now directly and deterministically testable.
//

import Testing
import Foundation
import CoreLocation
@testable import Party_Watcher

// MARK: - Test doubles

final class MockLocationProvider: LocationProviding {
    var lastLocation: CLLocation?
    var onMovement: (() -> Void)?
    var onLocationChange: ((CLLocation?) -> Void)?
    private(set) var startTrackingCalled = false
    private(set) var stopTrackingCalled = false

    func startTracking() { startTrackingCalled = true }
    func stopTracking() { stopTrackingCalled = true }

    /// Simulate a new GPS fix.
    func emit(_ location: CLLocation) {
        lastLocation = location
        onLocationChange?(location)
    }

    /// Simulate significant movement.
    func move() { onMovement?() }
}

/// A scheduler that records the registered ticks and fires them on demand.
final class ManualTimerScheduler: TimerScheduling {
    private var ticks: [(interval: TimeInterval, fire: () -> Void)?] = []

    func schedule(every interval: TimeInterval, _ tick: @escaping () -> Void) -> TimerToken {
        let index = ticks.count
        ticks.append((interval, tick))
        return TimerToken { [weak self] in
            // Leave a tombstone so indices stay stable; a cancelled tick no-ops.
            guard let self, self.ticks.indices.contains(index) else { return }
            self.ticks[index] = nil
        }
    }

    /// Fire every tick whose interval matches `interval` once.
    func advance(interval: TimeInterval) {
        for entry in ticks where entry?.interval == interval {
            entry?.fire()
        }
    }
}

final class StubGemini: GeminiSending {
    var result: Result<String, GeminiManager.GeminiError>
    private(set) var sendCount = 0

    init(result: Result<String, GeminiManager.GeminiError> = .success("ok")) {
        self.result = result
    }

    func send(messages: [GeminiManager.GeminiMessage],
              completion: @escaping (Result<String, GeminiManager.GeminiError>) -> Void) {
        sendCount += 1
        completion(result)
    }
}

final class InMemoryContactStore: ContactStoring {
    var contacts: [EmergencyContact]
    init(_ contacts: [EmergencyContact] = []) { self.contacts = contacts }
    func load() -> [EmergencyContact] { contacts }
    func save(_ contacts: [EmergencyContact]) { self.contacts = contacts }
}

// MARK: - Tests

@MainActor
struct SafetyWatcherViewModelTests {

    /// A fixed clock the tests advance manually.
    final class Clock {
        var date: Date
        init(_ date: Date) { self.date = date }
        var now: () -> Date { { self.date } }
    }

    private func makeVM(
        location: MockLocationProvider = MockLocationProvider(),
        gemini: StubGemini = StubGemini(),
        store: InMemoryContactStore = InMemoryContactStore(),
        scheduler: ManualTimerScheduler = ManualTimerScheduler(),
        clock: Clock = Clock(Date(timeIntervalSince1970: 1_000_000))
    ) -> SafetyWatcherViewModel {
        SafetyWatcherViewModel(location: location,
                               gemini: gemini,
                               contactStore: store,
                               scheduler: scheduler,
                               now: clock.now)
    }

    // MARK: - Check-in timer

    @Test func checkInTickPostsMessageAndMovesToChecking() {
        let scheduler = ManualTimerScheduler()
        let vm = makeVM(scheduler: scheduler)
        vm.onAppear()
        let before = vm.messages.count
        #expect(vm.status == .safe)

        scheduler.advance(interval: vm.checkInInterval)

        #expect(vm.messages.count == before + 1)
        #expect(vm.messages.last?.text.contains("checking in") == true)
        #expect(vm.status == .checking)
    }

    // MARK: - Inactivity escalation

    @Test func inactivityPastThresholdEscalates() {
        let scheduler = ManualTimerScheduler()
        let clock = Clock(Date(timeIntervalSince1970: 1_000_000))
        let vm = makeVM(scheduler: scheduler, clock: clock)
        vm.onAppear()

        // Jump past the inactivity threshold without any activity.
        clock.date = clock.date.addingTimeInterval(vm.inactivityThreshold + 10)
        scheduler.advance(interval: 5)

        #expect(vm.status == .alert)
        #expect(vm.showAutoAlert)
    }

    @Test func movementResetsInactivityClock() {
        let scheduler = ManualTimerScheduler()
        let clock = Clock(Date(timeIntervalSince1970: 1_000_000))
        let location = MockLocationProvider()
        let vm = makeVM(location: location, scheduler: scheduler, clock: clock)
        vm.onAppear()

        // Advance most of the way, then move to reset the clock.
        clock.date = clock.date.addingTimeInterval(vm.inactivityThreshold - 10)
        location.move()
        // Now advance past the original deadline; because movement reset the
        // clock, we should NOT have escalated.
        clock.date = clock.date.addingTimeInterval(20)
        scheduler.advance(interval: 5)

        #expect(vm.status != .alert)
        #expect(vm.showAutoAlert == false)
    }

    // MARK: - Safety actions

    @Test func markSafeReturnsToSafeAndPostsReassurance() {
        let vm = makeVM()
        vm.onAppear()
        // Force a non-safe state via a check-in tick first.
        let scheduler = ManualTimerScheduler()
        let vm2 = makeVM(scheduler: scheduler)
        vm2.onAppear()
        scheduler.advance(interval: vm2.checkInInterval)
        #expect(vm2.status == .checking)

        vm2.markSafe()
        #expect(vm2.status == .safe)
        #expect(vm2.messages.last?.text.contains("glad you're okay") == true)
    }

    @Test func startAndArriveWalkClearsSession() {
        let vm = makeVM()
        vm.onAppear()
        vm.walkDestination = "Jester"
        vm.walkMinutes = 10
        vm.startWalk()
        #expect(vm.walkSession != nil)
        #expect(vm.walkSession?.destination == "Jester")

        vm.arriveSafely()
        #expect(vm.walkSession == nil)
        #expect(vm.messages.last?.text.contains("made it to Jester") == true)
    }

    @Test func overdueWalkEscalatesOnceThenClears() {
        let scheduler = ManualTimerScheduler()
        let clock = Clock(Date(timeIntervalSince1970: 1_000_000))
        let vm = makeVM(scheduler: scheduler, clock: clock)
        vm.onAppear()
        vm.walkDestination = "Home"
        vm.walkMinutes = 5
        vm.startWalk()

        // Run past the ETA.
        clock.date = clock.date.addingTimeInterval(5 * 60 + 30)
        scheduler.advance(interval: 5)

        #expect(vm.walkSession == nil)        // cleared after overrun escalation
        #expect(vm.status == .alert)
        #expect(vm.messages.contains { $0.text.contains("didn't arrive in time") })
    }

    // MARK: - Contacts

    @Test func addAndRemoveContactPersists() {
        let store = InMemoryContactStore()
        let vm = makeVM(store: store)
        vm.onAppear()
        vm.newContactName = "Mom"
        vm.newContactPhone = "512-555-0100"
        vm.addContact()

        #expect(vm.contacts.count == 1)
        #expect(store.contacts.count == 1)
        #expect(vm.showAddContact == false)

        let added = vm.contacts[0]
        vm.removeContact(added)
        #expect(vm.contacts.isEmpty)
        #expect(store.contacts.isEmpty)
    }

    @Test func contactsLoadFromStoreOnInit() {
        let store = InMemoryContactStore([EmergencyContact(name: "Dad", phone: "5551234")])
        let vm = makeVM(store: store)
        #expect(vm.contacts.count == 1)
        #expect(vm.contacts.first?.name == "Dad")
    }

    // MARK: - Lifecycle

    @Test func onAppearStartsTrackingAndOnDisappearStops() {
        let location = MockLocationProvider()
        let vm = makeVM(location: location)
        vm.onAppear()
        #expect(location.startTrackingCalled)

        vm.onDisappear()
        #expect(location.stopTrackingCalled)
    }

    @Test func locationChangeMirrorsIntoViewModel() {
        let location = MockLocationProvider()
        let vm = makeVM(location: location)
        vm.onAppear()
        #expect(vm.lastLocation == nil)

        let fix = CLLocation(latitude: 30.28, longitude: -97.73)
        location.emit(fix)
        #expect(vm.lastLocation?.coordinate.latitude == fix.coordinate.latitude)
    }
}
