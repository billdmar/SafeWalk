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
    /// Honor the system "Reduce Motion" setting — when on, the status hero stops
    /// pulsing so the animation doesn't bother motion-sensitive users.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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

    // Walk timer / ETA: an optional active walk to a destination. When set, the
    // inactivity poll also escalates if the walk runs past its expected arrival.
    @State private var walkSession: WalkSession? = nil
    @State private var showStartWalk = false
    @State private var walkDestination = ""
    @State private var walkMinutes = 15

    /// The map camera. Starts framed on campus and recenters on the user once a
    /// fix arrives. Uses the modern `MapCameraPosition` API (iOS 17+) rather than
    /// the deprecated `MKCoordinateRegion` binding.
    @State private var cameraPosition: MapCameraPosition = .region(
        MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 30.285, longitude: -97.736),
                           span: MKCoordinateSpan(latitudeDelta: 0.005, longitudeDelta: 0.005))
    )

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
                        walkCard
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
        .sheet(isPresented: $showStartWalk) { startWalkSheet }
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
                    .symbolEffect(.pulse,
                                  options: (status == .safe || reduceMotion) ? .nonRepeating : .repeating,
                                  value: status)
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
            if let userLocation = userLocationAnnotation.first {
                Map(position: $cameraPosition) {
                    Marker("You", systemImage: "figure.walk", coordinate: userLocation.coordinate)
                        .tint(Theme.burntOrange)
                }
                .frame(height: 170)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .accessibilityLabel("Map showing your live location")
                .onAppear { recenter(on: locationManager.lastLocation?.coordinate) }
                .onChange(of: locationManager.lastLocation) { _, newLoc in
                    recenter(on: newLoc?.coordinate)
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

    /// The walk timer / ETA card. When no walk is active it offers a "Start a
    /// walk" button; while a walk is in progress it shows the destination, a
    /// live countdown to the expected arrival, and an "I've arrived" button that
    /// ends the walk safely. If the walk runs past its ETA without arriving, the
    /// inactivity poll escalates.
    private var walkCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Walk timer", systemImage: "figure.walk")
                .font(.headline)
                .foregroundColor(Theme.burntOrange)
            if let session = walkSession {
                let overdue = session.isOverdue(at: now)
                HStack(spacing: 12) {
                    Image(systemName: overdue ? "exclamationmark.triangle.fill" : "location.north.line.fill")
                        .font(.title3)
                        .foregroundColor(overdue ? Theme.alert : Theme.safe)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Walking to \(session.destination)")
                            .fontWeight(.semibold)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(overdue
                             ? "Past your expected arrival — escalating if you don't arrive."
                             : "Arrive in \(SafetyEngine.countdownString(secondsRemaining: session.secondsRemaining(at: now)))")
                            .font(.caption)
                            .foregroundColor(overdue ? Theme.alert : .secondary)
                    }
                    Spacer()
                }
                Button(action: arriveSafely) {
                    Label("I've arrived", systemImage: "flag.checkered")
                        .font(.subheadline).fontWeight(.semibold)
                        .frame(maxWidth: .infinity, minHeight: 30)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.safe)
                .accessibilityHint("Ends the walk timer and confirms you reached \(session.destination).")
            } else {
                Text("Heading somewhere? Start a timed walk and SafeWalk will escalate if you don't arrive by your ETA.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button(action: { showStartWalk = true }) {
                    Label("Start a walk", systemImage: "figure.walk.departure")
                        .font(.subheadline).fontWeight(.semibold)
                        .frame(maxWidth: .infinity, minHeight: 30)
                }
                .buttonStyle(.bordered)
                .tint(Theme.burntOrange)
                .accessibilityHint("Set a destination and expected duration.")
            }
        }
        .card()
        .accessibilityElement(children: .contain)
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
                    .onChange(of: messages.count) {
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

    private var startWalkSheet: some View {
        NavigationView {
            Form {
                Section("Where are you headed?") {
                    TextField("Destination (e.g. Jester dorm)", text: $walkDestination)
                        .autocapitalization(.words)
                        .disableAutocorrection(true)
                }
                Section("How long should it take?") {
                    Picker("Expected duration", selection: $walkMinutes) {
                        ForEach(WalkTimer.presetMinutes, id: \.self) { mins in
                            Text("\(mins) min").tag(mins)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                Section {
                    Text("If you haven't tapped “I've arrived” by then, SafeWalk escalates — alerting your contact and offering a call to UT Police.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Start a walk")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showStartWalk = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Start") { startWalk() }
                        .disabled(walkDestination.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
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

    /// A distinct error/escalation haptic so an automatic alert is *felt*, not
    /// only seen — important when the phone is in a pocket during a walk.
    private func escalationHaptic() {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }

    /// Recenters the map camera on a coordinate, keeping the existing zoom.
    private func recenter(on coordinate: CLLocationCoordinate2D?) {
        guard let coordinate else { return }
        cameraPosition = .region(
            MKCoordinateRegion(center: coordinate,
                               span: MKCoordinateSpan(latitudeDelta: 0.005, longitudeDelta: 0.005))
        )
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

    /// Begins a timed walk to the entered destination for the chosen duration.
    /// Marks activity so the walk starts from a calm "safe" state and dismisses
    /// the sheet.
    func startWalk() {
        let name = walkDestination.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        walkSession = WalkSession(destination: name,
                                  startDate: Date(),
                                  expectedDuration: TimeInterval(walkMinutes * 60))
        walkDestination = ""
        showStartWalk = false
        markActivity()
        haptic(.medium)
        messages.append(ChatMessage(text: "🤖 Walk to \(name) started — I'll watch the clock. Tap “I've arrived” when you get there.", isUser: false))
    }

    /// Ends the active walk safely (the user reached their destination). Clears
    /// the session and resets the safety clocks, the same as marking safe.
    func arriveSafely() {
        guard let session = walkSession else { return }
        walkSession = nil
        haptic(.medium)
        markActivity()
        scheduleNextCheckIn()
        messages.append(ChatMessage(text: "🤖 Glad you made it to \(session.destination) safely! 🎉", isUser: false))
    }

    /// Quick action: escalate immediately, reusing the existing escalation path.
    /// `triggerAutoAlert` owns the escalation haptic, so this doesn't add its own.
    func triggerHelpNow() {
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
            // A walk that runs past its ETA escalates regardless of recent
            // movement — the user may be moving but in the wrong place / under
            // duress. Clear the session so the overrun escalates once, then the
            // standard inactivity watcher governs any continued non-response.
            if WalkTimer.decide(session: walkSession, now: Date()) == .escalateOverdue {
                walkSession = nil
                messages.append(ChatMessage(text: "🤖 You didn't arrive in time — escalating now.", isUser: false))
                triggerAutoAlert()
                sendPoliceNotification()
                return
            }
            let decision = SafetyEngine.decide(
                timeSinceLastResponse: Date().timeIntervalSince(lastResponseDate),
                timeSinceLastMovement: Date().timeIntervalSince(lastMovementDate),
                checkInInterval: checkInInterval,
                inactivityThreshold: inactivityThreshold
            )
            switch decision {
            case .escalate:
                triggerAutoAlert()
                sendPoliceNotification()
            case .checking:
                if status == .safe { status = .checking }
            case .none:
                break
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
        escalationHaptic()
        showAutoAlert = true
        status = .alert
        lastResponseDate = Date()
        lastMovementDate = Date()
        scheduleNextCheckIn()
    }

    func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    /// Builds the escalation notification. When the user has saved emergency
    /// contacts, the alert offers a single "Text <n> contacts" action that opens
    /// a group SMS to *every* contact with a dialable number (prefilled with a
    /// help message + last known location) — not just the first. The "Call UT
    /// Police" action is always present, so escalation reaches the contacts *and*
    /// UTPD when contacts exist, and falls back to UTPD only when none is saved.
    func sendPoliceNotification() {
        // Hand the delegate the data it needs to place the call / group SMS from
        // a notification action tap. Retained as a singleton so the action fires.
        NotificationDelegate.shared.contacts = contacts
        NotificationDelegate.shared.lastCoordinate = locationManager.lastLocation?.coordinate

        // Count only contacts we can actually text, so the copy is truthful and
        // we don't offer a text action that would open an empty group compose.
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

    // Timer string for next check-in. Reads `now` (advanced by the display
    // timer) so the countdown re-renders every second.
    var timerString: String {
        SafetyEngine.countdownString(secondsRemaining: nextCheckIn.timeIntervalSince(now))
    }
}

/// Handles taps on the actionable emergency notification. Placing a `tel://`
/// call to campus police on "Call UT Police", or composing a *group* `sms:` to
/// every saved emergency contact (prefilled with a help message and the last
/// known location) on "Text <n> contacts".
///
/// A shared singleton so it outlives the notification and so the escalation code
/// can hand it the current contacts + coordinate before posting the notification.
class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationDelegate()

    /// The contacts to text when the user taps the contact action. Set by the
    /// escalation code right before a notification is posted.
    var contacts: [EmergencyContact] = []
    /// The most recent known coordinate, embedded into the SMS body if present.
    var lastCoordinate: CLLocationCoordinate2D?

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        switch response.actionIdentifier {
        case "CALL_UTPD_ACTION":
            if let url = Escalation.utpdCallURL() {
                UIApplication.shared.open(url)
            }
        case "TEXT_CONTACTS_ACTION":
            if let url = Escalation.groupSMSURL(phones: contacts.map(\.phone), coordinate: lastCoordinate) {
                UIApplication.shared.open(url)
            }
        default:
            break
        }
        completionHandler()
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
                .fixedSize(horizontal: false, vertical: true)
                .padding(12)
                .background(isUser ? Theme.burntOrange.opacity(0.92) : Color(UIColor.secondarySystemBackground))
                .foregroundColor(isUser ? .white : .primary)
                .cornerRadius(16)
                .shadow(color: .black.opacity(0.04), radius: 2, x: 0, y: 1)
                // Cap the bubble at ~75% of the row so long replies wrap instead
                // of clipping — but let it grow with Dynamic Type rather than a
                // fixed 260 pt that truncated at large accessibility sizes.
                .frame(maxWidth: 300, alignment: isUser ? .trailing : .leading)
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
            if SafetyEngine.isSignificantMovement(distance: distance) {
                onMovement?()
            }
        }
        lastLocation = newLocation
    }
}
