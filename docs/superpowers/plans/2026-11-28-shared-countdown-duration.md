# Shared Countdown Duration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `workflow-implementation` for execution. It delegates all coding tasks to subagents; do not implement inline. Steps use checkbox syntax for tracking.

**Goal:** Add a configurable Mac screen-activation countdown and display its weak-signal countdown on iPhone while preserving truthful local-estimate and app-screen semantics.

**Architecture:** The Mac owns and persists a validated `CountdownDuration`, then sends it as an authenticated `PeerMessage`. Each device's `PresenceTracker` captures the configured duration when a loss countdown starts, so changing the setting affects only later countdowns. The iPhone stores the last authenticated Mac value for disconnected estimates and updates its home status without claiming that macOS is locked.

**Tech Stack:** Swift, SwiftUI, Combine, XCTest, Xcode project and shared `PeerSession` protocol.

---

**Approved specification:** `docs/superpowers/specs/2026-11-28-shared-countdown-duration-design.md` (approved by user on 2026-11-28).
**GitHub issues:** [#11](https://github.com/hornley/near-but-far/issues/11), [#12](https://github.com/hornley/near-but-far/issues/12).
**Planning branch:** `t3/issue-11-12-shared-countdown`.

## File map and ownership

- `Sources/Shared/PresenceTracker.swift` — define the 15–180 second, 5-second-step duration value and preserve the duration captured by an active countdown.
- `Sources/Shared/PeerSession.swift` — add an authenticated Mac-to-phone countdown-duration message with strict payload and value validation.
- `Sources/Mac/MacCoordinator.swift` — load and persist the Mac setting, configure new countdowns, and send the value when a session becomes ready or the setting changes.
- `Sources/Mac/MacMenuBarPanel.swift` — add the stepped **Time to lock** slider below **Signal threshold** with the approved clarification.
- `Sources/iOS/PhoneModel.swift` — cache the last authenticated duration, use the 60-second fallback when no value has been received, configure new local estimates, and expose a pure, testable status-presentation mapping for weak-signal and connection-loss copy.
- `Sources/iOS/NearButFarPhoneApp.swift` — show the weak-signal countdown in the main status area, preserve the distinct **Signal lost** heading, and keep VoiceOver from announcing every tick.
- `Tests/NearButFarTests.swift` — extend the current XCTest suite for duration validation, tracker timing, protocol transfer, and phone-model behavior. Task 1 finishes editing the file before Task 3 adds its phone-model cases.
- `README.md` — update the current-behavior and validation notes after integration if their description of the iPhone countdown is stale.

## Dependency order

1. **Task 1: Shared duration and wire contract.** Ready immediately. It owns the shared source files and test file until complete.
2. **Tasks 2 and 3: Mac integration and iPhone integration.** Both depend on Task 1 and own disjoint app source files. They may run together once Task 1 is complete and Task 2's settings dependency is cleared. Task 3 edits `NearButFarTests.swift` only after Task 1 has finished; Task 2 must not edit that file.
   - **Task 2 gate:** Issue #10 is open and its Mac Settings work is in progress. Do not edit `MacMenuBarPanel.swift` or `MacCoordinator.swift` until that work is integrated into this branch or both changes are deliberately coordinated in the same branch. If the gate is still pending, queue Task 2 while Task 3 proceeds.
3. **Task 4: Integrated validation, documentation, and final review.** Depends on Tasks 2 and 3 and on the issue #10 Settings integration. Run one final review of the complete diff after integration.

The work stays in one coordinated feature branch. At implementation time, `workflow-implementation` dispatches coding tasks to GPT 6 Luna with Medium reasoning. The final independent review uses GPT 6.1 Sol with Low reasoning. The coordinator owns integration and any shared issue or PR updates.

## Protocol compatibility assumption

`PeerSession` currently rejects unknown message tags and closes the link. This plan assumes the paired Mac and iPhone are upgraded together before the Mac sends the new duration message. If mixed-version pairing must remain supported, stop before implementation and revise the spec to define capability negotiation; do not ignore decode failures or change the envelope version without approval.

### Task 1: Shared duration value, tracker, and protocol

**Owner:** Coding worker — GPT 6 Luna, Medium reasoning.
**Dependencies:** None.
**Files:**

- Modify: `Sources/Shared/PresenceTracker.swift`
- Modify: `Sources/Shared/PeerSession.swift`
- Test: `Tests/NearButFarTests.swift`

- [ ] **Step 1: Add failing duration and active-countdown tests**

Add tests proving that 15, 60, and 180 seconds are accepted; 14, 16, 181, and any non-5-second value are rejected; and changing the configured value does not change a countdown already in progress.

```swift
func testCountdownDurationValidatesBoundsAndStep() {
    XCTAssertEqual(CountdownDuration(validating: 15)?.seconds, 15)
    XCTAssertEqual(CountdownDuration(validating: 60)?.seconds, 60)
    XCTAssertEqual(CountdownDuration(validating: 180)?.seconds, 180)
    XCTAssertNil(CountdownDuration(validating: 14))
    XCTAssertNil(CountdownDuration(validating: 16))
    XCTAssertNil(CountdownDuration(validating: 61))
    XCTAssertNil(CountdownDuration(validating: 181))
}
```

After the duration API is defined in Step 3, add this tracker test to the same test file:

```swift
func testTrackerKeepsTheDurationCapturedWhenLossStarts() throws {
    let sixty = try XCTUnwrap(CountdownDuration(validating: 60))
    let thirty = try XCTUnwrap(CountdownDuration(validating: 30))
    var tracker = PresenceTracker(duration: sixty)
    let start = ContinuousClock.now
    tracker.acknowledge(at: start)
    tracker.missedChallenge(at: start)

    tracker.setConfiguredDuration(thirty)

    XCTAssertEqual(tracker.secondsRemaining(at: start.advanced(by: .seconds(59))), 1)
    XCTAssertTrue(tracker.takeWouldLock(at: start.advanced(by: .seconds(60))))
    tracker.acknowledge(at: start.advanced(by: .seconds(61)))
    tracker.missedChallenge(at: start.advanced(by: .seconds(61)))
    XCTAssertEqual(tracker.secondsRemaining(at: start.advanced(by: .seconds(61))), 30)
}
```

- [ ] **Step 2: Run the current test scheme and confirm the new tests fail**

Run: `xcodebuild -project NearButFar.xcodeproj -scheme NearButFarTests -destination 'platform=macOS' test`
Expected: the new tests fail to compile because `CountdownDuration` and the configurable tracker API do not exist yet.

- [ ] **Step 3: Add the validated duration and capture it at countdown start**

In `PresenceTracker.swift`, add a `CountdownDuration` value with default 60 seconds, allowed range 15–180, and validation that `(seconds - 15) % 5 == 0`. Give `PresenceTracker` a configured duration and a separate active duration snapshot. When `missedChallenge` starts a loss, copy the configured duration to the active snapshot; use that snapshot for `secondsRemaining` and `takeWouldLock`; clear it with the loss on a fresh acknowledgement. Add a setter for the configured duration so settings and authenticated updates affect only future loss episodes.

The new validation must have this shape:

```swift
struct CountdownDuration: Equatable {
    static let defaultDuration = CountdownDuration(validatedSeconds: 60)
    static let allowedRange: ClosedRange<Int> = 15 ... 180

    let seconds: Int

    init?(validating seconds: Int) {
        guard Self.allowedRange.contains(seconds), (seconds - 15).isMultiple(of: 5) else { return nil }
        self.init(validatedSeconds: seconds)
    }

    private init(validatedSeconds: Int) {
        self.seconds = validatedSeconds
    }
}
```

Add the duration to the tracker initializer and snapshot it only when a new loss begins:

```swift
private var configuredDuration: CountdownDuration
private var activeCountdownDuration: CountdownDuration? = nil

init(threshold: SignalThreshold = .default,
     duration: CountdownDuration = .defaultDuration) {
    self.threshold = threshold
    self.configuredDuration = duration
}

mutating func setConfiguredDuration(_ duration: CountdownDuration) {
    configuredDuration = duration
}

mutating func missedChallenge(at time: ContinuousClock.Instant) {
    guard isArmed, lossStartedAt == nil else { return }
    lossStartedAt = time
    activeCountdownDuration = configuredDuration
}
```

Update `acknowledge`, `secondsRemaining`, and `takeWouldLock` to clear or use `activeCountdownDuration`. Keep the existing monotonic-clock elapsed-time calculation and replace only the fixed 60-second constant with the captured value.

- [ ] **Step 4: Run shared duration tests and confirm the tracker uses its captured value**

Run: `xcodebuild -project NearButFar.xcodeproj -scheme NearButFarTests -destination 'platform=macOS' test`
Expected: duration validation and tracker tests pass; an active 60-second countdown still expires at 60 seconds after the configured value changes to 30 seconds, and the next countdown uses 30 seconds.

- [ ] **Step 5: Add failing authenticated-message tests**

Use the existing `makeEstablishedSessions()` helper to send a new countdown-duration message from the Mac session to the phone session. Also assert that the phone-side decoder rejects a value outside the allowed range or off the 5-second step.

```swift
func testCountdownDurationMessageUsesTheAuthenticatedSession() throws {
    let (phone, mac, phoneLink, macLink) = try makeEstablishedSessions()
    let bytes = try XCTUnwrap(
        try mac.send(.countdownDuration(90), on: macLink).outbound.first
    ).bytes

    let effects = try phone.receive(bytes, from: phoneLink)
    XCTAssertTrue(effects.events.contains {
        if case let .received(message) = $0 { return message.message == .countdownDuration(90) }
        return false
    })
    XCTAssertThrowsError(try phone.send(.countdownDuration(90), on: phoneLink))
    XCTAssertThrowsError(try PeerSession.decodeMessage(tag: 11, payload: [0, 14], receiver: .phone))
    XCTAssertThrowsError(try PeerSession.decodeMessage(tag: 11, payload: [0, 91], receiver: .phone))
    XCTAssertThrowsError(try PeerSession.decodeMessage(tag: 11, payload: [0, 181], receiver: .phone))
    XCTAssertThrowsError(try PeerSession.decodeMessage(tag: 11, payload: [90], receiver: .phone))
    XCTAssertThrowsError(try PeerSession.decodeMessage(tag: 11, payload: [0, 90], receiver: .mac))
}
```

- [ ] **Step 6: Add the Mac-to-phone message to `PeerSession`**

Add `.countdownDuration(UInt16)` to `PeerMessage`. Assign it the next unused tag, 11. Encode seconds as a two-byte big-endian unsigned integer in `encodeEnvelope`; decode tag 11 only for the phone and reject wrong-role, wrong-length, out-of-range, and off-step payloads as malformed. Add the Mac sender case to both the operational-message allowlist and authenticated sender-role check, validate outbound values through `CountdownDuration`, and add the phone receiver case to the established-session receive-state allowlist. Keep the existing threshold message first during session setup because the phone uses it to complete its current operational-session transition; send the new duration after that message.

- [ ] **Step 7: Run protocol and full shared tests**

Run: `xcodebuild -project NearButFar.xcodeproj -scheme NearButFarTests -destination 'platform=macOS' test`
Expected: valid authenticated duration messages arrive as `.countdownDuration`; malformed values fail decode; all existing tests continue to pass.

**Task acceptance:** A validated duration type exists, each tracker loss uses a duration snapshot, and the authenticated protocol accepts only valid Mac-to-phone duration values.

### Task 2: Mac setting, persistence, and automatic screen timing

**Owner:** Coding worker — GPT 6 Luna, Medium reasoning.
**Dependencies:** Task 1; wait for issue #10 Settings integration before changing the Mac settings files.
**Files:**

- Modify: `Sources/Mac/MacCoordinator.swift`
- Modify: `Sources/Mac/MacMenuBarPanel.swift`

- [ ] **Step 1: Load the Mac duration before creating its tracker**

Add a `countdownDurationSeconds` preference key. Load an integer from `UserDefaults.standard`, validate it with `CountdownDuration`, and use 60 seconds when it is missing or invalid. Initialize `MacCoordinator`'s tracker with both the existing threshold and this duration. Update the tracker reset in `clearOperationalState` to keep using the current selected duration instead of reverting to 60 seconds.

```swift
private static let countdownDurationPreferenceKey = "countdownDurationSeconds"

let storedDuration = UserDefaults.standard.object(forKey: Self.countdownDurationPreferenceKey) as? Int
let initialDuration = storedDuration.flatMap { CountdownDuration(validating: $0) }
    ?? .defaultDuration
```

- [ ] **Step 2: Add a coordinator setter that affects only future countdowns**

Expose the selected `CountdownDuration` to SwiftUI. The setter must validate its integer input, persist accepted values, update only the tracker's configured duration, and send the duration immediately when an authenticated link is active. Do not reset `tracker.lossStartedAt` or the active duration snapshot.

```swift
func setCountdownDuration(_ seconds: Int) {
    guard let duration = CountdownDuration(validating: seconds) else { return }
    countdownDuration = duration
}
```

Implement the published property so its `didSet` persists the accepted value, calls `tracker.setConfiguredDuration(countdownDuration)`, and sends the message on the active authenticated link. Initialization must assign the loaded value and construct the tracker directly so it does not depend on a property observer running during initialization.

- [ ] **Step 3: Send the duration when an authenticated session becomes ready**

At the existing `.ready` handler, preserve `sendThreshold(on:)` as the first operational message, then send the configured duration before battery and app-screen state. Add `sendCountdownDuration(on:)` using the same session/link/peer guards and error handling as `sendThreshold(on:)`. A setting change sends the same message through the active authenticated session.

- [ ] **Step 4: Add the setting under Signal threshold**

Add a SwiftUI group below the existing threshold group. Show **Time to lock** and the selected value in a header, then a `Slider` with a binding over `15 ... 180` and `step: 5`. Set the accessibility label to **Time to lock**, expose the selected value, and add the approved helper copy:

```swift
HStack {
    Text("Time to lock")
        .font(.subheadline.weight(.medium))
    Spacer()
    Text(durationLabel(coordinator.countdownDuration.seconds))
        .font(.system(.subheadline, design: .monospaced))
}
Slider(value: countdownDurationBinding, in: 15 ... 180, step: 5)
    .accessibilityLabel("Time to lock")
    .accessibilityValue(durationLabel(coordinator.countdownDuration.seconds))
```

Use this binding so every slider selection passes through the coordinator's validator:

```swift
private var countdownDurationBinding: Binding<Double> {
    Binding(
        get: { Double(coordinator.countdownDuration.seconds) },
        set: { coordinator.setCountdownDuration(Int($0.rounded())) }
    )
}
```

```swift
Text("This activates Near But Far’s app screen; it does not lock macOS.")
    .font(.caption)
    .foregroundStyle(.secondary)
```

Use this formatter for the value text and accessibility value:

```swift
private func durationLabel(_ seconds: Int) -> String {
    guard seconds >= 60 else { return "\(seconds) sec" }
    let minutes = seconds / 60
    let remainder = seconds % 60
    return remainder == 0 ? "\(minutes) min" : "\(minutes) min \(remainder) sec"
}
```

- [ ] **Step 5: Build the Mac app and manually verify preference behavior**

Run: `xcodebuild -project NearButFar.xcodeproj -scheme NearButFarMac -destination 'platform=macOS' build`
Expected: Build Succeeded. In the running Mac app, verify 15 and 180 second endpoints, 5-second increments, the 60-second default, persistence after relaunch, live transfer when paired, and that changing the setting during a countdown does not alter that countdown.

**Task acceptance:** Mac Settings exposes and persists the selected value, new Mac countdowns use it, and connected phones receive it over the authenticated session.

### Task 3: iPhone duration cache and live home countdown

**Owner:** Coding worker — GPT 6 Luna, Medium reasoning.
**Dependencies:** Task 1. This task may run alongside Task 2 after Task 1 completes. It takes ownership of `Tests/NearButFarTests.swift` only after Task 1 has finished editing that file.
**Files:**

- Modify: `Sources/iOS/PhoneModel.swift`
- Modify: `Sources/iOS/NearButFarPhoneApp.swift`
- Modify: `Tests/NearButFarTests.swift` (after Task 1)

- [ ] **Step 1: Add phone-model and presentation tests for defaults, receipt, persistence, and countdown copy**

Test that a phone with no saved duration uses 60 seconds, that an authenticated 30-second message updates the configured duration, that a new `PhoneModel` loads the saved value, and that receipt during an active countdown does not alter that active countdown. Add presentation tests proving weak signal says **Locks in 45s** with app-screen/macOS-unlocked clarification, while connection loss still says **Signal lost** and labels its seconds as a local estimate. Put this pure mapping in `PhoneModel.swift` as an internal `PhonePresencePresentation` value with `headline`, `detailsHeadline`, `countdownDisclosure`, and `announcementTitle`; have the SwiftUI view consume those fields so the tests exercise the displayed copy. Give `PhoneModel` a `UserDefaults` initializer parameter defaulting to `.standard` so tests can use a uniquely named defaults suite and remove it after the test.

Call `didReceiveAuthenticated(.countdownDuration(91), at:)` directly after a valid 30-second value in a model test and assert that the selected value remains 30; this verifies the model's boundary validation even though `PeerSession` already rejects malformed wire values.

Use this test shape; after changing the setting during the timer, the active value remains 1 second at elapsed time 59 seconds, while a reloaded model reads the newly saved 30-second setting:

```swift
@MainActor
func testPhoneCachesNewDurationWithoutChangingActiveEstimate() throws {
    let suite = "CountdownDurationTests-\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }

    let model = PhoneModel(userDefaults: defaults)
    XCTAssertEqual(model.countdownDuration.seconds, 60)
    model.didAuthenticate(peerID: UUID())
    let start = ContinuousClock.now
    model.didReadAuthenticatedRSSI(-70, at: start)
    model.didReceiveAuthenticated(.countdownDuration(30), at: start.advanced(by: .seconds(10)))
    model.refreshPresence(at: start.advanced(by: .seconds(59)))
    XCTAssertEqual(model.presenceState, .weakSignalCountdown(1))

    let reloaded = PhoneModel(userDefaults: defaults)
    XCTAssertEqual(reloaded.countdownDuration.seconds, 30)
}
```

Also cover disconnected estimates with fresh defaults suites: after authenticating, receiving a challenge, then disconnecting, the default model reports `.connectionLostCountdown(1)` at 59 seconds; a model initialized with a saved 90-second duration reports `.connectionLostCountdown(1)` at 89 seconds. These cases prove the cached Mac duration and 60-second fallback both survive the disconnect transition.

Test the presentation mapping directly with these assertions:

```swift
let weak = PhonePresencePresentation(state: .weakSignalCountdown(45))
XCTAssertEqual(weak.headline, "Locks in 45s")
XCTAssertEqual(weak.detailsHeadline, "Weak signal")
XCTAssertTrue(weak.countdownDisclosure?.contains("macOS stays unlocked") == true)

let lost = PhonePresencePresentation(state: .connectionLostCountdown(45))
XCTAssertEqual(lost.headline, "Signal lost")
XCTAssertEqual(lost.detailsHeadline, "Signal lost")
XCTAssertTrue(lost.countdownDisclosure?.contains("Local estimate") == true)
XCTAssertTrue(lost.countdownDisclosure?.contains("45s") == true)
XCTAssertEqual(
    PhonePresencePresentation(state: .weakSignalCountdown(44)).announcementTitle,
    weak.announcementTitle
)
```

Implement that mapping in `PhoneModel.swift` so it can be exercised by the macOS test target without importing the iOS-only SwiftUI view:

```swift
struct PhonePresencePresentation {
    let state: PhonePresenceState

    var headline: String {
        switch state {
        case .waiting: "Waiting for Mac"
        case .nearby: "Nearby"
        case .weakSignalCountdown(let seconds): "Locks in \(seconds)s"
        case .connectionLostCountdown: "Signal lost"
        case .away: "Away"
        case .unavailable: "Unavailable"
        }
    }

    var detailsHeadline: String {
        switch state {
        case .weakSignalCountdown: "Weak signal"
        case .connectionLostCountdown: "Signal lost"
        default: headline
        }
    }

    var countdownDisclosure: String? {
        switch state {
        case .weakSignalCountdown:
            "Near But Far’s app screen only; macOS stays unlocked."
        case .connectionLostCountdown(let seconds):
            "Local estimate: app screen in \(seconds)s; macOS stays unlocked."
        default:
            nil
        }
    }

    var announcementTitle: String {
        switch state {
        case .weakSignalCountdown: "Weak signal countdown started"
        case .connectionLostCountdown: "Signal lost"
        default: headline
        }
    }
}
```

- [ ] **Step 2: Run the new phone-model tests and confirm they fail**

Run: `xcodebuild -project NearButFar.xcodeproj -scheme NearButFarTests -destination 'platform=macOS' test`
Expected: the new tests fail because `PhoneModel` has no duration preference or message case handling yet.

- [ ] **Step 3: Persist and apply authenticated Mac durations**

In `PhoneModel`, use injected defaults for both the existing saved signal threshold and the new duration. Load the last valid duration or use 60 seconds. On `.countdownDuration`, validate again at the model boundary, persist the accepted integer, and update the tracker's configured duration. Ignore invalid values without overwriting the cached value. Keep the tracker's active snapshot intact when a new setting arrives. When `didDisconnect` resets the tracker for `.pairingStarted` or `.bluetoothUnavailable`, initialize it with both the saved threshold and cached duration; do not lose the last authenticated Mac duration during a lifecycle reset. Existing `PhoneCentral` already refreshes `PhoneModel` once per second and forwards authenticated messages; do not add another timer or transport path.

Handle the new message with this ordering so an update cannot be applied before session readiness:

```swift
case let .countdownDuration(seconds):
    guard sessionReady,
          let duration = CountdownDuration(validating: Int(seconds)) else { return }
    countdownDuration = duration
    userDefaults.set(duration.seconds, forKey: Self.countdownDurationPreferenceKey)
    presenceTracker.setConfiguredDuration(duration)
```

- [ ] **Step 4: Put the weak-signal countdown in the home headline**

Use `PhonePresencePresentation` from Step 1 for the Home headline, status-details label, disclosure, and state-change announcement. Map `.weakSignalCountdown(seconds)` to **“Locks in {seconds}s”** on Home. Keep `.connectionLostCountdown` mapped to **Signal lost** and add its local countdown estimate to supporting text. Add a home-summary disclosure immediately after the large headline and before the signal reading: during weak signal, explain that this activates Near But Far's app screen and macOS remains unlocked; during connection loss, label the seconds as a local estimate and include the same app-screen clarification. Keep the existing signal and threshold details and the current recovery transition to **Nearby**. In Status details, keep **Weak signal** as the state label and use its existing **Time remaining** row so the countdown does not appear twice.

In `PhoneContentView`, derive one presentation value from `model.presenceState` and use its fields:

```swift
private var presencePresentation: PhonePresencePresentation {
    PhonePresencePresentation(state: model.presenceState)
}

private var statusTitle: String { presencePresentation.headline }
private var statusDetailsTitle: String { presencePresentation.detailsHeadline }
private var countdownDisclosure: String? { presencePresentation.countdownDisclosure }
```

Use `statusDetailsTitle` for the **Phone presence** row in `statusDetailsScreen`; keep its **Time remaining** row unchanged.

Place the line in `presenceSummary` directly after the title and before `homeSignalReading`:

```swift
if let countdownDisclosure {
    Text(countdownDisclosure)
        .font(.caption)
        .multilineTextAlignment(.center)
}
```

- [ ] **Step 5: Announce state changes, not every countdown tick**

The current `.onChange(of: statusTitle)` posts a VoiceOver announcement. Once `statusTitle` includes the changing seconds, that would announce every second. Change it to `.onChange(of: presencePresentation.announcementTitle)` and post the new title:

```swift
.onChange(of: presencePresentation.announcementTitle) { _, title in
    UIAccessibility.post(notification: .announcement, argument: title)
}
```

Build `statusCardAccessibilityLabel` from `presencePresentation.headline`, `countdownDisclosure`, `statusContext`, `signalSummaryAccessibility`, and the Mac battery text:

```swift
let disclosure = countdownDisclosure.map { "\($0). " } ?? ""
let context = statusContext.map { "\($0). " } ?? ""
let battery = model.macBatteryLevel.map { "Mac battery, \($0) percent." } ?? "Mac battery unavailable."
return "Phone presence: \(presencePresentation.headline). \(disclosure)\(context)\(signalSummaryAccessibility) \(battery)"
```

Do not append a second countdown value: the weak-signal headline already contains it, and the connection-loss disclosure labels its seconds as a local estimate.

- [ ] **Step 6: Run phone-model tests and build the iPhone app**

Run: `xcodebuild -project NearButFar.xcodeproj -scheme NearButFarTests -destination 'platform=macOS' test`
Expected: phone-model tests pass for default, last-synced persistence, active-countdown snapshot, recovery, and the distinct connection-loss state.

Run: `xcodebuild -project NearButFar.xcodeproj -scheme NearButFarPhone -destination 'generic/platform=iOS Simulator' build`
Expected: Build Succeeded.

**Task acceptance:** The home headline shows live seconds for weak signal; connection loss remains visibly distinct; the phone uses its last authenticated duration offline, or 60 seconds if none has been received; recovery clears the estimate; VoiceOver does not announce each second.

### Task 4: Integrated validation, docs, and final review

**Owner:** Coordinator for integration; independent review worker — GPT 6.1 Sol, Low reasoning.
**Dependencies:** Tasks 2 and 3 complete; issue #10 Settings changes integrated.
**Files:**

- Review all files changed by Tasks 1–3.
- Modify: `README.md` only if its current-behavior description needs to mention the configurable countdown and iPhone estimate.

- [ ] **Step 1: Check the integrated diff against the approved spec**

Confirm the Mac setting, authenticated message direction and validation, last-synced phone behavior, active-countdown snapshot, recovery behavior, copy, accessibility announcements, and all scope boundaries match `docs/superpowers/specs/2026-11-28-shared-countdown-duration-design.md`.

- [ ] **Step 2: Run the full Xcode test scheme and both app builds**

Run: `xcodebuild -project NearButFar.xcodeproj -scheme NearButFarTests -destination 'platform=macOS' test`
Expected: all tests pass.

Run: `xcodebuild -project NearButFar.xcodeproj -scheme NearButFarMac -destination 'platform=macOS' build`
Expected: Build Succeeded.

Run: `xcodebuild -project NearButFar.xcodeproj -scheme NearButFarPhone -destination 'generic/platform=iOS Simulator' build`
Expected: Build Succeeded.

- [ ] **Step 3: Perform the paired-device walkthrough**

On a paired Mac and iPhone, confirm the Mac setting's default, endpoints, and 5-second increments; change it and verify the phone receives it; start a countdown, change the setting, and verify the active countdown is unchanged; recover with a strong sample; disconnect and verify the phone uses the last received duration; confirm the fallback is 60 seconds when no duration was received; and verify the app-screen wording never claims macOS is locked.

- [ ] **Step 4: Update README behavior notes if they are stale**

Describe the selected Mac duration and iPhone's local countdown estimate without implying native macOS locking or guaranteed iOS background refresh. Do not add any unmeasured BLE or battery claims.

- [ ] **Step 5: Request independent final review**

Have the review worker inspect the full integrated diff for spec compliance, message-direction validation, countdown races, unintended timer changes, and accessibility copy. Fix accepted findings through `workflow-implementation`, then rerun the required test and build commands above.

**Task acceptance:** The integrated Mac and iPhone builds and test scheme pass, the device walkthrough confirms live synchronization and offline estimates, docs match behavior, and the complete diff passes independent review.

## Workflow boundary

This document completes the **plan** stage only. Execution must use `workflow-implementation`, which dispatches the coding tasks to subagents under the canonical workflow. Do not implement inline or continue to PR, release, deployment, or verification from this plan stage. The repository documents local Xcode builds and physical-device checks but no deployment environment or release sequence.
