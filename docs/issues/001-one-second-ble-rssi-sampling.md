# Issue 001: Sample BLE signal about once per second

- **Status:** Open — GitHub issue [#1](https://github.com/hornley/near-but-far/issues/1); planned, not implemented
- **Area:** Mac challenge interval and iPhone RSSI reporting

## Problem

The Mac currently sends a BLE challenge every five seconds, and the iPhone reads RSSI after each challenge. The status screen can therefore take several seconds to reflect a signal change. The one-second countdown refresh only updates the display timer; it does not request a new signal reading.

## Proposed change

Change the connected challenge/RSSI sampling cadence from five seconds to about one second so the phone status responds sooner. This is a target cadence while the companion is active, not continuous measurement or a promise that iOS will deliver readings at that rate in the background. Keep the Mac's five-second missed-response/retransmit timeout and the phone's ten-second no-challenge fallback unchanged; those timers detect loss and are separate from the sample cadence.

Keep the approved `-70 dBm` experimental threshold and 60-second “Would lock” countdown. Do not change the five-second Mac missed-response/retransmit timeout or the ten-second phone fallback as part of this issue; record any evidence for revisiting them as a separate follow-up. Do not add automatic Mac locking.

## Acceptance criteria

- While the iPhone app is active and connected, Mac challenges and resulting RSSI readings arrive at roughly one-second intervals.
- A transition across `-70 dBm` appears on the phone promptly; a stronger sample clears the countdown, and the countdown still expires once after 60 seconds of sustained loss.
- A missed response still starts the Mac's loss timer after five seconds; the same challenge is retried on that five-second timeout, and the phone's no-challenge fallback remains ten seconds.
- Test the cadence with the iPhone in the background and locked, and document any iOS throttling or suspension.
- Compare battery and CPU use against the current five-second cadence.
- Repeat physical threshold, recovery, disconnect, and Bluetooth-unavailable checks. RSSI remains a relative signal reading, not a distance measurement.

## Notes

One-second sampling is near-live feedback, not true real-time BLE. RSSI can fluctuate around the threshold; record that behavior during trials before deciding whether the test should add filtering or hysteresis.
