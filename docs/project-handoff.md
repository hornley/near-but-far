# Near But Far project handoff

**Updated:** 2026-11-25

**Merged change:** [PR #3](https://github.com/hornley/near-but-far/pull/3)

**Open issues:** [#1, one-second BLE sampling](https://github.com/hornley/near-but-far/issues/1) and [#2, secure pairing and Mac monitoring](https://github.com/hornley/near-but-far/issues/2)

Use this note to resume the project after PR #3 and the app-screen implementation. The app implements authenticated iPhone presence, the approved status-first interfaces, and a separate app-owned screen state. Physical reliability and device walkthroughs remain incomplete. The app does not observe or change macOS's secure lock state.

## What PR #3 delivered

- Active BLE challenges target roughly one-second sampling. The five-second missed-response retry and ten-second iPhone fallback remain in place.
- One-use QR enrollment uses a two-minute setup secret, local Mac approval, device-only identity storage, pinned peers, and authenticated Noise sessions through the Snow 0.10.0 Rust bridge.
- Mac monitoring has a persistent on/off setting and an authenticated signal threshold. The default is `-70 dBm`; the range is `-90` to `-50 dBm`.
- The Mac and iPhone use the approved status-first interface. Recent activity appears in the iPhone menu.
- The PR reports passing Rust bridge tests, formatting, XCFramework generation, macOS and iOS simulator builds, and installation and launch of the signed iPhone build on the connected phone.

## What the app-screen implementation adds

- The Mac menu's **Lock now** activates the app screen and reports its current Active or Inactive state. Local return uses the screen card's macOS Local Authentication prompt; there is no Mac menu **Unlock** button.
- Authenticated iPhone controls can activate or dismiss the app screen. A fresh authenticated phone return can dismiss an away-triggered screen. These paths control app-screen state, separate from macOS's secure lock state.

## App-screen final-tree validation captured on 2026-11-24

Final-tree automated validation ran on a MacBook Air (Mac14,2, Apple M2) with macOS 26.5 (build 25F71). The system reported the built-in 2560 × 1664 display and one external 1920 × 1080 display online. This is the build/test host setup; the app overlay was not launched on either display.

Commands and results:

- `xcodebuild build -project NearButFar.xcodeproj -scheme NearButFarMac -destination 'platform=macOS'` — **BUILD SUCCEEDED**. Xcode selected the arm64 macOS destination; the build emitted the standard App Intents metadata skipped warning because the target has no AppIntents dependency.
- `xcodebuild build -project NearButFar.xcodeproj -scheme NearButFarPhone -destination 'generic/platform=iOS Simulator'` — **BUILD SUCCEEDED**. This built for the generic iOS Simulator destination; it did not launch a simulator or phone.
- `xcodebuild test -project NearButFar.xcodeproj -scheme NearButFarTests -destination 'platform=macOS'` — **TEST SUCCEEDED**, 30 tests, 0 failures.

A later device walkthrough attempt found one booted iPhone 15 Pro Max simulator on iOS 26.5 (UDID `6D95529B-214F-4D32-8D6F-EE2F536AAAEA`) and no physical devices. `device_open` returned its agent-device command, but installation failed with `DEVICE_IN_USE`: the simulator is owned by session `t3-022e49954765a2e27768681f` in workspace `/Users/hornley/Projects/near_but_far`. The prescribed status check reports that remote-host ownership cannot be inspected from this command. The simulator was not retried or taken over; no phone UI or BLE walkthrough was verified.

Visible Mac app checks were not available in this run. `getState` listed native apps, but `getApp` for the current built app path timed out with computer-use server error `-10005: timeoutReached`; lookup by bundle ID was ambiguous among three installed copies. No app was launched, no overlay action was taken, and no local-authentication prompt or kiosk behavior was observed. The recorded machine/display details above do not verify overlay presentation.

Still open: on-device pairing and iOS app walkthrough; app-screen appearance and input containment on each active display; display attach/detach; localized clock/date and VoiceOver behavior; successful, cancelled, unavailable, and failed local authentication; Command-Tab, Force Quit, Apple-menu, app-hide, and session-termination behavior and presentation-option restoration; authenticated phone activation/dismissal and state sync; 60-second presence expiry and pre-expiry recovery; reconnect without a fresh strong sample; monitoring-off behavior; Bluetooth-unavailable ordering and persistence while active; and physical BLE sampling/reconnection checks. Do not infer results for any of these from a successful build or unit suite.

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

The secure pairing, monitoring path, and approved app-screen implementation are present. Physical pairing, presence, and app-screen walkthroughs remain pending. See the [app screen protection design](superpowers/specs/2026-11-24-app-screen-protection-design.md).

The Mac pairing menu uses one panel for Home, Settings, Pair iPhone, and its confirmations. Canceling Forget or Replace returns to the paired-phone view without changing the saved identity. The visible menu walkthrough remains pending: attaching Computer Use to the current Mac build returned `Computer Use server error -10005: timeoutReached`. No pairing menu was opened, and no Forget or Replace action was confirmed.

- Check QR expiration, one-use behavior, cancellation, Mac approval or rejection, and recovery after a failed attempt.
- Check reconnect with the pinned identity and verify that replacing or forgetting a phone revokes the old identity.
- The Rust bridge tests cover handshake, wrong PSK or Mac pin rejection, transport replay rejection, and short-buffer retry. Keep the device walkthrough focused on the app flow and Bluetooth lifecycle.
- Verify the iPhone and Mac status screens through pairing, reconnect, monitoring off, Bluetooth unavailable, signal loss, and recovery.
- Walk through app-screen activation from the Mac and iPhone, phone dismissal, local authentication, and fresh-presence return behavior on devices.

## Lock and unlock

Do not claim that the app screen locks the macOS session. The iPhone **Lock now** and **Unlock** controls operate app-screen state over the authenticated session, not operating-system lock or unlock requests. The Mac **Lock now** button activates the same app screen. Local Mac return is through the screen card's authentication prompt.

The Apple API review found no supported local-app request and confirmation path for macOS's secure lock screen. Apple's [Device Lock command](https://developer.apple.com/documentation/devicemanagement/device-lock-command) is an MDM endpoint that requires Mac supervision and a management access right; it is not the app's implementation route.

Use macOS's Local Authentication prompt for local Touch ID or password. Never collect the password in the app. The overlay is a deterrent and can still be stopped through other system or physical means.

### Apple API review (2026-11-24)

The public Core Graphics session dictionary reports user, console, and login properties; the documented `SessionAttributeBits` report root, graphics, TTY, and remote-session properties. Neither API documents a lock-state value. Apple's Device Management **Device Lock** command is an MDM endpoint: on macOS it requires supervision and the `AllowPasscodeRemovalAndLock` access right. It is not a local app API, and its acknowledgement is not a query for current lock state. Keep the operating-system lock state unavailable; the approved app-screen controls are separate. Sources: [CGSessionCopyCurrentDictionary](https://developer.apple.com/documentation/coregraphics/cgsessioncopycurrentdictionary()), [Window Server Session Properties](https://developer.apple.com/documentation/coregraphics/window-server-session-properties), [SessionAttributeBits](https://developer.apple.com/documentation/security/sessionattributebits), [Device Lock](https://developer.apple.com/documentation/devicemanagement/device-lock-command), [DeviceLockResponse](https://developer.apple.com/documentation/devicemanagement/devicelockresponse).

## App-screen design

[The Quiet Graphite design](lock-screen-design.md) is the selected app-screen appearance. It uses a quiet graphite screen with the time, date, a lock symbol, and the messages “Mac is locked” and “Use Touch ID or password to return.” The app presents this overlay; macOS presents and handles the local authentication prompt.

The overlay is not a replacement for macOS's secure lock screen. Keep app-screen state separate from macOS lock-state observation in the protocol and UI. The app does not observe or change macOS's secure lock state. The full-screen overlay covers the desktop and suppresses common shortcuts while active, but other system or physical means can stop it; it is an app-level deterrent, not kiosk enforcement.

## Suggested next sequence

1. Complete the Issue #1 physical reliability and resource-use checks. Attach measurements and logs to Issue #1.
2. Complete the QR, pairing recovery, and Bluetooth lifecycle walkthrough. Record the results on Issue #2.
3. Walk through the implemented app-screen overlay and all three return paths: authenticated iPhone dismissal, fresh authenticated phone return, and local authentication on the Mac.
4. Complete physical BLE sampling, pairing, reconnection, and Bluetooth lifecycle checks. Keep macOS secure-lock state unobserved and unchanged unless Apple documents a supported local app mechanism.
