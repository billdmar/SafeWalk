import SwiftUI

/// User-facing settings: check-in cadence, inactivity threshold, background
/// tracking, AI history depth, an optional campus emergency number, and a
/// "clear chat" action. Edits a local copy and commits via `vm.applySettings`
/// on save so the timers re-arm atomically.
struct SettingsView: View {
    @ObservedObject var vm: SafetyWatcherViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var draft: SafetySettings
    @State private var showClearConfirm = false

    init(vm: SafetyWatcherViewModel) {
        self.vm = vm
        _draft = State(initialValue: vm.settings)
    }

    var body: some View {
        NavigationView {
            Form {
                Section("Check-ins") {
                    Picker("Check in every", selection: $draft.checkInInterval) {
                        ForEach(SafetySettings.checkInOptions, id: \.self) { secs in
                            Text(label(forSeconds: secs)).tag(secs)
                        }
                    }
                    Picker("Escalate after no activity for", selection: $draft.inactivityThreshold) {
                        ForEach(SafetySettings.inactivityOptions, id: \.self) { secs in
                            Text(label(forSeconds: secs)).tag(secs)
                        }
                    }
                }

                Section {
                    Toggle("Background location", isOn: $draft.backgroundLocationEnabled)
                } header: {
                    Text("Tracking")
                } footer: {
                    Text("Keeps watching your walk when the screen is locked. Turning this off saves battery but stops monitoring while SafeWalk is in the background.")
                }

                Section {
                    TextField("e.g. 512-471-4441", text: emergencyNumberBinding)
                        .keyboardType(.phonePad)
                        .disableAutocorrection(true)
                } header: {
                    Text("Emergency number")
                } footer: {
                    Text("The number the escalation alert dials. Leave blank to use UT Austin Police (\(Escalation.utpdDisplayNumber)).")
                }

                Section {
                    Stepper("AI memory: \(draft.historyTurnLimit) messages",
                            value: $draft.historyTurnLimit, in: 4...50, step: 2)
                } header: {
                    Text("AI companion")
                } footer: {
                    Text("How many recent messages the companion remembers for context. Fewer is faster and cheaper.")
                }

                Section {
                    Button(role: .destructive) {
                        showClearConfirm = true
                    } label: {
                        Label("Clear chat history", systemImage: "trash")
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        vm.applySettings(draft)
                        dismiss()
                    }
                }
            }
            .confirmationDialog("Clear the check-in chat?",
                                isPresented: $showClearConfirm, titleVisibility: .visible) {
                Button("Clear chat", role: .destructive) {
                    vm.clearChat()
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            }
        }
    }

    /// Binds the optional override to a non-optional text field (empty == nil).
    private var emergencyNumberBinding: Binding<String> {
        Binding(
            get: { draft.emergencyNumberOverride ?? "" },
            set: { draft.emergencyNumberOverride = $0.isEmpty ? nil : $0 }
        )
    }

    private func label(forSeconds seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        if mins == 0 { return "\(secs) sec" }
        if secs == 0 { return mins == 1 ? "1 min" : "\(mins) min" }
        return "\(mins) min \(secs) sec"
    }
}
