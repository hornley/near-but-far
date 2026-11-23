# Status-First UI/UX Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `subagent-driven-development` or an equivalent task-by-task execution workflow to implement this plan.

**Goal:** Make the phone show a clear presence estimate, Mac monitoring readiness, and Mac lock observation as separate facts.

**Architecture:** Bind SwiftUI views to `PhoneModel` and `MacCoordinator`; keep CoreBluetooth transport details out of view code. Use the approved status-first direction, with disabled lock actions explaining the current capability limits.

**Tech Stack:** SwiftUI, CoreBluetooth-backed view models, VoiceOver, Xcode. Keep the approved macOS 14 and iOS 17 deployment minimums.

---

**Sequence:** Issue #1 sampling and the Issue #2 Snow C ABI gate are complete, and the approved status-first presentation is implemented. The Mac and iPhone use one-use QR enrollment and authenticated pinned sessions. Keep Lock now and Unlock disabled because the lock request and confirmation capability is unresolved. Physical pairing, background behavior, and range validation remain pending. The approved design is [Near But Far app design](../specs/2026-11-23-near-but-far-app-design.md).

## Files

- Modify `Sources/iOS/NearButFarPhoneApp.swift` to make the primary screen status-first and bind it to `PhoneModel`.
- Modify `Sources/Mac/NearButFarMacApp.swift` to show the monitoring preference, readiness, and pairing actions from `MacCoordinator`.
- Modify `Sources/iOS/PhoneModel.swift` and `Sources/Mac/MacCoordinator.swift` only when a view needs a missing presentation state; do not duplicate transport or policy.
- Update `README.md`, `spec.md`, and `docs/issues/001-one-second-ble-rssi-sampling.md` to distinguish implemented behavior from the prototype and keep pending physical checks visible.

## Tasks

### Task 1: Define independent presentation values

**Files:** `Sources/iOS/PhoneModel.swift`, `Sources/Mac/MacCoordinator.swift`

- [x] Keep the phone’s local presence estimate separate from authenticated Mac monitoring readiness and current Mac lock observation.
- [x] Keep lock action availability as a capability value. Under current findings, `canLockNow` and `canUnlock` remain false.
- [x] Ensure the Mac effective status can distinguish Off, Waiting for authenticated iPhone, Nearby, Countdown, Bluetooth unavailable, and Lock unavailable without describing the Mac as protected when it is not.

### Task 2: Refactor the iPhone status-first card

**Files:** `Sources/iOS/NearButFarPhoneApp.swift`

- [x] Make the primary card show **Nearby**, **Weak signal**, **Signal lost**, or **Unavailable** from the phone-side estimate. Keep the countdown for weak/lost states and preserve its original start time after a disconnect.
- [x] Show the latest RSSI and `-70 dBm` threshold as signal strength when available. Never show a distance estimate.
- [x] Show Mac monitoring readiness and Mac lock observation as distinct labels below the local presence state. Until verified, the lock observation reads **Mac lock state unavailable**.
- [x] At countdown expiry, show **Lock unavailable**; do not claim **Would lock**, **Locked**, or **Unlocked** as Mac state.
- [x] Keep the activity log below the main status card. Do not add a graph, extra navigation, or a cloud status.

### Task 3: Explain disabled actions and pairing recovery

**Files:** `Sources/iOS/NearButFarPhoneApp.swift`, `Sources/iOS/PairingScannerView.swift`

- [x] Show **Lock now** disabled with the reason that the Mac cannot confirm a lock result.
- [x] Show **Unlock** disabled with the instruction to authenticate on the Mac.
- [x] Show clear pairing states and next steps for unpaired, scanning, waiting for approval, paired, expired, QR mismatch, untrusted Mac, Bluetooth unavailable, and camera denied. The phone preserves its saved Mac identity until authenticated approval; it does not infer revocation from a disconnect.
- [x] Give disabled controls accessibility labels and hints with the reason. Announce status changes without relying on color alone.

### Task 4: Update the Mac menu-bar controls

**Files:** `Sources/Mac/NearButFarMacApp.swift`, `Sources/Mac/PairingView.swift`

- [x] Bind the persistent monitoring toggle and readiness label to `MacCoordinator`.
- [x] Make Off, Waiting for authenticated iPhone, Bluetooth unavailable, Nearby, Countdown, and Lock unavailable readable in the menu.
- [x] Add explicit Pair phone and Forget phone entry points. Pairing requires the unlocked Mac, a two-minute QR window, and local approval.
- [x] Keep the menu wording honest: an enabled preference with an unavailable lock capability is not active protection.

### Task 5: Apply the deslop pass and update product docs

**Files:** Changed app files, `README.md`, `spec.md`, `docs/issues/001-one-second-ble-rssi-sampling.md`

- [x] Compare the complete change with `main`. Remove unnecessary comments, duplicate guards, pass-through wrappers, and unused view/state code without changing approved behavior.
- [x] Update the README and product spec to describe QR pairing, one-second active sampling, fixed timeout semantics, disabled lock controls, the current lock capability gate, and outstanding physical checks.
- [x] Keep issue #2 open while verified Lock now remains unsupported. Do not mark any pending physical check complete without recorded evidence.

### Task 6: Build and review visible states

**Files:** No additional source files.

- [x] Build the Mac target with `xcodebuild build -project NearButFar.xcodeproj -scheme NearButFarMac -destination 'platform=macOS'`.
- [x] Build the phone simulator target with `xcodebuild build -project NearButFar.xcodeproj -scheme NearButFarPhone -destination 'platform=iOS Simulator,name=iPhone 15 Pro Max' CODE_SIGNING_ALLOWED=NO`.
- [x] Review the simulator's **Unavailable** state, separate status facts, and disabled lock actions. A signed simulator build reports **Not paired**; the unsigned build's secure-storage error is simulator-only.
- [ ] Review Nearby, Weak signal, Signal lost, Unavailable, pairing failures, and countdown expiry on the phone; review Off, waiting, Bluetooth unavailable, and Lock unavailable on the Mac.
- [ ] Review VoiceOver labels, larger text, and status meaning without color cues. Confirm both lock actions remain disabled and no visible state claims an unverified result.

## Completion order

Implementation and build checks are complete. Visual review covered the unavailable status, disabled controls, and corrected title; the remaining phone and Mac states plus VoiceOver/larger-text review still need checking. Physical pairing, locked-phone background behavior, varied-range trials, Bluetooth-unavailable behavior, and the exact countdown boundary also remain open. The user reports an overnight locked-phone run, but duration and telemetry were not recorded, so it is not a measured pass. Automatic locking remains gated on reliable presence validation and a supported lock request with trustworthy confirmation.
