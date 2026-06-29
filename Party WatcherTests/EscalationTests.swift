//
//  EscalationTests.swift
//  Party WatcherTests
//
//  Regression guards around the escalation deep-link builders in `Escalation`.
//  A malformed `sms:` / `tel:` URL means help never reaches the contact, so the
//  number normalization and URL construction are covered here, including the
//  fail-safe `nil` for an undialable number.
//

import Testing
import Foundation
import CoreLocation
@testable import Party_Watcher

struct EscalationTests {

    // MARK: - Phone normalization

    @Test func stripsFormattingToDialableDigits() {
        #expect(Escalation.dialableDigits(from: "+1 (737) 555-0199") == "+17375550199")
        #expect(Escalation.dialableDigits(from: "512-555-0100") == "5125550100")
    }

    /// A number with no digits is not dialable — callers fail safe.
    @Test func undialableNumbersReturnNil() {
        #expect(Escalation.dialableDigits(from: "") == nil)
        #expect(Escalation.dialableDigits(from: "no digits here") == nil)
        #expect(Escalation.dialableDigits(from: "+") == nil)
    }

    // MARK: - SMS body

    @Test func smsBodyOmitsLocationWhenUnknown() {
        let body = Escalation.smsBody(coordinate: nil)
        #expect(body.contains("I may need help"))
        #expect(!body.contains("maps.apple.com"))
    }

    @Test func smsBodyIncludesMapsLinkWhenLocationKnown() {
        let coord = CLLocationCoordinate2D(latitude: 30.285, longitude: -97.736)
        let body = Escalation.smsBody(coordinate: coord)
        #expect(body.contains("https://maps.apple.com/?ll=30.285,-97.736"))
    }

    // MARK: - SMS URL

    @Test func smsURLBuildsForValidNumber() {
        let url = Escalation.smsURL(phone: "512-555-0100", coordinate: nil)
        #expect(url != nil)
        #expect(url?.scheme == "sms")
        #expect(url?.absoluteString.contains("5125550100") == true)
        // The help body is percent-encoded into the query.
        #expect(url?.query?.contains("body=") == true)
    }

    /// An undialable number yields no URL, so escalation can fall back rather
    /// than opening a broken link.
    @Test func smsURLNilForUndialableNumber() {
        #expect(Escalation.smsURL(phone: "garbage", coordinate: nil) == nil)
    }

    // MARK: - Group SMS (multi-contact escalation)

    @Test func groupSMSURLAddressesAllDialableContacts() {
        let url = Escalation.groupSMSURL(phones: ["512-555-0100", "+1 (737) 555-0199"], coordinate: nil)
        #expect(url?.scheme == "sms")
        // Both numbers, comma-joined, drive iOS's group compose.
        #expect(url?.absoluteString.contains("5125550100,+17375550199") == true)
        #expect(url?.query?.contains("body=") == true)
    }

    /// A single bad entry is dropped, not allowed to suppress escalation to the
    /// others — the safety-critical fail-safe.
    @Test func groupSMSURLSkipsUndialableButKeepsValidOnes() {
        let url = Escalation.groupSMSURL(phones: ["garbage", "512-555-0100"], coordinate: nil)
        #expect(url != nil)
        #expect(url?.absoluteString.contains("5125550100") == true)
        #expect(url?.absoluteString.contains("garbage") == false)
    }

    /// Only when *no* contact is dialable does the group URL fail (caller falls
    /// back to UTPD-only).
    @Test func groupSMSURLNilWhenNoDialableContacts() {
        #expect(Escalation.groupSMSURL(phones: ["garbage", "", "+"], coordinate: nil) == nil)
        #expect(Escalation.groupSMSURL(phones: [], coordinate: nil) == nil)
    }

    @Test func dialableCountIgnoresUndialableEntries() {
        #expect(Escalation.dialableCount(in: ["512-555-0100", "garbage", "+1 737 555 0199"]) == 2)
        #expect(Escalation.dialableCount(in: []) == 0)
    }

    // MARK: - UTPD call

    @Test func utpdCallURLIsValidTelLink() {
        let url = Escalation.utpdCallURL()
        #expect(url?.absoluteString == "tel://5124714441")
    }

    // MARK: - Emergency number override

    /// A dialable override is used for the call URL and the display copy.
    @Test func overrideNumberIsUsedWhenDialable() {
        #expect(Escalation.callURL(override: "512-555-0123")?.absoluteString == "tel://5125550123")
        #expect(Escalation.displayNumber(override: "512-555-0123") == "512-555-0123")
    }

    /// A nil / blank / undialable override falls back to UTPD — escalation can
    /// never be left without a number to call.
    @Test func overrideFallsBackToUTPDWhenMissingOrInvalid() {
        #expect(Escalation.callURL(override: nil)?.absoluteString == "tel://5124714441")
        #expect(Escalation.callURL(override: "")?.absoluteString == "tel://5124714441")
        #expect(Escalation.callURL(override: "garbage")?.absoluteString == "tel://5124714441")
        #expect(Escalation.displayNumber(override: nil) == Escalation.utpdDisplayNumber)
        #expect(Escalation.displayNumber(override: "nope") == Escalation.utpdDisplayNumber)
    }
}
