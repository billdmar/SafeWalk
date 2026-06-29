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
    @Published var showAutoAlert = false
    @Published var newContactName = ""
    @Published var newContactPhone = ""
    @Published var walkDestination = ""
    @Published var walkMinutes = 15

    // MARK: - Configuration

    let checkInInterval: TimeInterval = 60   // 1 minute
    let inactivityThreshold: TimeInterval = 120 // 2 minutes

    // MARK: - Dependencies

    private let location: LocationProviding
    private let gemini: GeminiSending
    private let contactStore: ContactStoring
    private let scheduler: TimerScheduling
    private let clock: () -> Date

    // MARK: - Private state

    private var lastResponseDate: Date
    private var lastMovementDate: Date
    private var conversation: [GeminiManager.GeminiMessage] = [
        .init(role: "user", parts: [.init(text: "You are a friendly safety companion for students walking alone at night. Keep responses short, supportive, and focused on safety.")])
    ]
    private var checkInToken: TimerToken?
    private var inactivityToken: TimerToken?
    private var displayToken: TimerToken?

    // MARK: - Init

    init(location: LocationProviding = LocationManager(),
         gemini: GeminiSending = GeminiManager.shared,
         contactStore: ContactStoring = ContactStore(),
         scheduler: TimerScheduling = RealTimerScheduler(),
         now: @escaping () -> Date = Date.init) {
        self.location = location
        self.gemini = gemini
        self.contactStore = contactStore
        self.scheduler = scheduler
        self.clock = now
        let start = now()
        self.now = start
        self.lastResponseDate = start
        self.lastMovementDate = start
        self.nextCheckIn = start.addingTimeInterval(60)
        self.contacts = contactStore.load()
        self.lastLocation = location.lastLocation
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
        location.startTracking()
        startCheckInTimer()
        startInactivityTimer()
        startDisplayTimer()
        requestNotificationPermission()
    }

    func onDisappear() {
        location.stopTracking()
        location.onMovement = nil
        location.onLocationChange = nil
        checkInToken?.cancel()
        inactivityToken?.cancel()
        displayToken?.cancel()
    }

    // MARK: - Chat

    func sendMessage() {
        let userMsg = userInput
        messages.append(ChatMessage(text: userMsg, isUser: true))
        conversation.append(.init(role: "user", parts: [.init(text: userMsg)]))
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
                case .failure:
                    self.messages.append(ChatMessage(text: "🤖 Sorry, I couldn't get a response right now.", isUser: false))
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
    }

    /// Ends the active walk safely (the user reached their destination).
    func arriveSafely() {
        guard let session = walkSession else { return }
        walkSession = nil
        haptic(.medium)
        markActivity()
        scheduleNextCheckIn()
        messages.append(ChatMessage(text: "🤖 Glad you made it to \(session.destination) safely! 🎉", isUser: false))
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

    /// Builds the escalation notification. When the user has saved emergency
    /// contacts, the alert offers a single "Text <n> contacts" action that opens
    /// a group SMS to *every* contact with a dialable number (prefilled with a
    /// help message + last known location). The "Call UT Police" action is
    /// always present, so escalation reaches the contacts *and* UTPD when
    /// contacts exist, and falls back to UTPD only when none is saved.
    private func sendPoliceNotification() {
        NotificationDelegate.shared.contacts = contacts
        NotificationDelegate.shared.lastCoordinate = lastLocation?.coordinate

        let textableCount = Escalation.dialableCount(in: contacts.map(\.phone))

        let content = UNMutableNotificationContent()
        content.title = "No response detected!"
        if textableCount > 0 {
            let noun = textableCount == 1 ? "contact" : "contacts"
            content.body = "Tap to call UT Austin Police (\(Escalation.utpdDisplayNumber)) or text your \(textableCount) emergency \(noun) immediately."
        } else {
            content.body = "Tap to call UT Austin Police (\(Escalation.utpdDisplayNumber)) immediately."
        }
        content.sound = .default
        content.categoryIdentifier = textableCount > 0 ? "ESCALATE" : "CALL_UTPD"

        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)

        let callAction = UNNotificationAction(identifier: "CALL_UTPD_ACTION", title: "Call UT Police", options: .foreground)
        var actions = [callAction]
        if textableCount > 0 {
            let noun = textableCount == 1 ? "contact" : "contacts"
            let textContactsAction = UNNotificationAction(
                identifier: "TEXT_CONTACTS_ACTION",
                title: "Text \(textableCount) \(noun)",
                options: .foreground
            )
            actions.insert(textContactsAction, at: 0)
        }
        let utpdCategory = UNNotificationCategory(identifier: "CALL_UTPD", actions: [callAction], intentIdentifiers: [], options: [])
        let escalateCategory = UNNotificationCategory(identifier: "ESCALATE", actions: actions, intentIdentifiers: [], options: [])
        UNUserNotificationCenter.current().setNotificationCategories([utpdCategory, escalateCategory])
        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared
    }

    // MARK: - Haptics

    private func haptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }

    /// A distinct error/escalation haptic so an automatic alert is *felt*, not
    /// only seen — important when the phone is in a pocket during a walk.
    private func escalationHaptic() {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }
}
