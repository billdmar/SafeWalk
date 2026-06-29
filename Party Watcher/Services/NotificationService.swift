import Foundation
import CoreLocation
import UserNotifications

/// Builds and posts SafeWalk's escalation notification.
///
/// Two reliability properties matter for a safety feature:
///
/// 1. **Categories are registered once at launch** (`registerCategories()`),
///    not lazily when an escalation fires. Registering an actionable category in
///    the same moment the notification is posted races the notification's own
///    delivery, so the action buttons can be missing on the first alert. Doing
///    it at launch removes that race.
/// 2. **Each notification carries its own immutable payload** in `userInfo`
///    (the contacts to text + the last coordinate), so the delegate reads a
///    per-notification snapshot at tap time instead of a shared mutable
///    singleton that a second, rapid escalation could overwrite.
enum NotificationService {

    static let callCategory = "CALL_UTPD"
    static let escalateCategory = "ESCALATE"
    static let callAction = "CALL_UTPD_ACTION"
    static let textAction = "TEXT_CONTACTS_ACTION"

    // userInfo keys for the per-notification payload.
    static let phonesKey = "phones"
    static let latitudeKey = "lat"
    static let longitudeKey = "lon"
    static let emergencyNumberKey = "emergencyNumber"

    /// Registers the actionable categories and wires the delegate. Call once at
    /// app launch, before any notification can be posted.
    static func registerCategories(center: UNUserNotificationCenter = .current(),
                                   delegate: UNUserNotificationCenterDelegate = NotificationDelegate.shared) {
        let call = UNNotificationAction(identifier: callAction, title: "Call UT Police", options: .foreground)
        let text = UNNotificationAction(identifier: textAction, title: "Text contacts", options: .foreground)
        let callOnly = UNNotificationCategory(identifier: callCategory, actions: [call], intentIdentifiers: [], options: [])
        let escalate = UNNotificationCategory(identifier: escalateCategory, actions: [text, call], intentIdentifiers: [], options: [])
        center.setNotificationCategories([callOnly, escalate])
        center.delegate = delegate
    }

    /// Posts the escalation notification for the given contacts + coordinate.
    /// The payload is embedded in the request's `userInfo` so the action handler
    /// reads an immutable snapshot. `onFailure` runs (on the main queue) if the
    /// system rejects the request, so the caller can fall back to an in-app
    /// escalation instead of failing silently.
    static func postEscalation(contacts: [EmergencyContact],
                               coordinate: CLLocationCoordinate2D?,
                               emergencyNumberOverride: String? = nil,
                               center: UNUserNotificationCenter = .current(),
                               onFailure: (() -> Void)? = nil) {
        let textableCount = Escalation.dialableCount(in: contacts.map(\.phone))
        let displayNumber = Escalation.displayNumber(override: emergencyNumberOverride)

        let content = UNMutableNotificationContent()
        content.title = "No response detected!"
        if textableCount > 0 {
            let noun = textableCount == 1 ? "contact" : "contacts"
            content.body = "Tap to call \(displayNumber) or text your \(textableCount) emergency \(noun) immediately."
        } else {
            content.body = "Tap to call \(displayNumber) immediately."
        }
        content.sound = .default
        content.categoryIdentifier = textableCount > 0 ? escalateCategory : callCategory

        // Per-notification payload — read by the delegate at tap time.
        var userInfo: [String: Any] = [phonesKey: contacts.map(\.phone)]
        if let coordinate {
            userInfo[latitudeKey] = coordinate.latitude
            userInfo[longitudeKey] = coordinate.longitude
        }
        if let emergencyNumberOverride, !emergencyNumberOverride.isEmpty {
            userInfo[emergencyNumberKey] = emergencyNumberOverride
        }
        content.userInfo = userInfo

        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        center.add(request) { error in
            if let error {
                #if DEBUG
                print("[NotificationService] Failed to post escalation: \(error)")
                #endif
                DispatchQueue.main.async { onFailure?() }
            }
        }
    }
}
