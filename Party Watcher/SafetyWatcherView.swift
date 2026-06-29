import SwiftUI

/// The app's main screen — a thin composition of focused card subviews.
///
/// All safety state and side effects live in ``SafetyWatcherViewModel``; each
/// card (`StatusHeroView`, `MapCardView`, `WalkCardView`, `QuickActionsView`,
/// `ChatCardView`, `ContactsCardView`) and the two sheets (`AddContactSheet`,
/// `StartWalkSheet`) render a slice of that state and forward user intent.
struct SafetyWatcherView: View {
    @Environment(\.colorScheme) private var scheme
    @StateObject private var vm = SafetyWatcherViewModel()

    var body: some View {
        ZStack {
            Theme.background(scheme)
                .ignoresSafeArea()
            VStack(spacing: 0) {
                appBar
                ScrollView {
                    VStack(spacing: 14) {
                        if vm.lowBatteryWarning { lowBatteryBanner }
                        StatusHeroView(status: vm.status)
                        MapCardView(vm: vm)
                        WalkCardView(vm: vm)
                        QuickActionsView(vm: vm)
                        ChatCardView(vm: vm)
                        ContactsCardView(vm: vm)
                    }
                    .padding(.horizontal)
                    .padding(.top, 4)
                    .padding(.bottom, 16)
                }
            }
        }
        .onAppear { vm.onAppear() }
        .onDisappear { vm.onDisappear() }
        .fullScreenCover(isPresented: $vm.showAddContact) { AddContactSheet(vm: vm) }
        .sheet(isPresented: $vm.showStartWalk) { StartWalkSheet(vm: vm) }
        .sheet(isPresented: $vm.showSettings) { SettingsView(vm: vm) }
        .alert("No response detected! Sending emergency alert.", isPresented: $vm.showAutoAlert) {
            Button("OK", role: .cancel) {}
        }
    }

    private var appBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "shield.lefthalf.fill")
                .foregroundColor(Theme.burntOrange)
                .font(.title2)
            Text("SafeWalk")
                .font(.title2).fontWeight(.heavy)
                .foregroundColor(Theme.burntOrange)
            Spacer()
            Button(action: { vm.showSettings = true }) {
                Image(systemName: "gearshape.fill")
                    .font(.title3)
                    .foregroundColor(Theme.burntOrange)
            }
            .accessibilityLabel("Settings")
            .accessibilityIdentifier("settingsButton")
        }
        .padding(.horizontal)
        .padding(.top, 16)
        .padding(.bottom, 10)
    }

    /// Surfaced when background tracking is on and the battery is critically low.
    private var lowBatteryBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "battery.25")
                .foregroundColor(Theme.alert)
            Text("Low battery — background tracking is draining power. Disable it in Settings to conserve.")
                .font(.caption).fontWeight(.medium)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .padding(12)
        .background(Theme.alert.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}
