import Foundation

/// Persistence for the user's emergency contacts, abstracted so the view model
/// can be tested with an in-memory store instead of `UserDefaults`.
protocol ContactStoring {
    func load() -> [EmergencyContact]
    func save(_ contacts: [EmergencyContact])
}

/// The production store, backed by `UserDefaults` via the existing
/// `saveContacts`/`loadContacts` helpers.
struct ContactStore: ContactStoring {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> [EmergencyContact] {
        defaults.loadContacts()
    }

    func save(_ contacts: [EmergencyContact]) {
        defaults.saveContacts(contacts)
    }
}
