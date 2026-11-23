# Near But Far

**Logo mark:** `nbt`
**Status:** The current branch implements one-use QR pairing, authenticated BLE presence, persistent monitoring preference, and the approved status-first UI. Issue #1's one-second active sampling is implemented; physical validation remains pending. Issue #2 remains open because verified Mac lock and unlock actions are unavailable.

## Implementation status

- The current branch schedules active Mac challenges about once per second while keeping the five-second Mac response/retry timing, ten-second iPhone fallback, `-70 dBm` test threshold, and 60-second test countdown.
- Physical validation of this cadence and its timeout behavior remains pending. iOS may throttle or suspend background BLE work.
- Snow 0.10.0 passed the reviewed Rust-to-Swift C ABI gate and is used by the pairing and authenticated BLE session path on macOS 14 and iOS 17 targets. Its tag contains eight remediations validated by Trail of Bits; it does not mean the exact release received a full audit, and two informational findings were not among those validated fixes. Physical QR pairing, background reliability, and range behavior still need device validation.
- Lock now and Unlock remain unavailable. The app neither requests nor confirms Mac lock state.

## Product goal

Near But Far is a local macOS utility that locks the Mac when its paired iPhone moves out of Bluetooth range. Bluetooth reports a lost connection, not a physical distance: range loss, radio interference, Bluetooth being disabled, and the companion app stopping can all look the same.

The production utility should use macOS's secure lock screen and leave authentication to macOS. A custom screen is not security. While locked, the Mac should stay awake; the display follows the user's macOS timeout, including on battery. Returning to range never unlocks the Mac automatically.

## Confirmed behavior

- Use a small iPhone companion app and local Bluetooth Low Energy (BLE); no router, account, or cloud service.
- The Mac advertises a BLE service. The iPhone companion scans for it and connects, including while in the background where iOS permits.
- A connected iPhone counts as nearby. If valid presence signals stop, start a 60-second grace period. A signal returning before expiry cancels it; after expiry, the production app locks the Mac.
- Treat Bluetooth unavailable on the Mac as monitoring unavailable, not proof that the iPhone left.
- Keep the grace period configurable, with 60 seconds as the initial value.
- The approved Quiet Graphite mockup is a visual reference. The production app must invoke macOS's native secure lock screen, not cover the session with a custom window.

## Production security gate

The approved one-time QR enrollment, pinned identity, and authenticated BLE session path are implemented on this branch. Physical pairing and monitoring checks remain open. Keep the app's presence status informational: no supported macOS lock request and trustworthy lock-state confirmation have been established, so Lock now and Unlock remain disabled and no lock message is sent.

## BLE feasibility prototype

Build two minimal native apps in one Xcode project: a macOS menu-bar app using `CBPeripheralManager`, and an iPhone app using `CBCentralManager`. The Mac advertises a service and sends a small numbered challenge notification every five seconds. The iPhone scans for that service, connects, subscribes, and writes an acknowledgement after each challenge. Use iOS's `bluetooth-central` background mode and Core Bluetooth state restoration so the iPhone can keep or restore the connection where the OS allows. The Mac measures presence by the last valid acknowledgement, avoiding reliance on an undocumented peripheral-side disconnect callback. Keep one challenge outstanding; if Core Bluetooth cannot queue it, retry that same challenge when the peripheral manager is ready. A notification that Core Bluetooth couldn’t queue is not counted as a missed response.

The prototype logs timestamped BLE state changes, challenges, acknowledgements, missed responses, and RSSI events locally on the Mac. The iPhone also keeps a local log of discoveries, connections, disconnections, and Bluetooth state. After a challenge notification, the iPhone reads the connected Mac's RSSI and includes the sample in its acknowledgement when available. RSSI is a rough proximity signal, not a distance measurement; do not display meters or claim a precise range. Background sampling may be sparse, so record every value the OS provides without promising a fixed sample rate. If the same challenge remains unanswered, the Mac retransmits that sequence on subsequent five-second intervals so the phone can recover after a dropped notification; it does not issue another sequence until the outstanding one is acknowledged.

For the current status experiment, both apps use a raw `-70 dBm` weak-signal threshold and a 60-second test countdown. RSSI at or below the threshold starts the countdown; a later stronger sample clears it. An acknowledgement without RSSI and a reconnect by themselves do not clear an active countdown. The phone shows **Nearby**, **Weak signal**, **Signal lost**, **Would lock**, or **Unavailable**, plus its latest RSSI and the test threshold. If the phone receives no challenge for ten seconds or Core Bluetooth reports a disconnect, it starts a phone-side estimate that can continue after the connection drops. This estimate may differ from the Mac timer. The phone always labels the real Mac lock state unavailable. If iPhone Bluetooth is unavailable, the phone shows **Unavailable** and does not infer a lock state.

After the first valid acknowledgement, mark monitoring as armed. If a queued challenge remains unacknowledged at the next five-second interval, mark presence lost and start the 60-second grace period; do not start a timer before monitoring has first been armed. In the status experiment, a received RSSI sample above `-70 dBm` clears the timer; a weak or missing RSSI sample does not. A later missed challenge starts a new timer. If it expires, log **“would lock”** and the elapsed time. The prototype must never actually lock the Mac, block input, or hold a power assertion.

## Validation and acceptance

The user has chosen to proceed to actual app design and implementation using the prototype results, while carrying the remaining physical checks into app development and validation. The user now reports leaving the app on overnight with the iPhone locked and considers the 30-minute background check complete. Exact elapsed time and connection telemetry were not captured, so record this as user-reported rather than a measured pass. Background reliability must still be established before automatic locking is relied on.

On a physical iPhone, follow these checks:

1. Start the Mac app, open the iPhone companion, grant Bluetooth access, and confirm challenges, acknowledgements, and RSSI samples appear in the local logs. For the phone status experiment, move the phone in two-to-three-metre steps until a sample is at or below `-70 dBm`; do not interpret this as a distance boundary.
2. **User-reported complete, not instrumented:** The user left the companion on overnight with the iPhone locked and considers the 30-minute check done. Exact duration and missed-response telemetry were not recorded. Verify the current one-second build separately when the phone is available.
3. Walk the iPhone away until acknowledgements stop. Record the last RSSI and the first missed-response time.
4. Return within 60 seconds. Expect acknowledgements to resume and the timer to cancel.
5. The user reports that the phone-side 60-second **Would lock** status works. The Mac CSV has three `would_lock` entries with `elapsed_seconds=60`, at `19:12:03Z`, `19:15:03Z`, and `19:19:43Z` on 2026-11-22. The prototype does not lock the Mac.
6. While monitoring is armed, turn off iPhone Bluetooth or force-quit the companion; both should produce the same **“would lock”** result. Turning off Bluetooth on the Mac should instead show monitoring as unavailable.
7. Repeat out-of-range and return scenarios ten times with different orientations and through walls. Compare RSSI at known positions only as a relative signal-strength reading, not as meters. This repeatability test is still pending.
8. Clarify the exact 60-second boundary. A weak sample at `19:20:17Z` recovered from `-70` to `-67 dBm` at `19:21:17Z` with no `would_lock` row. CSV timestamps have one-second precision, so the order of recovery and expiry is unresolved.

The Mac CSV snapshot ending `2026-11-22T19:24:07Z` contains 1,834 acknowledgements with RSSI from `-84` to `-28 dBm`, three missed responses each followed by an acknowledgement within 11 seconds, nine `weak_signal` events, ten `signal_recovered` events, and three `would_lock` events. It also records recovery from `-76 dBm` to `-47 dBm` in 15 seconds (sequences 153 and 156). The user reports that the BLE exchange continued while the companion was backgrounded, that the threshold/countdown and return-to-Nearby behavior worked, and that iPhone Bluetooth off/on restored the Mac UI from **Waiting for iPhone** to **iPhone subscribed**. The later overnight run with the phone locked is user-reported, but its duration and connection telemetry were not recorded.

The original feasibility gate remains open until background reliability, signal-loss fallback, Bluetooth-unavailable behavior, and repeatability are checked. The user has chosen to perform these checks during actual app development rather than block the start of that work. Do not treat them as passed or rely on automatic locking until the required safety and reliability checks are complete.

In later user-reported physical trials, RSSI readings ranged from about `-40` to `-55 dBm` depending on distance and obstruction; the BLE exchange continued with the phone app in the background. The user reports successful threshold/countdown, return-to-Nearby, 60-second phone status, and iPhone Bluetooth off/on recovery. The Mac UI returned from **Waiting for iPhone** to **iPhone subscribed** after Bluetooth was restored. The user now reports an overnight run with the phone locked; the duration and connection telemetry were not recorded.

The latest checked Mac CSV snapshot ended at `2026-11-22T19:24:07Z` and contained 1,834 acknowledgements (RSSI range `-84` to `-28 dBm`), three missed responses each followed by an acknowledgement within 11 seconds, nine `weak_signal` rows, ten `signal_recovered` rows, and three `would_lock` rows. Each `would_lock` row reports `elapsed_seconds=60`; the three entries occurred at `19:12:03Z`, `19:15:03Z`, and `19:19:43Z` after weak samples persisted through expiry. The CSV also records a weak sample of `-76 dBm` (sequence 153) and recovery to `-47 dBm` 15 seconds later (sequence 156). One later weak sample at `19:20:17Z` recovered to `-67 dBm` at `19:21:17Z` with no expiry row; one-second timestamp precision leaves the event order at the exact 60-second boundary unresolved.

Walking out of range before a weak sample, the phone's exact **Unavailable** screen while Bluetooth is off, Mac Bluetooth-off handling, and ten varied-orientation trials remain pending. The overnight locked-phone run is user-reported complete, but its exact duration and connection telemetry remain unverified; validate the current one-second build separately.

## Out of scope for the prototype

- Triggering the actual macOS lock screen or automatically unlocking.
- Keeping the Mac awake or changing display sleep behavior.
- Router detection, remote services, App Store distribution, or a custom lock-screen overlay.

For the implementation handoff, see [the prototype results and next-step handoff](docs/prototype-handoff.md).
