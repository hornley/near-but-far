# Near But Far project handoff

**Updated:** 2026-11-24

**Merged change:** [PR #3](https://github.com/hornley/near-but-far/pull/3)

**Open issues:** [#1, one-second BLE sampling](https://github.com/hornley/near-but-far/issues/1) and [#2, secure pairing and Mac monitoring](https://github.com/hornley/near-but-far/issues/2)

Use this note to resume the project after PR #3. The app implements authenticated iPhone presence and the approved status-first interfaces. Physical reliability checks remain incomplete. The app does not lock or unlock the Mac.

## What PR #3 delivered

- Active BLE challenges target roughly one-second sampling. The five-second missed-response retry and ten-second iPhone fallback remain in place.
- One-use QR enrollment uses a two-minute setup secret, local Mac approval, device-only identity storage, pinned peers, and authenticated Noise sessions through the Snow 0.10.0 Rust bridge.
- Mac monitoring has a persistent on/off setting and an authenticated signal threshold. The default is `-70 dBm`; the range is `-90` to `-50 dBm`.
- The Mac and iPhone use the approved status-first interface. Recent activity appears in the iPhone menu.
- **Lock now** and **Unlock** remain disabled. The app sends no lock command and makes no claim that the Mac is locked.
- The PR reports passing Rust bridge tests, formatting, XCFramework generation, macOS and iOS simulator builds, and installation and launch of the signed iPhone build on the connected phone.

Snow 0.10.0 contains eight fixes validated by Trail of Bits. The exact release did not receive a full audit, and two informational findings were not among those validated fixes. Do not describe the dependency as fully audited.

## Decisions to preserve

- Keep presence, monitoring readiness, and Mac lock state as separate facts. A phone-side estimate is not proof that macOS locked the computer.
- Treat RSSI as a rough signal reading, not a distance measurement. The threshold is configurable and may vary by environment.
- Require fresh authenticated presence after app startup or Bluetooth recovery. Bluetooth being unavailable does not prove that the phone left.
- Do not add lock or unlock messages to the BLE protocol while those actions are unavailable.
- Do not implement a custom full-screen window as a replacement for the macOS secure lock screen.

## Remaining work for Issue #1

The one-second target cadence is implemented. Keep Issue #1 open until physical checks on the current build produce usable evidence.

1. Measure challenge and RSSI cadence with the iPhone active, then with the iPhone in the background and locked. Record exact run time and available app logs.
2. Compare battery and CPU use against the five-second cadence.
3. Exercise weak-signal entry, recovery, disconnect, reconnect, and the 60-second expiry. Record the exact ordering at the expiry boundary.
4. Repeat range and orientation trials, including obstructions. Record RSSI and connection events rather than converting RSSI into distance.
5. Turn Bluetooth off and on at each device. Confirm the UI reports unavailable states honestly and fresh authenticated presence is required after recovery.
6. Confirm the five-second Mac retry and ten-second phone fallback still behave as designed.

The older overnight locked-phone run is user-reported, but it has no exact duration or supporting telemetry. It does not validate the current one-second build.

## Remaining work for Issue #2

The secure pairing and monitoring path is implemented. Complete a physical lifecycle walkthrough and record any gaps before treating pairing and background monitoring as validated.

- Check QR expiration, one-use behavior, cancellation, Mac approval or rejection, and recovery after a failed attempt.
- Check reconnect with the pinned identity and verify that replacing or forgetting a phone revokes the old identity.
- The Rust bridge tests cover handshake, wrong PSK or Mac pin rejection, transport replay rejection, and short-buffer retry. Keep the device walkthrough focused on the app flow and Bluetooth lifecycle.
- Verify the iPhone and Mac status screens through pairing, reconnect, monitoring off, Bluetooth unavailable, signal loss, and recovery.

## Lock and unlock

Keep both controls disabled. Do not emit lock or unlock requests, and do not interpret a phone countdown as the Mac's lock state.

Reconsider **Lock now** only after a documented macOS mechanism can request the native secure lock screen and the app can reliably confirm the resulting lock state. Test the request and confirmation path on supported macOS versions before enabling the control.

Keep **Unlock** unavailable until a documented mechanism preserves macOS local authentication. Do not bypass or simulate Touch ID or password authentication. If macOS provides no supported mechanism for the requested behavior, rescope the feature and leave the control disabled.

## Lock-screen design

[The Quiet Graphite design](lock-screen-design.md) is a visual reference. It describes a quiet graphite screen with the time, date, a lock symbol, and the messages “Mac is locked” and “Use Touch ID or password to return.”

The app must invoke the macOS secure lock screen if a supported lock action becomes available. macOS owns that screen and its authentication behavior. Do not use the mockup as a custom app window or claim that its appearance protects the session. Confirm which parts of the reference are achievable through the native macOS lock screen before planning further lock-screen UI work.

## Suggested next sequence

1. Complete the Issue #1 physical reliability and resource-use checks. Attach measurements and logs to Issue #1.
2. Complete the QR, pairing recovery, and Bluetooth lifecycle walkthrough. Record the results on Issue #2.
3. Research the documented macOS lock request and lock-state observation options without enabling either control.
4. Decide whether the Quiet Graphite mockup remains a visual reference or whether its presentation needs to change to match the native macOS lock screen.
