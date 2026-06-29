import Foundation

/// Persistence for `SafetySettings`, abstracted so the view model can be tested
/// with an in-memory store instead of `UserDefaults`.
protocol SettingsStoring {
    func load() -> SafetySettings
    func save(_ settings: SafetySettings)
}

/// The production store, JSON-encoding settings into `UserDefaults`.
struct SettingsStore: SettingsStoring {
    private let defaults: UserDefaults
    private let key = "safetySettings"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> SafetySettings {
        guard let data = defaults.data(forKey: key),
              let settings = try? JSONDecoder().decode(SafetySettings.self, from: data) else {
            return .default
        }
        return settings
    }

    func save(_ settings: SafetySettings) {
        if let data = try? JSONEncoder().encode(settings) {
            defaults.set(data, forKey: key)
        }
    }
}
