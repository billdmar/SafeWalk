import SwiftUI

/// The walk timer / ETA card. When no walk is active it offers a "Start a walk"
/// button; while a walk is in progress it shows the destination, a live
/// countdown to the expected arrival, and an "I've arrived" button. If the walk
/// runs past its ETA without arriving, the inactivity poll escalates.
struct WalkCardView: View {
    @ObservedObject var vm: SafetyWatcherViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Walk timer", systemImage: "figure.walk")
                .font(.headline)
                .foregroundColor(Theme.burntOrange)
            if let session = vm.walkSession {
                let overdue = session.isOverdue(at: vm.now)
                HStack(spacing: 12) {
                    Image(systemName: overdue ? "exclamationmark.triangle.fill" : "location.north.line.fill")
                        .font(.title3)
                        .foregroundColor(overdue ? Theme.alert : Theme.safe)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Walking to \(session.destination)")
                            .fontWeight(.semibold)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(overdue
                             ? "Past your expected arrival — escalating if you don't arrive."
                             : "Arrive in \(SafetyEngine.countdownString(secondsRemaining: session.secondsRemaining(at: vm.now)))")
                            .font(.caption)
                            .foregroundColor(overdue ? Theme.alert : .secondary)
                    }
                    Spacer()
                }
                Button(action: vm.arriveSafely) {
                    Label("I've arrived", systemImage: "flag.checkered")
                        .font(.subheadline).fontWeight(.semibold)
                        .frame(maxWidth: .infinity, minHeight: 30)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.safe)
                .accessibilityHint("Ends the walk timer and confirms you reached \(session.destination).")
            } else {
                Text("Heading somewhere? Start a timed walk and SafeWalk will escalate if you don't arrive by your ETA.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button(action: { vm.showStartWalk = true }) {
                    Label("Start a walk", systemImage: "figure.walk.departure")
                        .font(.subheadline).fontWeight(.semibold)
                        .frame(maxWidth: .infinity, minHeight: 30)
                }
                .buttonStyle(.bordered)
                .tint(Theme.burntOrange)
                .accessibilityHint("Set a destination and expected duration.")
            }
        }
        .card()
        .accessibilityElement(children: .contain)
    }
}
