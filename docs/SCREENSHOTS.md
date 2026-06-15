# Screenshots

Captured in the iOS Simulator (iPhone 17 Pro), in SafeWalk's burnt-orange-and-white theme.

## Dashboard (hero)

![SafeWalk dashboard — live map, active walk timer, quick actions, and check-in chat](screenshots/hero-dashboard.png)

The full dashboard with an **active walk** in progress: the live location map with a check-in
countdown, the walk timer counting down to the ETA, the **I'm safe** / **I need help** quick
actions, and the check-in chat.

## Alert-sent state

![Alert-sent state with the idle walk timer](screenshots/dashboard-alert.png)

After escalation, the status hero turns red — **Alert sent · "No response detected — escalation
triggered."** — with the idle walk timer below, ready to start a new walk.

## Walk timer

![Start a walk: destination and expected duration](screenshots/walk-timer-start.png)

Starting a walk: name a destination and pick how long it should take (5–30 min). SafeWalk
escalates — alerting your contact and offering a call to UT Police — if you haven't tapped
"I've arrived" by then.

## Deterministic quick replies

| "I'm okay" confirms safety | "I need help" escalates |
| :--: | :--: |
| ![Quick reply confirming safety](screenshots/quick-replies-safe.png) | ![Quick reply triggering escalation](screenshots/quick-replies-help.png) |

The chat offers tappable canned replies. Each posts your message **and** a fixed companion
response with no network call — "I'm okay 👍" confirms safety and resets the check-in clock,
while "I need help 🚨" posts a distress message and escalates immediately.

## How to capture

1. Open `Party Watcher.xcodeproj` in Xcode and run the **Party Watcher** scheme on an iOS
   Simulator (e.g. iPhone 17 Pro).
2. Give the app a location: in the Simulator, **Features ▸ Location ▸ Custom Location…** (or pick
   a city) so the map and movement logic have data.
3. Walk through each screen — start a walk, tap the quick replies, and let the inactivity timer
   escalate to see the alert state.
4. Capture each screen with **⌘S** (File ▸ Save Screen) in the Simulator; it saves a clean,
   device-framed PNG.
5. Move the files into `docs/screenshots/`.
