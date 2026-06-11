//
//  Escalation.swift
//  Party Watcher
//
//  Pure builders for SafeWalk's escalation deep links and message bodies,
//  extracted from `NotificationDelegate` so the safety-critical part — turning
//  a user-entered phone number and a last-known coordinate into a valid
//  `sms:` / `tel:` URL — can be unit-tested without the notification runtime.
//
//  A malformed escalation URL means help never gets summoned, so these helpers
//  are deliberately small, total, and covered by regression tests.
//

import Foundation
import CoreLocation

/// Builds the deep links and message bodies used when SafeWalk escalates.
enum Escalation {
    /// UT Austin Police Department's published emergency line.
    static let utpdPhoneDigits = "5124714441"
    static let utpdDisplayNumber = "512-471-4441"

    /// Normalizes a user-entered phone string to the digits (and a leading `+`)
    /// that a `tel:` / `sms:` URL accepts. Returns `nil` when nothing dialable
    /// remains, so callers can fail safe rather than open a broken URL.
    ///
    /// Examples: `"+1 (737) 555-0199"` → `"+17375550199"`; `"abc"` → `nil`.
    static func dialableDigits(from raw: String) -> String? {
        let kept = raw.filter { $0.isNumber || $0 == "+" }
        // A bare "+" with no digits is not dialable.
        return kept.contains(where: { $0.isNumber }) ? kept : nil
    }

    /// The prefilled SMS body sent to an emergency contact, optionally embedding
    /// a Maps link to the user's last known location.
    ///
    /// Kept as a pure function so the wording — and the conditional inclusion of
    /// the location link — is verified without posting a real notification.
    static func smsBody(coordinate: CLLocationCoordinate2D?) -> String {
        var body = "I may need help. This is SafeWalk reaching out on my behalf — please check on me."
        if let coordinate {
            body += " My last location: \(mapsLink(for: coordinate))"
        }
        return body
    }

    /// An Apple Maps URL string for a coordinate.
    static func mapsLink(for coordinate: CLLocationCoordinate2D) -> String {
        "https://maps.apple.com/?ll=\(coordinate.latitude),\(coordinate.longitude)"
    }

    /// Builds the `sms:` deep link to a contact, prefilled with the help body.
    /// Returns `nil` when the contact's number has no dialable digits.
    static func smsURL(phone: String, coordinate: CLLocationCoordinate2D?) -> URL? {
        guard let digits = dialableDigits(from: phone) else { return nil }
        var components = URLComponents()
        components.scheme = "sms"
        components.path = digits
        components.queryItems = [URLQueryItem(name: "body", value: smsBody(coordinate: coordinate))]
        return components.url
    }

    /// The `tel:` URL for UTPD. Static and always valid; provided as a function
    /// so the call site has a single source of truth.
    static func utpdCallURL() -> URL? {
        URL(string: "tel://\(utpdPhoneDigits)")
    }
}
