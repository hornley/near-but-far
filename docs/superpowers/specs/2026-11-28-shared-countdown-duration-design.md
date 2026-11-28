# Shared countdown duration and iPhone countdown design

**Status:** Approved by user on 2026-11-28
**Issues:** [#11](https://github.com/hornley/near-but-far/issues/11), [#12](https://github.com/hornley/near-but-far/issues/12)

## Goal

Let the user choose how long Near But Far waits before activating its app-owned Mac screen, and show the active countdown prominently on iPhone. Both devices use the Mac's configured duration when it is available. The countdown and its copy must not claim that macOS is locked.

## Current behavior

`PresenceTracker` uses a fixed 60-second grace period. The Mac and iPhone each track presence independently. The Mac can activate Near But Far's app-owned screen when its timer expires. The iPhone shows **Weak signal** as the main headline and exposes its remaining time only in Status details. The phone can also continue a local estimate after losing the connection, so its start time may differ from the Mac's.

## Approved decisions

- The Mac setting ranges from 15 seconds to 3 minutes in 5-second steps. Its default is 60 seconds.
- A setting change affects the next countdown. A countdown already running keeps the duration it started with.
- The iPhone stores the last duration received from the authenticated Mac and uses it for a disconnected local estimate. If it has never received a duration, it uses 60 seconds.
- During a weak-signal countdown, the iPhone's main headline is **“Locks in {seconds}s”**. Supporting copy immediately explains that the action activates Near But Far's app screen and does not lock macOS.
- A connection-loss countdown remains distinguishable: its headline stays **Signal lost**, with the local estimate shown as supporting text.
- When a fresh strong signal clears the countdown, the iPhone returns to **Nearby**.

## Mac settings

Add a **Time to lock** duration control directly below **Signal threshold** in Mac Settings. Use a stepped slider from 15 to 180 seconds with 5-second steps, and show its selected value in a readable time format. Keep 60 seconds selected by default and persist the value on the Mac.

Place this helper text with the control: **“This activates Near But Far’s app screen; it does not lock macOS.”** The setting controls only the grace period before that app-owned screen activates. It does not request or report macOS's secure lock state.

## Shared duration and countdown behavior

The Mac is the source of the configured duration. Send the duration over the existing authenticated session when the session becomes ready and whenever the user changes the setting. The iPhone validates and persists each accepted value as its last-synced duration. The duration is expressed in whole seconds and must be between 15 and 180, inclusive, in 5-second increments. Invalid values are ignored and do not replace the saved value.

Each countdown captures the configured duration when it starts. Updating the setting changes the duration used by later countdowns but does not restart, shorten, or extend an active countdown. A fresh strong RSSI sample continues to clear the active countdown. Keep the current 5-second missed-response/retry timing and 10-second iPhone no-challenge fallback unchanged.

The Mac and iPhone continue to measure their own presence events. Their countdowns may start at different times. If the phone is disconnected, it continues its local estimate using its last-synced duration, or the 60-second fallback if none is saved. Do not describe this estimate as a synchronized Mac countdown. iOS may pause visual refresh while suspended; refresh from the timer's absolute start time when the app is active, without adding notifications or promising background updates.

## iPhone home status

While the phone is in `weakSignalCountdown`, replace the large **Weak signal** headline with **“Locks in {seconds}s”** and update the remaining seconds as the timer runs. Keep signal strength and threshold context visible. Show the app-screen clarification immediately below the countdown so users do not mistake it for a macOS lock.

Keep **Signal lost** as the headline for `connectionLostCountdown`; show its countdown as a local estimate in the supporting line. This preserves the distinction between a weak signal sample and loss of fresh responses. When signal recovers, clear the countdown and show **Nearby** again.

The phone's local timer is not proof that the Mac screen activated. Show the Mac app-screen state as active only after receiving the authenticated state from the Mac. Never infer macOS lock state from the countdown or its expiry. Keep the countdown value in the status card's accessibility label, but avoid announcing each second as a separate VoiceOver alert.

## Scope boundaries

- Do not add a native macOS lock/unlock mechanism or claim to observe macOS lock state.
- Do not add a separate iPhone duration setting.
- Do not change signal-threshold behavior, the 5-second Mac retry, or the 10-second iPhone fallback.
- Do not add notifications or promise countdown updates while iOS suspends the app.

## Acceptance criteria

- Mac Settings places the duration control below **Signal threshold**, offers 15–180 seconds in 5-second steps, defaults to 60 seconds, and persists the selection across relaunch.
- The Mac sends the configured duration on authenticated session readiness and after setting changes. The iPhone rejects invalid values and persists the last valid authenticated duration.
- A phone that has never received a duration uses 60 seconds for its local estimate. A disconnected phone uses the last received duration.
- The Mac and iPhone use the configured duration for new countdowns. A setting change does not alter an active countdown; recovery on a fresh strong sample clears it.
- The iPhone home screen shows **“Locks in {seconds}s”** during a weak-signal countdown, keeps **Signal lost** distinct during a connection-loss estimate, and returns to **Nearby** after recovery.
- The app-screen clarification is visible with the countdown. The phone does not claim the Mac screen is active without an authenticated state report and never claims macOS is locked.
- Countdown updates remain accessible without a VoiceOver announcement on every second.
- The existing one-second countdown refresh, 5-second Mac missed-response/retry behavior, and 10-second iPhone no-challenge fallback remain unchanged.

## Validation

Add behavior tests for the supported duration range and increments, default and persistence behavior, active-countdown duration capture, authenticated duration synchronization and validation, disconnected fallback, countdown recovery, weak-signal versus connection-loss copy, and screen-state reporting. Build the macOS and iOS targets and run the existing Xcode test scheme. On devices, verify that changes synchronize, reconnect uses the latest received duration, and weak-signal and connection-loss states remain distinguishable.

## Integration note

Issue #10 is in progress and also changes Mac Settings. Integrate the duration control after that settings work is available, or coordinate both changes in the same branch, to avoid concurrent edits to the settings panel.
