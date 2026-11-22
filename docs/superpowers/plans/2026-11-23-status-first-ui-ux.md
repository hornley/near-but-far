# Status-First UI/UX Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `subagent-driven-development` or an equivalent task-by-task execution workflow to implement this plan.

**Goal:** Make the phone show a clear presence estimate, Mac monitoring readiness, and Mac lock observation as separate facts.

**Architecture:** Bind SwiftUI views to `PhoneModel` and `MacCoordinator`; keep CoreBluetooth transport details out of view code. Use the approved status-first direction, with disabled lock actions explaining the current capability limits.

**Tech Stack:** SwiftUI, CoreBluetooth-backed view models, macOS 14, iOS 17, VoiceOver, Xcode.

---

**Sequence:** Final phase, after [issue #1 sampling](2026-11-23-issue-1-rssi-sampling.md) and [issue #2 pairing/monitoring](2026-11-23-issue-2-pairing-monitoring.md). The approved design is [Near But Far app design](../specs/2026-11-23-near-but-far-app-design.md).

## Files

- Modify `Sources/iOS/NearButFarPhoneApp.swift` to make the primary screen status-first and bind it to `PhoneModel`.
- Modify `Sources/Mac/NearButFarMacApp.swift` to show the monitoring preference, readiness, and pairing actions from `MacCoordinator`.
- Modify `Sources/iOS/PhoneModel.swift` and `Sources/Mac/MacCoordinator.swift` only when a view needs a missing presentation state; do not duplicate transport or policy.
- Update `README.md`, `spec.md`, and `docs/issues/001-one-second-ble-rssi-sampling.md` to distinguish implemented behavior from the prototype and keep pending physical checks visible.

## Tasks

### Task 1: Define independent presentation values

**Files:** `Sources/iOS/PhoneModel.swift`, `Sources/Mac/MacCoordinator.swift`

- [ ] Keep the phone’s local presence estimate separate from authenticated Mac monitoring readiness and current Mac lock observation.
- [ ] Keep lock action availability as a capability value. Under current findings, `canLockNow` and `canUnlock` remain false.
- [ ] Ensure the Mac effective status can distinguish Off, Waiting for authenticated iPhone, Nearby, Countdown, Bluetooth unavailable, and Lock unavailable without describing the Mac as protected when it is not.

### Task 2: Refactor the iPhone status-first card

**Files:** `Sources/iOS/NearButFarPhoneApp.swift`

- [ ] Make the primary card show **Nearby**, **Weak signal**, **Signal lost**, or **Unavailable** from the phone-side estimate. Keep the countdown for weak/lost states and preserve its original start time after a disconnect.
- [ ] Show the latest RSSI and `-70 dBm` threshold as signal strength when available. Never show a distance estimate.
- [ ] Show Mac monitoring readiness and Mac lock observation as distinct labels below the local presence state. Until verified, the lock observation reads **Mac lock state unavailable**.
- [ ] At countdown expiry, show **Lock unavailable**; do not claim **Would lock**, **Locked**, or **Unlocked** as Mac state.
- [ ] Keep the activity log below the main status card. Do not add a graph, extra navigation, or a cloud status.

### Task 3: Explain disabled actions and pairing recovery

**Files:** `Sources/iOS/NearButFarPhoneApp.swift`, `Sources/iOS/PairingScannerView.swift`

- [ ] Show **Lock now** disabled with the reason that the Mac cannot confirm a lock result.
- [ ] Show **Unlock** disabled with the instruction to authenticate on the Mac.
- [ ] Show clear pairing states and next steps for unpaired, scanning, waiting for approval, paired, expired, revoked, Bluetooth unavailable, and camera denied.
- [ ] Give disabled controls accessibility labels and hints with the reason. Announce status changes without relying on color alone.

### Task 4: Update the Mac menu-bar controls

**Files:** `Sources/Mac/NearButFarMacApp.swift`, `Sources/Mac/PairingView.swift`

- [ ] Bind the persistent monitoring toggle and readiness label to `MacCoordinator`.
- [ ] Make Off, Waiting for authenticated iPhone, Bluetooth unavailable, Nearby, Countdown, and Lock unavailable readable in the menu.
- [ ] Add explicit Pair phone and Forget phone entry points. Pairing requires the unlocked Mac, a two-minute QR window, and local approval.
- [ ] Keep the menu wording honest: an enabled preference with an unavailable lock capability is not active protection.

### Task 5: Apply the deslop pass and update product docs

**Files:** Changed app files, `README.md`, `spec.md`, `docs/issues/001-one-second-ble-rssi-sampling.md`

- [ ] Compare the complete change with `main`. Remove unnecessary comments, duplicate guards, pass-through wrappers, and unused view/state code without changing approved behavior.
- [ ] Update the README and product spec to describe QR pairing, one-second active sampling, fixed timeout semantics, disabled lock controls, the current lock capability gate, and outstanding physical checks.
- [ ] Keep issue #2 open while verified Lock now remains unsupported. Do not mark any pending physical check complete without recorded evidence.

### Task 6: Build and review visible states

**Files:** No additional source files.

- [ ] Build the Mac target with `xcodebuild build -project NearButFar.xcodeproj -scheme NearButFarMac -destination 'platform=macOS'`.
- [ ] Build the phone simulator target with `xcodebuild build -project NearButFar.xcodeproj -scheme NearButFarPhone -destination 'platform=iOS Simulator,name=iPhone 15 Pro Max' CODE_SIGNING_ALLOWED=NO`.
- [ ] Review Nearby, Weak signal, Signal lost, Unavailable, pairing failures, and countdown expiry on the phone; review Off, waiting, Bluetooth unavailable, and Lock unavailable on the Mac.
- [ ] Review VoiceOver labels, larger text, and status meaning without color cues. Confirm both lock actions remain disabled and no visible state claims an unverified result.

## Completion order

Complete the three implementation plans in order: issue #1 sampling, issue #2 secure pairing and monitoring, then this UI/UX pass. The user’s 30-minute background run and varied-range physical checks remain pending throughout until performed. Automatic locking remains gated on both reliable presence validation and a supported lock request with trustworthy confirmation.
