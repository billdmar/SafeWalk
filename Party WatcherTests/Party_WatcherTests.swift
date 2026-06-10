//
//  Party_WatcherTests.swift
//  Party WatcherTests
//
//  Created by Bill Mar on 7/23/25.
//

import Testing
import Foundation
@testable import Party_Watcher

struct Party_WatcherTests {

    // MARK: - ChatMessage

    /// A message's sender is carried explicitly, so bubble alignment no longer
    /// depends on a message's position in the list (the old even/odd bug).
    @Test func chatMessageCarriesSenderExplicitly() {
        let user = ChatMessage(text: "I'm okay", isUser: true)
        let bot = ChatMessage(text: "Glad to hear it!", isUser: false)
        #expect(user.isUser == true)
        #expect(bot.isUser == false)
        // Distinct identities even when text repeats.
        let dup = ChatMessage(text: "I'm okay", isUser: true)
        #expect(user.id != dup.id)
    }

    // MARK: - SafetyStatus

    @Test func safetyStatusExposesDistinctPresentation() {
        #expect(SafetyStatus.safe.title == "You're safe")
        #expect(SafetyStatus.checking.title == "Checking in…")
        #expect(SafetyStatus.alert.title == "Alert sent")
        // Each state has its own SF Symbol so the hero icon changes with state.
        let symbols = Set([SafetyStatus.safe.symbol,
                           SafetyStatus.checking.symbol,
                           SafetyStatus.alert.symbol])
        #expect(symbols.count == 3)
    }

    // MARK: - EmergencyContact persistence

    /// Contacts round-trip through the `UserDefaults` Codable helpers.
    @Test func emergencyContactsRoundTripThroughUserDefaults() {
        let defaults = UserDefaults(suiteName: "test.safewalk.contacts")!
        defaults.removePersistentDomain(forName: "test.safewalk.contacts")

        let original = [
            EmergencyContact(name: "Alex Rivera", phone: "512-555-0100"),
            EmergencyContact(name: "Sam Lee", phone: "+1 (737) 555-0199")
        ]
        defaults.saveContacts(original)
        let loaded = defaults.loadContacts()

        #expect(loaded.count == 2)
        #expect(loaded.first?.name == "Alex Rivera")
        #expect(loaded.last?.phone == "+1 (737) 555-0199")

        defaults.removePersistentDomain(forName: "test.safewalk.contacts")
    }

    /// Loading from an empty store yields no contacts rather than throwing.
    @Test func loadingContactsFromEmptyStoreReturnsEmpty() {
        let defaults = UserDefaults(suiteName: "test.safewalk.empty")!
        defaults.removePersistentDomain(forName: "test.safewalk.empty")
        #expect(defaults.loadContacts().isEmpty)
    }
}
