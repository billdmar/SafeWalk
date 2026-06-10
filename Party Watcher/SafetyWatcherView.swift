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

/// A map-annotatable wrapper for the user's current coordinate.
struct UserLocation: Identifiable {
    let id = UUID()
    let coordinate: CLLocationCoordinate2D
}

/// The app's main screen and safety controller.
///
/// `SafetyWatcherView` ties together the live location map, the Gemini-powered
/// check-in chat, and the emergency-contacts panel. Two timers drive the safety
/// logic: a periodic check-in timer that prompts the user, and an inactivity
/// timer that escalates (alert + local notification to call campus police) when
/// the user neither replies nor moves within `inactivityThreshold`.
struct SafetyWatcherView: View {
    @State private var messages: [String] = ["👋 Hi! I’ll check in with you as you walk. Reply to my messages so I know you’re safe!"]
    @State private var userInput: String = ""
    @State private var isUserActive: Bool = true
    @State private var lastResponseDate = Date()
    @ObservedObject private var locationManager = LocationManager()
    @State private var contacts: [EmergencyContact] = UserDefaults.standard.loadContacts()
    @State private var showAddContact = false
    @State private var newContactName = ""
    @State private var newContactPhone = ""
    @State private var lastLocation: CLLocation? = nil
    @State private var lastMovementDate = Date()
    @State private var showAutoAlert = false
    @State private var checkInTimer: Timer? = nil
    @State private var inactivityTimer: Timer? = nil
    @State private var isLoadingResponse = false
    @State private var conversation: [GeminiManager.GeminiMessage] = [
        .init(role: "user", parts: [.init(text: "You are a friendly safety companion for students walking alone at night. Keep responses short, supportive, and focused on safety.")])
    ]
    @State private var nextCheckIn: Date = Date().addingTimeInterval(60)
    let checkInInterval: TimeInterval = 60 // 1 minute
    let inactivityThreshold: TimeInterval = 120 // 2 minutes
    var burntOrange: Color { Color(red: 191/255, green: 87/255, blue: 0/255) }
    var lightGray: Color { Color(UIColor.systemGray6) }
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
            LinearGradient(gradient: Gradient(colors: [Color.white, burntOrange.opacity(0.08)]), startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            VStack(spacing: 0) {
                // App Bar
                HStack {
                    Image(systemName: "shield.lefthalf.fill")
                        .foregroundColor(burntOrange)
                        .font(.title2)
                    Text("Safety Watcher Bot")
                        .font(.title2).fontWeight(.bold)
                        .foregroundColor(burntOrange)
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.top, 16)
                .padding(.bottom, 8)
                // Live Location Map
                if !userLocationAnnotation.isEmpty {
                    Map(coordinateRegion: $region, annotationItems: userLocationAnnotation) { location in
                        MapMarker(coordinate: location.coordinate, tint: .blue)
                    }
                    .frame(height: 160)
                    .cornerRadius(16)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
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
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.gray.opacity(0.1))
                        .frame(height: 160)
                        .overlay(Text("Locating... ").foregroundColor(.gray))
                        .padding(.horizontal)
                        .padding(.bottom, 8)
                }
                // Next Check-in Timer
                HStack {
                    Image(systemName: "clock")
                        .foregroundColor(.gray)
                    Text("Next check-in: ")
                        .foregroundColor(.gray)
                    Text(timerString)
                        .fontWeight(.semibold)
                        .foregroundColor(burntOrange)
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.bottom, 4)
                // Chat
                ScrollViewReader { scrollProxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(Array(messages.enumerated()), id: \ .offset) { idx, msg in
                                ChatBubble(message: msg, isUser: isUserMessage(idx: idx))
                                    .id(idx)
                            }
                            if isLoadingResponse {
                                HStack(spacing: 8) {
                                    ProgressView()
                                    Text("Bot is typing...")
                                        .foregroundColor(.gray)
                                }
                                .padding(10)
                            }
                        }
                        .padding()
                        .onChange(of: messages.count) { _ in
                            withAnimation { scrollProxy.scrollTo(messages.count - 1, anchor: .bottom) }
                        }
                    }
                }
                // Input
                HStack {
                    TextField("Type your reply...", text: $userInput)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .frame(minHeight: 44)
                        .autocapitalization(.sentences)
                        .disableAutocorrection(true)
                    Button("Send") {
                        #if DEBUG
                        print("[SafetyWatcherView] Send button tapped")
                        #endif
                        sendMessage()
                    }
                    .disabled(userInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .padding(.leading, 8)
                    .padding(.vertical, 6)
                    .background(userInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.gray.opacity(0.3) : burntOrange)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }
                .padding()
                Divider()
                // Emergency Contacts & Alert
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Emergency Contacts")
                            .font(.headline)
                            .foregroundColor(burntOrange)
                        Spacer()
                        Button(action: {
                            #if DEBUG
                            print("[SafetyWatcherView] Add Contact button tapped")
                            #endif
                            showAddContact = true
                        }) {
                            Image(systemName: "plus.circle.fill")
                                .font(.title2)
                                .foregroundColor(burntOrange)
                        }
                    }
                    ForEach(contacts) { contact in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(contact.name)
                                Text(contact.phone).font(.caption).foregroundColor(.gray)
                            }
                            Spacer()
                            Button(action: { removeContact(contact) }) {
                                Image(systemName: "trash").foregroundColor(.red)
                            }
                        }
                    }
                }
                .padding()
            }
        }
        .onAppear {
            locationManager.startTracking()
            startCheckInTimer()
            startInactivityTimer()
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
        .fullScreenCover(isPresented: $showAddContact) {
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
                .background((newContactName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || newContactPhone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) ? Color.gray.opacity(0.3) : burntOrange)
                .foregroundColor(.white)
                .cornerRadius(8)
                Button("Cancel") { showAddContact = false }
                    .padding(.top, 4)
            }
            .padding()
        }
        .alert("No response detected! Sending emergency alert.", isPresented: $showAutoAlert) {
            Button("OK", role: .cancel) {}
        }
    }

    func sendMessage() {
        let userMsg = userInput
        messages.append(userMsg)
        conversation.append(.init(role: "user", parts: [.init(text: userMsg)]))
        userInput = ""
        lastResponseDate = Date()
        resetInactivityTimer()
        isLoadingResponse = true
        GeminiManager.shared.sendMessage(messages: conversation) { response in
            DispatchQueue.main.async {
                if let reply = response {
                    messages.append("🤖 " + reply)
                    conversation.append(.init(role: "model", parts: [.init(text: reply)]))
                } else {
                    messages.append("🤖 Sorry, I couldn't get a response right now.")
                }
                isLoadingResponse = false
            }
        }
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

    // AI Chatbot logic
    func startCheckInTimer() {
        checkInTimer?.invalidate()
        checkInTimer = Timer.scheduledTimer(withTimeInterval: checkInInterval, repeats: true) { _ in
            let checkInMsg = "🤖 Just checking in! Please reply if you’re okay."
            messages.append(checkInMsg)
            conversation.append(.init(role: "model", parts: [.init(text: checkInMsg)]))
            resetInactivityTimer()
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
            }
        }
    }
    func resetInactivityTimer() {
        lastResponseDate = Date()
    }
    func stopTimers() {
        checkInTimer?.invalidate()
        inactivityTimer?.invalidate()
    }
    func triggerAutoAlert() {
        showAutoAlert = true
        resetInactivityTimer()
        lastMovementDate = Date()
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

    // Helper to determine if a message is from the user
    func isUserMessage(idx: Int) -> Bool {
        // System prompt is always bot
        if idx == 0 { return false }
        // Even indices after the first are bot, odd are user
        return idx % 2 == 1
    }
    // Timer string for next check-in
    var timerString: String {
        let interval = max(0, Int(nextCheckIn.timeIntervalSinceNow))
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
    var burntOrange: Color { Color(red: 191/255, green: 87/255, blue: 0/255) }
    var body: some View {
        HStack {
            if isUser { Spacer() }
            Text(message)
                .padding(12)
                .background(isUser ? burntOrange.opacity(0.9) : Color.white)
                .foregroundColor(isUser ? .white : .black)
                .cornerRadius(16)
                .shadow(color: .black.opacity(0.04), radius: 2, x: 0, y: 1)
                .frame(maxWidth: 260, alignment: isUser ? .trailing : .leading)
            if !isUser { Spacer() }
        }
        .padding(isUser ? .leading : .trailing, 40)
        .padding(.vertical, 2)
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
 