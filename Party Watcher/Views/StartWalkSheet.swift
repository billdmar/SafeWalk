import SwiftUI

/// Modal sheet for starting a timed walk: a destination and an expected
/// duration. "Start" is disabled until a destination is entered.
struct StartWalkSheet: View {
    @ObservedObject var vm: SafetyWatcherViewModel

    var body: some View {
        NavigationView {
            Form {
                Section("Where are you headed?") {
                    TextField("Destination (e.g. Jester dorm)", text: $vm.walkDestination)
                        .autocapitalization(.words)
                        .disableAutocorrection(true)
                }
                Section("How long should it take?") {
                    Picker("Expected duration", selection: $vm.walkMinutes) {
                        ForEach(WalkTimer.presetMinutes, id: \.self) { mins in
                            Text("\(mins) min").tag(mins)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                Section {
                    Text("If you haven't tapped “I've arrived” by then, SafeWalk escalates — alerting your contact and offering a call to UT Police.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Start a walk")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { vm.showStartWalk = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Start") { vm.startWalk() }
                        .disabled(vm.walkDestination.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
