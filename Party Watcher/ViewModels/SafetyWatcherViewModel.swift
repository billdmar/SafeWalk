import Foundation
import SwiftUI
import CoreLocation
import UserNotifications

/// The brain behind the main screen.
///
/// `SafetyWatcherViewModel` owns all of SafeWalk's safety state and side effects
/// — the check-in chat, the live location mirror, the three timers that drive
/// the safety logic, contact persistence, and escalation orchestration — leaving
/// `SafetyWatcherView` to render that state and forward user intent.
///
/// Every dependency is injected through the initializer (`LocationProviding`,
/// `GeminiSending`, `ContactStoring`, `TimerScheduling`, and a `now` clock) so
/// the whole controller can be unit-tested deterministically, without a real
/// `CLLocationManager`, network, `UserDefaults`, or wall-clock waits.
@MainActor
final class SafetyWatcherViewModel: ObservableObject {

    // MARK: - Published state

    @Published private(set) var messages: [ChatMessage] = [
        ChatMessage(text: "👋 Hi! I'll check in with you as you walk. Reply to my messages so I know you're safe!", isUser: false)
    ]
    @Published var userInput: String = ""
    @Published private(set) var status: SafetyStatus = .safe
    @Published private(set) var isLoadingResponse = false
    @Published private(set) var contacts: [EmergencyContact] = []
    @Published var walkSession: WalkSession?
    @Published private(set) var lastLocation: CLLocation?
    @Published private(set) var nextCheckIn: Date
    @Published private(set) var now: Date

    // Presentation + draft state surfaced to the view's sheets.
    @Published var showAddContact = false
    @Published var showStartWalk = false
    @Published var showSettings = false
    @Published var showAutoAlert = false
    @Published var newContactName = ""
    @Published var newContactPhone = ""
    @Published var walkDestination = ""
    @Published var walkMinutes = 15

    /// User-tunable preferences (thresholds, background tracking, etc.).
    @Published private(set) var settings: SafetySettings
    /// Set when background tracking is on and the battery is critically low, so
    /// the UI can suggest disabling background location to conserve power.
    @Published private(set) var lowBatteryWarning = false

    // MARK: - Configuration (driven by `settings`)

    var checkInInterval: TimeInterval { settings.checkInInterval }
    var inactivityThreshold: TimeInterval { settings.inactivityThreshold }
    /// How many recent conversation turns (besides the leading system prompt) to
    /// send to Gemini. Bounds an ever-growing history on a long walk.
    var historyTurnLimit: Int { settings.historyTurnLimit }

    // MARK: - Dependencies

    private let location: LocationProviding
    private let gemini: GeminiSending
    private let contactStore: ContactStoring
    private let settingsStore: SettingsStoring
    private let chatStore: ChatHistoryStoring
    private let battery: BatteryMonitoring?
    private let scheduler: TimerScheduling
    private let clock: () -> Date

    /// The leading system prompt that sets the companion's behavior.
    private static let systemPrompt = "You are a friendly safety companion for students walking alone at night. Keep responses short, supportive, and focused on safety."

    // MARK: - Private state

    private var lastResponseDate: Date
    private var lastMovementDate: Date
    private var conversation: [GeminiManager.GeminiMessage]
    private var checkInToken: TimerToken?
    private var inactivityToken: TimerToken?
    private var displayToken: TimerToken?

    // MARK: - Init

    init(location: LocationProviding = LocationManager(),
         gemini: GeminiSending = GeminiManager.shared,
         contactStore: ContactStoring = ContactStore(),
         settingsStore: SettingsStoring = SettingsStore(),
         chatStore: ChatHistoryStoring = ChatHistoryStore(),
         battery: BatteryMonitoring? = BatteryMonitor(),
         scheduler: TimerScheduling = RealTimerScheduler(),
         now: @escaping () -> Date = Date.init) {
        self.location = location
        self.gemini = gemini
        self.contactStore = contactStore
        self.settingsStore = settingsStore
        self.chatStore = chatStore
        self.battery = battery
        self.scheduler = scheduler
        self.clock = now
        let loadedSettings = settingsStore.load()
        self.settings = loadedSettings
        let start = now()
        self.now = start
        self.lastResponseDate = start
        self.lastMovementDate = start
        self.nextCheckIn = start.addingTimeInterval(loadedSettings.checkInInterval)
        self.contacts = contactStore.load()
        self.lastLocation = location.lastLocation

        // Restore a persisted chat, or start a fresh one with the system prompt.
        if let saved = chatStore.load(), !saved.messages.isEmpty {
            self.messages = saved.messages.map { ChatMessage(text: $0.text, isUser: $0.isUser) }
            self.conversation = saved.conversation.map { .init(role: $0.role, parts: [.init(text: $0.text)]) }
        } else {
            self.conversation = [.init(role: "user", parts: [.init(text: Self.systemPrompt)])]
        }
    }

    // MARK: - Derived state

    var inputIsEmpty: Bool {
        userInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// The user's location as a map annotation, or empty before the first fix.
    var userLocationAnnotation: [UserLocation] {
        if let loc = lastLocation {
            return [UserLocation(coordinate: loc.coordinate)]
        }
        return []
    }

    /// The "Next check-in" countdown string. Reads `now` (advanced by the
    /// display timer) so it re-renders every second.
    var timerString: String {
        SafetyEngine.countdownString(secondsRemaining: nextCheckIn.timeIntervalSince(now))
    }

    // MARK: - Lifecycle

    func onAppear() {
        location.onMovement = { [weak self] in
            self?.registerMovement()
        }
        location.onLocationChange = { [weak self] newLocation in
            self?.lastLocation = newLocation
        }
        location.setBackgroundUpdatesEnabled(settings.backgroundLocationEnabled)
        location.startTracking()
        startCheckInTimer()
        startInactivityTimer()
        startDisplayTimer()
        requestNotificationPermission()

        battery?.onChange = { [weak self] in self?.refreshBatteryWarning() }
        battery?.start()
        refreshBatteryWarning()
    }

    func onDisappear() {
        location.stopTracking()
        location.onMovement = nil
        location.onLocationChange = nil
        battery?.onChange = nil
        battery?.stop()
        checkInToken?.cancel()
        inactivityToken?.cancel()
        displayToken?.cancel()
    }

    /// Warn when background tracking is on, the battery is critically low, and
    /// the device isn't charging — background GPS is the biggest drain. No-ops
    /// when the level is unknown (e.g. the Simulator reports `nil`).
    private func refreshBatteryWarning() {
        guard settings.backgroundLocationEnabled, let level = battery?.level else {
            lowBatteryWarning = false
            return
        }
        lowBatteryWarning = level < 0.20 && !(battery?.isCharging ?? false)
    }

    // MARK: - Chat

    func sendMessage() {
        let userMsg = userInput
        messages.append(ChatMessage(text: userMsg, isUser: true))
        conversation.append(.init(role: "user", parts: [.init(text: userMsg)]))
        pruneConversation()
        userInput = ""
        markActivity()
        haptic(.light)
        isLoadingResponse = true
        gemini.send(messages: conversation) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                switch result {
                case .success(let reply):
                    self.messages.append(ChatMessage(text: "🤖 " + reply, isUser: false))
                    self.conversation.append(.init(role: "model", parts: [.init(text: reply)]))
                    self.pruneConversation()
                case .failure(let error):
                    self.messages.append(ChatMessage(text: error.companionMessage, isUser: false))
                    self.persistChat()
                }
                self.isLoadingResponse = false
            }
        }
    }

    /// Handles a tap on a quick-reply button. The tapped text is posted as the
    /// user's message and then sent to Gemini for a genuine, context-aware reply
    /// — the canned `botResponse` is the instant offline fallback. The reply's
    /// safety effect is applied immediately so the safety state never waits on
    /// the network. The `.escalate` reply is the exception: it must be instant
    /// and network-independent, so it posts the fixed line and escalates now.
    func tapQuickReply(_ reply: QuickReply) {
        messages.append(ChatMessage(text: reply.label, isUser: true))

        switch reply.effect {
        case .escalate:
            messages.append(ChatMessage(text: "🤖 " + reply.botResponse, isUser: false))
            triggerHelpNow()
            return
        case .reassure:
            haptic(.light)
            markActivity()
            scheduleNextCheckIn()
        case .neutral:
            haptic(.light)
            markActivity()
        }

        conversation.append(.init(role: "user", parts: [.init(text: reply.label)]))
        pruneConversation()
        isLoadingResponse = true
        gemini.send(messages: conversation) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                let aiReply: String
                switch result {
                case .success(let reply): aiReply = reply
                case .failure: aiReply = reply.botResponse
                }
                self.messages.append(ChatMessage(text: "🤖 " + aiReply, isUser: false))
                self.conversation.append(.init(role: "model", parts: [.init(text: aiReply)]))
                self.pruneConversation()
                self.isLoadingResponse = false
            }
        }
    }

    // MARK: - Safety actions

    /// Quick action: confirm safety. Resets the inactivity clock and check-in
    /// countdown, returns the hero to "safe", and posts a reassuring line.
    func markSafe() {
        haptic(.medium)
        markActivity()
        scheduleNextCheckIn()
        messages.append(ChatMessage(text: "🤖 Great — glad you're okay! I'll keep watching.", isUser: false))
        persistChat()
    }

    /// Begins a timed walk to the entered destination for the chosen duration.
    func startWalk() {
        let name = walkDestination.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        walkSession = WalkSession(destination: name,
                                  startDate: clock(),
                                  expectedDuration: TimeInterval(walkMinutes * 60))
        walkDestination = ""
        showStartWalk = false
        markActivity()
        haptic(.medium)
        messages.append(ChatMessage(text: "🤖 Walk to \(name) started — I'll watch the clock. Tap “I've arrived” when you get there.", isUser: false))
        persistChat()
    }

    /// Ends the active walk safely (the user reached their destination).
    func arriveSafely() {
        guard let session = walkSession else { return }
        walkSession = nil
        haptic(.medium)
        markActivity()
        scheduleNextCheckIn()
        messages.append(ChatMessage(text: "🤖 Glad you made it to \(session.destination) safely! 🎉", isUser: false))
        persistChat()
    }

    /// Quick action: escalate immediately, reusing the escalation path.
    /// `triggerAutoAlert` owns the escalation haptic, so this doesn't add one.
    func triggerHelpNow() {
        triggerAutoAlert()
        sendPoliceNotification()
    }

    // MARK: - Contacts

    func addContact() {
        let contact = EmergencyContact(name: newContactName, phone: newContactPhone)
        contacts.append(contact)
        contactStore.save(contacts)
        newContactName = ""
        newContactPhone = ""
        showAddContact = false
    }

    func removeContact(_ contact: EmergencyContact) {
        contacts.removeAll { $0.id == contact.id }
        contactStore.save(contacts)
    }

    // MARK: - Safety logic

    private func startCheckInTimer() {
        checkInToken?.cancel()
        scheduleNextCheckIn()
        checkInToken = scheduler.schedule(every: checkInInterval) { [weak self] in
            guard let self else { return }
            let checkInMsg = "🤖 Just checking in! Please reply if you're okay."
            self.messages.append(ChatMessage(text: checkInMsg, isUser: false))
            self.conversation.append(.init(role: "model", parts: [.init(text: checkInMsg)]))
            self.scheduleNextCheckIn()
            if self.status == .safe { self.status = .checking }
        }
    }

    private func startInactivityTimer() {
        inactivityToken?.cancel()
        inactivityToken = scheduler.schedule(every: 5) { [weak self] in
            guard let self else { return }
            // A walk past its ETA escalates regardless of recent movement — the
            // user may be moving but in the wrong place / under duress. Clear the
            // session so the overrun escalates once, then the standard inactivity
            // watcher governs any continued non-response.
            if WalkTimer.decide(session: self.walkSession, now: self.clock()) == .escalateOverdue {
                self.walkSession = nil
                self.messages.append(ChatMessage(text: "🤖 You didn't arrive in time — escalating now.", isUser: false))
                self.triggerAutoAlert()
                self.sendPoliceNotification()
                return
            }
            let decision = SafetyEngine.decide(
                timeSinceLastResponse: self.clock().timeIntervalSince(self.lastResponseDate),
                timeSinceLastMovement: self.clock().timeIntervalSince(self.lastMovementDate),
                checkInInterval: self.checkInInterval,
                inactivityThreshold: self.inactivityThreshold
            )
            switch decision {
            case .escalate:
                self.triggerAutoAlert()
                self.sendPoliceNotification()
            case .checking:
                if self.status == .safe { self.status = .checking }
            case .none:
                break
            }
        }
    }

    /// A 1 s ticker that advances `now` so the "Next check-in" countdown stays
    /// live even when no other state changes.
    private func startDisplayTimer() {
        displayToken?.cancel()
        displayToken = scheduler.schedule(every: 1) { [weak self] in
            self?.now = self?.clock() ?? Date()
        }
    }

    /// Records user activity (a reply or an "I'm safe" tap) and returns the hero
    /// to a calm "safe" state. Mirrors the original `markActivity`, which reset
    /// only the response clock.
    private func markActivity() {
        lastResponseDate = clock()
        if status != .alert { status = .safe }
    }

    /// Records significant movement: resets the inactivity (movement) clock and,
    /// like the original `onMovement` handler, the response clock via
    /// `markActivity`.
    private func registerMovement() {
        lastMovementDate = clock()
        markActivity()
    }

    /// Resets the visible countdown to a full interval from now.
    private func scheduleNextCheckIn() {
        nextCheckIn = clock().addingTimeInterval(checkInInterval)
    }

    private func triggerAutoAlert() {
        escalationHaptic()
        showAutoAlert = true
        status = .alert
        lastResponseDate = clock()
        lastMovementDate = clock()
        scheduleNextCheckIn()
    }

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    /// Posts the escalation notification via ``NotificationService``, which
    /// embeds the contacts + coordinate as a per-notification snapshot (no shared
    /// mutable state) and reports a delivery failure so we can fall back rather
    /// than fail silently. The actionable categories are registered at launch.
    private func sendPoliceNotification() {
        NotificationService.postEscalation(
            contacts: contacts,
            coordinate: lastLocation?.coordinate,
            emergencyNumberOverride: settings.emergencyNumberOverride
        ) { [weak self] in
            // The system rejected the notification (e.g. notifications denied).
            // Don't let escalation die quietly — surface the in-app alert and a
            // chat line pointing the user to the on-screen "I need help" button.
            guard let self else { return }
            self.showAutoAlert = true
            self.messages.append(ChatMessage(
                text: "🤖 I couldn't post a notification — use the “I need help” button to call UT Police or text your contacts.",
                isUser: false))
        }
    }

    /// Bounds the stored conversation so a long walk doesn't grow it without
    /// limit (and re-send the whole history on every request). Delegates to the
    /// pure ``GeminiManager/prune(_:keepingLast:)`` helper, then persists.
    private func pruneConversation() {
        conversation = GeminiManager.prune(conversation, keepingLast: historyTurnLimit)
        persistChat()
    }

    /// Persists the transcript + conversation so they survive a relaunch.
    private func persistChat() {
        let history = ChatHistory(
            messages: messages.map { .init(text: $0.text, isUser: $0.isUser) },
            conversation: conversation.map { .init(role: $0.role, text: $0.parts.first?.text ?? "") }
        )
        chatStore.save(history)
    }

    // MARK: - Settings

    /// Applies updated settings: persists them and re-arms the timers so a new
    /// check-in cadence takes effect immediately.
    func applySettings(_ newSettings: SafetySettings) {
        settings = newSettings
        settingsStore.save(newSettings)
        location.setBackgroundUpdatesEnabled(newSettings.backgroundLocationEnabled)
        scheduleNextCheckIn()
        startCheckInTimer()
        startInactivityTimer()
        pruneConversation()        // re-bound history if the limit shrank
        refreshBatteryWarning()
    }

    /// Clears the chat back to the opening greeting + system prompt.
    func clearChat() {
        messages = [ChatMessage(text: "👋 Hi! I'll check in with you as you walk. Reply to my messages so I know you're safe!", isUser: false)]
        conversation = [.init(role: "user", parts: [.init(text: Self.systemPrompt)])]
        chatStore.clear()
    }

    // MARK: - Haptics

    /// Routine tap feedback, delegated to the centralized ``Haptics`` helper.
    private func haptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        switch style {
        case .medium, .heavy: Haptics.medium()
        default: Haptics.light()
        }
    }

    /// A distinct error/escalation haptic so an automatic alert is *felt*, not
    /// only seen — important when the phone is in a pocket during a walk.
    private func escalationHaptic() {
        Haptics.escalation()
    }
}
