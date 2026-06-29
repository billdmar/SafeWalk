import CoreLocation

/// A map-annotatable wrapper for the user's current coordinate.
struct UserLocation: Identifiable {
    let id = UUID()
    let coordinate: CLLocationCoordinate2D
}
