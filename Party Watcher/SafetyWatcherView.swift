import SwiftUI
import CoreLocation
import MapKit

/// The app's main screen.
///
/// `SafetyWatcherView` renders the live location map, the Gemini-powered
/// check-in chat, the walk timer, and the emergency-contacts panel, forwarding
/// user intent to ``SafetyWatcherViewModel``. All safety state and side effects
/// — the timers, networking, persistence, and escalation — live in the view
/// model; this view is presentation only.
struct SafetyWatcherView: View {
    @Environment(\.colorScheme) private var scheme
    /// Honor the system "Reduce Motion" setting — when on, the status hero stops
    /// pulsing so the animation doesn't bother motion-sensitive users.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @StateObject private var vm = SafetyWatcherViewModel()

    /// The map camera. Starts framed on campus and recenters on the user once a
    /// fix arrives. Uses the modern `MapCameraPosition` API (iOS 17+) rather than
    /// the deprecated `MKCoordinateRegion` binding.
    @State private var cameraPosition: MapCameraPosition = .region(
        MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 30.285, longitude: -97.736),
                           span: MKCoordinateSpan(latitudeDelta: 0.005, longitudeDelta: 0.005))
    )

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
        .onAppear { vm.onAppear() }
        .onDisappear { vm.onDisappear() }
        .fullScreenCover(isPresented: $vm.showAddContact) { addContactSheet }
        .sheet(isPresented: $vm.showStartWalk) { startWalkSheet }
        .alert("No response detected! Sending emergency alert.", isPresented: $vm.showAutoAlert) {
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
                    .fill(vm.status.color.opacity(0.18))
                    .frame(width: 64, height: 64)
                Image(systemName: vm.status.symbol)
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundColor(vm.status.color)
                    .symbolEffect(.pulse,
                                  options: (vm.status == .safe || reduceMotion) ? .nonRepeating : .repeating,
                                  value: vm.status)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(vm.status.title)
                    .font(.title3).fontWeight(.bold)
                    .foregroundColor(vm.status.color)
                Text(vm.status.subtitle)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .card()
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(vm.status.color.opacity(0.5), lineWidth: 1.5)
        )
        .animation(.easeInOut(duration: 0.35), value: vm.status)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(vm.status.title). \(vm.status.subtitle)")
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
                    Text("Next check-in \(vm.timerString)")
                }
                .font(.caption).fontWeight(.semibold)
                .foregroundColor(.secondary)
            }
            if let userLocation = vm.userLocationAnnotation.first {
                Map(position: $cameraPosition) {
                    Marker("You", systemImage: "figure.walk", coordinate: userLocation.coordinate)
                        .tint(Theme.burntOrange)
                }
                .frame(height: 170)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .accessibilityLabel("Map showing your live location")
                .onAppear { recenter(on: vm.lastLocation?.coordinate) }
                .onChange(of: vm.lastLocation) { _, newLoc in
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
    /// live countdown to the expected arrival, and an "I've arrived" button.
    private var walkCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Walk timer", systemImage: "figure.walk")
                .font(.headline)
                .foregroundColor(Theme.burntOrange)
            if let session = vm.walkSession {
                let overdue = session.isOverdue(at: vm.now)
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
                             : "Arrive in \(SafetyEngine.countdownString(secondsRemaining: session.secondsRemaining(at: vm.now)))")
                            .font(.caption)
                            .foregroundColor(overdue ? Theme.alert : .secondary)
                    }
                    Spacer()
                }
                Button(action: vm.arriveSafely) {
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
                Button(action: { vm.showStartWalk = true }) {
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
            Button(action: vm.markSafe) {
                Label("I'm safe", systemImage: "checkmark.circle.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 30)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.safe)
            .accessibilityHint("Resets the check-in timer and lets the companion know you're okay.")

            Button(action: vm.triggerHelpNow) {
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
                        ForEach(vm.messages) { msg in
                            ChatBubble(message: msg.text, isUser: msg.isUser)
                                .id(msg.id)
                        }
                        if vm.isLoadingResponse {
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
                    .onChange(of: vm.messages.count) {
                        if let last = vm.messages.last {
                            withAnimation { scrollProxy.scrollTo(last.id, anchor: .bottom) }
                        }
                    }
                }
                .frame(height: 240)
            }
            quickReplyRow
            inputBar
        }
        .card()
    }

    /// A horizontal row of deterministic quick-reply buttons. Tapping one posts
    /// a canned exchange (and may confirm safety or escalate) without any network
    /// call — the chat stays conversational even offline.
    private var quickReplyRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(QuickReplies.all) { reply in
                    Button(action: { vm.tapQuickReply(reply) }) {
                        Text(reply.label)
                            .font(.subheadline).fontWeight(.medium)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(
                                Capsule().fill(reply.effect == .escalate
                                               ? Theme.alert.opacity(0.15)
                                               : Theme.burntOrange.opacity(0.12))
                            )
                            .foregroundColor(reply.effect == .escalate ? Theme.alert : Theme.burntOrange)
                    }
                    .accessibilityHint(reply.effect == .escalate
                                       ? "Sends a distress message and escalates immediately."
                                       : "Sends a quick reply to the companion.")
                }
            }
            .padding(.vertical, 2)
        }
    }

    private var inputBar: some View {
        HStack(spacing: 8) {
            TextField("Type your reply…", text: $vm.userInput)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .frame(minHeight: 44)
                .autocapitalization(.sentences)
                .disableAutocorrection(true)
                .submitLabel(.send)
                .onSubmit { if !vm.inputIsEmpty { vm.sendMessage() } }
            Button(action: { vm.sendMessage() }) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 32))
                    .foregroundColor(vm.inputIsEmpty ? Color.gray.opacity(0.4) : Theme.burntOrange)
            }
            .disabled(vm.inputIsEmpty)
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
                Button(action: { vm.showAddContact = true }) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .foregroundColor(Theme.burntOrange)
                }
                .accessibilityLabel("Add emergency contact")
            }
            if vm.contacts.isEmpty {
                Text("Add a trusted contact so SafeWalk can offer a one-tap text to them if you stop responding.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(vm.contacts) { contact in
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
                        Button(action: { vm.removeContact(contact) }) {
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
            TextField("Name", text: $vm.newContactName)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .autocapitalization(.words)
                .disableAutocorrection(true)
            TextField("Phone Number", text: $vm.newContactPhone)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .keyboardType(.phonePad)
                .autocapitalization(.none)
                .disableAutocorrection(true)
            Button("Add") { vm.addContact() }
            .disabled(addContactDisabled)
            .padding()
            .frame(maxWidth: .infinity)
            .background(addContactDisabled ? Color.gray.opacity(0.3) : Theme.burntOrange)
            .foregroundColor(.white)
            .cornerRadius(12)
            Button("Cancel") { vm.showAddContact = false }
                .padding(.top, 4)
        }
        .padding()
    }

    private var startWalkSheet: some View {
        NavigationView {
            Form {
                Section("Where are you headed?") {
                    TextField("Destination (e.g. Jester dorm)", text: $vm.walkDestination)
                        .autocapitalization(.words)
                        .disableAutocorrection(true)
                }
                Section("How long should it take?") {
                    Picker("Expected duration", selection: $vm.walkMinutes) {
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
                    Button("Cancel") { vm.showStartWalk = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Start") { vm.startWalk() }
                        .disabled(vm.walkDestination.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    // MARK: - Helpers

    private var addContactDisabled: Bool {
        vm.newContactName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || vm.newContactPhone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func initials(for name: String) -> String {
        let parts = name.split(separator: " ")
        let letters = parts.prefix(2).compactMap { $0.first }
        return String(letters).uppercased()
    }

    /// Recenters the map camera on a coordinate, keeping the existing zoom.
    private func recenter(on coordinate: CLLocationCoordinate2D?) {
        guard let coordinate else { return }
        cameraPosition = .region(
            MKCoordinateRegion(center: coordinate,
                               span: MKCoordinateSpan(latitudeDelta: 0.005, longitudeDelta: 0.005))
        )
    }
}
