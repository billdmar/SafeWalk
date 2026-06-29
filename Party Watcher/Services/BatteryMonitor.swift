import Foundation
import UIKit

/// The battery state SafeWalk cares about for its low-battery warning,
/// abstracted so the view model can be tested without a real device (the
/// Simulator reports `-1` / `.unknown`).
protocol BatteryMonitoring: AnyObject {
    /// 0.0–1.0, or `nil` when the level is unknown (e.g. the Simulator).
    var level: Float? { get }
    /// Whether the device is currently charging or full.
    var isCharging: Bool { get }
    /// Called when the level or charging state changes.
    var onChange: (() -> Void)? { get set }
    func start()
    func stop()
}

/// The production monitor, backed by `UIDevice` battery APIs.
final class BatteryMonitor: BatteryMonitoring {
    var onChange: (() -> Void)?
    private var observers: [NSObjectProtocol] = []

    var level: Float? {
        let value = UIDevice.current.batteryLevel
        // UIDevice reports -1 when monitoring is off or the level is unknown.
        return value < 0 ? nil : value
    }

    var isCharging: Bool {
        switch UIDevice.current.batteryState {
        case .charging, .full: return true
        default: return false
        }
    }

    func start() {
        UIDevice.current.isBatteryMonitoringEnabled = true
        let center = NotificationCenter.default
        let handler: (Notification) -> Void = { [weak self] _ in self?.onChange?() }
        observers = [
            center.addObserver(forName: UIDevice.batteryLevelDidChangeNotification, object: nil, queue: .main, using: handler),
            center.addObserver(forName: UIDevice.batteryStateDidChangeNotification, object: nil, queue: .main, using: handler)
        ]
    }

    func stop() {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers.removeAll()
        UIDevice.current.isBatteryMonitoringEnabled = false
    }
}
