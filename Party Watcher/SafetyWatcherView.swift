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
        }
        .padding(.horizontal)
        .padding(.top, 16)
        .padding(.bottom, 10)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("SafeWalk")
    }
}
