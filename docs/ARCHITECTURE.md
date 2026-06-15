# SafeWalk Architecture

SafeWalk is a single-screen SwiftUI iOS app (deployment target iOS 18.5) built
entirely on Apple frameworks — SwiftUI, Core Location, MapKit, and
UserNotifications — plus a thin `URLSession` client for the Google Gemini REST
API. There is no SPM/CocoaPods dependency graph and no backend of its own.

## Component diagram

```
Party_WatcherApp (@main)
        │
        ▼
   ContentView
        │
        ▼
  SafetyWatcherView  ──────────────────────────────────────────────┐
        │  card-based dashboard: status hero, map, walk timer,      │
        │  quick actions, check-in chat, emergency contacts. Uses   │
        │  Theme for color, surfaces (.card()), dark-mode-aware     │
        │  styling, Reduce Motion + Dynamic Type support.           │
        │  Messages are modeled as ChatMessage{id,text,isUser} so   │
        │  bubble alignment is explicit (not index-parity).         │
        │  Pure decision logic is delegated to:                     │
        │    • SafetyEngine  — escalation decision, movement rule,  │
        │                      mm:ss countdown (tested)             │
        │    • WalkSession/WalkTimer — ETA + overrun rule (tested)  │
        │    • Escalation    — sms:/tel: + group-SMS builders,      │
        │                      phone normalization (tested)         │
        │    • QuickReplies  — AI quick-reply catalog + effects;    │
        │                      Gemini reply, instant fallback       │
        │  owns / drives                                            │
        ├── LocationManager (StateObject, CLLocationManagerDelegate)
        │        • requestWhenInUse → escalates to requestAlways
        │        • allowsBackgroundLocationUpdates (guarded on Always auth)
        │        • publishes lastLocation; fires onMovement when moved > 5 m
        │
        ├── GeminiManager.shared (singleton)
        │        • POST gemini-2.0-flash:generateContent via URLSession
        │        • Codable request/response; key from Secrets.geminiAPIKey
        │
        ├── NotificationDelegate.shared (UNUserNotificationCenterDelegate)
        │        • "Call UT Police"  → tel://5124714441
        │        • "Text <contact>"  → sms: deep link w/ help msg + Maps link
        │
        ├── Check-in timer  (60 s, repeating) ── prompts "Reply if you're okay"
        ├── Display timer   (1 s, repeating)  ── advances the visible countdown
        └── Inactivity timer (polls every 5 s)
                 • escalates if no reply  > 120 s
                 •         OR no movement > 120 s
                 • flips status hero safe → checking when a prompt awaits a reply
                 ▼
            triggerAutoAlert()  +  sendPoliceNotification()
            (also reachable instantly via the "I need help" quick action;
             "I'm safe" resets the inactivity clock + countdown and returns to safe)
                 │
                 ▼
        Escalation (UNNotification, actionable category)
          • contact saved  → notify + offer SMS to contact AND call to UTPD
          • no contact     → call to UTPD only (fallback)
```

## Runtime flow

1. **On appear** `SafetyWatcherView` starts location tracking, the 60 s
   check-in timer, and the 5 s inactivity poll, and requests notification
   permission.
2. **Check-in loop** — every 60 s a bot message asks the user to confirm
   they're okay. Replying (or any inbound location movement) resets the
   inactivity clock.
3. **Inactivity detection** — a timer fires every 5 s and compares "now"
   against the last reply time and last movement time. If *either* exceeds the
   120 s threshold, escalation runs.
4. **Escalation** — an in-app alert is shown and an actionable local
   notification is posted. The notification always offers "Call UT Police"
   (`tel://5124714441`). If the user has saved at least one emergency contact,
   the notification also names that contact and offers a "Text <name>" action
   that opens an `sms:` deep link prefilled with a help message and a Maps link
   to the last known coordinate.

## Persistence

Emergency contacts are `Codable` `EmergencyContact` values stored in
`UserDefaults` under `emergencyContacts` (encode/decode helpers live in a
`UserDefaults` extension). There is no database or remote sync.

## Configuration & secrets

`GeminiManager` reads `Secrets.geminiAPIKey` from `Secrets.swift`, which is
**gitignored**. `Secrets.example.swift` documents the shape; its declaration is
intentionally commented out because the file is part of the app's synchronized
source group and an active `enum Secrets` there would collide with the real one
("invalid redeclaration of 'Secrets'"). CI writes a stub `Secrets.swift` with an
empty key so the project compiles without any real credential.

## Location & background mode

Background location is configured via build settings (the project uses
`GENERATE_INFOPLIST_FILE = YES`, so usage strings and background modes are set
through `INFOPLIST_KEY_*` rather than a checked-in `Info.plist`). The app target
sets, in both Debug and Release:

- `INFOPLIST_KEY_NSLocationWhenInUseUsageDescription`
- `INFOPLIST_KEY_NSLocationAlwaysAndWhenInUseUsageDescription`
- `INFOPLIST_KEY_UIBackgroundModes = location`

`LocationManager` requests when-in-use first, escalates to *Always* via the
authorization callback, and only sets `allowsBackgroundLocationUpdates = true`
once Always authorization is granted (setting it without the entitlement +
background mode crashes at runtime).

## What is verified vs. needs a device

- **Verified in CI / locally:** the project compiles and the unit-test target
  builds and runs on the iOS Simulator with the shared scheme; Swift sources
  are type-checked. The test target covers the pure types and decision logic
  (**37 tests across 5 suites**): `ChatMessage` sender/identity, `SafetyStatus`
  presentation, `EmergencyContact` round-tripping, the `SafetyEngine` escalation
  decision + movement rule + countdown clamp, the `WalkSession`/`WalkTimer`
  overrun rule, the `Escalation` deep-link + group-SMS builders,
  `GeminiManager`'s status-code/retry classification, and the `QuickReplies`
  catalog + label→effect mapping (all network-free).
- **Needs device/simulator verification by the user:** runtime background-GPS
  delivery and lock-screen wakeups, the "Always" authorization prompt flow,
  notification delivery, and the `tel:` / `sms:` deep links (these require user
  interaction and real system services that CI does not exercise). The unit
  test target covers the pure model/presentation types; the timer-driven safety
  flow, escalation, and UI are exercised manually in the Simulator.
```
