# BLE prototype results and next-step handoff

This note carries the physical-device results into the next thread for the actual Near But Far app. The user has chosen to proceed with app work using these results. This does not mean every prototype acceptance check has passed.

## What the prototype showed

- The Mac and iPhone apps exchanged BLE challenges, acknowledgements, and RSSI samples on physical devices.
- The user saw RSSI around `-40` to `-55 dBm`, varying with distance and obstructions, and reports that the connection kept working while the iPhone app was in the background. The user now reports leaving the app on overnight with the iPhone locked and considers the 30-minute background check complete. The exact elapsed time and connection telemetry were not recorded, so treat this as user-reported rather than a measured pass.
- The user reports that the experimental `-70 dBm` countdown, recovery to **Nearby**, phone-side 60-second **Would lock** status, and iPhone Bluetooth off/on recovery worked. After Bluetooth returned, the Mac UI went from **Waiting for iPhone** to **iPhone subscribed**.
- The Mac CSV snapshot ending `2026-11-22T19:24:07Z` contained 1,834 acknowledgements with RSSI from `-84` to `-28 dBm`; three missed responses were followed by an acknowledgement within 11 seconds; and it contained nine `weak_signal`, ten `signal_recovered`, and three `would_lock` rows.
- The three `would_lock` rows report `elapsed_seconds=60` at `19:12:03Z`, `19:15:03Z`, and `19:19:43Z` on 2026-11-22. Each followed a weak sample at or below `-70 dBm` that persisted through expiry. Whole-second log timestamps place these rows 61 seconds after their weak-signal starts.
- The CSV also records a weak sample of `-76 dBm` recovering to `-47 dBm` 15 seconds later (sequences 153 and 156), as well as multiple other recoveries before expiry.

## Limits and unresolved checks

- RSSI is a rough signal-strength sample, not a distance measurement. The `-70 dBm` threshold is experimental and is not a reliable physical boundary.
- A weak sample at `19:20:17Z` recovered from `-70` to `-67 dBm` at `19:21:17Z` with no `would_lock` row. The CSV has one-second timestamp precision, so it cannot establish whether the recovery or expiry check ran first at the exact 60-second boundary.
- The phone's **Would lock** display and Mac `would_lock` log are estimates only. The prototype never locks or unlocks the Mac. Its public BLE service is unauthenticated and is not safe as a production presence credential.
- Still to check during actual app validation: walking out of range before a weak RSSI sample; the iPhone **Unavailable** state with Bluetooth off; Mac monitoring behavior with Mac Bluetooth off; repeated range/return trials in varied orientations and through walls; and how RSSI flickers around the threshold.
- The user reports an overnight background run with the iPhone locked and considers the 30-minute check complete. No exact duration or missed-response log evidence was captured. This report does not validate the current one-second sampling build; verify that build separately when the physical phone is available.

## Guidance for the actual app

- Reuse the prototype as BLE feasibility evidence, not as proof of authenticated pairing, reliable distance measurement, or a working macOS lock operation.
- Keep **actual lock/unlock and secure pairing** as a separate safety design. Do not automatically unlock when the phone returns. Do not treat this prototype's unauthenticated BLE signal as proof of identity.
- Before relying on automatic locking, carry out the remaining connection-loss, Bluetooth-unavailable, boundary, and repeatability checks above. The overnight locked-phone run is user-reported, but its exact duration and telemetry remain unverified.
- Follow [issue #1](https://github.com/hornley/near-but-far/issues/1) for the proposed one-second RSSI sampling change and [issue #2](https://github.com/hornley/near-but-far/issues/2) for the Mac monitoring toggle and manual iPhone lock controls.

See [the product spec](../spec.md), [the prototype validation README](../README.md), and [the phone-presence implementation plan](superpowers/plans/2026-11-23-phone-presence-status.md) for full details.
