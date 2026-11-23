# Mac UI and Shared Threshold Refresh Implementation Plan

> **For agentic workers:** Execute sequentially with a fresh implementer and spec-compliance/code-quality review for each task. Keep the Mac UI aligned with the previously approved minimalist status-first mockup.

**Goal:** Replace the stale Mac prototype menu with the approved minimalist status-first interface and make its editable signal threshold real across both authenticated apps.

**Architecture:** The Mac owns and persists the threshold, applies it to Mac presence tracking, and sends it only through the existing authenticated `PeerSession`. The iPhone stores the most recently authenticated value, uses it for its local estimate, and displays it read-only. The Mac status panel stays minimal; a settings screen contains the threshold control and Pair iPhone action. Lock and Unlock remain disabled.

**Tech Stack:** SwiftUI, CoreBluetooth, authenticated Snow session, UserDefaults, Xcode. Preserve macOS 14 and iOS 17 minimums.

---

**Approved design:** The Mac mockup and decisions in the conversation: status-first presentation, centered phone presence, a minimal settings icon immediately left of a close control, and settings containing the threshold and Pair iPhone. The existing approved app spec requires persistence and authenticated cross-device propagation for an editable Mac threshold. The user explicitly requested this correction on 2026-11-24.

**Plan status:** Approved for execution by the user on 2026-11-24 after the plan proposed the `−90...−50 dBm` range in 1 dBm steps, default `−70`.

**Scope:** Implement the Mac UI that the iPhone-only refresh intentionally left out. Add the shared threshold flow required by the approved spec. Do not add locking, unlocking, phone-side threshold editing, or unrelated Mac activity features.

## Files and responsibilities

- `Sources/Shared/PresenceTracker.swift` — validate and apply an instance threshold while preserving existing countdown state.
- `Sources/Shared/PeerSession.swift` — encode and decode the Mac-to-phone threshold as an authenticated operational message.
- `Sources/Mac/MacCoordinator.swift` — persist the Mac setting, apply it to Mac tracking, and send it at session readiness and after edits.
- `Sources/iOS/PhoneModel.swift` — accept only authenticated threshold messages, persist the latest value, and apply it to local estimates.
- `Sources/iOS/NearButFarPhoneApp.swift` — display the effective threshold read-only, including a clear last-synced/waiting state.
- `Sources/Mac/NearButFarMacApp.swift` — status-first home, centered presence state, minimal settings/close controls, and settings panel.
- `Sources/Mac/PairingView.swift` — retain one-use QR enrollment and local approval while using the approved concise Mac pairing copy.
- `README.md` and the approved spec — document the shared threshold and its limitations accurately.

## Task 1: Add a validated, authenticated shared threshold

- [x] Replace the fixed static threshold with a validated `SignalThreshold` value. Use a default of `−70 dBm`, an allowed range of `−90...−50 dBm`, and 1 dBm increments.
- [x] Make `PresenceTracker` receive its threshold as instance state. Changing the setting alone must not reset a countdown; the new value takes effect on the next fresh RSSI sample.
- [x] Add `PeerMessage.threshold(Int16)` as Mac-to-phone-only operational message tag 7. Validate the range when encoding and decoding. Reject malformed or phone-originated threshold messages.
- [x] Persist the Mac value in UserDefaults. Send it after every authenticated session becomes ready, before any status or challenge that uses it, and send updates after an edit when a secure session is available.
- [x] Persist the last authenticated value on iPhone and use it for the local presence estimate. The phone must not expose an edit control. Until any authenticated value arrives, show a waiting/unavailable threshold state rather than claiming a received custom value.
- [x] Preserve one-use QR enrollment, peer identity pinning, status behavior, and all disabled Lock/Unlock behavior. Add no lock or unlock messages.

## Task 2: Implement the approved Mac home and settings screens

- [x] Replace the old “Prototype only” menu contents with the approved minimalist status-first home. Center the phone-presence state and keep supporting state text concise.
- [x] Keep Lock now and Unlock visible and disabled with an accurate explanation; do not imply the Mac is protected or locked.
- [x] Put a minimal `slider.horizontal.3` settings button immediately left of an accessible close `xmark` control. The close control dismisses the menu panel.
- [x] The settings screen contains the editable shared threshold and the Pair iPhone action. Keep the threshold default at `−70 dBm`, restrict it to `−90...−50 dBm`, and label it as a signal threshold; explain that lock execution remains unavailable.
- [x] Keep QR enrollment, identity pinning, and the Mac-local approval action intact. Remove the phone-fingerprint field and the “Approve only if you started pairing on this Mac” warning from the pairing UI, as previously requested; keep concise text that a phone is requesting pairing.
- [x] Verify the Pair iPhone action opens the existing one-use QR flow and that Cancel/Close does not leave a second menu panel open.

## Task 3: Align the iPhone read-only threshold display

- [x] Replace the hardcoded `−70 dBm` label with the last authenticated Mac threshold from `PhoneModel`.
- [x] Track whether the threshold arrived in the current secure session. Label a cached value as last synced when disconnected; show waiting/unavailable before the first authenticated threshold arrives in a session.
- [x] Confirm a secure reconnect updates the threshold before the Mac begins sending monitoring statuses or challenges.
- [x] Keep the iPhone threshold read-only and preserve all existing home order, Recent activity behavior, pairing copy, and disabled Lock/Unlock actions.
- [x] Update README and the approved app spec to describe the configurable Mac threshold (default `−70 dBm`, range `−90...−50 dBm`) and authenticated, read-only iPhone synchronization.

## Task 4: Build, install, and review both apps

- [x] Run `git diff --check`.
- [x] Build `NearButFarMac` for macOS and `NearButFarPhone` for the connected physical iPhone using the existing Apple Development identity.
- [x] Install the Mac app in `~/Applications` and the iPhone app on the connected device. Relaunch each with existing instances terminated; verify one process per target.
- [ ] Review the Mac home, settings view, close action, threshold adjustment, QR pairing entry, phone threshold display, and accessibility labels. Keep physical background/range reliability claims unchanged.

Native GUI review remains pending: `cua.getState()` returned `Native apps: Error: Sky Computer Use native pipe startup failed` and `Browsers: Error: The browser access host is unavailable`. The simulator copy remains owned by another workspace and was left untouched.

## Acceptance

- The running Mac UI matches the approved minimalist status-first mockup and no longer exposes the old prototype layout.
- The editable Mac threshold persists, stays within the specified range, affects both presence trackers on fresh samples, and reaches the iPhone only over an authenticated session.
- The phone reflects the last authenticated threshold without offering an edit control and without presenting stale data as current.
- Existing pairing identity checks, Mac-local approval, and disabled Lock/Unlock controls remain intact.
- macOS and physical iPhone builds succeed, and exactly one app process per target is launched.
