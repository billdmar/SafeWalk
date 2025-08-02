import SwiftUI
import CoreLocation
import UserNotifications
import MapKit

struct EmergencyContact: Identifiable, Codable, Hashable {
    let id = UUID()
    var name: String
    var phone: String
}

struct UserLocation: Identifiable {
    let id = UUID()
    let coordinate: CLLocationCoordinate2D
}

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
                        print("Send button tapped with input: \(userInput)")
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
                            print("Add Contact button tapped")
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
                    print("Add Contact confirmed: \(newContactName), \(newContactPhone)")
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
    func sendPoliceNotification() {
        let content = UNMutableNotificationContent()
        content.title = "No response detected!"
        content.body = "Tap to call UT Austin Police (512-471-4441) immediately."
        content.sound = .default
        content.categoryIdentifier = "CALL_UTPD"
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
        let callAction = UNNotificationAction(identifier: "CALL_UTPD_ACTION", title: "Call UT Police", options: .foreground)
        let category = UNNotificationCategory(identifier: "CALL_UTPD", actions: [callAction], intentIdentifiers: [], options: [])
        UNUserNotificationCenter.current().setNotificationCategories([category])
        UNUserNotificationCenter.current().delegate = NotificationDelegate()
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

class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        if response.actionIdentifier == "CALL_UTPD_ACTION" {
            if let url = URL(string: "tel://5124714441") {
                UIApplication.shared.open(url)
            }
        }
        completionHandler()
    }
}

// Chat bubble view
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

// Simple location manager for live tracking
class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    @Published var lastLocation: CLLocation?
    var onMovement: (() -> Void)?
    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
    }
    func startTracking() {
        manager.requestWhenInUseAuthorization()
        manager.startUpdatingLocation()
    }
    func stopTracking() {
        manager.stopUpdatingLocation()
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
 