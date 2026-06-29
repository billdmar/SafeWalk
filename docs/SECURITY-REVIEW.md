# SafeWalk — Security & Privacy Review

_Last updated: 2026-06-11. Scope: the SwiftUI app as of the enhancement wave
(foundation refactor + walk timer + multi-contact escalation + UI/accessibility).
This is an advisory review — findings and recommendations only._

## Executive summary

SafeWalk is a local-only, single-screen SwiftUI safety app. There is no backend
of its own, no analytics, and no third-party SDKs; the only network egress is
HTTPS to the Google Gemini API. PII (an emergency contact's name and phone
number) and the user's location stay on-device except for two intentional,
user-initiated egress paths: the chat text the user types (sent to Gemini) and
the Maps link in the escalation SMS (sent only when the user taps the action).

The overall posture is reasonable for a prototype. The most important issues are
**not** classic data leaks — they are **fail-safe gaps in the escalation path**,
which is the core promise of a safety app. Those are called out as High below.

## Git-history secret scan — **clean** (verified)

The Gemini API key lives in `Secrets.swift`, which is gitignored
(`.gitignore:4`). Verified on 2026-06-11:

- `git grep -i "AIza" $(git rev-list --all)` → **no matches** (Google API keys
  begin with `AIza`; none appear in any commit).
- `git log --all -- "Party Watcher/Secrets.swift"` → **no history** — the file
  was never tracked.

Conclusion: no real key has ever been committed. `Secrets.example.swift` ships
only a commented-out placeholder, and CI writes its own empty stub.

## Findings (severity-ranked)

| Severity | Area | Finding | Recommendation |
|---|---|---|---|
| ~~High~~ → addressed | Escalation fail-safe | `sendPoliceNotification()` called `UNUserNotificationCenter.add(request)` with **no completion handler** — a denied/failed add made escalation **silently no-op**. | **Fixed (PR5).** `NotificationService.postEscalation` now passes a completion handler; on failure the view model raises the in-app alert and posts a chat line pointing the user to the on-screen "I need help" button, so escalation never dies quietly. |
| ~~High~~ → addressed | Escalation fail-safe | Notification categories were registered **at escalation time**, racing the notification's own delivery, so the action buttons could be missing on the first alert. | **Fixed (PR5).** Categories + the delegate are now registered **once at app launch** (`Party_WatcherApp.init` → `NotificationService.registerCategories()`). |
| ~~High~~ → addressed | Escalation race | The notification delegate read the contacts/coordinate from **shared mutable singleton state** set just before each post — a second, rapid escalation could overwrite it before the first was handled. | **Fixed (PR5).** Each notification now carries its contacts + coordinate as an immutable `userInfo` snapshot, read at tap time; no shared mutable state. |
| ~~High~~ → addressed | Escalation fail-safe | Previously only `contacts.first` was ever notified. | **Fixed in the multi-contact PR** — escalation now offers a group SMS to *every* dialable contact; undialable numbers are dropped rather than aborting the send. The "manual tap required" limitation below remains. |
| Medium | Escalation fail-safe | Escalation requires the user to **tap** the notification action — nothing is sent fully autonomously. This is an iOS constraint (apps can't silently place calls/SMS), but it means a fully incapacitated user is not helped by the SMS/call path. | Document prominently in-app and in the README. Consider a server-assisted escalation (out of scope for a local-only prototype) for true autonomy. |
| Medium | API key exposure | The Gemini key ships **in the app binary** (`Secrets.geminiAPIKey`, sent as `X-goog-api-key`). Any client-embedded key is extractable from the IPA. Acceptable for a prototype, not for distribution. | For production, proxy Gemini through a backend so the key never ships to the client; scope/restrict the key in Google Cloud. |
| Low | PII / SMS injection | The escalation SMS/`tel:` URLs are built from the **user-controlled** contact phone string. It is filtered to digits and `+` (`Escalation.dialableDigits`) and the body is placed via `URLComponents` (percent-encoded), so there is **no URL-injection vector**. A malformed number simply yields `nil` and is skipped. | Validate phone format at input time (`addContact`) and warn the user, so a bad number is caught before an emergency rather than silently dropped. |
| Low | Contact storage | Emergency contacts (name + phone = PII) are stored in **`UserDefaults`** — an unencrypted plist in the app sandbox, readable on a jailbroken or unencrypted-backup device. | Low risk given the iOS sandbox + device encryption, but for a PII-handling safety app prefer the Keychain or `NSFileProtectionComplete`, or document the limitation. |
| Low | Permission scope | "Always" + background location with `allowsBackgroundLocationUpdates` is broad but **justified** for a background safety watcher, and is well-guarded (only enabled after Always is granted). | No change; keep the usage-string justifications clear for App Review and users. |
| Info | Network / transport | The Gemini endpoint is HTTPS; `tel://` / `sms:` are standard system schemes; the Maps link is `https://`. No cleartext, no custom ATS exceptions. | None. |
| Info | DEBUG logging | All `print` statements are `#if DEBUG`-gated. The DEBUG-only Gemini "Response body" log can contain chat content but never ships in release. No PII (location, phone, message body) is logged in release. | None; the gating is correctly applied. |
| Info | Chat content egress | Chat text the user types is sent to Google Gemini (expected for the feature). Location/coordinates are **not** sent to Gemini; the only coordinate egress is the user-tapped SMS Maps link. | Note in a privacy disclosure that chat messages go to Google. |

## What's already done well

- **API key correctly gitignored**, with a commented-out template and a clean
  empty working-tree stub; CI writes its own empty stub so no real key is needed
  to build. Git history is verified clean.
- **DEBUG-gated logging throughout** — no PII reaches release logs.
- **HTTPS-only egress**; no cleartext, no insecure ATS exceptions.
- **SMS recipients sanitized** to digits/`+` before building the deep link, with
  `URLComponents` handling body encoding — no injection vector.
- **Coordinate shared only on explicit user action** (tapping the text action),
  and only with the user's own saved contacts.
- **Background location properly guarded** — `allowsBackgroundLocationUpdates`
  is only set after Always auth, avoiding the known runtime crash.
- **Escalation logic is now unit-tested** (the foundation refactor extracted the
  decision + deep-link builders into `SafetyEngine` / `Escalation` with
  regression tests), making the safety-critical path far harder to regress.

## Overall risk verdict

**Low–Moderate.** No critical data-leak or injection vulnerabilities, and the
API key is verified clean in history. The three **High** fail-safe gaps in the
notification escalation path (no `add()` completion handler; async category
registration race; shared-mutable-state escalation race) have all been
**addressed in PR5** — categories register at launch, each notification carries
its own immutable payload, and a delivery failure now falls back to the in-app
escalation rather than failing silently. The remaining items are the documented
prototype limitations (manual-tap escalation, client-embedded API key, PII in
`UserDefaults`); resolve those before treating SafeWalk as anything more than a
prototype.
