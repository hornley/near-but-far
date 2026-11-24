# App Screen Protection Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `workflow-implementation` to execute this plan task-by-task under the project workflow rules.

**Goal:** Replace the disabled lock controls with an authenticated app-owned Mac screen that follows the existing presence rules, supports phone and local-authentication dismissal, and never claims to lock macOS.

**Architecture:** `MacCoordinator` owns app-screen policy and state. A focused AppKit controller presents one overlay window per active display and restores the app's previous presentation options; the screen view starts system local authentication through a coordinator callback. `PeerSession` carries authenticated app-screen commands and state, while `PhoneCentral` and `PhoneModel` keep phone controls and the last authenticated app-screen state separate from macOS lock state.

**Tech Stack:** Swift 5, SwiftUI, AppKit, LocalAuthentication, CoreBluetooth, the existing Snow-backed `PeerSession`, XCTest, Xcode. Preserve the macOS 14 and iOS 17 deployment minimums.

---

## Review result and planning decisions

The spec is ready for an implementation plan. Its ownership boundaries match the current code, and the selected AppKit approach is compatible with the existing menu-bar app. These implementation details resolve lifecycle questions without changing the approved user behavior:

- After phone or local dismissal, keep the screen dismissed for that absence episode. A fresh strong authenticated RSSI sample rearms automatic activation for a later away episode.
- If monitoring is turned off while the screen is active, keep authenticated challenges running only to detect a fresh return sample. Do not trigger new automatic screens while monitoring is off. This preserves the specified return path without dismissing the active screen as a side effect of the toggle.
- Send the current authenticated app-screen state as soon as a secure phone session is ready. On disconnect, the phone shows Unavailable until it receives the next authenticated state.
- In the Mac menu, enable **Lock now** as a local activation action. Remove the menu's **Unlock** action; the screen card remains the only local dismissal path and invokes macOS authentication. The iPhone's **Unlock** remains an authenticated remote command.
- Keep automatic screen activation gated by the existing 60-second tracker, and keep Bluetooth unavailable from being treated as proof of absence.

## Files

- Create `Sources/Shared/AppScreenPolicy.swift` — pure Mac-side transition policy for manual/automatic activation, away-then-return dismissal, and dismissal latching. It does not read RSSI or own AppKit.
- Modify `Sources/Shared/PeerSession.swift` — add typed app-screen commands and app-screen state messages, wire encoding/decoding, and sender-role validation.
- Create `Sources/Mac/AppScreenView.swift` — accessible Quiet Graphite screen with localized time/date, lock symbol, approved copy, and a single authentication action.
- Create `Sources/Mac/AppScreenOverlayController.swift` — full-screen AppKit windows for active displays, kiosk presentation options, display-change handling, and cleanup/restoration.
- Modify `Sources/Mac/MacCoordinator.swift` — own screen state and policy; coordinate presence, authenticated commands, local authentication results, and overlay lifecycle.
- Modify `Sources/Mac/NearButFarMacApp.swift` — expose local **Lock now**, show app-screen state and accurate app-level limits, and remove the bypassing menu **Unlock** action.
- Modify `Sources/iOS/PhoneModel.swift` — store authenticated app-screen state and report Unavailable after disconnect; remove the obsolete Mac lock observation and `lockUnavailable` presentation.
- Modify `Sources/iOS/PhoneCentral.swift` — send authenticated app-screen commands through the established session and handle session-state synchronization.
- Modify `Sources/iOS/NearButFarPhoneApp.swift` — enable phone actions only for a ready secure session, label the row **App screen**, and explain that actions control the app screen rather than macOS's secure lock.
- Modify `Tests/NearButFarTests.swift` — test policy transitions, peer-message direction/validation, and phone state behavior using the existing test target.
- Modify `NearButFar.xcodeproj/project.pbxproj` — add the new Swift files to the Mac target and add `AppScreenPolicy.swift` and `PhoneModel.swift` to the test target; retain explicit target membership.
- Modify `README.md`, `docs/lock-screen-design.md`, and `docs/project-handoff.md` — replace outdated disabled-control claims and describe the implemented app-level deterrent and remaining physical checks.

## Tasks

### Task 1: Add app-screen protocol types and transition policy

**Files:** Create `Sources/Shared/AppScreenPolicy.swift`; modify `Sources/Shared/PeerSession.swift`, `Tests/NearButFarTests.swift`, and `NearButFar.xcodeproj/project.pbxproj`.

- [x] **Step 1: Define the app-screen wire types and message cases**

Use distinct command and state types. Keep the wire names explicitly app-screen scoped:

```swift
enum AppScreenCommand: UInt8, Equatable {
    case activate = 1
    case dismiss = 2
}

enum AppScreenState: UInt8, Equatable {
    case inactive = 1
    case active = 2
}
```

Add `PeerMessage.appScreenCommand(AppScreenCommand)` and `PeerMessage.appScreenState(AppScreenState)`. Assign new message tags after the existing tags. Commands are valid only from `.phone`; state is valid only from `.mac`. Reject unknown payload values, wrong-role messages, and malformed payload lengths through the existing `PeerSessionError.malformedRecord` / `.wrongPeer` paths. Remove the obsolete `MacStatus.lockUnavailable` value and its phone mapping; app-screen state is reported by the new separate message. Do not add any OS lock/unlock message.

- [x] **Step 2: Add protocol behavior tests**

In `Tests/NearButFarTests.swift`, cover valid command and state round trips, invalid raw values, wrong-role send/receive attempts, and replay of a previously accepted authenticated record. Assert the visible result: an invalid, replayed, or wrong-role message does not produce a verified app-screen command/state event.

Run: `xcodebuild test -project NearButFar.xcodeproj -scheme NearButFarTests -destination 'platform=macOS' -only-testing:NearButFarTests`
Expected: compilation fails because the app-screen cases and types do not exist yet.

- [x] **Step 3: Implement message encoding and role checks**

Extend the current `PeerSession` envelope codec and operational-message validation for the two app-screen messages. Preserve the existing Noise session and transport replay behavior; accept a message only after successful `receive` verification on the active link and expected pinned peer.

- [x] **Step 4: Write failing transition-policy tests**

Write tests for manual activation while nearby; manual and automatic activation while already away; weak signal followed by fresh strong recovery; reconnect without a fresh strong sample; and explicit dismissal during an away episode that must not trigger again until fresh strong presence rearms the next episode.

Run: `xcodebuild test -project NearButFar.xcodeproj -scheme NearButFarTests -destination 'platform=macOS' -only-testing:NearButFarTests`
Expected: compilation fails because `AppScreenPolicy` does not exist yet.

- [x] **Step 5: Implement the pure app-screen transition policy**

Add `AppScreenPolicy` with this API:

```swift
struct AppScreenPolicy {
    private(set) var state: AppScreenState = .inactive
    private(set) var returnIsArmed = false
    private(set) var dismissalIsLatched = false

    mutating func activateManually(whileAway: Bool)
    mutating func activateAutomatically() -> Bool
    mutating func observeAway()
    mutating func observeFreshStrongPresence() -> Bool
    mutating func dismiss()
}
```

Automatic activation returns `false` when a screen is already active or dismissal is latched. Manual activation while away arms return; activation while nearby does not. Observing away while active arms return. A fresh strong sample dismisses only when return is armed; if an explicit dismissal was latched, that sample clears the latch and rearms future automatic activation. `dismiss()` latches only when dismissing an active screen whose return is armed. Monitoring and RSSI interpretation remain in `MacCoordinator`.

Run: `xcodebuild test -project NearButFar.xcodeproj -scheme NearButFarTests -destination 'platform=macOS' -only-testing:NearButFarTests`
Expected: all protocol and policy tests pass.

- [x] **Step 6: Add the new policy and phone model files to test membership**

Register `AppScreenPolicy.swift` in the Mac app and test target. Add `PhoneModel.swift` to the test target for model-state tests. Keep Mac-only policy out of the iOS target and retain the existing explicit file membership.

### Task 2: Implement AppKit overlay and local-authentication callback seam

**Files:** Create `Sources/Mac/AppScreenView.swift` and `Sources/Mac/AppScreenOverlayController.swift`; modify `NearButFar.xcodeproj/project.pbxproj`.

- [x] **Step 1: Build the accessible screen view**

Create a SwiftUI view that matches `docs/lock-screen-design.md`: near-black graphite background, centered rounded card, live localized Mac time/date, a simple lock symbol, **Mac is locked**, and **Use Touch ID or password to return.** Make the card a VoiceOver-focusable button with an explicit label and hint. It invokes one callback and contains no text field, password state, or password logging.

- [x] **Step 2: Add one borderless full-screen window for each active display**

The controller creates a borderless window sized to each active `NSScreen`, places the screen view in it, and orders all windows above ordinary app windows. Use AppKit window level and collection behavior that keep the app-owned overlay in the active user session; do not create a login window or claim secure-session protection. Reconcile windows when `NSApplication.didChangeScreenParametersNotification` arrives so newly attached displays get an overlay and removed displays do not retain stale windows. Ensure keyboard input cannot reach applications behind a visible overlay; the card action remains available to pointer and VoiceOver users.

- [x] **Step 3: Apply and restore kiosk presentation options**

When first presenting, save `NSApp.presentationOptions`, then apply the documented options supported by macOS 14 to hide the Dock and menu bar and suppress app switching, Force Quit, Apple-menu actions, hiding the app, and session-termination panels. Do not claim these options block restart or external process termination. On dismissal and orderly app termination, close all overlay windows and restore the saved presentation options exactly once.

- [x] **Step 4: Connect the card through the coordinator callback seam**

Expose one simple callback seam from the card action for Task 3 to wire to `MacCoordinator`; the callback only hands off the action. Do not evaluate `LAContext`, keep credential state, or add authentication logic in the view or overlay controller. Do not create an app-owned credential field or read, store, or log a password.

- [x] **Step 5: Register both Mac files and build the Mac target**

Add the files to the Mac target in the explicit Xcode project, then run:

`xcodebuild build -project NearButFar.xcodeproj -scheme NearButFarMac -destination 'platform=macOS'`

Expected: the Mac app builds with the new view and controller. Keep runtime presentation-option verification for the manual acceptance task; a build alone does not prove kiosk behavior.

### Task 3: Wire coordinator presence and screen lifecycle

**Files:** Modify `Sources/Mac/MacCoordinator.swift` and `Sources/Mac/MacPeripheral.swift`; use `Sources/Shared/AppScreenPolicy.swift` and `Sources/Mac/AppScreenOverlayController.swift`.

- [x] **Step 1: Add coordinator-owned screen state and explicit activation/dismissal entry points**

Add a read-only published app-screen state and route policy transitions through coordinator methods. Manual phone activation presents immediately. Automatic activation occurs only after the existing `PresenceTracker` reports its single 60-second expiry while monitoring is enabled. Bluetooth unavailable never starts an automatic away timer. Keep app-screen state in memory only; a process restart starts inactive and still requires fresh authenticated presence for monitoring.

- [x] **Step 2: Handle authenticated phone commands**

In the existing verified-message path, accept only `.appScreenCommand` messages from the currently authenticated paired peer. Activation presents the overlay immediately; dismissal hides it and latches dismissal for the current away episode. Reply with the current authenticated app-screen state after every accepted transition. Ignore commands from any other link/session through the existing peer and link guards.

- [x] **Step 3: Dismiss only on a qualifying fresh return sample**

After each accepted authenticated RSSI sample, update the existing tracker and the app-screen policy. A return dismissal requires a sample strictly stronger than the current threshold and an armed away-then-return transition. Reconnection without a fresh strong RSSI sample does not dismiss. For a manual screen activated while nearby, arm return only after weak signal or connection loss is observed while the screen is active.

- [x] **Step 4: Preserve active-screen behavior when monitoring is toggled off**

Turning monitoring off prevents new automatic activations and does not dismiss the active screen. If the screen is active, keep only the authenticated challenge/RSSI path needed for return detection; do not emit “waiting” monitoring status or run the away-trigger branch while monitoring is off. Stop that limited sampling when the screen is dismissed. If Bluetooth becomes unavailable, keep the overlay active and wait for local authentication or a recovered secure session.

- [x] **Step 5: Report Bluetooth unavailability before link teardown**

When the radio leaves `.poweredOn`, have `MacPeripheral` report the Bluetooth-unavailable state to `MacCoordinator` before closing or invalidating links, or carry an equivalent typed cause through teardown. The coordinator must process that state before any resulting disconnect callbacks and must not record shutdown-induced link loss as away evidence. Bluetooth unavailable alone never starts an away timer or triggers an automatic screen. Preserve real connection loss while Bluetooth remains powered as away evidence for the existing 60-second grace period.

- [x] **Step 6: Synchronize state on secure session readiness and disconnect**

After the Mac authenticates the phone, send the signal threshold and current app-screen state through the secure session even when monitoring is off. On disconnect, do not mutate app-screen state. The phone will mark its view Unavailable until the next secure session reports the current value.

- [x] **Step 7: Evaluate local authentication in MacCoordinator**

Use the view's callback seam to evaluate `LAContext` with `.deviceOwnerAuthentication`. Capture the current overlay activation identity before evaluating; on success, return to the main actor and report a local dismissal only if that same activation is still active. A cancelled, unavailable, failed, or stale result leaves the overlay visible. Use the system prompt only; do not create an app-owned credential field or read, store, or log a password.

- [ ] **Step 8: Exercise coordinator policy integration**

Test or manually drive these observable sequences: 59 seconds of weak/lost presence does not activate; expiry does; fresh recovery before expiry cancels; Bluetooth-unavailable state reaches the coordinator before link teardown and causes no away evidence or activation; connection loss while Bluetooth remains powered follows the existing 60-second away path; monitoring off prevents a new automatic activation while manual activation still works; turning monitoring off during an active screen leaves it visible; fresh strong return dismisses only when armed; explicit dismissal does not retrigger during the same away episode.

### Task 4: Enable phone controls and show authenticated app-screen state

**Files:** Modify `Sources/iOS/PhoneModel.swift`, `Sources/iOS/PhoneCentral.swift`, and `Sources/iOS/NearButFarPhoneApp.swift`; modify `Tests/NearButFarTests.swift`.

- [x] **Step 1: Model app-screen state independently from phone presence**

Store the last authenticated `AppScreenState` separately from local phone presence and Mac monitoring status. Track whether an app-screen state has arrived for the current secure session. Derive display state as Active/Inactive only after receiving an authenticated value; use Unavailable before the first value and after disconnect. Remove the obsolete Mac lock observation. Replace `PhonePresenceState.lockUnavailable` with the local-presence result `away`, so the phone's presence card never reports that the Mac lock is unavailable or confirmed. Remove `PhoneMacStatus.lockUnavailable` and its view mapping along with `MacStatus.lockUnavailable`.

- [x] **Step 2: Add secure command methods to PhoneCentral**

Add activate and dismiss actions that send the matching `PeerMessage` only when the active `PeerSession` is established, the active link is current, Bluetooth/session state permits delivery, and the current session has delivered an authenticated app-screen state. The state message confirms the peer supports app-screen commands. Do not change the displayed Mac state optimistically; wait for the authenticated state message from the Mac. Disable both controls until that state arrives and whenever the secure session is unavailable.

- [x] **Step 3: Handle authenticated state and reset presentation on disconnect**

Route verified `.appScreenState` messages to `PhoneModel`. On any disconnect or Bluetooth-unavailable transition, clear the last authenticated app-screen state to Unavailable without inferring Inactive. On reconnect, accept the Mac's immediate current-state message as the new value.

- [x] **Step 4: Update iPhone controls, row, copy, and accessibility**

Keep **Lock now** and **Unlock** enabled only after the current secure session has delivered an authenticated app-screen state and can carry commands. Change **Mac lock state** to **App screen**, with values **Active**, **Inactive**, or **Unavailable**. Add concise copy that the controls show or dismiss the app-owned Mac screen and do not lock/unlock macOS. Keep the native macOS lock state unavailable and do not infer it from app-screen state. Update VoiceOver labels/hints and status announcements to use “App screen.”

- [x] **Step 5: Replace obsolete countdown copy and test the phone states**

Update the local presence card and accessibility summary to show a local away/presence estimate after grace expiry without saying “Lock unavailable,” “No lock request was sent,” or “Mac not locked.” Test Active/Inactive/Unavailable mapping, disconnect, authenticated reconnect synchronization, disabled controls without a session, and command delivery with a session.

Run:

```bash
xcodebuild test -project NearButFar.xcodeproj -scheme NearButFarTests -destination 'platform=macOS' -only-testing:NearButFarTests
xcodebuild build -project NearButFar.xcodeproj -scheme NearButFarPhone -destination 'generic/platform=iOS Simulator'
```

Expected: the shared model/protocol tests pass and the iOS app target builds.

### Task 5: Update Mac menu and project documentation

**Files:** Modify `Sources/Mac/NearButFarMacApp.swift`, `README.md`, `docs/lock-screen-design.md`, and `docs/project-handoff.md`.

- [x] **Step 1: Enable local Mac activation and remove the menu dismissal bypass**

Wire the Mac menu's **Lock now** button to coordinator activation. Remove its **Unlock** button because local return must go through the screen card's LocalAuthentication prompt. Show the current app-screen state in the menu and replace “locking unavailable” threshold help with accurate language about the app-level screen and its limits.

- [x] **Step 2: Update user-facing project documentation**

Update the README so it no longer says the controls are disabled or the app provides no screen protection. Update the design note and handoff with the implemented app-level deterrent, separate authenticated app-screen state, phone and local return paths, documented kiosk limitations, and the explicit statement that macOS's secure lock state is not observed or changed.

- [x] **Step 3: Search for stale native-lock claims**

Run `rg -n "Lock unavailable|locking is unavailable|controls remain disabled|Mac lock state|Mac not locked|does not protect or lock" README.md docs Sources` and review every match. Retain historical explanation only where it is clearly marked as superseded; remove stale current-state UI and project guidance.

### Task 6: Run release-path verification and record remaining limits

**Files:** `Sources/Mac/AppScreenOverlayController.swift`, `Sources/Mac/AppScreenView.swift`, `Sources/Mac/MacCoordinator.swift`, `Sources/iOS/PhoneCentral.swift`, `Sources/iOS/PhoneModel.swift`, `Sources/iOS/NearButFarPhoneApp.swift`, `docs/project-handoff.md`.

- [x] **Step 1: Build all supported targets and run the existing automated suite**

Run:

```bash
xcodebuild build -project NearButFar.xcodeproj -scheme NearButFarMac -destination 'platform=macOS'
xcodebuild build -project NearButFar.xcodeproj -scheme NearButFarPhone -destination 'generic/platform=iOS Simulator'
xcodebuild test -project NearButFar.xcodeproj -scheme NearButFarTests -destination 'platform=macOS'
```

Expected: both app targets build and the XCTest suite passes.

- [ ] **Step 2: Walk through overlay presentation and local authentication on a Mac**

Verify the supplied screen design on every active display, including display attach/detach while active, current locale/time formatting, VoiceOver focus and activation, successful Touch ID/password authentication, cancellation, unavailable authentication, and failure. Confirm ordinary pointer/keyboard input cannot reach apps behind the overlay.

- [ ] **Step 3: Verify the documented kiosk restrictions and record surviving exits**

On each supported macOS version, while the overlay is active, exercise Command-Tab, Force Quit, Apple-menu actions, app hiding, and the session-termination panel. Confirm previous `NSApp.presentationOptions` are restored after dismissal. Record any route that remains available; do not claim full resistance to deliberate bypass, restart, or external process termination.

- [ ] **Step 4: Walk through the authenticated phone and presence paths**

With paired devices, verify immediate phone Lock now, authenticated phone Unlock, auto activation at the existing 60-second boundary, strong RSSI recovery before expiry, recovery after the manual screen was activated while nearby, reconnect without RSSI, Bluetooth unavailable while active, monitoring off while active, and status synchronization after reconnect. Verify the overlay never disappears from connection alone and no stale/unauthenticated/replayed message changes it.

- [x] **Step 5: Update the handoff with evidence and remaining physical checks**

Record the tested Mac model/macOS version, display setup, phone/iOS version, exact run conditions, kiosk routes tested, and observed BLE/RSSI ordering. Leave physical pairing, BLE sampling, reconnection, and Bluetooth-unavailable checks open until supported by device evidence; do not describe the overlay as a substitute for macOS's secure lock screen.

## Self-review against the spec

- Automatic trigger, existing threshold, 60-second grace period, and recovery cancellation: Tasks 1 and 3.
- Authenticated phone activation/dismissal and authenticated state: Tasks 1, 3, and 4.
- Return requires fresh strong RSSI; reconnect alone is insufficient: Tasks 1, 3, 4, and 6.
- Manual screen while nearby stays active until explicit dismissal or an observed away-then-return cycle: Tasks 1 and 3.
- All active displays, input containment, kiosk restrictions, option restoration, and documented bypass limits: Tasks 2 and 6.
- LocalAuthentication uses the system prompt; cancellation/failure does not dismiss; no app password handling: Task 2 exposes the callback seam, Task 3 owns authentication, and Task 6 verifies the behavior.
- VoiceOver and adaptive localized design: Tasks 2 and 6.
- Phone says App screen Active/Inactive/Unavailable and never claims macOS lock state: Tasks 4 and 5.
- Bluetooth shutdown is not treated as away evidence or allowed to clear an active screen; Bluetooth-on connection loss remains eligible for the 60-second away trigger: Task 3.
- Physical BLE/pairing/recovery checks remain explicitly open: Task 6.

## Execution handoff

Implementation is complete. The Mac and generic iOS Simulator builds succeeded, and the macOS XCTest suite passed (30 tests, 0 failures). Manual overlay, local-authentication, kiosk, phone, and physical BLE integration checks remain pending; Task 6 Steps 2–4 are unchecked until verified on available devices.
