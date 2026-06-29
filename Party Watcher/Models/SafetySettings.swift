import Foundation

/// User-tunable safety preferences, persisted across launches.
///
/// The thresholds here feed directly into the (already parameterized)
/// `SafetyEngine.decide(...)` and the check-in timer, so adjusting them changes
/// real behavior with no engine change. Codable so it round-trips through
/// `UserDefaults` as JSON.
struct SafetySettings: Codable, Equatable {
    /// How often the companion proactively checks in (seconds).
    var checkInInterval: TimeInterval
    /// How long without a reply *or* movement before SafeWalk escalates (seconds).
    var inactivityThreshold: TimeInterval
    /// Whether to keep tracking location while backgrounded / screen-locked.
    var backgroundLocationEnabled: Bool
    /// How many recent conversation turns (besides the system prompt) to send
    /// to Gemini.
    var historyTurnLimit: Int
    /// An optional campus/police number to dial on escalation instead of the
    /// built-in UTPD default. Stored as the user typed it; normalized at dial
    /// time. `nil`/empty means use UTPD.
    var emergencyNumberOverride: String?

    static let `default` = SafetySettings(
        checkInInterval: 60,
        inactivityThreshold: 120,
        backgroundLocationEnabled: true,
        historyTurnLimit: 20,
        emergencyNumberOverride: nil
    )

    /// Selectable check-in cadences shown in the picker (seconds).
    static let checkInOptions: [TimeInterval] = [30, 60, 120, 300]
    /// Selectable inactivity thresholds shown in the picker (seconds).
    static let inactivityOptions: [TimeInterval] = [60, 120, 300, 600]
}
