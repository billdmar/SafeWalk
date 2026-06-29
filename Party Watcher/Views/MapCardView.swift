import SwiftUI
import CoreLocation
import MapKit

/// The live-location card: a MapKit map centered on the user, with the next
/// check-in countdown. Owns its own camera state (a pure view concern).
///
/// The camera follows the user's *first* fix, then stops auto-recentering so a
/// stream of location updates doesn't yank the map back while the user is
/// panning around to look at the area. A "locate me" button re-centers on
/// demand.
struct MapCardView: View {
    @ObservedObject var vm: SafetyWatcherViewModel

    /// The map camera. Starts framed on campus and recenters on the first fix
    /// (and on an explicit recenter tap). Uses the modern `MapCameraPosition`
    /// API (iOS 17+) rather than the deprecated `MKCoordinateRegion` binding.
    @State private var cameraPosition: MapCameraPosition = .region(
        MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 30.285, longitude: -97.736),
                           span: MKCoordinateSpan(latitudeDelta: 0.005, longitudeDelta: 0.005))
    )
    /// Whether the camera has already centered on a real fix. After that we stop
    /// auto-recentering so the user's panning is preserved.
    @State private var hasCenteredOnce = false

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
                .overlay(alignment: .bottomTrailing) { recenterButton(to: userLocation.coordinate) }
                .accessibilityLabel("Map showing your live location")
                .onAppear { centerOnFirstFix(vm.lastLocation?.coordinate) }
                .onChange(of: vm.lastLocation) { _, newLoc in
                    centerOnFirstFix(newLoc?.coordinate)
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

    private func recenterButton(to coordinate: CLLocationCoordinate2D) -> some View {
        Button {
            recenter(on: coordinate)
        } label: {
            Image(systemName: "location.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(Theme.burntOrange)
                .padding(8)
                .background(.regularMaterial, in: Circle())
        }
        .padding(10)
        .accessibilityLabel("Recenter map on my location")
    }

    /// Centers the camera the first time a real fix arrives, then leaves it alone
    /// so subsequent updates don't fight the user's panning.
    private func centerOnFirstFix(_ coordinate: CLLocationCoordinate2D?) {
        guard !hasCenteredOnce, let coordinate else { return }
        hasCenteredOnce = true
        recenter(on: coordinate)
    }

    /// Recenters the map camera on a coordinate, keeping the existing zoom.
    private func recenter(on coordinate: CLLocationCoordinate2D) {
        withAnimation {
            cameraPosition = .region(
                MKCoordinateRegion(center: coordinate,
                                   span: MKCoordinateSpan(latitudeDelta: 0.005, longitudeDelta: 0.005))
            )
        }
    }
}
