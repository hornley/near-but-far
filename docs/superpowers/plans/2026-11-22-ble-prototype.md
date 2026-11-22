# Near But Far BLE Prototype Implementation Plan

> **For agentic workers:** Use this plan task by task on the local `feature/ble-prototype` branch. Do not stage or commit unless the user asks. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Build a non-locking Mac/iPhone BLE prototype that logs connection acknowledgements and raw RSSI, and emits a 60-second “would lock” event after presence stops.

**Architecture:** One Xcode project contains a macOS app that advertises a GATT service and an iPhone app that scans, connects, and acknowledges challenge notifications. The Mac logs heartbeat and RSSI data locally; the iPhone logs its Core Bluetooth state locally. The prototype never locks the Mac or holds a sleep assertion.

**Tech Stack:** SwiftUI, CoreBluetooth, Foundation, XCTest, Xcode 26.6; no third-party dependencies.

---

## Files

- Create `NearButFar.xcodeproj/project.pbxproj` and shared scheme files for the Mac app, iPhone app, and test target.
- Create `Sources/Shared/BLEProtocol.swift` for service/characteristic UUIDs and the challenge/acknowledgement payload format.
- Create `Sources/Shared/PresenceTracker.swift` for the first-ack arm state and the 60-second grace timer.
- Create `Sources/Mac/NearButFarMacApp.swift`, `Sources/Mac/MacPeripheral.swift`, and `Sources/Mac/CSVLogger.swift` for the Mac UI, advertiser, challenge flow, and local CSV log.
- Create `Sources/iOS/NearButFarPhoneApp.swift` and `Sources/iOS/PhoneCentral.swift` for the companion UI, background central, RSSI read, and local event log.
- Create `Tests/NearButFarTests.swift` for protocol and timer boundary checks.
- Update `README.md` with build/run instructions and the physical-device validation steps.

## Task 1: Project skeleton and deterministic presence logic

**Files:** Xcode project, shared sources, unit test target.

- [x] Create macOS 14 and iOS 17 app targets with Bluetooth usage descriptions; set `UIBackgroundModes` to `bluetooth-central` on iOS and use a stable Core Bluetooth restoration identifier.
- [x] Define one service UUID, one notify challenge characteristic, and one write-with-response acknowledgement characteristic in `BLEProtocol.swift`. Encode each payload as a big-endian 32-bit challenge sequence followed by a signed 16-bit RSSI value; use `Int16.min` when no RSSI sample is available.
- [x] Implement `PresenceTracker` with `missedChallenge(at:)`, `acknowledge(at:)`, `takeWouldLock(at:)`, and `secondsRemaining(at:)`. It stays unarmed until the first acknowledgement, records the first missed challenge, cancels on acknowledgement, and reports only once after 60 seconds from the active miss.
- [x] Add XCTest cases for payload round trips, negative RSSI, unarmed state, the exact 60-second boundary, acknowledgement cancellation, and a new grace period after recovery.
- [x] Run `xcodebuild test -project NearButFar.xcodeproj -scheme NearButFarTests -destination 'platform=macOS'` and require all cases to pass (7 tests passed).

## Task 2: Mac advertiser, timer, and durable log

**Files:** `Sources/Mac/NearButFarMacApp.swift`, `Sources/Mac/MacPeripheral.swift`, `Sources/Mac/CSVLogger.swift`.

- [x] Start `CBPeripheralManager` on the main queue, add the service and characteristics when Bluetooth is powered on, and advertise the service UUID.
- [x] Send one numbered challenge every five seconds to the subscribed iPhone. Keep only one challenge outstanding; retransmit the same unanswered sequence every five seconds for recovery. If `updateValue` returns false, retain and retry that same challenge from `peripheralManagerIsReady(toUpdateSubscribers:)`; do not treat queue backpressure as a missed response.
- [x] On each valid write acknowledgement, record its sequence and RSSI, arm or reset `PresenceTracker`, and append an ISO-8601 timestamped CSV row under `~/Library/Application Support/NearButFar/ble-log.csv`.
- [x] If an accepted challenge has no matching acknowledgement by the next interval, mark presence lost. At 60 seconds, log `would_lock`; when an acknowledgement resumes, cancel the timer. Never invoke the system lock shortcut.
- [x] Show Bluetooth state, subscriber/heartbeat state, last RSSI in dBm, countdown, and the log file location in the Mac app. An unavailable Mac Bluetooth state is shown as unavailable, not as an away event.

## Task 3: iPhone background central and RSSI samples

**Files:** `Sources/iOS/NearButFarPhoneApp.swift`, `Sources/iOS/PhoneCentral.swift`.

- [x] Request Bluetooth permission with a clear usage description, scan only for the prototype service UUID, connect to the discovered Mac, and subscribe to the challenge characteristic.
- [x] Initialize `CBCentralManager` with a restoration identifier and restore scanning/connection state in `centralManager(_:willRestoreState:)`.
- [x] For each new challenge sequence, call `readRSSI()`. Write the matching sequence and RSSI in a write-with-response acknowledgement; use `Int16.min` if the RSSI read fails. Ignore duplicate or stale challenges.
- [x] Show scan/connection/Bluetooth state, most recent RSSI in dBm, and a timestamped local event log. Do not display estimated meters.

## Task 4: Build and real-device runbook

**Files:** `README.md`, test/build results.

- [x] Run `xcodebuild -list -project NearButFar.xcodeproj` and confirm the Mac, iPhone, and test schemes are visible.
- [x] Build the Mac app with `xcodebuild -project NearButFar.xcodeproj -scheme NearButFarMac -destination 'platform=macOS' build`.
- [x] Build the iPhone app for the available iPhone 15 Pro Max simulator with `xcodebuild -project NearButFar.xcodeproj -scheme NearButFarPhone -destination 'platform=iOS Simulator,id=6D95529B-214F-4D32-8D6F-EE2F536AAAEA' CODE_SIGNING_ALLOWED=NO build`. Use the device tools to launch it and inspect the status UI; simulator results are not BLE evidence.
- [x] Launch the Mac app locally and confirm the CSV log records Bluetooth on and advertising started.
- [x] Document the physical-device run: run the Mac app; install and launch the iPhone app on a physical iPhone; grant Bluetooth access; confirm RSSI logs; background the app and lock the phone for 30 minutes; move it out of range; return before and after 60 seconds; repeat ten times; toggle iPhone Bluetooth and force-quit the companion; then toggle Mac Bluetooth and confirm the unavailable state.
- [x] Select the approved Personal Team for `NearButFarPhone`, then build, install, and launch it on the paired iPhone (`roasted ginger`). Xcode reported `Running NearButFarPhone on roasted ginger`.
- [x] Confirm an initial physical BLE exchange: the Mac logged a subscription and acknowledgements for sequences 1–33 from `2026-11-22T16:44:10Z` to `2026-11-22T16:46:53Z`; acknowledged RSSI ranged from `-47` to `-51 dBm`. The iPhone showed **Connected to Mac** at `-48 dBm`.
- [ ] Run the 30-minute nearby test with the iPhone companion backgrounded and the phone locked; expect no missed-response timer.
- [ ] Run controlled out-of-range trials. Verify presence loss starts the 60-second grace period, return before expiry cancels it, and staying away past expiry logs **“would lock”** without locking the Mac.
- [ ] Test iPhone Bluetooth off and force-quit behavior, Mac Bluetooth unavailable behavior, then repeat out-of-range and return trials ten times across orientations and through walls.

## Scope limits

- No actual macOS lock, overlay, power assertion, router integration, account, cloud service, or App Store release.
- No conversion from RSSI to meters; radio range and RSSI vary by room, orientation, and interference.
- No production authentication protocol. Do not use this prototype to protect a Mac; authenticate and pin the iPhone before any production auto-lock implementation.
- Keep the work local and uncommitted; no GitHub issue or pull request exists for this local-only repository.
