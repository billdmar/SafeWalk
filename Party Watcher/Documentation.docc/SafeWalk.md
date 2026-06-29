# ``Party_Watcher``

Your AI companion for the walk home — a personal-safety app that checks in with
you, watches for inactivity, and escalates to your contacts or campus police
when something seems wrong.

## Overview

SafeWalk keeps an eye on you while you walk alone. A Gemini-powered companion
checks in on a timer; if you stop replying *or* stop moving past a threshold —
or run past a walk's ETA — it escalates: a local notification offers a one-tap
call to campus police and a group text to your trusted contacts, prefilled with
your last known location.

## Architecture

SafeWalk follows MVVM with dependency injection so the safety-critical logic is
deterministically testable, without a device, network, or wall-clock waits.

- **Views** (`SafetyWatcherView` + the card subviews) are presentation only.
  They read published state from the view model and forward user intent.
- **``SafetyWatcherViewModel``** owns all safety state and side effects: the
  check-in chat, the live-location mirror, the three timers, persistence, and
  escalation orchestration. Every dependency is injected:
  - ``LocationProviding`` — the location source (real `LocationManager`, or a
    mock that emits synthetic fixes).
  - ``GeminiSending`` — the AI client (real `GeminiManager`, or a stub).
  - `ContactStoring` / `SettingsStoring` / `ChatHistoryStoring` — persistence
    (UserDefaults-backed, or in-memory in tests).
  - `TimerScheduling` — real `Timer`s in the app, a manual ticker in tests.
  - `BatteryMonitoring` — `UIDevice` battery state, or a mock.
  - a `now: () -> Date` clock for pure time-based assertions.
- **Pure safety logic** lives in side-effect-free types covered by unit tests:
  - `SafetyEngine` — the escalation decision, movement threshold, countdown.
  - `WalkSession` / `WalkTimer` — ETA and walk-overrun rules.
  - `Escalation` — the `sms:` / `tel:` deep-link builders.
  - `QuickReplies` — the deterministic quick-reply catalog.

Because the escalation deep links and the decision rule are pure functions, the
part that decides whether help is summoned can be reasoned about and regression-
tested in isolation from the UI.

## Topics

### The controller
- ``SafetyWatcherViewModel``

### Injectable services
- ``LocationProviding``
- ``GeminiSending``
