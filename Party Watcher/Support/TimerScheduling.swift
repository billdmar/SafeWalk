import Foundation

/// A cancellable repeating timer, abstracted so the safety logic can be driven
/// by a real `Timer` in the app and by a manual, deterministic ticker in tests.
protocol TimerScheduling {
    /// Schedules `tick` to run every `interval` seconds. The returned handle
    /// stops the timer when cancelled (or deallocated).
    func schedule(every interval: TimeInterval, _ tick: @escaping () -> Void) -> TimerToken
}

/// An opaque handle that cancels its timer when `cancel()` is called.
final class TimerToken {
    private let onCancel: () -> Void
    private var cancelled = false

    init(onCancel: @escaping () -> Void) {
        self.onCancel = onCancel
    }

    func cancel() {
        guard !cancelled else { return }
        cancelled = true
        onCancel()
    }

    deinit { cancel() }
}

/// The production scheduler: a `Timer` on the main run loop.
struct RealTimerScheduler: TimerScheduling {
    func schedule(every interval: TimeInterval, _ tick: @escaping () -> Void) -> TimerToken {
        let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
            tick()
        }
        return TimerToken { timer.invalidate() }
    }
}
