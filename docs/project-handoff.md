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
- Keep the app-screen overlay state separate from macOS lock state. The overlay is an app-level deterrent.
- Treat RSSI as a rough signal reading, not a distance measurement. The threshold is configurable and may vary by environment.
- Require fresh authenticated presence after app startup or Bluetooth recovery. Bluetooth being unavailable does not prove that the phone left.
- Do not add BLE messages that claim to lock or unlock the macOS session. App-screen commands must use separate terminology.
- Do not describe the app overlay as a replacement for the macOS secure lock screen.

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

The secure pairing and monitoring path is implemented. A user-approved app-screen overlay design now replaces the prior native-lock requirement; implementation and physical walkthroughs remain pending. See the [app screen protection design](superpowers/specs/2026-11-24-app-screen-protection-design.md).

- Check QR expiration, one-use behavior, cancellation, Mac approval or rejection, and recovery after a failed attempt.
- Check reconnect with the pinned identity and verify that replacing or forgetting a phone revokes the old identity.
- The Rust bridge tests cover handshake, wrong PSK or Mac pin rejection, transport replay rejection, and short-buffer retry. Keep the device walkthrough focused on the app flow and Bluetooth lifecycle.
- Verify the iPhone and Mac status screens through pairing, reconnect, monitoring off, Bluetooth unavailable, signal loss, and recovery.
- Implement the app-screen overlay, authenticated iPhone controls and status, local macOS authentication, and fresh-presence return behavior from the approved design.

## Lock and unlock

Do not claim that the app screen locks the macOS session. The iPhone **Lock now** and **Unlock** controls will operate the app overlay over the authenticated session, not issue operating-system lock or unlock requests.

The Apple API review found no supported local-app request and confirmation path for macOS's secure lock screen. Apple's [Device Lock command](https://developer.apple.com/documentation/devicemanagement/device-lock-command) is an MDM endpoint that requires Mac supervision and a management access right; it is not the app's implementation route.

Use macOS's Local Authentication prompt for local Touch ID or password. Never collect the password in the app. The overlay is a deterrent and can still be stopped through other system or physical means.

### Apple API review (2026-11-24)

The public Core Graphics session dictionary reports user, console, and login properties; the documented `SessionAttributeBits` report root, graphics, TTY, and remote-session properties. Neither API documents a lock-state value. Apple's Device Management **Device Lock** command is an MDM endpoint: on macOS it requires supervision and the `AllowPasscodeRemovalAndLock` access right. It is not a local app API, and its acknowledgement is not a query for current lock state. Keep the operating-system lock state unavailable; the approved app-screen controls are separate. Sources: [CGSessionCopyCurrentDictionary](https://developer.apple.com/documentation/coregraphics/cgsessioncopycurrentdictionary()), [Window Server Session Properties](https://developer.apple.com/documentation/coregraphics/window-server-session-properties), [SessionAttributeBits](https://developer.apple.com/documentation/security/sessionattributebits), [Device Lock](https://developer.apple.com/documentation/devicemanagement/device-lock-command), [DeviceLockResponse](https://developer.apple.com/documentation/devicemanagement/devicelockresponse).

## App-screen design

[The Quiet Graphite design](lock-screen-design.md) is the selected app-screen appearance. It uses a quiet graphite screen with the time, date, a lock symbol, and the messages “Mac is locked” and “Use Touch ID or password to return.” The app presents this overlay; macOS presents and handles the local authentication prompt.

The overlay is not a replacement for macOS's secure lock screen. Keep app-screen state separate from macOS lock-state observation in the protocol and UI.

## Suggested next sequence

1. Complete the Issue #1 physical reliability and resource-use checks. Attach measurements and logs to Issue #1.
2. Complete the QR, pairing recovery, and Bluetooth lifecycle walkthrough. Record the results on Issue #2.
3. Implement and validate the approved app-screen overlay and all three release paths.
4. Complete physical BLE sampling, pairing, reconnection, and Bluetooth lifecycle checks. Keep macOS secure-lock state unavailable unless Apple documents a supported local app mechanism.
