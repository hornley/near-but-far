# Issue 001: Sample BLE signal about once per second

- **Status:** Implementation present on this branch; physical-device validation pending. GitHub issue [#1](https://github.com/hornley/near-but-far/issues/1) remains open.
- **Area:** Mac challenge interval and iPhone RSSI reporting

## Problem

The Mac currently sends a BLE challenge every five seconds, and the iPhone reads RSSI after each challenge. The status screen can therefore take several seconds to reflect a signal change. The one-second countdown refresh only updates the display timer; it does not request a new signal reading.

## Proposed change

The implementation targets a new challenge and fresh RSSI read about once per second while the companion is active. The Mac's five-second missed-response timeout and same-sequence retry interval remain unchanged, as does the phone's ten-second no-challenge fallback. These timers detect loss and are separate from the sample cadence. iOS may throttle or suspend background work, so one-second sampling is not guaranteed when the app is backgrounded or the phone is locked.

Keep the approved `-70 dBm` experimental threshold and 60-second “Would lock” countdown. Do not change the five-second Mac missed-response/retransmit timeout or the ten-second phone fallback as part of this issue; record any evidence for revisiting them as a separate follow-up. Do not add automatic Mac locking.

The transport permits one RSSI read at a time. Each acknowledgement uses the RSSI returned for its challenge; unavailable readings are reported as unavailable rather than reusing a cached value. The implementation does not claim protection or provide locking.

## Acceptance criteria

- While the iPhone app is active and connected, the implementation schedules new Mac challenges roughly once per second and reads RSSI serially, with no overlapping reads or stale/cached samples.
- A transition across `-70 dBm` appears on the phone promptly; a stronger sample clears the countdown, and the countdown still expires once after 60 seconds of sustained loss.
- A missed response still starts the Mac's loss timer after five seconds; the same challenge is retried on that five-second timeout, and the phone's no-challenge fallback remains ten seconds.
- **Pending physical validation:** observe active connected challenge and RSSI cadence, verify threshold/recovery, five-second Mac loss and retry behavior, and the ten-second phone fallback on devices.
- **Pending physical validation:** test with the iPhone backgrounded and locked; record iOS throttling or suspension.
- **Pending physical validation:** compare battery and CPU use against the former five-second cadence, and repeat physical threshold, recovery, disconnect, and Bluetooth-unavailable checks.
- **Pending physical validation:** complete the 30-minute locked-phone run and varied-range checks.
- RSSI remains a relative signal reading, not a distance measurement. No protection or locking behavior is claimed.

## Notes

One-second sampling is near-live feedback, not true real-time BLE. RSSI can fluctuate around the threshold; record that behavior during trials before deciding whether the test should add filtering or hysteresis.
