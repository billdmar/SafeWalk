import Foundation
import CoreLocation
import UserNotifications
import UIKit

/// Handles taps on the actionable emergency notification. Placing a `tel://`
/// call to campus police on "Call UT Police", or composing a *group* `sms:` to
/// every saved emergency contact (prefilled with a help message and the last
/// known location) on "Text <n> contacts".
///
/// A shared singleton so it outlives the notification and so the escalation code
/// can hand it the current contacts + coordinate before posting the notification.
class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationDelegate()

    /// The contacts to text when the user taps the contact action. Set by the
    /// escalation code right before a notification is posted.
    var contacts: [EmergencyContact] = []
    /// The most recent known coordinate, embedded into the SMS body if present.
    var lastCoordinate: CLLocationCoordinate2D?

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        switch response.actionIdentifier {
        case "CALL_UTPD_ACTION":
            if let url = Escalation.utpdCallURL() {
                UIApplication.shared.open(url)
            }
        case "TEXT_CONTACTS_ACTION":
            if let url = Escalation.groupSMSURL(phones: contacts.map(\.phone), coordinate: lastCoordinate) {
                UIApplication.shared.open(url)
            }
        default:
            break
        }
        completionHandler()
    }
}
