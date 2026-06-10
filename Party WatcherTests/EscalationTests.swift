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

    // MARK: - UTPD call

    @Test func utpdCallURLIsValidTelLink() {
        let url = Escalation.utpdCallURL()
        #expect(url?.absoluteString == "tel://5124714441")
    }
}
