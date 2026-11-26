# Mac Battery Indicator Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `workflow-implementation` with task-by-task subagent execution. Keep file ownership exclusive as listed below.

**Goal:** Show the Mac's current battery percentage in a small battery icon on the NearButFar Mac app screen and iPhone home screen.

**Architecture:** A Mac-side monitor reads the local power-source level and updates the app screen. `MacCoordinator` sends the initial and refreshed reading over the existing authenticated `PeerSession`; `PhoneModel` accepts it only for the active session and clears it when it becomes stale or disconnected. Both surfaces use one shared SwiftUI battery icon.

**Tech Stack:** Swift, SwiftUI, IOKit power-source APIs, CoreBluetooth, the existing Noise-backed `PeerSession`, and Xcode project targets.

---

**Issue:** [#6 — Show Mac battery percentage on the lock screen and in the iPhone app](https://github.com/hornley/near-but-far/issues/6).

**Approved specification:** [Mac Battery Indicator Design](../specs/2026-11-26-mac-battery-indicator-design.md), approved by the user on 2026-11-26.

**Plan status:** Implementation complete. Mac and iPhone builds passed on 2026-11-26. Tests were not run. Live visual and VoiceOver verification remain pending.

**Change branch:** `t3/show-battery-percentage-lock-screen-app`, based on `origin/main`.

**Dependency order:** Complete Task 1 first. Tasks 2 and 3 can then run in parallel. Task 4 integrates their results and performs the final review.

## File ownership

| Task | Files owned |
| --- | --- |
| 1. Shared message and icon | `Sources/Shared/PeerSession.swift`; new `Sources/Shared/BatteryPercentageIcon.swift`; `NearButFar.xcodeproj/project.pbxproj` for the shared icon in both targets |
| 2. Mac battery source and overlay | new `Sources/Mac/MacBatteryMonitor.swift`; `Sources/Mac/MacCoordinator.swift`; `Sources/Mac/AppScreenOverlayController.swift`; `Sources/Mac/AppScreenView.swift`; `NearButFar.xcodeproj/project.pbxproj` for the Mac monitor in the Mac target |
| 3. iPhone model and UI | `Sources/iOS/PhoneModel.swift`; `Sources/iOS/NearButFarPhoneApp.swift` |
| 4. Integration and final review | Read-only review across the completed files; route required fixes back to the task that owns each file |

## Tasks

### Task 1: Define the authenticated battery message and shared icon

**Owner:** Coding worker — GPT-6 Luna, Medium reasoning.

**Depends on:** None. Tasks 2 and 3 depend on this task.

**Files:** `Sources/Shared/PeerSession.swift`; create `Sources/Shared/BatteryPercentageIcon.swift`; `NearButFar.xcodeproj/project.pbxproj`.

**Acceptance criteria:** Only the Mac can send battery-level messages, and only the phone can receive them. A valid message carries an integer from 0 through 100; `0xFF` represents unavailable. Values from 101 through 254 and invalid sender roles are rejected. The shared icon draws the outlined battery with the value inside, or an em dash when unavailable, and exposes the value through VoiceOver.

- [x] Add `PeerMessage.macBatteryLevel(UInt8?)` to `Sources/Shared/PeerSession.swift`.
- [x] Assign message tag `10`; encode `0...100` as one byte and encode unavailable as `0xFF`.
- [x] Decode tag `10` only for a phone receiver; reject `101...254`, reject phone-sent battery messages, and allow the message only as authenticated operational traffic.
- [x] Create `BatteryPercentageIcon` with a percentage, a configurable visual size, a neutral outline, and an em-dash state. Give it a VoiceOver label for a Mac battery value or an unavailable reading.
- [x] Register the shared icon source in both the Mac and iPhone target build phases in `NearButFar.xcodeproj/project.pbxproj`.
- [x] Commit as `feat: add authenticated Mac battery message and icon`.

### Task 2: Read and display Mac battery level; send it to the phone

**Owner:** Coding worker — GPT-6 Luna, Medium reasoning.

**Depends on:** Task 1. Can run in parallel with Task 3 after Task 1 completes.

**Files:** Create `Sources/Mac/MacBatteryMonitor.swift`; modify `Sources/Mac/MacCoordinator.swift`, `Sources/Mac/AppScreenOverlayController.swift`, and `Sources/Mac/AppScreenView.swift`; register the monitor in `NearButFar.xcodeproj/project.pbxproj` for the Mac target.

**Acceptance criteria:** The local Mac app screen shows the level in the small icon, centered near the top and below the display's safe inset. It has no visible “Mac” label. The coordinator sends the current value when an authenticated session becomes ready, on a changed value, and at least once per minute while connected. It never sends battery data before authentication.

- [x] Create a main-actor `MacBatteryMonitor` that reads the current and maximum capacity from macOS power-source information, converts them to an integer percentage, and reports unavailable when no valid source exists.
- [x] Refresh the monitor immediately, then at least once per minute; publish a changed value for the local view and provide a fresh reading to the coordinator on every refresh.
- [x] Give `MacCoordinator` ownership of the monitor. Send its latest value on `.ready`, then send each refresh only when `pairingSession`, `pairingLink`, and `securePeerID` identify the authenticated active session.
- [x] Pass the monitor and each `NSScreen.safeAreaInsets.top` value through `AppScreenOverlayController` to `AppScreenView`; update the view when screen parameters change.
- [x] Place the shared icon at the horizontal center near the top, with a small gap below the notch safe area. Keep the existing clock, date, and authentication card positions and visual hierarchy.
- [x] Register `MacBatteryMonitor.swift` in the Mac target in `NearButFar.xcodeproj/project.pbxproj` after Task 1's project-file edit is complete.
- [x] Commit as `feat: show Mac battery on app screen`.

### Task 3: Receive the reading and show it on the iPhone home screen

**Owner:** Coding worker — GPT-6 Luna, Medium reasoning.

**Depends on:** Task 1. Can run in parallel with Task 2 after Task 1 completes. `PhoneCentral` already forwards verified messages to `PhoneModel` and resets it on disconnect, so it does not need a source change for this feature.

**Files:** Modify `Sources/iOS/PhoneModel.swift` and `Sources/iOS/NearButFarPhoneApp.swift`.

**Acceptance criteria:** The iPhone shows the Mac's battery icon, smaller than the Mac version and centered directly below RSSI. No visible “Mac” label or extra card is added. The phone never displays an old value as current.

- [x] Add the optional battery percentage and last authenticated update time to `PhoneModel`.
- [x] Handle `.macBatteryLevel` only while `sessionReady`; update the value and timestamp on each authenticated refresh.
- [x] Clear the value on every disconnect. After two minutes without an authenticated refresh, clear it to unavailable so the icon shows an em dash. A fresh message restores the number.
- [x] Add the shared icon below `homeSignalReading` in `presenceSummary`, using a smaller size than the Mac view and keeping it centered.
- [x] Update the parent accessibility summary so VoiceOver announces the Mac battery percentage or unavailable state along with the existing presence and signal information.
- [x] Commit as `feat: show Mac battery on iPhone home screen`.

### Task 4: Integrate and complete final review

**Owner:** Coordinator for integration; independent reviewer — GPT-6.1 Sol, Low reasoning.

**Depends on:** Tasks 2 and 3.

**Files:** Read-only review across all task files; no source ownership. Route any fixes to the worker responsible for the affected files.

**Acceptance criteria:** The full change matches the approved spec, both targets include the shared view, and battery updates remain authenticated. The change does not alter presence policy or macOS secure-lock behavior.

- [x] Review the integrated diff against every acceptance criterion in the approved specification.
- [x] Confirm `NearButFar.xcodeproj/project.pbxproj` registers `BatteryPercentageIcon.swift` in both targets and `MacBatteryMonitor.swift` only in the Mac target.
- [x] Build the Mac target with `xcodebuild build -project NearButFar.xcodeproj -scheme NearButFarMac -destination 'platform=macOS'`.
- [x] Build the iPhone target with `xcodebuild build -project NearButFar.xcodeproj -scheme NearButFarPhone -destination 'generic/platform=iOS Simulator'`.
- [x] Review the Mac app screen near the top-center safe area and the smaller iPhone icon below RSSI against the approved layout, including source-level review of the unavailable state and VoiceOver labels.
- [ ] Verify live rendering and VoiceOver behavior on Mac and iPhone.
- [x] Have independent reviewers check protocol sender/receiver restrictions, stale-value clearing, notch spacing, and preservation of the existing lock/authentication flow.

## Spec coverage

- Mac battery source and authenticated updates: Task 2.
- Mac top-center placement and notch clearance: Task 2.
- Smaller iPhone icon beneath RSSI: Task 3.
- Unavailable, disconnected, and stale states: Tasks 1–3.
- VoiceOver labels and preservation of app-screen behavior: Tasks 1–4.
- End-to-end integration and final review: Task 4.
