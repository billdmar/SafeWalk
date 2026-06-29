# Changelog

All notable changes to SafeWalk are documented here. The format loosely follows
[Keep a Changelog](https://keepachangelog.com/); this project is a prototype and
is not yet versioned for release.

## [Unreleased] — architecture & quality refactor (2026-06)

A staged, eight-PR pass that re-architected the app to MVVM, fixed seven known
bugs, added user-facing features, and built out the quality infrastructure.
Each item corresponds to a reviewed, individually-green pull request.

### Added
- **Settings screen** — adjustable check-in cadence and inactivity threshold
  (fed straight into `SafetyEngine`), a background-location toggle, AI memory
  depth, an optional campus emergency-number override (UTPD stays the default),
  and clear-chat. Persisted via a `SettingsStore`.
- **Persistent chat history** — the transcript and Gemini conversation survive
  an app relaunch (`ChatHistoryStore`), bounded by history pruning.
- **Contextual AI errors** — a failed companion reply now shows copy keyed off
  the `GeminiError` (no connection / busy / not configured / generic) instead of
  one opaque apology, always keeping the safety framing.
- **Battery-aware warning** — a banner when background tracking is on, the
  battery is below 20%, and the device isn't charging (`BatteryMonitoring`).
- **UI polish** — an animated typing indicator, message fade-in transitions, a
  pressable button style, centralized `Haptics`, screen-relative chat-bubble
  sizing for Dynamic Type, and accessibility identifiers on key controls.

### Changed
- **Re-architected the main screen to MVVM** — the former 1008-line
  `SafetyWatcherView` god view is now an ~80-line composition of focused card
  subviews. All state, timers, networking, persistence, and escalation moved
  into a `@MainActor SafetyWatcherViewModel`. Every dependency is injected behind
  a protocol (`LocationProviding`, `GeminiSending`, `ContactStoring`,
  `SettingsStoring`, `ChatHistoryStoring`, `BatteryMonitoring`, `TimerScheduling`,
  a `now` clock), making the controller deterministically testable.
- **`GeminiManager`** gained a test-injectable session/key/retry-delay, a pure
  conversation-pruning helper, and a distinct `invalidRequest` error (the
  request-build failure was previously misclassified as `decoding`).

### Fixed
- Status-hero pulse no longer animates under Reduce Motion (now uses
  `symbolEffect(.pulse, isActive:)`).
- The map recenters only on the first fix and on an explicit "locate me" tap,
  instead of snapping back on every location update while the user pans.
- The keyboard dismisses after sending a chat message.
- **Escalation fail-safes (the three High-severity gaps from the security
  review).** Notification categories + delegate now register **once at app
  launch** (no more delivery race that could drop the action buttons); each
  escalation notification carries its contacts + coordinate as an **immutable
  `userInfo` snapshot** (no shared mutable singleton state a rapid second
  escalation could clobber); and `add(request)` now has a completion handler
  that **falls back to the in-app alert** instead of failing silently.

### Quality infrastructure
- **SwiftLint** configuration + a CI lint job (non-strict: errors gate,
  warnings guide).
- **Code coverage** enabled in CI with an `xccov` summary published to the run.
- **DocC** catalog documenting the MVVM + DI architecture.
- A **`URLProtocol`-based integration test** that exercises `GeminiManager`'s
  real request / decode / retry pipeline without the network, plus real
  **XCUITest** end-to-end flows replacing the empty stubs (the UI-tests target
  was also wired into the shared scheme, which it never had been).

### Testing
- Test coverage grew to **74 unit tests across 8 suites** — the prior pure-logic
  suites plus `SafetyWatcherViewModelTests` (timers, escalation, settings,
  persistence, battery — all via injected mocks) and the `GeminiManager`
  integration test — all network-free, plus the new XCUITest UI flows.

## [Unreleased] — earlier enhancement wave (2026-06)

A parallel, multi-track enhancement pass that preceded the refactor above:
extract the safety-critical logic into tested units, add the walk-timer feature,
harden escalation, and polish the UI. Each item below corresponds to a reviewed
pull request.

### Added
- **Walk timer / ETA** — name a destination and expected duration; SafeWalk
  counts down and **auto-escalates on overrun** if you don't tap "I've arrived"
  in time. New pure `WalkSession` / `WalkTimer` types with regression tests.
- **Multi-contact escalation** — escalation now offers a group SMS to *every*
  saved contact with a dialable number (previously only the first was notified).
  Undialable numbers are dropped, not allowed to abort the send.
- **Resilient Gemini calls** — a request timeout, one automatic retry on
  transient network/server failures (5xx / 429 / network blips), an empty-key
  fast-fail, and a typed `GeminiError` so the UI can fail gracefully offline.
- **AI chat quick replies** — a row of tappable suggested replies under the
  chat. Tapping one sends it to the Gemini AI companion for a real, context-aware
  response (with an instant built-in fallback when offline) and carries a safety
  effect (`reassure` / `neutral` / `escalate`). The `escalate` reply ("I need
  help") triggers escalation instantly without an AI round-trip. Pure
  `QuickReplies` catalog with regression tests over labels and effects.
- **Accessibility** — Reduce Motion support for the status hero, a distinct
  error haptic on automatic escalation, and Dynamic Type-friendly chat bubbles.
- **`docs/SECURITY-REVIEW.md`** — a security & privacy review (PII handling, key
  management, escalation fail-safe gaps), with a verified-clean git-history scan.

### Changed
- **Refactored the safety logic into pure, testable units** — the escalation
  decision, movement rule, and countdown formatting moved to `SafetyEngine`; the
  `sms:` / `tel:` deep-link builders moved to `Escalation` (previously a
  `private` method inside `NotificationDelegate`). No behavior change.
- Modernized the deprecated `Map(coordinateRegion:annotationItems:)` to the
  iOS 17+ `Map(position:)` / `Marker` API; cleared the related deprecation
  warnings.

### Testing
- Test coverage grew from **4** to **37** unit tests across 5 suites
  (`SafetyEngine`, `Escalation`, `WalkSession`/`WalkTimer`, `GeminiManager`
  classification, `QuickReplies`), all network-free and run on the iOS Simulator
  in CI. _(Since grown to 74 across 8 suites in the refactor wave above.)_

### Known limitations (carried forward — see SECURITY-REVIEW.md)
- Escalation requires the user to tap the notification action; nothing is sent
  fully autonomously (iOS constraint).
- The notification `add()` has no completion handler and categories are
  registered at escalation time — two High-severity fail-safe gaps recommended
  for a follow-up PR. _(Both — plus a shared-mutable-state escalation race —
  fixed in the refactor wave above; see SECURITY-REVIEW.md.)_
- The Gemini key ships in the app binary; fine for a prototype, not for release.

## Earlier history

See the git log for the initial build: safety companion UI, AI check-ins,
inactivity detection, one-tap police escalation, CI + shared scheme, background
location, emergency-contact escalation, and the visual overhaul.
