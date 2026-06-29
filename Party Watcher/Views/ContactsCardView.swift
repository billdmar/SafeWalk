import SwiftUI

/// The emergency-contacts panel: lists saved contacts and offers add/remove.
struct ContactsCardView: View {
    @ObservedObject var vm: SafetyWatcherViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Emergency contacts", systemImage: "person.2.fill")
                    .font(.headline)
                    .foregroundColor(Theme.burntOrange)
                Spacer()
                Button(action: { vm.showAddContact = true }) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .foregroundColor(Theme.burntOrange)
                }
                .accessibilityLabel("Add emergency contact")
                .accessibilityIdentifier("addContactButton")
            }
            if vm.contacts.isEmpty {
                Text("Add a trusted contact so SafeWalk can offer a one-tap text to them if you stop responding.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(vm.contacts) { contact in
                    contactRow(contact)
                }
            }
        }
        .card()
    }

    private func contactRow(_ contact: EmergencyContact) -> some View {
        HStack {
            ZStack {
                Circle().fill(Theme.burntOrange.opacity(0.15)).frame(width: 36, height: 36)
                Text(initials(for: contact.name))
                    .font(.caption).fontWeight(.bold)
                    .foregroundColor(Theme.burntOrange)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(contact.name).fontWeight(.semibold)
                Text(contact.phone).font(.caption).foregroundColor(.secondary)
            }
            Spacer()
            Button(action: { vm.removeContact(contact) }) {
                Image(systemName: "trash").foregroundColor(Theme.alert)
            }
            .accessibilityLabel("Remove \(contact.name)")
        }
        .padding(.vertical, 2)
    }

    private func initials(for name: String) -> String {
        let parts = name.split(separator: " ")
        let letters = parts.prefix(2).compactMap { $0.first }
        return String(letters).uppercased()
    }
}
