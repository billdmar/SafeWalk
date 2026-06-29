import SwiftUI
import CoreLocation
import MapKit

/// The live-location card: a MapKit map centered on the user, with the next
/// check-in countdown. Owns its own camera state (pure view concern) and
/// recenters as new fixes arrive.
struct MapCardView: View {
    @ObservedObject var vm: SafetyWatcherViewModel

    /// The map camera. Starts framed on campus and recenters on the user once a
    /// fix arrives. Uses the modern `MapCameraPosition` API (iOS 17+) rather
    /// than the deprecated `MKCoordinateRegion` binding.
    @State private var cameraPosition: MapCameraPosition = .region(
        MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 30.285, longitude: -97.736),
                           span: MKCoordinateSpan(latitudeDelta: 0.005, longitudeDelta: 0.005))
    )

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Live location", systemImage: "location.fill")
                    .font(.headline)
                    .foregroundColor(Theme.burntOrange)
                Spacer()
                HStack(spacing: 6) {
                    Image(systemName: "clock")
                    Text("Next check-in \(vm.timerString)")
                }
                .font(.caption).fontWeight(.semibold)
                .foregroundColor(.secondary)
            }
            if let userLocation = vm.userLocationAnnotation.first {
                Map(position: $cameraPosition) {
                    Marker("You", systemImage: "figure.walk", coordinate: userLocation.coordinate)
                        .tint(Theme.burntOrange)
                }
                .frame(height: 170)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .accessibilityLabel("Map showing your live location")
                .onAppear { recenter(on: vm.lastLocation?.coordinate) }
                .onChange(of: vm.lastLocation) { _, newLoc in
                    recenter(on: newLoc?.coordinate)
                }
            } else {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.gray.opacity(0.12))
                    .frame(height: 170)
                    .overlay(
                        VStack(spacing: 8) {
                            ProgressView()
                            Text("Locating you…")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    )
            }
        }
        .card()
    }

    /// Recenters the map camera on a coordinate, keeping the existing zoom.
    private func recenter(on coordinate: CLLocationCoordinate2D?) {
        guard let coordinate else { return }
        cameraPosition = .region(
            MKCoordinateRegion(center: coordinate,
                               span: MKCoordinateSpan(latitudeDelta: 0.005, longitudeDelta: 0.005))
        )
    }
}
