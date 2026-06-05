# SafeWalk

**Your AI companion for the walk home.**

SafeWalk is an iOS app that keeps an eye on you when you're walking alone — late at night, leaving a party, or crossing campus. An AI chatbot checks in with you at regular intervals; if you stop responding or stop moving, it raises an alert and gives you one tap to call campus police, so help is never more than a button away.

![Swift](https://img.shields.io/badge/Swift-5-orange?logo=swift&logoColor=white)
![iOS](https://img.shields.io/badge/iOS-18%2B-000000?logo=apple&logoColor=white)
![SwiftUI](https://img.shields.io/badge/UI-SwiftUI-0071e3)
![Gemini](https://img.shields.io/badge/AI-Google%20Gemini-4285F4?logo=google&logoColor=white)
![License](https://img.shields.io/badge/License-MIT-green)

---

## Features

- **AI check-in companion** — A friendly chatbot powered by Google Gemini messages you on a timer ("Just checking in! Reply if you're okay") and holds a natural, supportive conversation while you walk.
- **Live location map** — A MapKit view tracks your position in real time using Core Location.
- **Inactivity & no-movement detection** — If you don't reply or you stop moving for too long, the app assumes something may be wrong and escalates automatically.
- **One-tap emergency escalation** — A push notification with a "Call UT Police" action dials campus police (512-471-4441) directly from the lock screen.
- **Emergency contacts** — Add and manage trusted contacts, persisted locally with `UserDefaults`.

## How it works

| Mechanism | Detail |
| --- | --- |
| Check-in timer | Prompts you every 60 seconds; resets whenever you respond. |
| Inactivity threshold | No reply **or** no movement for 2 minutes triggers an alert. |
| Movement detection | `CLLocationManager` flags movement when you travel more than 5 m. |
| Escalation | Local notification with an actionable "Call UT Police" button (`tel://`). |

## Tech stack

| Area | Technology |
| --- | --- |
| UI | SwiftUI (iOS 18+) |
| Language | Swift 5 / Xcode |
| AI chat | Google Gemini (`gemini-2.0-flash`) |
| Location & maps | Core Location + MapKit |
| Notifications | UserNotifications (actionable categories) |
| Persistence | `UserDefaults` (Codable emergency contacts) |

## Screenshots

<!--
  Add screenshots here. Drop your images into a `docs/` folder and reference them, e.g.:

  | Check-in chat | Live map | Emergency contacts |
  | :--: | :--: | :--: |
  | ![Chat](docs/chat.png) | ![Map](docs/map.png) | ![Contacts](docs/contacts.png) |

  In the iOS Simulator: File ▸ Save Screen (⌘S) saves a clean device-framed PNG.
-->

_Screenshots coming soon — run the app in the iOS Simulator and capture the chat, live map, and emergency-contacts screens._

## Architecture

- **`SafetyWatcherView`** — the main screen: live map, check-in countdown, chat feed, and emergency-contacts panel.
- **`GeminiManager`** — a singleton that wraps the Gemini REST API with `Codable` request/response models.
- **`LocationManager`** — an `ObservableObject` `CLLocationManagerDelegate` that publishes location updates and fires a movement callback.
- **`NotificationDelegate`** — handles the actionable notification and places the emergency call.

## Getting started

1. Clone the repo and open `Party Watcher.xcodeproj` in Xcode.
2. Get a Google Gemini API key from [Google AI Studio](https://aistudio.google.com/app/apikey).
3. Copy the secrets template and add your key:
   ```bash
   cp "Party Watcher/Secrets.example.swift" "Party Watcher/Secrets.swift"
   ```
   Then edit `Secrets.swift` and set `geminiAPIKey`. This file is gitignored and never committed.
4. Build and run on a device or simulator (location features work best on a real device).

## Notes

This project was built as a campus-safety prototype for the University of Texas at Austin; the emergency-call action is wired to UTPD. The escalation logic is a proof of concept and is **not** a substitute for emergency services — always call 911 in a real emergency.

## License

[MIT](LICENSE) © William Mar
