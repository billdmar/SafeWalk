import Foundation
import CoreLocation
import UserNotifications
import UIKit

/// Handles taps on the actionable emergency notification: placing a `tel://`
/// call to campus police on "Call UT Police", or composing a *group* `sms:` to
/// every saved emergency contact (prefilled with a help message and the last
/// known location) on "Text contacts".
///
/// The contacts and coordinate are read from the tapped notification's own
/// `userInfo` payload — an immutable per-notification snapshot embedded by
/// ``NotificationService`` — rather than from shared mutable state. That removes
/// the race where a second, rapid escalation could overwrite the data before
/// the first notification's action was handled.
class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationDelegate()

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let userInfo = response.notification.request.content.userInfo
        switch response.actionIdentifier {
        case NotificationService.callAction:
            let override = userInfo[NotificationService.emergencyNumberKey] as? String
            if let url = Escalation.callURL(override: override) {
                UIApplication.shared.open(url)
            }
        case NotificationService.textAction:
            let phones = (userInfo[NotificationService.phonesKey] as? [String]) ?? []
            let coordinate = Self.coordinate(from: userInfo)
            if let url = Escalation.groupSMSURL(phones: phones, coordinate: coordinate) {
                UIApplication.shared.open(url)
            }
        default:
            break
        }
        completionHandler()
    }

    /// Reconstructs the coordinate embedded in a notification's `userInfo`, or
    /// `nil` if no location was attached.
    private static func coordinate(from userInfo: [AnyHashable: Any]) -> CLLocationCoordinate2D? {
        guard let lat = userInfo[NotificationService.latitudeKey] as? CLLocationDegrees,
              let lon = userInfo[NotificationService.longitudeKey] as? CLLocationDegrees else {
            return nil
        }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }
}
