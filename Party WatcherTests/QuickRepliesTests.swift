//
//  QuickRepliesTests.swift
//  Party WatcherTests
//
//  Regression guards for the deterministic chat quick replies: the catalog is
//  well-formed (unique labels, exactly one escalating option) and the
//  label→response mapping is stable. These are what make the chat feel like an
//  AI while staying fully deterministic and network-free.
//

import Testing
import Foundation
@testable import Party_Watcher

struct QuickRepliesTests {

    @Test func catalogIsNonEmptyWithUniqueLabels() {
        let labels = QuickReplies.all.map(\.label)
        #expect(!labels.isEmpty)
        #expect(Set(labels).count == labels.count) // no duplicates
    }

    @Test func everyReplyHasANonEmptyResponse() {
        for reply in QuickReplies.all {
            #expect(!reply.botResponse.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    /// Exactly one button escalates, so a distress tap is unambiguous and we
    /// don't accidentally ship two (or zero) ways to trigger help from the row.
    @Test func exactlyOneReplyEscalates() {
        let escalators = QuickReplies.all.filter { $0.effect == .escalate }
        #expect(escalators.count == 1)
        #expect(escalators.first?.label.contains("help") == true)
    }

    @Test func responseLookupReturnsTheMatchingReply() {
        let known = QuickReplies.all[0]
        let found = QuickReplies.response(for: known.label)
        #expect(found == known)
        #expect(found?.botResponse == known.botResponse)
    }

    @Test func responseLookupIsNilForUnknownLabel() {
        #expect(QuickReplies.response(for: "this is not a quick reply") == nil)
    }

    /// The reassuring options confirm safety; the lookup is deterministic — the
    /// same label always yields the same effect.
    @Test func effectsAreStablePerLabel() {
        #expect(QuickReplies.response(for: "I'm okay 👍")?.effect == .reassure)
        #expect(QuickReplies.response(for: "Just walking")?.effect == .neutral)
        #expect(QuickReplies.response(for: "I need help 🚨")?.effect == .escalate)
    }
}
