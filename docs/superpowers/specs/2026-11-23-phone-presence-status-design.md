# iPhone Presence Status Design

**Superseded implementation note (2026-11-24):** This prototype-era screen guidance predates the implemented app screen. The current app reports separate app-screen state and does not observe or change macOS secure-lock state.


## Goal

Make the Near But Far iPhone companion show a clear, minimal estimate of whether the Mac is nearby, approaching the prototype's weak-signal limit, or past the prototype countdown. Keep the real Mac lock state explicitly unavailable: this prototype never locks or unlocks the Mac.

## Approved decisions

- Keep the current dark, simple iPhone screen and put the current presence status first.
- Use `-70 dBm` as an experimental weak-signal threshold. RSSI is negative; values at or below `-70 dBm` are weaker than the threshold. This value is for testing and does not represent a fixed distance.
- Start a 60-second prototype countdown on the first RSSI sample at or below the threshold. A later sample above the threshold clears the countdown. Do not smooth or debounce readings in this first trial; the physical range tests will show whether the raw threshold is too noisy.
- If the BLE connection drops before a weak sample arrives, start a phone-side estimated countdown when iOS reports the disconnect or no new challenge has arrived for 10 seconds (two expected five-second challenge intervals). The phone counts locally, so it can keep showing the estimate after it leaves range.
- After 60 seconds, show **“Would lock”** and label it **test only**. The Mac continues to use its own presence timer and CSV log; it never locks.
- When the iPhone gets a stronger sample above the threshold, show **Nearby** again. Do not call this **Unlocked**.
- Always show **“Mac lock state unavailable”** while this prototype is running. Neither a pending countdown nor a completed **Would lock** event means the Mac is actually locked.
- When iPhone Bluetooth is unavailable, show that presence status is unavailable. Do not infer that the Mac is away from that state.
- Keep the countdown in the foreground screen and refresh it from an absolute start time when the app is active. iOS may pause screen updates while the app is suspended; this change does not add push notifications.

## Phone screen

Use one status-first card that fits the existing screen:

- **Nearby:** show the Mac is responding, with the latest RSSI and the `-70 dBm` test threshold.
- **Weak signal:** show the local countdown prominently, the latest RSSI, and the threshold.
- **Signal lost:** when the countdown starts from a disconnect or missed challenges, show the estimate without implying a current RSSI measurement. If the link drops during a weak-signal countdown, show **Signal lost** while preserving the original countdown start time.
- **Would lock:** replace the countdown with **“Would lock”**, and keep **“Mac lock state unavailable · prototype only”** visible.
- **Unavailable:** show Bluetooth or connection status without claiming the Mac is locked or away.

Keep the activity log available below the status card. Avoid a graph, estimated distance, lock/unlock controls, and extra navigation.

## Behavior and data flow

The iPhone already reads RSSI after each Mac challenge, and sends that value in its acknowledgement. The iPhone uses the sample to update its local status and countdown. The Mac applies the same `-70 dBm` rule to the acknowledgement it receives and continues its own timer. If a weak signal persists, each side can reach its test event independently; small timing differences are expected because the phone and Mac observe Bluetooth callbacks at different times.

If the BLE link drops, the phone starts its estimate from the disconnect callback or 10 seconds without a challenge, while the Mac starts its own timer from a missed challenge. Those start times may differ by several seconds. The phone label must say this is an estimate, not a synchronized report of Mac state.

Record status changes in the existing local logs: weak-signal start, recovery above threshold, phone-side estimated would-lock, and the Mac's existing would-lock event. Keep existing Bluetooth and connection diagnostics.

## Limits and failure handling

- RSSI varies with walls, orientation, obstacles, and radio interference. `-70 dBm` is a test setting, not a distance boundary.
- A single weak sample starts the countdown in this first trial, so a noisy reading can cause a false countdown. A stronger sample cancels it. Log the transitions so repeated physical trials can assess this behavior.
- The iPhone estimate can differ from the Mac timer because the phone is not receiving updates after disconnection, and iOS can suspend the companion.
- If iPhone Bluetooth becomes unavailable, the phone cannot assess proximity; display unavailable and do not claim a lock event.
- The prototype does not lock or unlock the Mac, and cannot report whether macOS is actually locked or unlocked.
- Do not add notification permission, a network relay, or a distance estimate for this change.

## Manual validation

1. With both apps running nearby and signal above `-70 dBm`, confirm the phone shows **Nearby** and the Mac receives acknowledgements.
2. Move the phone until an RSSI sample is at or below `-70 dBm`. Confirm the phone and Mac start their own 60-second test countdowns and record weak-signal events.
3. Return to a stronger signal before 60 seconds. Confirm the phone returns to **Nearby**, the Mac countdown clears, and recovery is logged.
4. Stay below threshold beyond 60 seconds. Confirm the phone shows **Would lock** and the Mac logs its **would_lock** event. Confirm the Mac remains unlocked.
5. Walk out of range before receiving a weak sample. Confirm the phone starts an estimated countdown after disconnect or 10 seconds without a challenge and does not claim to know the Mac's lock state.
6. Reconnect with a stronger sample and confirm **Nearby** returns. Turn iPhone Bluetooth off and confirm presence becomes unavailable rather than claiming the Mac is locked.
7. Repeat near the threshold and at several positions/orientations. Record RSSI and false countdowns; do not translate readings into meters.

## Scope

This is a test-status feature for the existing local BLE prototype. It does not implement automatic Mac locking, actual lock-state detection, automatic unlocking, authenticated pairing, notifications, a graph, or App Store distribution.
