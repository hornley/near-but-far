# Near But Far BLE Prototype

This local prototype checks whether an iPhone can acknowledge a Mac's BLE challenges while nearby and whether missed acknowledgements can drive a 60-second presence timer. It only logs **“would lock”**; it never locks the Mac or keeps it awake.

## Build and run

1. Open `NearButFar.xcodeproj` in Xcode.
2. Run the `NearButFarMac` scheme on the Mac. Its menu-bar item shows Bluetooth state and the last RSSI sample.
3. Run `NearButFarPhone` on an iPhone. For a physical device, select your signing team in Xcode. Approve Bluetooth access and leave the app open until it connects to the Mac.
4. The Mac CSV log is at `~/Library/Application Support/NearButFar/ble-log.csv`. The iPhone app displays its most recent 200 local BLE events.

The iPhone simulator can check compilation and the status screen, but it cannot validate BLE radio range or iOS background behavior.

## Current validation status

The Mac app was built and run locally, and the iPhone app was signed with the saved Personal Team, installed, and launched on the paired iPhone (`roasted ginger`). The iPhone showed **Connected to Mac** with RSSI `-48 dBm`. From `2026-11-22T16:44:10Z` through `2026-11-22T16:46:53Z`, the Mac log recorded a subscription and acknowledgements for challenge sequences 1–33, with RSSI samples from `-47` to `-51 dBm`. During setup the app briefly continued acknowledging while the iPhone was on its Home Screen, but this was not a controlled or long-duration background test.

In the latest user-reported physical trials, RSSI ranged from about `-40` to `-55 dBm`, varying with distance and obstruction. BLE continued working while the phone app was in the background. The user reports that the `-70 dBm` countdown, return-to-Nearby behavior, 60-second phone status, and iPhone Bluetooth off/on recovery worked. The Mac menu-bar state returned from **Waiting for iPhone** to **iPhone subscribed** after Bluetooth came back on. The duration and locked-screen state of the background test were not recorded. RSSI is relative signal strength, not distance.

At the latest CSV snapshot (`2026-11-22T19:24:07Z`, challenge sequence 764), there are 1,834 acknowledgements with RSSI from `-84` to `-28 dBm`, three `missed_response` events each followed by an acknowledgement within 11 seconds, nine `weak_signal` events, ten `signal_recovered` events, and three `would_lock` events. The three `would_lock` rows report `elapsed_seconds=60`, at `19:12:03Z`, `19:15:03Z`, and `19:19:43Z`. Each followed a weak sample at or below `-70 dBm` that persisted through expiry. Their displayed timestamps are 61 seconds after the corresponding weak-signal rows, while the event detail says 60 seconds. The log also records recovery from `-76 dBm` to `-47 dBm` in 15 seconds (sequences 153 and 156). A later `-70 dBm` sample at `19:20:17Z` recovered to `-67 dBm` at `19:21:17Z` with no `would_lock` row; because CSV timestamps have one-second precision, the event ordering at exactly 60 seconds remains unclear. These are log-only events; the prototype never locks the Mac. The out-of-range-before-weak-sample fallback, Mac Bluetooth-off behavior, 30-minute locked-phone run, and ten varied-orientation trials remain untested.

The phone status experiment uses a raw `-70 dBm` threshold and a 60-second local estimate. The iPhone shows **Nearby**, **Weak signal**, **Signal lost**, **Would lock**, or **Unavailable**, and always says that the actual Mac lock state is unavailable. A stronger sample clears the countdown; reconnecting alone or an acknowledgement with no RSSI does not. The Mac keeps its own timer and CSV log. Neither app locks the Mac.

## Handoff to actual app work

The user has chosen to continue to actual app design and implementation using the prototype results. The remaining physical checks are carried forward; they do not block starting app work. In particular, the 30-minute background-and-locked-phone run was not done. Keep it on the validation list and do it along the way; do not mark it passed. Resolve the remaining safety and reliability checks before relying on automatic locking. See [prototype results and next-step handoff](docs/prototype-handoff.md).

## Planned change

- [GitHub issue #1: Increase BLE RSSI sampling cadence to one second](https://github.com/hornley/near-but-far/issues/1)
- [GitHub issue #2: Add Mac monitoring toggle and manual iPhone lock controls](https://github.com/hornley/near-but-far/issues/2)
- [Local issue notes](docs/issues/001-one-second-ble-rssi-sampling.md)

On 2026-11-23, all 12 macOS unit tests passed; the Mac target, iPhone simulator target, and signed iPhone target built successfully. The updated phone build was installed and launched on the paired iPhone. After restarting the Mac app, its challenge sequence reset to 1; the phone acknowledged sequences 1 and 2 at `-50` and `-49 dBm`. The phone now resets its remembered sequence on a new connection, so a Mac app restart does not leave it rejecting challenges as stale. This confirms the updated apps launch and exchange BLE messages at a strong signal. It does not verify the `-70 dBm` threshold or a 60-second physical walk-away trial. A simulator screenshot confirmed the layout; simulator Bluetooth is unsupported.

Command-line checks:

```sh
xcodebuild -list -project NearButFar.xcodeproj
xcodebuild test -project NearButFar.xcodeproj -scheme NearButFarTests -destination 'platform=macOS'
xcodebuild build -project NearButFar.xcodeproj -scheme NearButFarMac -destination 'platform=macOS'
xcodebuild build -project NearButFar.xcodeproj -scheme NearButFarPhone -destination 'platform=iOS Simulator,name=iPhone 15 Pro Max' CODE_SIGNING_ALLOWED=NO
```

## Physical-device validation

Run these steps with the Mac app and iPhone companion installed. The feasibility decision depends on actual-device results; a simulator pass is not evidence that BLE background detection works.

1. Grant Bluetooth access and confirm the Mac log contains challenge, acknowledgement, and RSSI rows.
2. **Deferred during actual app testing:** Put the phone beside the Mac, background the companion, lock the iPhone, and leave both for 30 minutes. Check that no missed-response timer starts. This is not a blocker to starting app work and is not yet passed.
3. Carry the phone out of range. Record the last RSSI and first `missed_response` time in the Mac CSV log.
4. The user reports that the weak-signal countdown and return to **Nearby** work. The Mac CSV corroborates a weak sample at `-76 dBm` and recovery at `-47 dBm`. For a repeatable range record, move in two-to-three-metre steps and note the RSSI when the countdown starts; do not treat it as a distance boundary.
5. The user reports the phone-side 60-second **Would lock** status works. The Mac CSV now records three `would_lock` events, each with `elapsed_seconds=60`; this confirms the Mac-side timer logging too. These events are log-only, and the prototype must not lock the Mac.
6. The user reports iPhone Bluetooth off/on recovery works and the Mac returns from **Waiting for iPhone** to **iPhone subscribed**. Still confirm the phone's **Unavailable** label while Bluetooth is off, then turn off Mac Bluetooth and confirm the Mac reports monitoring unavailable without a `would_lock` event.
7. Test walking out of range before a weak RSSI sample; confirm the phone starts its estimate after disconnect or ten seconds without a challenge.
8. Repeat the out-of-range and return scenarios ten times in different orientations and through walls. Treat RSSI as a relative signal-strength reading, never as meters.
9. Clarify the exact 60-second boundary: the CSV shows one recovery at the same whole-second timestamp as the countdown boundary and no `would_lock` event, but its timestamp precision cannot show which event happened first.

The user has chosen to start actual app work while carrying the remaining checks forward. The original prototype feasibility gate is not fully passed: the 30-minute background run and ten varied-orientation trials remain outstanding, as do the fallback and Bluetooth-unavailable checks. The 30-minute run can happen during actual app testing. Do not rely on automatic locking until the required reliability and safety checks are complete; if background presence or heartbeat detection proves unreliable, choose another detection method.

## Safety and prototype limits

- RSSI is an imperfect signal-strength sample and cannot be translated reliably into distance.
- The BLE service is public and does not authenticate or pin the iPhone. Do not use this prototype to protect a Mac.
- The prototype has no automatic lock, automatic unlock, sleep assertion, custom lock screen, router detection, account, or cloud service.
