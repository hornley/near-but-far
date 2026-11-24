# iPhone Presence Status Implementation Plan

> **Superseded implementation note (2026-11-24):** Historical prototype instructions below that show Mac lock state as unavailable or use “Would lock” predate the app-screen implementation. The current app has a separate app-screen state and does not observe or change macOS secure-lock state.


> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show an honest phone-side estimate of the Mac's nearby, weak-signal, and “would lock” test states using an experimental `-70 dBm` threshold and the existing 60-second grace period.

**Architecture:** Extend the shared `PresenceTracker` with a single-sample RSSI threshold. The Mac applies that threshold to phone acknowledgements and keeps its own countdown/log. The iPhone uses the same tracker locally, starts an estimate on weak RSSI or lost check-ins, and displays the timer even after Bluetooth drops. The phone always says the actual Mac lock state is unavailable; neither app locks the Mac.

**Tech Stack:** SwiftUI, CoreBluetooth, Foundation, XCTest, Xcode 26.6; no new dependencies.

---

**Approved design:** [2026-11-23-phone-presence-status-design.md](../specs/2026-11-23-phone-presence-status-design.md), approved by the user on 2026-11-23.

**Workflow constraints:** Continue on local branch `feature/ble-prototype`. The private GitHub repository tracks follow-up issues #1 and #2; the current prototype work remains uncommitted, with no pull request or deployment target. Preserve the existing work; this handoff does not stage or commit it.

## Files

- Modify `Sources/Shared/PresenceTracker.swift` to add the shared `-70 dBm` threshold and RSSI observation behavior.
- Modify `NearButFar.xcodeproj/project.pbxproj` to include the shared tracker in the phone target.
- Modify `Sources/Mac/MacPeripheral.swift` to apply the threshold to acknowledgements and log weak-signal and recovery transitions. Keep the existing missed-challenge fallback and never lock the Mac.
- Modify `Sources/Mac/NearButFarMacApp.swift` only if needed to show the threshold beside the existing RSSI/countdown.
- Modify `Sources/iOS/PhoneCentral.swift` to maintain the local estimate, start it after weak RSSI or a disconnect/10 seconds without a challenge, refresh it once per second, and record state changes.
- Modify `Sources/iOS/NearButFarPhoneApp.swift` to show the status-first card from the approved mockup.
- Modify `Tests/NearButFarTests.swift` with deterministic threshold and recovery cases.
- Update `README.md` and `spec.md` with the test behavior, limitations, and remaining physical checks.
- Update the approved design spec to distinguish **Signal lost** from **Weak signal** in the phone status card.

## Task 1: Add tested RSSI behavior to the shared tracker

**Files:** `Sources/Shared/PresenceTracker.swift`, `Tests/NearButFarTests.swift`.

- [x] **Step 1: Add tracker tests.** Add these methods to `NearButFarTests`:

```swift
func testWeakRSSIAtThresholdStartsSixtySecondCountdown() {
    var tracker = PresenceTracker()
    let now = Date(timeIntervalSince1970: 100)

    tracker.observeRSSI(-70, at: now)

    XCTAssertTrue(tracker.isArmed)
    XCTAssertEqual(tracker.secondsRemaining(at: now), 60)
}

func testStrongerRSSICancelsWeakSignalCountdown() {
    var tracker = PresenceTracker()
    let now = Date(timeIntervalSince1970: 100)
    tracker.observeRSSI(-72, at: now)

    tracker.observeRSSI(-69, at: now.addingTimeInterval(10))

    XCTAssertNil(tracker.secondsRemaining(at: now.addingTimeInterval(10)))
}

func testRepeatedWeakRSSIDoesNotRestartCountdown() {
    var tracker = PresenceTracker()
    let now = Date(timeIntervalSince1970: 100)
    tracker.observeRSSI(-70, at: now)

    tracker.observeRSSI(-75, at: now.addingTimeInterval(10))

    XCTAssertEqual(tracker.secondsRemaining(at: now.addingTimeInterval(10)), 50)
}

func testMissingRSSIDoesNotClearWeakSignalCountdown() {
    var tracker = PresenceTracker()
    let now = Date(timeIntervalSince1970: 100)
    tracker.observeRSSI(-70, at: now)

    tracker.observeRSSI(nil, at: now.addingTimeInterval(10))

    XCTAssertEqual(tracker.secondsRemaining(at: now.addingTimeInterval(10)), 50)
}
```

- [x] **Step 2: Run the focused test suite after implementation and confirm the new methods compile.**

Run: `xcodebuild test -project NearButFar.xcodeproj -scheme NearButFarTests -destination 'platform=macOS'`

Expected: the new tests compile against `PresenceTracker.observeRSSI(_:at:)`.

- [x] **Step 3: Implement the smallest shared RSSI rule.** In `PresenceTracker.swift`, add `static let weakSignalThreshold: Int16 = -70` and this method:

```swift
mutating func observeRSSI(_ rssi: Int16?, at time: Date) {
    isArmed = true
    guard let rssi else { return }
    if rssi <= Self.weakSignalThreshold {
        missedChallenge(at: time)
    } else {
        acknowledge(at: time)
    }
}
```

This starts the existing grace timer on a weak sample, leaves its original start time unchanged for repeated weak samples, and clears it on a stronger sample.

- [x] **Step 4: Run all tracker tests.**

Run: `xcodebuild test -project NearButFar.xcodeproj -scheme NearButFarTests -destination 'platform=macOS'`

Expected: all existing and new tests pass, including the exact 60-second boundary, stronger-signal recovery, and missing-RSSI preservation cases.

## Task 2: Apply the threshold in the Mac app

**Files:** `Sources/Mac/MacPeripheral.swift`, optionally `Sources/Mac/NearButFarMacApp.swift`.

- [x] **Step 1: Use received RSSI to update the Mac timer.** In the validated acknowledgement branch, replace the unconditional `tracker.acknowledge(at: Date())` with:

```swift
let now = Date()
let wasCountingDown = tracker.lossStartedAt != nil
tracker.observeRSSI(acknowledgement.rssi, at: now)
if !wasCountingDown && tracker.lossStartedAt != nil, let rssi = acknowledgement.rssi {
    logger?.log("weak_signal", sequence: acknowledgement.sequence, rssi: rssi,
                details: "threshold_dbm=\(PresenceTracker.weakSignalThreshold)")
} else if wasCountingDown && tracker.lossStartedAt == nil, let rssi = acknowledgement.rssi {
    logger?.log("signal_recovered", sequence: acknowledgement.sequence, rssi: rssi)
}
countdown = tracker.secondsRemaining(at: now)
```

A valid acknowledgement without RSSI arms the tracker but does not clear an active countdown; only a stronger RSSI sample confirms recovery.

Keep the existing acknowledgement CSV row, sequence validation, challenge retry, missed-response fallback, Bluetooth-unavailable handling, and one-shot `would_lock` log. Do not call any macOS lock API.

- [x] **Step 2: Keep the menu bar wording accurate.** If the existing countdown text still says `Would lock in: Ns`, retain it and add a small `Test threshold: -70 dBm` line beside the last RSSI. Do not add a real `Locked` state.

- [x] **Step 3: Build the Mac target.**

Run: `xcodebuild build -project NearButFar.xcodeproj -scheme NearButFarMac -destination 'platform=macOS'`

Expected: `BUILD SUCCEEDED`.

## Task 3: Add the iPhone-side estimate

**Files:** `Sources/iOS/PhoneCentral.swift`.

- [x] **Step 1: Add a display state and local timer fields.** Add this type above `PhoneCentral`:

```swift
enum PhonePresenceState: Equatable {
    case waiting
    case nearby
    case weakSignalCountdown(Int)
    case connectionLostCountdown(Int)
    case wouldLock
    case unavailable
}

private enum PresenceLossReason: Equatable {
    case weakSignal
    case connectionLost
}
```

Add these members to `PhoneCentral`:

```swift
@Published private(set) var presenceState: PhonePresenceState = .waiting

private var presenceTracker = PresenceTracker()
private var lastChallengeAt: Date?
private var presenceTimer: Timer?
private var presenceLossReason: PresenceLossReason?
```

After creating `CBCentralManager` in `init`, start a one-second main-run-loop timer that calls `refreshPresence()` through a `Task { @MainActor in ... }` closure and captures `self` weakly.

- [x] **Step 2: Arm and update the local state from Core Bluetooth callbacks.** On successful challenge subscription, set `lastChallengeAt = Date()`. Arm the tracker only if it has not been armed before; reconnecting alone must not clear an active loss countdown. On each accepted challenge notification, set `lastChallengeAt = Date()` before reading RSSI. In `didReadRSSI`, call `observeRSSI(_:at:)`; a missing RSSI must leave the current presence estimate unchanged. A weak RSSI countdown displays **Weak signal**; a disconnect or missed-challenge estimate displays **Signal lost**. Preserve the existing acknowledgement write and local RSSI log. Reset the remembered sequence on a new connection because the Mac restarts its sequence when its app restarts.

On disconnect, start the local estimate with `presenceTracker.missedChallenge(at: Date())` only if the tracker is armed. When Bluetooth becomes unavailable, clear `lastChallengeAt`, reset `presenceTracker`, set `.unavailable`, and do not report a phone-side `would_lock` event.

- [x] **Step 3: Detect missed challenge notifications and update the state.** Add this method to `PhoneCentral`:

```swift
private func refreshPresence(at now: Date = Date()) {
    guard central.state == .poweredOn else {
        presenceState = .unavailable
        return
    }

    if let lastChallengeAt,
       presenceTracker.isArmed,
       presenceTracker.lossStartedAt == nil,
       now.timeIntervalSince(lastChallengeAt) >= 10 {
        startEstimatedLoss(at: lastChallengeAt.addingTimeInterval(10))
    }

    if presenceTracker.takeWouldLock(at: now) {
        record("phone_estimated_would_lock")
    }

    guard presenceTracker.isArmed else {
        presenceLossReason = nil
        presenceState = .waiting
        return
    }

    if let remaining = presenceTracker.secondsRemaining(at: now) {
        if remaining == 0 {
            presenceState = .wouldLock
        } else if presenceLossReason == .weakSignal {
            presenceState = .weakSignalCountdown(remaining)
        } else {
            presenceState = .connectionLostCountdown(remaining)
        }
    } else {
        presenceLossReason = nil
        presenceState = .nearby
    }
}
```

Define the loss-start helper used above:

```swift
private func startEstimatedLoss(at time: Date) {
    guard presenceTracker.isArmed else { return }
    let wasCountingDown = presenceTracker.lossStartedAt != nil
    presenceTracker.missedChallenge(at: time)
    if presenceTracker.lossStartedAt != nil {
        presenceLossReason = .connectionLost
    }
    if !wasCountingDown, presenceTracker.lossStartedAt != nil {
        record("estimated_presence_lost")
    }
}
```

Call it after RSSI updates, disconnects, challenge subscription, and from the timer. The ten-second fallback covers two expected five-second challenge intervals. The phone countdown is an estimate and can differ from the Mac timer; it is not a synchronized lock report.

- [x] **Step 4: Build the iPhone simulator target without signing.**

Run: `xcodebuild build -project NearButFar.xcodeproj -scheme NearButFarPhone -destination 'platform=iOS Simulator,name=iPhone 15 Pro Max' CODE_SIGNING_ALLOWED=NO`

Expected: `BUILD SUCCEEDED`.

## Task 4: Show the approved minimal status card

**Files:** `Sources/iOS/NearButFarPhoneApp.swift`, `Sources/iOS/PhoneCentral.swift`.

- [x] **Step 1: Replace the connection-only headline with the presence state.** In `PhoneContentView`, show these primary labels for `presenceState`: `Waiting for Mac`, `Nearby`, `Weak signal`, `Signal lost`, `Would lock`, and `Unavailable`. Keep `connectionState` as secondary text so scanning and reconnecting remain visible.

- [x] **Step 2: Show the countdown and safety text.** For weak-signal and connection-loss countdown states, show `seconds` as `MM:SS`, latest RSSI, and `Test threshold −70 dBm`, with copy that identifies the phone-side estimate. For `.wouldLock`, show **Would lock** and **Mac lock state unavailable · prototype only**. Keep that unavailable statement visible in every state. Keep the existing Scan again control and local log below the status card. Do not show meters, an actual `Locked` or `Unlocked` state, or a lock control.

- [x] **Step 3: Update the project docs.** Update `README.md` and `spec.md` to describe the `-70 dBm` experiment, phone-side countdown estimate, ten-second no-challenge fallback, actual lock state unavailable, and physical-device tests still pending. Preserve the existing warning that RSSI is not distance and the prototype never locks the Mac.

## Task 5: Validate on Mac and paired iPhone

**Files:** `Tests/NearButFarTests.swift`, build output, live device screens, and `~/Library/Application Support/NearButFar/ble-log.csv`.

- [x] **Step 1: Run the macOS unit suite and both target builds.** Run the test command from Task 1 and the Mac/iPhone build commands from Tasks 2 and 3. Expected: tests pass and both builds report `BUILD SUCCEEDED`.

- [x] **Step 2: Install and launch the signed iPhone app on the paired device.** Use the saved Personal Team and device `roasted ginger`. Confirm the Mac CSV resumes acknowledgements and reports RSSI after launch. The latest run recovered after the Mac reset its challenge counter to 1 and logged acknowledgements for sequences 53–54 at `-45` to `-42 dBm`.

- [ ] **Step 3: Visually confirm the physical phone status.** User reports RSSI readings around `-40` to `-55 dBm`, varying with distance and obstructions, and that BLE continued while the app was in the background. A screen check of **Nearby**, latest RSSI, `-70 dBm` threshold, and **Mac lock state unavailable** has not been recorded. The background test duration and whether the iPhone was locked were not recorded. The user wants the 30-minute locked-phone check carried into actual app testing; it does not block starting that work.

- [x] **Step 4: Test a weak sample and quick return.** User reports the `-70 dBm` countdown and return-to-**Nearby** behavior work. The Mac CSV independently records `weak_signal` at `-76 dBm` and `signal_recovered` at `-47 dBm`, 15 seconds later (challenge sequences 153 and 156). RSSI is not a fixed distance boundary.

- [x] **Step 5: Confirm the Mac-side expiry.** The CSV records three `would_lock` events with `elapsed_seconds=60` at `19:12:03Z`, `19:15:03Z`, and `19:19:43Z` on 2026-11-22. Each followed a weak RSSI sample at or below `-70 dBm` that persisted through the countdown; the whole-second timestamps are 61 seconds apart. The event is log-only; the prototype does not lock the Mac. The user also reports the phone-side 60-second status works.

- [ ] **Step 6: Resolve the exact-expiry recovery boundary.** The CSV shows a weak sample of `-70 dBm` at `19:20:17Z` followed by recovery to `-67 dBm` at `19:21:17Z`, with no `would_lock` row. Repeat with a controlled recovery near 60 seconds and use the phone and Mac logs to determine whether recovery or expiry wins at the boundary; CSV timestamps have only one-second precision.

- [ ] **Step 7: Test signal-loss fallback before a weak sample.** Walk out of range before receiving a weak RSSI sample and confirm the phone starts an estimate on disconnect or after ten seconds without a challenge.

- [x] **Step 8: Test iPhone Bluetooth recovery and record results.** User reports that turning iPhone Bluetooth off and back on works: the Mac shows **Waiting for iPhone**, then **iPhone subscribed** after reconnection. The RSSI observations, reported phone behavior, CSV evidence, and remaining checks are recorded in `README.md`.

- [ ] **Step 9: Check unavailable Bluetooth states.** Confirm the phone reports **Unavailable** while iPhone Bluetooth is off. Turn off Mac Bluetooth and confirm the Mac reports monitoring unavailable without a `would_lock` event.

- [ ] **Step 10: Run the 30-minute background check during actual app validation.** Keep the iPhone app backgrounded and the phone locked beside the Mac for 30 minutes with no false loss event. This has not been done; the user wants to carry it into testing along the way. It does not block starting actual app work.

- [ ] **Step 11: Complete range repeatability checks during actual app validation.** Repeat out-of-range and return scenarios ten times in varied orientations and through walls. Record any readings that flicker around `-70 dBm`. The user has chosen to carry this into app testing rather than block starting implementation.

## Self-review

- All approved status states, threshold behavior, phone-side disconnect/no-challenge estimate, unavailable lock-state copy, activity logging, documentation, and physical validation guidance have corresponding implementation or validation tasks above.
- Missing RSSI no longer clears a countdown. Reconnecting does not clear it either; recovery requires an RSSI sample stronger than `-70 dBm`.
- Weak RSSI and lost connection use separate phone states so the UI does not imply that a signal measurement exists after the BLE link drops.

## Out of scope

- Actual Mac locking, lock/unlock state detection, or automatic unlocking.
- RSSI-to-metre conversion, smoothing/hysteresis, push notifications, network relays, authenticated pairing, App Store packaging, and unrelated UI redesign.
- Pull requests, commits, or deployment; these remain out of scope for this prototype validation task.
