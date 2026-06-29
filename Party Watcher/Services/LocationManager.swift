import Foundation
import CoreLocation

/// Publishes the user's live location and reports significant movement.
///
/// Wraps `CLLocationManager`, requests *always* authorization (escalating from
/// when-in-use so the user sees the standard two-step iOS prompt), and publishes
/// `lastLocation` for the map. Once "Always" is granted it enables background
/// location updates so SafeWalk can keep watching even when the screen is locked
/// or the app is backgrounded. When the user moves more than 5 metres between
/// updates it fires `onMovement`, which the safety logic uses to reset the
/// inactivity timer.
///
/// Note: background GPS delivery, the "Always" prompt, and lock-screen wakeups
/// are verified on a device/simulator, not in CI.
class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    @Published var lastLocation: CLLocation?
    var onMovement: (() -> Void)?
    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.pausesLocationUpdatesAutomatically = false
    }
    func startTracking() {
        // Request the strongest authorization available. iOS first surfaces the
        // when-in-use prompt and then offers the upgrade to "Always", which is
        // what background tracking requires.
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse:
            manager.requestAlwaysAuthorization()
        default:
            break
        }
        manager.startUpdatingLocation()
        enableBackgroundUpdatesIfPermitted()
    }
    func stopTracking() {
        manager.allowsBackgroundLocationUpdates = false
        manager.stopUpdatingLocation()
    }

    /// Enables background location updates, but only once the user has granted
    /// "Always" authorization. Setting `allowsBackgroundLocationUpdates = true`
    /// without the location background mode + always auth crashes at runtime, so
    /// this is guarded and called after updates have started.
    private func enableBackgroundUpdatesIfPermitted() {
        guard manager.authorizationStatus == .authorizedAlways else { return }
        // Setting `allowsBackgroundLocationUpdates = true` throws a runtime
        // exception (SIGABRT) unless "location" is declared in the bundle's
        // UIBackgroundModes. Verify it's actually present before enabling, so a
        // misconfigured Info.plist degrades to foreground-only tracking instead
        // of crashing on launch.
        let backgroundModes = Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String] ?? []
        guard backgroundModes.contains("location") else { return }
        manager.allowsBackgroundLocationUpdates = true
        manager.pausesLocationUpdatesAutomatically = false
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse:
            // Escalate to Always so background tracking can be enabled.
            manager.requestAlwaysAuthorization()
        case .authorizedAlways:
            enableBackgroundUpdatesIfPermitted()
        default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let newLocation = locations.last
        if let last = lastLocation, let newLoc = newLocation {
            let distance = last.distance(from: newLoc)
            if SafetyEngine.isSignificantMovement(distance: distance) {
                onMovement?()
            }
        }
        lastLocation = newLocation
    }
}
