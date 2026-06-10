# SafeWalk

**Your AI companion for the walk home.**

SafeWalk is an iOS app that keeps an eye on you when you're walking alone — late at night, leaving a party, or crossing campus. An AI chatbot checks in with you at regular intervals; if you stop responding or stop moving, it raises an alert and gives you one tap to call campus police or text a trusted contact, so help is never more than a button away.

[![CI](https://github.com/billdmar/SafeWalk/actions/workflows/ci.yml/badge.svg)](https://github.com/billdmar/SafeWalk/actions/workflows/ci.yml)
![Swift](https://img.shields.io/badge/Swift-5-orange?logo=swift&logoColor=white)
![iOS](https://img.shields.io/badge/iOS-18%2B-000000?logo=apple&logoColor=white)
![SwiftUI](https://img.shields.io/badge/UI-SwiftUI-0071e3)
![Gemini](https://img.shields.io/badge/AI-Google%20Gemini-4285F4?logo=google&logoColor=white)
![License](https://img.shields.io/badge/License-MIT-green)

---

## Features

- **AI check-in companion** — A friendly chatbot powered by Google Gemini messages you on a timer ("Just checking in! Reply if you're okay") and holds a natural, supportive conversation while you walk.
- **Live location map** — A MapKit view tracks your position in real time using Core Location.
- **Background tracking** — With "Always" location permission, SafeWalk keeps watching your position even when the screen is locked or the app is backgrounded (via the `location` background mode).
- **Inactivity & no-movement detection** — If you don't reply or you stop moving for too long, the app assumes something may be wrong and escalates automatically.
- **Emergency-contact escalation** — Add and manage trusted contacts (persisted locally with `UserDefaults`). When escalation fires and you have a contact saved, the alert offers a one-tap "Text <name>" action that opens a prefilled SMS — including a Maps link to your last known location — alongside the campus-police call.
- **One-tap emergency escalation** — A push notification with a "Call UT Police" action dials campus police (512-471-4441) directly from the lock screen.

## How it works

| Mechanism | Detail |
| --- | --- |
| Check-in timer | Prompts you every 60 seconds; resets whenever you respond. |
| Inactivity threshold | No reply **or** no movement for 2 minutes triggers an alert. |
| Movement detection | `CLLocationManager` flags movement when you travel more than 5 m. |
| Background tracking | Requests "Always" authorization and enables `allowsBackgroundLocationUpdates` (with the `location` background mode) so tracking continues when backgrounded/locked. |
| Escalation | Local notification with an actionable "Call UT Police" button (`tel://`), plus a "Text <contact>" button (`sms:` with a prefilled help message + location) when an emergency contact is saved. |

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

Placeholder slots below — capture instructions and the image filenames live in
[docs/SCREENSHOTS.md](docs/SCREENSHOTS.md). Drop the PNGs into `docs/` and they
render here automatically.

| Live map | Check-in chat |
| :--: | :--: |
| ![Live location map](docs/map.png) | ![AI check-in chat](docs/chat.png) |

| Emergency alert | Emergency contacts |
| :--: | :--: |
| ![Escalation alert](docs/alert.png) | ![Emergency contacts](docs/contacts.png) |

_Screenshots are placeholders until captured in the iOS Simulator — see [docs/SCREENSHOTS.md](docs/SCREENSHOTS.md)._

## Architecture

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for the full component diagram, runtime flow, and a note on what is verified by CI vs. what needs on-device testing.

- **`SafetyWatcherView`** — the main screen: live map, check-in countdown, chat feed, and emergency-contacts panel.
- **`GeminiManager`** — a singleton that wraps the Gemini REST API with `Codable` request/response models.
- **`LocationManager`** — an `ObservableObject` `CLLocationManagerDelegate` that publishes location updates, fires a movement callback, and escalates to "Always" authorization for background tracking.
- **`NotificationDelegate`** — a shared singleton that handles the actionable notification, placing the emergency call (`tel:`) or texting the saved contact (`sms:`).

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
