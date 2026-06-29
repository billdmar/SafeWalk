import Foundation

/// A trusted contact the user can notify in an emergency. Persisted via `UserDefaults`.
struct EmergencyContact: Identifiable, Codable, Hashable {
    let id = UUID()
    var name: String
    var phone: String
}

// MARK: - UserDefaults persistence

extension UserDefaults {
    func saveContacts(_ contacts: [EmergencyContact]) {
        if let data = try? JSONEncoder().encode(contacts) {
            set(data, forKey: "emergencyContacts")
        }
    }
    func loadContacts() -> [EmergencyContact] {
        if let data = data(forKey: "emergencyContacts"), let contacts = try? JSONDecoder().decode([EmergencyContact].self, from: data) {
            return contacts
        }
        return []
    }
}
