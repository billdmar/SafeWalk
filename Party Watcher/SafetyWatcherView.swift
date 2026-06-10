import SwiftUI
import CoreLocation
import UserNotifications
import MapKit

/// A trusted contact the user can notify in an emergency. Persisted via `UserDefaults`.
struct EmergencyContact: Identifiable, Codable, Hashable {
    let id = UUID()
    var name: String
    var phone: String
}

/// A single chat message with a stable identity and an explicit sender.
///
/// Modeling the sender explicitly (rather than inferring it from a message's
/// index parity) keeps bubble alignment correct even when the bot posts an
/// off-cadence message such as an automatic check-in.
struct ChatMessage: Identifiable, Hashable {
    let id = UUID()
    var text: String
    var isUser: Bool
}

/// A map-annotatable wrapper for the user's current coordinate.
struct UserLocation: Identifiable {
    let id = UUID()
    let coordinate: CLLocationCoordinate2D
}

/// The high-level safety state surfaced by the status hero.
enum SafetyStatus {
    case safe
    case checking
    case alert

    var title: String {
        switch self {
        case .safe: return "You're safe"
        case .checking: return "Checking in…"
        case .alert: return "Alert sent"
        }
    }

    var subtitle: String {
        switch self {
        case .safe: return "SafeWalk is watching your walk."
        case .checking: return "Reply or keep moving so I know you're okay."
        case .alert: return "No response detected — escalation triggered."
        }
    }

    var color: Color {
        switch self {
        case .safe: return Theme.safe
        case .checking: return Theme.checking
        case .alert: return Theme.alert
        }
    }

    var symbol: String {
        switch self {
        case .safe: return "checkmark.shield.fill"
        case .checking: return "clock.badge.questionmark.fill"
        case .alert: return "exclamationmark.shield.fill"
        }
    }
}

/// The app's main screen and safety controller.
///
/// `SafetyWatcherView` ties together the live location map, the Gemini-powered
/// check-in chat, and the emergency-contacts panel. Two timers drive the safety
/// logic: a periodic check-in timer that prompts the user, and an inactivity
/// timer that escalates (alert + local notification to call campus police) when
/// the user neither replies nor moves within `inactivityThreshold`.
struct SafetyWatcherView: View {
    @Environment(\.colorScheme) private var scheme

    @State private var messages: [ChatMessage] = [
        ChatMessage(text: "👋 Hi! I'll check in with you as you walk. Reply to my messages so I know you're safe!", isUser: false)
    ]
    @State private var userInput: String = ""
    @State private var lastResponseDate = Date()
    @StateObject private var locationManager = LocationManager()
    @State private var contacts: [EmergencyContact] = UserDefaults.standard.loadContacts()
    @State private var showAddContact = false
    @State private var newContactName = ""
    @State private var newContactPhone = ""
    @State private var lastMovementDate = Date()
    @State private var showAutoAlert = false
    @State private var checkInTimer: Timer? = nil
    @State private var inactivityTimer: Timer? = nil
    @State private var displayTimer: Timer? = nil
    @State private var isLoadingResponse = false
    @State private var status: SafetyStatus = .safe
    @State private var now = Date()
    @State private var conversation: [GeminiManager.GeminiMessage] = [
        .init(role: "user", parts: [.init(text: "You are a friendly safety companion for students walking alone at night. Keep responses short, supportive, and focused on safety.")])
    ]
    @State private var nextCheckIn: Date = Date().addingTimeInterval(60)
    let checkInInterval: TimeInterval = 60 // 1 minute
    let inactivityThreshold: TimeInterval = 120 // 2 minutes

    @State private var region = MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 30.285, longitude: -97.736), span: MKCoordinateSpan(latitudeDelta: 0.005, longitudeDelta: 0.005))

    // Computed property for user location annotation
    var userLocationAnnotation: [UserLocation] {
        if let loc = locationManager.lastLocation {
            return [UserLocation(coordinate: loc.coordinate)]
        }
        return []
    }

    var body: some View {
        ZStack {
            Theme.background(scheme)
                .ignoresSafeArea()
            VStack(spacing: 0) {
                appBar
                ScrollView {
                    VStack(spacing: 14) {
                        statusHero
                        mapCard
                        quickActions
                        chatCard
                        contactsCard
                    }
                    .padding(.horizontal)
                    .padding(.top, 4)
                    .padding(.bottom, 16)
                }
            }
        }
        .onAppear {
            locationManager.startTracking()
            startCheckInTimer()
            startInactivityTimer()
            startDisplayTimer()
            locationManager.onMovement = {
                lastMovementDate = Date()
                resetInactivityTimer()
            }
            requestNotificationPermission()
        }
        .onDisappear {
            locationManager.stopTracking()
            stopTimers()
            locationManager.onMovement = nil
        }
        .fullScreenCover(isPresented: $showAddContact) { addContactSheet }
        .alert("No response detected! Sending emergency alert.", isPresented: $showAutoAlert) {
            Button("OK", role: .cancel) {}
        }
    }

    // MARK: - Sections

    private var appBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "shield.lefthalf.fill")
                .foregroundColor(Theme.burntOrange)
                .font(.title2)
            Text("SafeWalk")
                .font(.title2).fontWeight(.heavy)
                .foregroundColor(Theme.burntOrange)
            Spacer()
        }
        .padding(.horizontal)
        .padding(.top, 16)
        .padding(.bottom, 10)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("SafeWalk")
    }

    /// The screenshot centerpiece: a large, animated safety status indicator.
    private var statusHero: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(status.color.opacity(0.18))
                    .frame(width: 64, height: 64)
                Image(systemName: status.symbol)
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundColor(status.color)
                    .symbolEffect(.pulse, options: status == .safe ? .nonRepeating : .repeating, value: status)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(status.title)
                    .font(.title3).fontWeight(.bold)
                    .foregroundColor(status.color)
                Text(status.subtitle)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .card()
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(status.color.opacity(0.5), lineWidth: 1.5)
        )
        .animation(.easeInOut(duration: 0.35), value: status)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(status.title). \(status.subtitle)")
    }

    private var mapCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Live location", systemImage: "location.fill")
                    .font(.headline)
                    .foregroundColor(Theme.burntOrange)
                Spacer()
                HStack(spacing: 6) {
                    Image(systemName: "clock")
                    Text("Next check-in \(timerString)")
                }
                .font(.caption).fontWeight(.semibold)
                .foregroundColor(.secondary)
            }
            if !userLocationAnnotation.isEmpty {
                Map(coordinateRegion: $region, annotationItems: userLocationAnnotation) { location in
                    MapMarker(coordinate: location.coordinate, tint: Theme.burntOrange)
                }
                .frame(height: 170)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .onAppear {
                    if let loc = locationManager.lastLocation {
                        region.center = loc.coordinate
                    }
                }
                .onChange(of: locationManager.lastLocation) { newLoc in
                    if let newLoc = newLoc {
                        region.center = newLoc.coordinate
                    }
                }
            } else {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.gray.opacity(0.12))
                    .frame(height: 170)
                    .overlay(
                        VStack(spacing: 8) {
                            ProgressView()
                            Text("Locating you…")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    )
            }
        }
        .card()
    }

    /// Functional one-tap actions: confirm safety or trigger escalation now.
    private var quickActions: some View {
        HStack(spacing: 12) {
            Button(action: markSafe) {
                Label("I'm safe", systemImage: "checkmark.circle.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 30)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.safe)
            .accessibilityHint("Resets the check-in timer and lets the companion know you're okay.")

            Button(action: triggerHelpNow) {
                Label("I need help", systemImage: "sos")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 30)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.alert)
            .accessibilityHint("Immediately sends the emergency alert and notification.")
        }
    }

    private var chatCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Check-in chat", systemImage: "bubble.left.and.bubble.right.fill")
                .font(.headline)
                .foregroundColor(Theme.burntOrange)
            ScrollViewReader { scrollProxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(messages) { msg in
                            ChatBubble(message: msg.text, isUser: msg.isUser)
                                .id(msg.id)
                        }
                        if isLoadingResponse {
                            HStack(spacing: 8) {
                                ProgressView()
                                Text("Companion is typing…")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 4)
                            .id("typing")
                        }
                    }
                    .padding(.vertical, 4)
                    .onChange(of: messages.count) { _ in
                        if let last = messages.last {
                            withAnimation { scrollProxy.scrollTo(last.id, anchor: .bottom) }
                        }
                    }
                }
                .frame(height: 240)
            }
            inputBar
        }
        .card()
    }

    private var inputBar: some View {
        HStack(spacing: 8) {
            TextField("Type your reply…", text: $userInput)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .frame(minHeight: 44)
                .autocapitalization(.sentences)
                .disableAutocorrection(true)
                .submitLabel(.send)
                .onSubmit { if !inputIsEmpty { sendMessage() } }
            Button(action: {
                #if DEBUG
                print("[SafetyWatcherView] Send button tapped")
                #endif
                sendMessage()
            }) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 32))
                    .foregroundColor(inputIsEmpty ? Color.gray.opacity(0.4) : Theme.burntOrange)
            }
            .disabled(inputIsEmpty)
            .accessibilityLabel("Send reply")
        }
    }

    private var contactsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Emergency contacts", systemImage: "person.2.fill")
                    .font(.headline)
                    .foregroundColor(Theme.burntOrange)
                Spacer()
                Button(action: {
                    #if DEBUG
                    print("[SafetyWatcherView] Add Contact button tapped")
                    #endif
                    showAddContact = true
                }) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .foregroundColor(Theme.burntOrange)
                }
                .accessibilityLabel("Add emergency contact")
            }
            if contacts.isEmpty {
                Text("Add a trusted contact so SafeWalk can offer a one-tap text to them if you stop responding.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(contacts) { contact in
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
                        Button(action: { removeContact(contact) }) {
                            Image(systemName: "trash").foregroundColor(Theme.alert)
                        }
                        .accessibilityLabel("Remove \(contact.name)")
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .card()
    }

    private var addContactSheet: some View {
        VStack(spacing: 16) {
            Text("Add Emergency Contact").font(.headline)
            TextField("Name", text: $newContactName)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .autocapitalization(.words)
                .disableAutocorrection(true)
            TextField("Phone Number", text: $newContactPhone)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .keyboardType(.phonePad)
                .autocapitalization(.none)
                .disableAutocorrection(true)
            Button("Add") {
                #if DEBUG
                print("[SafetyWatcherView] Add Contact confirmed")
                #endif
                addContact()
            }
            .disabled(newContactName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || newContactPhone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .padding()
            .frame(maxWidth: .infinity)
            .background((newContactName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || newContactPhone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) ? Color.gray.opacity(0.3) : Theme.burntOrange)
            .foregroundColor(.white)
            .cornerRadius(12)
            Button("Cancel") { showAddContact = false }
                .padding(.top, 4)
        }
        .padding()
    }

    // MARK: - Helpers

    private var inputIsEmpty: Bool {
        userInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func initials(for name: String) -> String {
        let parts = name.split(separator: " ")
        let letters = parts.prefix(2).compactMap { $0.first }
        return String(letters).uppercased()
    }

    private func haptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }

    // MARK: - Actions

    func sendMessage() {
        let userMsg = userInput
        messages.append(ChatMessage(text: userMsg, isUser: true))
        conversation.append(.init(role: "user", parts: [.init(text: userMsg)]))
        userInput = ""
        markActivity()
        haptic(.light)
        isLoadingResponse = true
        GeminiManager.shared.sendMessage(messages: conversation) { response in
            DispatchQueue.main.async {
                if let reply = response {
                    messages.append(ChatMessage(text: "🤖 " + reply, isUser: false))
                    conversation.append(.init(role: "model", parts: [.init(text: reply)]))
                } else {
                    messages.append(ChatMessage(text: "🤖 Sorry, I couldn't get a response right now.", isUser: false))
                }
                isLoadingResponse = false
            }
        }
    }

    /// Quick action: confirm safety. Resets the inactivity clock and the
    /// check-in countdown, returns the status hero to "safe", and posts a
    /// reassuring line from the companion.
    func markSafe() {
        haptic(.medium)
        markActivity()
        scheduleNextCheckIn()
        messages.append(ChatMessage(text: "🤖 Great — glad you're okay! I'll keep watching.", isUser: false))
    }

    /// Quick action: escalate immediately, reusing the existing escalation path.
    func triggerHelpNow() {
        haptic(.heavy)
        triggerAutoAlert()
        sendPoliceNotification()
    }

    func addContact() {
        let contact = EmergencyContact(name: newContactName, phone: newContactPhone)
        contacts.append(contact)
        UserDefaults.standard.saveContacts(contacts)
        newContactName = ""
        newContactPhone = ""
        showAddContact = false
    }

    func removeContact(_ contact: EmergencyContact) {
        contacts.removeAll { $0.id == contact.id }
        UserDefaults.standard.saveContacts(contacts)
    }

    // MARK: - Safety logic

    func startCheckInTimer() {
        checkInTimer?.invalidate()
        scheduleNextCheckIn()
        checkInTimer = Timer.scheduledTimer(withTimeInterval: checkInInterval, repeats: true) { _ in
            let checkInMsg = "🤖 Just checking in! Please reply if you're okay."
            messages.append(ChatMessage(text: checkInMsg, isUser: false))
            conversation.append(.init(role: "model", parts: [.init(text: checkInMsg)]))
            scheduleNextCheckIn()
            if status == .safe { status = .checking }
        }
    }

    func startInactivityTimer() {
        inactivityTimer?.invalidate()
        inactivityTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in
            let timeSinceLastResponse = Date().timeIntervalSince(lastResponseDate)
            let timeSinceLastMovement = Date().timeIntervalSince(lastMovementDate)
            if timeSinceLastResponse > inactivityThreshold || timeSinceLastMovement > inactivityThreshold {
                triggerAutoAlert()
                sendPoliceNotification()
            } else if timeSinceLastResponse > checkInInterval, status == .safe {
                status = .checking
            }
        }
    }

    /// A 1 s ticker that advances `now` so the "Next check-in" countdown stays
    /// live. Without it `timerString` would only update when other state
    /// changes, leaving the displayed countdown frozen.
    func startDisplayTimer() {
        displayTimer?.invalidate()
        displayTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            now = Date()
        }
    }

    /// Records user activity (a reply, an "I'm safe" tap, or movement) and
    /// returns the status hero to a calm "safe" state.
    func markActivity() {
        lastResponseDate = Date()
        if status != .alert { status = .safe }
    }

    func resetInactivityTimer() {
        markActivity()
    }

    /// Resets the visible countdown to a full interval from now.
    func scheduleNextCheckIn() {
        nextCheckIn = Date().addingTimeInterval(checkInInterval)
    }

    func stopTimers() {
        checkInTimer?.invalidate()
        inactivityTimer?.invalidate()
        displayTimer?.invalidate()
    }

    func triggerAutoAlert() {
        showAutoAlert = true
        status = .alert
        lastResponseDate = Date()
        lastMovementDate = Date()
        scheduleNextCheckIn()
    }

    func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    /// Builds the escalation notification. If the user has saved at least one
    /// emergency contact, the first contact is wired into both the notification
    /// body and an actionable "Text <name>" button (SMS deep link with a
    /// prefilled help message + the last known location). The "Call UT Police"
    /// action is always present, so escalation reaches the contact *and* UTPD
    /// when a contact exists, and falls back to UTPD only when none is saved.
    func sendPoliceNotification() {
        // The most recently loaded contacts; the first is treated as primary.
        let primaryContact = contacts.first
        // Hand the delegate the data it needs to place the call / SMS from a
        // notification action tap. Retained as a singleton so the action fires.
        NotificationDelegate.shared.primaryContact = primaryContact
        NotificationDelegate.shared.lastCoordinate = locationManager.lastLocation?.coordinate

        let content = UNMutableNotificationContent()
        content.title = "No response detected!"
        if let contact = primaryContact {
            content.body = "Tap to call UT Austin Police (512-471-4441) or text \(contact.name) immediately."
        } else {
            content.body = "Tap to call UT Austin Police (512-471-4441) immediately."
        }
        content.sound = .default
        content.categoryIdentifier = primaryContact == nil ? "CALL_UTPD" : "ESCALATE"

        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)

        let callAction = UNNotificationAction(identifier: "CALL_UTPD_ACTION", title: "Call UT Police", options: .foreground)
        var actions = [callAction]
        if let contact = primaryContact {
            let textContactAction = UNNotificationAction(
                identifier: "TEXT_CONTACT_ACTION",
                title: "Text \(contact.name)",
                options: .foreground
            )
            actions.insert(textContactAction, at: 0)
        }
        let utpdCategory = UNNotificationCategory(identifier: "CALL_UTPD", actions: [callAction], intentIdentifiers: [], options: [])
        let escalateCategory = UNNotificationCategory(identifier: "ESCALATE", actions: actions, intentIdentifiers: [], options: [])
        UNUserNotificationCenter.current().setNotificationCategories([utpdCategory, escalateCategory])
        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared
    }

    // Timer string for next check-in. Reads `now` (advanced by the display
    // timer) so the countdown re-renders every second.
    var timerString: String {
        let interval = max(0, Int(nextCheckIn.timeIntervalSince(now)))
        let min = interval / 60
        let sec = interval % 60
        return String(format: "%02d:%02d", min, sec)
    }
}

/// Handles taps on the actionable emergency notification. Placing a `tel://`
/// call to campus police on "Call UT Police", or composing an `sms:` to the
/// user's primary emergency contact (prefilled with a help message and the last
/// known location) on "Text <name>".
///
/// A shared singleton so it outlives the notification and so the escalation code
/// can hand it the current contact + coordinate before posting the notification.
class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationDelegate()

    /// The contact to text when the user taps the contact action. Set by the
    /// escalation code right before a notification is posted.
    var primaryContact: EmergencyContact?
    /// The most recent known coordinate, embedded into the SMS body if present.
    var lastCoordinate: CLLocationCoordinate2D?

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        switch response.actionIdentifier {
        case "CALL_UTPD_ACTION":
            if let url = URL(string: "tel://5124714441") {
                UIApplication.shared.open(url)
            }
        case "TEXT_CONTACT_ACTION":
            if let url = smsURL(for: primaryContact) {
                UIApplication.shared.open(url)
            }
        default:
            break
        }
        completionHandler()
    }

    /// Builds an `sms:` deep link to the contact's number with a prefilled body
    /// that includes a help message and, when available, a Maps link to the
    /// user's last known location.
    private func smsURL(for contact: EmergencyContact?) -> URL? {
        guard let contact = contact else { return nil }
        let digits = contact.phone.filter { $0.isNumber || $0 == "+" }
        guard !digits.isEmpty else { return nil }
        var body = "I may need help. This is SafeWalk reaching out on my behalf — please check on me."
        if let coord = lastCoordinate {
            body += " My last location: https://maps.apple.com/?ll=\(coord.latitude),\(coord.longitude)"
        }
        var components = URLComponents()
        components.scheme = "sms"
        components.path = digits
        components.queryItems = [URLQueryItem(name: "body", value: body)]
        return components.url
    }
}

/// A single chat message bubble, styled and aligned by whether the user sent it.
struct ChatBubble: View {
    let message: String
    let isUser: Bool
    var body: some View {
        HStack {
            if isUser { Spacer(minLength: 40) }
            Text(message)
                .padding(12)
                .background(isUser ? Theme.burntOrange.opacity(0.92) : Color(UIColor.secondarySystemBackground))
                .foregroundColor(isUser ? .white : .primary)
                .cornerRadius(16)
                .shadow(color: .black.opacity(0.04), radius: 2, x: 0, y: 1)
                .frame(maxWidth: 260, alignment: isUser ? .trailing : .leading)
            if !isUser { Spacer(minLength: 40) }
        }
        .padding(.vertical, 1)
        .accessibilityLabel("\(isUser ? "You" : "Companion"): \(message)")
    }
}

// MARK: - UserDefaults helpers
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

/// Publishes the user's live location and reports significant movement.
///
/// Wraps `CLLocationManager`, requests *always* authorization (escalating from
/// when-in-use so the user sees the standard two-step iOS prompt), and publishes
/// `lastLocation` for the map. Once "Always" is granted it enables background
/// location updates so SafeWalk can keep watching even when the screen is locked
/// or the app is backgrounded. When the user moves more than 5 metres between
/// updates it fires `onMovement`, which the safety logic uses to reset the
/// inactivity timer.
///
/// Note: background GPS delivery, the "Always" prompt, and lock-screen wakeups
/// are verified on a device/simulator, not in CI.
class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    @Published var lastLocation: CLLocation?
    var onMovement: (() -> Void)?
    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.pausesLocationUpdatesAutomatically = false
    }
    func startTracking() {
        // Request the strongest authorization available. iOS first surfaces the
        // when-in-use prompt and then offers the upgrade to "Always", which is
        // what background tracking requires.
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse:
            manager.requestAlwaysAuthorization()
        default:
            break
        }
        manager.startUpdatingLocation()
        enableBackgroundUpdatesIfPermitted()
    }
    func stopTracking() {
        manager.allowsBackgroundLocationUpdates = false
        manager.stopUpdatingLocation()
    }

    /// Enables background location updates, but only once the user has granted
    /// "Always" authorization. Setting `allowsBackgroundLocationUpdates = true`
    /// without the location background mode + always auth crashes at runtime, so
    /// this is guarded and called after updates have started.
    private func enableBackgroundUpdatesIfPermitted() {
        guard manager.authorizationStatus == .authorizedAlways else { return }
        // Setting `allowsBackgroundLocationUpdates = true` throws a runtime
        // exception (SIGABRT) unless "location" is declared in the bundle's
        // UIBackgroundModes. Verify it's actually present before enabling, so a
        // misconfigured Info.plist degrades to foreground-only tracking instead
        // of crashing on launch.
        let backgroundModes = Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String] ?? []
        guard backgroundModes.contains("location") else { return }
        manager.allowsBackgroundLocationUpdates = true
        manager.pausesLocationUpdatesAutomatically = false
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse:
            // Escalate to Always so background tracking can be enabled.
            manager.requestAlwaysAuthorization()
        case .authorizedAlways:
            enableBackgroundUpdatesIfPermitted()
        default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let newLocation = locations.last
        if let last = lastLocation, let newLoc = newLocation {
            let distance = last.distance(from: newLoc)
            if distance > 5 {
                onMovement?()
            }
        }
        lastLocation = newLocation
    }
}
