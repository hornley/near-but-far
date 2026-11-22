# Issue #1 RSSI Sampling Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `subagent-driven-development` or an equivalent task-by-task execution workflow to implement this plan.

**Goal:** Sample the connected iPhone’s RSSI about once per second while preserving the existing loss and retry timers.

**Architecture:** Add a shared challenge scheduler with one outstanding logical challenge. `MacCoordinator` owns that scheduler and the Mac presence tracker; `MacPeripheral` becomes its transport adapter. `PhoneModel` owns the local estimate; `PhoneCentral` becomes its transport adapter. The Mac scheduler starts loss after five seconds without a queued challenge response and retries the same challenge every five seconds.

**Tech Stack:** Swift, CoreBluetooth, SwiftUI, Xcode targets for macOS 14 and iOS 17.

---

**Sequence:** First of three implementation phases. The approved design is [Near But Far app design](../specs/2026-11-23-near-but-far-app-design.md). Pairing and the broad status-first redesign follow in their own plans. Until issue #2 replaces the public BLE protocol, this remains a prototype: do not claim active protection and do not enable lock actions.

## Files

- Create `Sources/Shared/ChallengeSchedule.swift` for the Mac’s sampling and retry schedule.
- Modify `Sources/Shared/PresenceTracker.swift` to use monotonic time and preserve the approved `-70 dBm`/60-second behavior.
- Create `Sources/Mac/MacCoordinator.swift` to own scheduling and Mac presence policy.
- Create `Sources/iOS/PhoneModel.swift` to own the local presence estimate.
- Modify `Sources/Mac/MacPeripheral.swift` and `Sources/iOS/PhoneCentral.swift` to report transport events and send coordinator/model requests without owning presence policy.
- Modify `Sources/Mac/NearButFarMacApp.swift` and `Sources/iOS/NearButFarPhoneApp.swift` only to bind the existing presentation to the new models; the broader UI pass follows later.
- Modify `NearButFar.xcodeproj/project.pbxproj` to add the shared and platform-specific files to their targets.
- Update `docs/issues/001-one-second-ble-rssi-sampling.md` with implementation status and active/background cadence limits.

## Tasks

### Task 1: Add the shared challenge schedule

**Files:** `Sources/Shared/ChallengeSchedule.swift`

- [x] Define the scheduler actions and fixed intervals:

```swift
enum ChallengeAction: Equatable {
    case sendNew(sequence: UInt32)
    case retry(sequence: UInt32)
}

struct ChallengeSchedule {
    static let sampleInterval: Duration = .seconds(1)
    static let responseTimeout: Duration = .seconds(5)
    static let retryInterval: Duration = .seconds(5)

    mutating func nextAction(at now: ContinuousClock.Instant) -> ChallengeAction?
    mutating func didQueue(_ action: ChallengeAction, at now: ContinuousClock.Instant)
    mutating func acknowledge(_ sequence: UInt32)
    mutating func reset()
}
```

- [x] Implement one outstanding logical sequence. Emit a new sequence only after the prior one is acknowledged and one second has elapsed. Emit a retry with the same sequence only after five seconds since its last successful queue.
- [x] Treat a failed `updateValue` queue attempt as pending. Do not start its response deadline or allocate a new sequence; resume that pending action from `peripheralManagerIsReady(toUpdateSubscribers:)`.

### Task 2: Move presence deadlines to monotonic time

**Files:** `Sources/Shared/PresenceTracker.swift`, `Sources/Mac/MacPeripheral.swift`, `Sources/iOS/PhoneCentral.swift`

- [x] Store loss-start instants from `ContinuousClock`; keep `-70 dBm` and 60 seconds unchanged.
- [x] Keep these rules in one tracker: a sample at or below `-70` starts the countdown once, a fresh stronger sample clears it, and missing RSSI or reconnecting alone does not.
- [x] When a fresh recovery sample and expiry have the same monotonic timestamp, apply the sample first.
- [x] Keep wall-clock `Date` only for CSV events and user-visible timestamps.

### Task 3: Integrate the Mac transport with `MacCoordinator`

**Files:** `Sources/Mac/MacCoordinator.swift`, `Sources/Mac/MacPeripheral.swift`, `Sources/Mac/NearButFarMacApp.swift`, `NearButFar.xcodeproj/project.pbxproj`

- [x] Make `MacCoordinator` the only owner of `ChallengeSchedule` and the Mac `PresenceTracker`. It receives typed transport events and exposes the existing status/countdown to the menu-bar view.
- [x] Keep `MacPeripheral` limited to CoreBluetooth state, subscriptions, writes, and queue readiness. It does not start countdowns or decide whether a sample means nearby.
- [x] Replace the five-second challenge timer with a one-second schedule tick in the coordinator. Keep a separate one-second display refresh only if required by the existing menu.
- [x] On a new queued action, ask the adapter to publish it and call `didQueue` only after CoreBluetooth accepts it. On a full queue, retain the action until CoreBluetooth is ready.
- [x] On the first five-second timeout, mark presence lost once. Continue retrying the same logical sequence every five seconds; do not change the one-second sample cadence into a one-second loss timeout.
- [x] On a valid acknowledgement, acknowledge the exact outstanding sequence, apply its fresh RSSI, and allow the next new challenge after the one-second interval.
- [x] Bind the existing Mac status to `MacCoordinator`; add the new Mac sources to the explicit Xcode target membership.

### Task 4: Integrate the iPhone transport with `PhoneModel`

**Files:** `Sources/iOS/PhoneModel.swift`, `Sources/iOS/PhoneCentral.swift`, `Sources/iOS/NearButFarPhoneApp.swift`, `NearButFar.xcodeproj/project.pbxproj`

- [x] Make `PhoneModel` the owner of the local `PresenceTracker`, last-challenge time, loss reason, and displayed presence state. `PhoneCentral` reports BLE and RSSI callback events only.
- [x] Keep at most one RSSI read in flight. A retry notification for the same sequence must not overwrite the pending sequence or start another read.
- [x] Send only the RSSI value returned for that challenge; never reuse a cached value as a fresh sample. Encode an unavailable or invalid sample as nil.
- [x] Preserve the ten-second no-challenge estimate. A reconnect or nil-RSSI acknowledgement alone does not cancel an active countdown.
- [x] Ignore stale callbacks from a previous peripheral connection generation.
- [x] Rebind the existing status view to `PhoneModel` without changing its selected layout; the full status-first UI/UX pass remains phase three.

### Task 5: Update issue documentation and build the targets

**Files:** `docs/issues/001-one-second-ble-rssi-sampling.md`

- [x] Record the active one-second target and unchanged five-second and ten-second timeouts.
- [x] Document that iOS may throttle background sampling and keep the handoff’s physical checks marked pending until performed.
- [x] Build the Mac target with `xcodebuild build -project NearButFar.xcodeproj -scheme NearButFarMac -destination 'platform=macOS'`.
- [x] Build the phone simulator target with `xcodebuild build -project NearButFar.xcodeproj -scheme NearButFarPhone -destination 'platform=iOS Simulator,name=iPhone 15 Pro Max' CODE_SIGNING_ALLOWED=NO`.

## Manual validation

- With an active connected iPhone, observe roughly one-second new challenges and RSSI readings.
- Confirm a queued unanswered sequence starts Mac loss after five seconds and retries as the same sequence every five seconds.
- Confirm the iPhone’s no-challenge estimate still starts at ten seconds, a stronger fresh sample clears the countdown, and a missing sample does not.
- Record battery/CPU impact and background throttling during physical-device validation. Do not mark the 30-minute locked-phone run or varied-range checks passed until performed.
