# Near But Far

**Logo mark:** `nbt`
**Status:** BLE feasibility prototype; Issue #1 sampling is implemented on the current branch, and Issue #2 is blocked at the authenticated-session dependency gate.

## Implementation status

- The current branch schedules active Mac challenges about once per second while keeping the five-second Mac response/retry timing, ten-second iPhone fallback, `-70 dBm` test threshold, and 60-second test countdown.
- Physical validation of this cadence and its timeout behavior remains pending. iOS may throttle or suspend background BLE work.
- No compatible maintained protocol library was found for macOS 14 and iOS 17, so authenticated pairing and effective monitoring are not implemented. The BLE sampling exchange remains an unauthenticated prototype and must not be treated or shipped as protection.
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

The prototype's public BLE service is only a signal for local sampling and must not be treated as authentication. The approved pairing design uses a one-time QR for enrollment and a pinned phone identity for reconnects, but no implementation has passed the dependency gate. Before production can use presence for protection, the pairing flow must authenticate and pin the user's iPhone so another nearby BLE device cannot keep the Mac marked present.

## BLE feasibility prototype

Build two minimal native apps in one Xcode project: a macOS menu-bar app using `CBPeripheralManager`, and an iPhone app using `CBCentralManager`. The Mac advertises a service and sends a small numbered challenge notification every five seconds. The iPhone scans for that service, connects, subscribes, and writes an acknowledgement after each challenge. Use iOS's `bluetooth-central` background mode and Core Bluetooth state restoration so the iPhone can keep or restore the connection where the OS allows. The Mac measures presence by the last valid acknowledgement, avoiding reliance on an undocumented peripheral-side disconnect callback. Keep one challenge outstanding; if Core Bluetooth cannot queue it, retry that same challenge when the peripheral manager is ready. A notification that Core Bluetooth couldn’t queue is not counted as a missed response.

The prototype logs timestamped BLE state changes, challenges, acknowledgements, missed responses, and RSSI events locally on the Mac. The iPhone also keeps a local log of discoveries, connections, disconnections, and Bluetooth state. After a challenge notification, the iPhone reads the connected Mac's RSSI and includes the sample in its acknowledgement when available. RSSI is a rough proximity signal, not a distance measurement; do not display meters or claim a precise range. Background sampling may be sparse, so record every value the OS provides without promising a fixed sample rate. If the same challenge remains unanswered, the Mac retransmits that sequence on subsequent five-second intervals so the phone can recover after a dropped notification; it does not issue another sequence until the outstanding one is acknowledged.

For the current status experiment, both apps use a raw `-70 dBm` weak-signal threshold and a 60-second test countdown. RSSI at or below the threshold starts the countdown; a later stronger sample clears it. An acknowledgement without RSSI and a reconnect by themselves do not clear an active countdown. The phone shows **Nearby**, **Weak signal**, **Signal lost**, **Would lock**, or **Unavailable**, plus its latest RSSI and the test threshold. If the phone receives no challenge for ten seconds or Core Bluetooth reports a disconnect, it starts a phone-side estimate that can continue after the connection drops. This estimate may differ from the Mac timer. The phone always labels the real Mac lock state unavailable. If iPhone Bluetooth is unavailable, the phone shows **Unavailable** and does not infer a lock state.

After the first valid acknowledgement, mark monitoring as armed. If a queued challenge remains unacknowledged at the next five-second interval, mark presence lost and start the 60-second grace period; do not start a timer before monitoring has first been armed. In the status experiment, a received RSSI sample above `-70 dBm` clears the timer; a weak or missing RSSI sample does not. A later missed challenge starts a new timer. If it expires, log **“would lock”** and the elapsed time. The prototype must never actually lock the Mac, block input, or hold a power assertion.

## Validation and acceptance

The user has chosen to proceed to actual app design and implementation using the prototype results, while carrying the remaining physical checks into app development and validation. This is not a claim that the original prototype feasibility gate has passed. The 30-minute background run is explicitly deferred to testing along the way; it does not block starting implementation, but background reliability must be established before automatic locking is relied on.

On a physical iPhone, follow these checks:

1. Start the Mac app, open the iPhone companion, grant Bluetooth access, and confirm challenges, acknowledgements, and RSSI samples appear in the local logs. For the phone status experiment, move the phone in two-to-three-metre steps until a sample is at or below `-70 dBm`; do not interpret this as a distance boundary.
2. **Deferred during actual app testing:** Background the companion, lock the iPhone, and leave it next to the Mac for 30 minutes. Expect no missed-response timer. This has not been done and is not a blocker to starting implementation.
3. Walk the iPhone away until acknowledgements stop. Record the last RSSI and the first missed-response time.
4. Return within 60 seconds. Expect acknowledgements to resume and the timer to cancel.
5. The user reports that the phone-side 60-second **Would lock** status works. The Mac CSV has three `would_lock` entries with `elapsed_seconds=60`, at `19:12:03Z`, `19:15:03Z`, and `19:19:43Z` on 2026-11-22. The prototype does not lock the Mac.
6. While monitoring is armed, turn off iPhone Bluetooth or force-quit the companion; both should produce the same **“would lock”** result. Turning off Bluetooth on the Mac should instead show monitoring as unavailable.
7. Repeat out-of-range and return scenarios ten times with different orientations and through walls. Compare RSSI at known positions only as a relative signal-strength reading, not as meters. This repeatability test is still pending.
8. Clarify the exact 60-second boundary. A weak sample at `19:20:17Z` recovered from `-70` to `-67 dBm` at `19:21:17Z` with no `would_lock` row. CSV timestamps have one-second precision, so the order of recovery and expiry is unresolved.

The Mac CSV snapshot ending `2026-11-22T19:24:07Z` contains 1,834 acknowledgements with RSSI from `-84` to `-28 dBm`, three missed responses each followed by an acknowledgement within 11 seconds, nine `weak_signal` events, ten `signal_recovered` events, and three `would_lock` events. It also records recovery from `-76 dBm` to `-47 dBm` in 15 seconds (sequences 153 and 156). The user reports that the BLE exchange continued while the companion was backgrounded, that the threshold/countdown and return-to-Nearby behavior worked, and that iPhone Bluetooth off/on restored the Mac UI from **Waiting for iPhone** to **iPhone subscribed**. The background run duration and locked-screen state were not recorded.

The original feasibility gate remains open until background reliability, signal-loss fallback, Bluetooth-unavailable behavior, and repeatability are checked. The user has chosen to perform these checks during actual app development rather than block the start of that work. Do not treat them as passed or rely on automatic locking until the required safety and reliability checks are complete.

In later user-reported physical trials, RSSI readings ranged from about `-40` to `-55 dBm` depending on distance and obstruction; the BLE exchange continued with the phone app in the background. The user reports successful threshold/countdown, return-to-Nearby, 60-second phone status, and iPhone Bluetooth off/on recovery. The Mac UI returned from **Waiting for iPhone** to **iPhone subscribed** after Bluetooth was restored. The background test duration and whether the phone was locked were not recorded.

The latest checked Mac CSV snapshot ended at `2026-11-22T19:24:07Z` and contained 1,834 acknowledgements (RSSI range `-84` to `-28 dBm`), three missed responses each followed by an acknowledgement within 11 seconds, nine `weak_signal` rows, ten `signal_recovered` rows, and three `would_lock` rows. Each `would_lock` row reports `elapsed_seconds=60`; the three entries occurred at `19:12:03Z`, `19:15:03Z`, and `19:19:43Z` after weak samples persisted through expiry. The CSV also records a weak sample of `-76 dBm` (sequence 153) and recovery to `-47 dBm` 15 seconds later (sequence 156). One later weak sample at `19:20:17Z` recovered to `-67 dBm` at `19:21:17Z` with no expiry row; one-second timestamp precision leaves the event order at the exact 60-second boundary unresolved.

Walking out of range before a weak sample, the phone's exact **Unavailable** screen while Bluetooth is off, Mac Bluetooth-off handling, a 30-minute locked-phone run, and ten varied-orientation trials remain pending. The user wants the 30-minute run carried into actual app testing rather than blocking the start of app work.

## Out of scope for the prototype

- Triggering the actual macOS lock screen or automatically unlocking.
- Keeping the Mac awake or changing display sleep behavior.
- Router detection, remote services, App Store distribution, or a custom lock-screen overlay.

For the implementation handoff, see [the prototype results and next-step handoff](docs/prototype-handoff.md).
