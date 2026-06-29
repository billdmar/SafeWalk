import SwiftUI

/// Functional one-tap actions: confirm safety or trigger escalation now.
struct QuickActionsView: View {
    @ObservedObject var vm: SafetyWatcherViewModel

    var body: some View {
        HStack(spacing: 12) {
            Button(action: vm.markSafe) {
                Label("I'm safe", systemImage: "checkmark.circle.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 30)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.safe)
            .accessibilityHint("Resets the check-in timer and lets the companion know you're okay.")

            Button(action: vm.triggerHelpNow) {
                Label("I need help", systemImage: "sos")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 30)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.alert)
            .accessibilityHint("Immediately sends the emergency alert and notification.")
        }
    }
}
