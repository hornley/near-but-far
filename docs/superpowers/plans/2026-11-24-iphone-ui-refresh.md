# iPhone UI Refresh Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development to implement this plan task-by-task. Keep each worker on its assigned files, integrate after the state interfaces are agreed, and review the visible app before handoff.

**Goal:** Implement the approved minimalist iPhone screen atlas, including Recent activity in the top-right menu, while keeping every displayed state truthful to authenticated app data.

**Architecture:** Keep `PhoneModel` responsible for local presence and authenticated Mac status, `PhoneCentral` responsible for CoreBluetooth lifecycle and the existing local event store, and SwiftUI responsible for presentation. Add no lock/unlock protocol operation. Use the existing QR enrollment and Mac-local approval flow.

**Tech Stack:** SwiftUI, CoreBluetooth, AVFoundation, VoiceOver, Xcode. Keep the existing macOS 14 and iOS 17 deployment minimums.

---

**Approved spec:** [Near But Far app design](../specs/2026-11-23-near-but-far-app-design.md), iPhone UI refresh approved 2026-11-24.

**Plan status:** Approved for execution by the user’s `$workflow-implementation` request on 2026-11-24; implementation in progress.

**Scope boundary:** Redesign the iPhone UI and make the smallest cross-app status changes needed to display Mac monitoring truthfully. The Mac visual redesign and editable signal-threshold setting are separate work. The iPhone displays the authenticated Mac-owned threshold read-only, including current-session, last-synced, and waiting-to-sync states.

## Files and responsibilities

- `Sources/iOS/PhoneModel.swift` — local presence transitions and whether an authenticated Mac monitoring status has arrived.
- `Sources/iOS/PhoneCentral.swift` — classify disconnect causes, preserve local loss timing, and expose existing local events.
- `Sources/Shared/PeerSession.swift` — leave initial Mac monitoring status selection to the Mac coordinator instead of sending Waiting unconditionally during reconnect.
- `Sources/Mac/MacCoordinator.swift` — send the actual initial monitoring state after a secure session is ready.
- `Sources/iOS/NearButFarPhoneApp.swift` — approved status-first home, upper-right menu, navigation, and disabled actions.
- `Sources/iOS/RecentActivityView.swift` — dedicated read-only view over the phone’s local event list, opened from the menu.
- `Sources/iOS/PairingScannerView.swift` — concise state-specific QR instructions and recovery copy; retain existing scanner and callbacks.
- `NearButFar.xcodeproj/project.pbxproj` — add the new activity view to the iOS target if the project’s explicit groups require it.
- `README.md` — describe the iPhone menu and clarify that its activity feed is local to the phone.

## Execution sequence

Implementation is divided into three work areas after the state interface is agreed: state semantics (`PhoneModel.swift`, `PhoneCentral.swift`, `PeerSession.swift`, `MacCoordinator.swift`); home and activity UI (`NearButFarPhoneApp.swift`, `RecentActivityView.swift`, project file, README); and pairing copy (`PairingScannerView.swift`, plus removing obsolete initializer inputs at its `NearButFarPhoneApp.swift` call site). Integrate the UI against the interface below, then perform one combined visual review.

### Task 1: Make local presence and Mac status truthful

**Files:** `Sources/iOS/PhoneModel.swift`, `Sources/iOS/PhoneCentral.swift`, `Sources/Shared/PeerSession.swift`, `Sources/Mac/MacCoordinator.swift`

- [x] Add explicit disconnect causes and an optional received Mac status:

```swift
enum PhoneDisconnectReason {
    case transportLost
    case reconnectAttempt
    case pairingStarted
    case bluetoothUnavailable
}

@Published private(set) var macStatus: PhoneMacStatus?

func didDisconnect(
    at now: ContinuousClock.Instant,
    reason: PhoneDisconnectReason
)
```

- [x] In `PhoneModel.didDisconnect`, preserve the original countdown on an unexpected transport loss. If presence was armed with no countdown, start the local loss estimate at the disconnect time. Change the cause to connection loss so the phone presents **Signal lost**. A fresh authenticated RSSI sample above the shared threshold clears the estimate; reconnecting alone does not.
- [x] Map each `PhoneCentral` call site to its cause. A transport close or authentication timeout is unexpected loss. Starting a new QR enrollment is `pairingStarted`; manual reconnect is `reconnectAttempt`. A retry preserves an existing loss countdown. An unexpected loss starts a countdown only when presence had already been armed. Bluetooth turning off clears the session and presents **Unavailable** without saying the Mac is away.
- [x] Reset `macStatus` to `nil` when a session ends or a new session begins. Set it only when an authenticated `.status` message arrives. The UI maps `nil` to **Unavailable** and `.unavailable` to **Off**.
- [x] Remove the unconditional `.status(.waiting)` emitted by `PeerSession` during reconnect. In `MacCoordinator`’s authenticated `.ready` handling, call `beginMonitoringEpoch()` when monitoring is enabled and send `.status(.unavailable)` when it is off. Reuse the existing status message; do not change the wire format.
- [x] Preserve QR approval, identity pinning, retry behavior, and the existing rule that `canLockNow` and `canUnlock` are false. Do not add lock/unlock messages or actions.

**Expected state behavior:** Unexpected disconnect with an active weak-signal timer preserves its start time and changes the phone estimate to Signal lost. Unexpected disconnect before a weak RSSI sample starts the local estimate at disconnect. A new authenticated status clears the “not received” condition; a fresh stronger RSSI sample, not connection alone, confirms local recovery. Bluetooth unavailable remains Unavailable.

### Task 2: Implement the status-first home, menu, and activity screen

**Files:** `Sources/iOS/NearButFarPhoneApp.swift`, create `Sources/iOS/RecentActivityView.swift`, `NearButFar.xcodeproj/project.pbxproj`, `README.md`

- [x] Keep one home screen and the current `NavigationStack`. Match the approved reference with no extra top inset below navigation; use a centered PHONE PRESENCE card with a subtle outline, large status title, 16 pt vertical padding, and one RSSI/threshold line; three single-line Pairing, Mac monitoring, and Mac lock-state rows with thin separators; then side-by-side filled capsule Lock now and Unlock buttons, each about 64 pt high, and one concise explanation. Keep Recent activity off Home.
- [x] Map the six `PhonePresenceState` cases to the approved home states: Waiting for Mac, Nearby, Weak signal with countdown, Signal lost with countdown, Lock unavailable, and Unavailable. Use the current connection phase as supporting text while waiting. Use Unavailable for phone Bluetooth unavailable/unauthorized, not for an ordinary disconnect.
- [x] Map `macStatus == nil` to **Unavailable**, `.unavailable` to **Off**, and the remaining authenticated statuses to Waiting for authenticated iPhone, Nearby, Weak signal, Signal lost, and Lock unavailable. Keep the Mac lock observation **Unavailable** in every current state.
- [x] Keep the compact Home pairing row in sync with `PairingScannerState`: Not paired, scanning, waiting for Mac approval, paired/connected, paired/reconnecting, and the relevant recovery status. Use concise Home values such as **Paired** and **Reconnecting**; keep the longer next-step copy in the pairing sheet. Show Retry connection only when `canRetryConnection` is true.
- [x] Keep the Mac-owned threshold read-only on iPhone. Show the authenticated current-session value, label a cached value as last synced, and show a waiting state while the current session awaits sync. Do not add an iPhone threshold setting.
- [x] Add the top-right menu actions in this order: **Pair a Mac**, **Scan again**, **Recent activity**. Pair a Mac calls `beginPairing()` and presents the existing scanner sheet. Scan again calls `scanAgain()`. Recent activity navigates to the dedicated screen without starting a scan or pairing session.
- [x] Keep **Lock now** and **Unlock** visibly disabled. Preserve concise explanatory text, VoiceOver labels and hints, and status announcements. Do not rely on color alone.
- [x] Add a `RecentActivityView` that receives the existing `[String]` event list from `PhoneCentral.events`, shows newest first, and displays **No local activity yet.** when empty. Keep the view read-only.
- [x] Present only event records that the phone actually stores: Bluetooth state, scan start, connection success/failure/disconnect, CoreBluetooth restoration, invalid QR, pairing expiry, and secure-session closure. Format known event names for people while preserving their recorded timestamps; show unknown records without dropping them.
- [x] Use concise labels for the known event names: `scan_started` → “Scanning for Mac”; `connected` → “Bluetooth connected”; `connect_failed` → “Bluetooth connection failed”; `disconnected` → “Bluetooth disconnected”; `core_bluetooth_restored` → “Bluetooth restored”; `invalid_pairing_qr` → “QR code not recognized”; `pairing_expired` → “Pairing expired”; `secure_session_closed` → “Secure session closed”. Humanize the suffix of `bluetooth_*` records as the recorded Bluetooth state. Keep unknown values visible as text.
- [x] Do not include mock RSSI, countdown, pairing-success, or Mac CSV rows. Those are not currently recorded by the phone. Do not merge or fetch the Mac’s local CSV log.
- [x] Show activity rows only on the dedicated Recent activity screen. Keep the local 200-entry retention limit and storage behavior in `PhoneCentral` unchanged.
- [x] Add the new Swift file to the explicit iOS target if required by the project file. Update the README to state that Recent activity is available from the phone menu and contains phone-local events.

### Task 3: Tighten QR pairing and recovery copy

**Files:** `Sources/iOS/PairingScannerView.swift`; `Sources/iOS/NearButFarPhoneApp.swift` only to remove obsolete view arguments.

- [x] Keep the current scanner, QR payload validation, one-use two-minute Mac offer, authenticated session, and Mac-local approval unchanged. Do not show the Mac fingerprint or an approval button on the phone.
- [x] Give each pairing state one concise title, one next step, and only the action already supported by the current callbacks. Use the approved copy:

| State | Title and next step | Action |
| --- | --- | --- |
| Scanning | **Scan the code on your Mac.** | Cancel |
| Waiting for approval | **Waiting for Mac approval.** Approve this phone on your Mac. Keep this screen open. | Cancel |
| Paired | **Paired.** This phone is paired with your Mac. | Done |
| Not paired | Open Pair iPhone on your Mac, then scan its one-use code. | Scan Mac QR code |
| Expired | The code expired. Create a new code on your Mac and scan it again. | Scan a new code |
| QR mismatch | This code does not match the Mac. Scan a fresh code. | Scan a new code |
| Mac identity mismatch | This is not the saved Mac. Your pairing is unchanged. | Retry connection |
| Camera unavailable | Allow camera access in iPhone Settings to scan a code. | Try camera again |
| Secure storage unavailable | Pairing is unavailable. Restart the app and try again. | None |
| Bluetooth unavailable | Turn on Bluetooth in Settings, then retry pairing. | None; resume when Bluetooth returns |

- [x] Avoid showing the same connection message twice. Use `connectionState` only when it adds actionable detail not already expressed by the state-specific next step.
- [x] Preserve the existing Done/Cancel dismissal semantics: dismissing the sheet cancels an unfinished enrollment, while an established paired identity remains saved.

### Task 4: Build and review the actual iPhone screens

**Files:** Changed app files; no additional product files.

- [x] Build the Mac and iPhone simulator targets because Task 1 changes the shared session and Mac coordinator status behavior:

```bash
xcodebuild build -project NearButFar.xcodeproj -scheme NearButFarMac -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
xcodebuild build -project NearButFar.xcodeproj -scheme NearButFarPhone -destination 'platform=iOS Simulator,name=iPhone 15 Pro Max' CODE_SIGNING_ALLOWED=NO
```

`git diff --check` and the final static review passed. Rendered-state, Dynamic Type, and VoiceOver checks remain pending, as do physical QR-flow checks: `agent-device install` failed with `DEVICE_IN_USE`, and its follow-up status command reported that it cannot inspect the other workspace session.

- [ ] Review the simulator’s six home presence states, menu with all three actions, empty and populated Recent activity, and all pairing/recovery states against the approved screen atlas. Do not add debug controls to the production UI to force a state.
- [ ] Confirm the activity screen shows only locally recorded phone events and never displays sample timestamps or RSSI values as actual history.
- [ ] Review the QR flow on devices: scan the one-use code, wait for local Mac approval, finish pairing, cancel an unfinished flow, and confirm the paired identity remains saved after dismissal.
- [ ] Review VoiceOver labels and hints, Dynamic Type, status changes, and color-independent state meaning. Confirm Lock now and Unlock remain disabled in every screen.
- [ ] Keep physical background reliability and range validation at their existing status; this UI work does not mark those checks complete.

## Acceptance checklist

- The phone UI matches the approved compact status-first screenshot. Home contains only the centered status card, three concise status rows, and compact disabled controls; **Recent activity** opens from the top-right menu on its dedicated screen.
- All six local presence states and the existing pairing/recovery states render from real model values.
- Unexpected loss retains or starts the local countdown per the approved state rules; a connection alone does not clear it.
- The phone distinguishes “Mac status not received” from the Mac reporting monitoring Off. The Mac sends the current monitoring state after authentication without changing the wire format.
- Recent activity is phone-local, chronological newest first, and contains no invented signal or Mac events.
- The QR pairing UX, local approval, one-use offer, and identity pinning remain intact.
- The authenticated Mac-owned threshold remains read-only on iPhone and displays current-session, last-synced, or waiting status accurately. This plan adds no iPhone threshold editor, lock API, or unlock API.
- Mac and iPhone simulator targets build, and the approved screens pass visual and accessibility review.
