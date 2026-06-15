# Changelog

All notable changes to SafeWalk are documented here. The format loosely follows
[Keep a Changelog](https://keepachangelog.com/); this project is a prototype and
is not yet versioned for release.

## [Unreleased] — enhancement wave (2026-06)

A parallel, multi-track enhancement pass: extract the safety-critical logic into
tested units, add the walk-timer feature, harden escalation, and polish the UI.
Each item below corresponds to a reviewed pull request.

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
  in CI.

### Known limitations (carried forward — see SECURITY-REVIEW.md)
- Escalation requires the user to tap the notification action; nothing is sent
  fully autonomously (iOS constraint).
- The notification `add()` has no completion handler and categories are
  registered at escalation time — two High-severity fail-safe gaps recommended
  for a follow-up PR.
- The Gemini key ships in the app binary; fine for a prototype, not for release.

## Earlier history

See the git log for the initial build: safety companion UI, AI check-ins,
inactivity detection, one-tap police escalation, CI + shared scheme, background
location, emergency-contact escalation, and the visual overhaul.
