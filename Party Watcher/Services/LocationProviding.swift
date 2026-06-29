import CoreLocation

/// The slice of location behavior the safety logic depends on.
///
/// Abstracting `LocationManager` behind a protocol lets `SafetyWatcherViewModel`
/// be unit-tested with a mock that publishes synthetic coordinates and triggers
/// movement on demand — without a real `CLLocationManager` or a device.
protocol LocationProviding: AnyObject {
    /// The most recent known location, or `nil` before the first fix.
    var lastLocation: CLLocation? { get }

    /// Invoked when the user moves a significant distance (used to reset the
    /// inactivity clock).
    var onMovement: (() -> Void)? { get set }

    /// Invoked whenever `lastLocation` changes, so an observer can mirror it
    /// (e.g. to drive the map) without binding to a concrete `ObservableObject`.
    var onLocationChange: ((CLLocation?) -> Void)? { get set }

    func startTracking()
    func stopTracking()

    /// Whether to keep delivering location while backgrounded. SafeWalk lets the
    /// user turn this off to conserve battery on short, in-foreground walks.
    func setBackgroundUpdatesEnabled(_ enabled: Bool)
}
