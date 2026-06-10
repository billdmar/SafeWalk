# Screenshots

These are placeholder slots. Drop the captured PNGs into `docs/` using the exact
filenames below and they will render here and in the README.

| Live map | Check-in chat |
| :--: | :--: |
| ![Live location map](map.png) | ![AI check-in chat](chat.png) |

| Emergency alert | Emergency contacts |
| :--: | :--: |
| ![Escalation alert / notification](alert.png) | ![Emergency contacts panel](contacts.png) |

| Slot | File | What to capture |
| --- | --- | --- |
| Live map | `docs/map.png` | The MapKit view tracking your position. |
| Check-in chat | `docs/chat.png` | The chat feed with a bot check-in and your reply. |
| Emergency alert | `docs/alert.png` | The "No response detected" alert / actionable notification. |
| Emergency contacts | `docs/contacts.png` | The emergency-contacts panel with at least one saved contact. |

## How to capture

1. Open `Party Watcher.xcodeproj` in Xcode and run the **Party Watcher** scheme
   on an iOS Simulator (e.g. iPhone 16 Pro).
2. Give the app a location: in the Simulator, **Features ▸ Location ▸ Custom
   Location…** (or pick a city) so the map and movement logic have data.
3. Walk through each screen — let a check-in fire, add an emergency contact,
   and let the inactivity timer escalate to see the alert.
4. Capture each screen with **⌘S** (File ▸ Save Screen) in the Simulator; it
   saves a clean device-framed PNG.
5. Rename/move the files to `docs/map.png`, `docs/chat.png`, `docs/alert.png`,
   and `docs/contacts.png`.
