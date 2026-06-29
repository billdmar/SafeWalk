import SwiftUI

/// Modal sheet for adding a new emergency contact. The "Add" button is disabled
/// until both a name and phone number are entered.
struct AddContactSheet: View {
    @ObservedObject var vm: SafetyWatcherViewModel

    private var isDisabled: Bool {
        vm.newContactName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || vm.newContactPhone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 16) {
            Text("Add Emergency Contact").font(.headline)
            TextField("Name", text: $vm.newContactName)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .autocapitalization(.words)
                .disableAutocorrection(true)
            TextField("Phone Number", text: $vm.newContactPhone)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .keyboardType(.phonePad)
                .autocapitalization(.none)
                .disableAutocorrection(true)
            Button("Add") { vm.addContact() }
                .disabled(isDisabled)
                .padding()
                .frame(maxWidth: .infinity)
                .background(isDisabled ? Color.gray.opacity(0.3) : Theme.burntOrange)
                .foregroundColor(.white)
                .cornerRadius(12)
            Button("Cancel") { vm.showAddContact = false }
                .padding(.top, 4)
        }
        .padding()
    }
}
