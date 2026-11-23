# Near But Far

Near But Far is a local macOS menu-bar app and iPhone companion. The current branch implements one-use QR pairing, authenticated BLE presence, and a status-first interface. It does **not** lock or unlock the Mac; the app cannot yet confirm the Mac's secure lock state.

## Current behavior

- The Mac displays a one-use QR pairing offer that expires after two minutes. The Mac user approves the phone locally before its identity is saved.
- Each device keeps its long-lived identity in device-only Keychain storage. Reconnection uses authenticated, encrypted BLE messages; the QR secret is erased after pairing, cancellation, or expiry.
- The Mac has a persistent presence-monitoring preference. Enabling it, relaunching the app, or recovering from Bluetooth loss waits for fresh authenticated presence. Session and countdown state are not restored from disk.
- The Mac owns a persisted signal threshold, defaulting to `-70 dBm` and adjustable from `-90` to `-50 dBm`. It sends the threshold over the authenticated session; the iPhone stores the last authenticated value and displays it read-only. RSSI is not distance.
- The iPhone keeps its local presence estimate separate from Mac monitoring readiness and the Mac lock-state observation. It labels the threshold as current only after receiving it in the secure session, otherwise showing the last synced or waiting state.
- Recent activity is available from the iPhone menu and shows events stored locally on the phone.
- Lock now and Unlock stay disabled. Presence monitoring is informational and does not protect or lock the Mac.
- The app targets macOS 14 and iOS 17. Snow 0.10.0 is linked through a reviewed Rust C ABI integration spike. Trail of Bits validated eight remediations included in the tag; the exact release was not fully audited, and two informational findings were not among those fixes.

## Build and run

1. Run `Rust/NearButFarSession/build-xcframework.sh` from the repository root. The first run needs network access to install the Rust targets and Cargo dependencies.
2. Open `NearButFar.xcodeproj` in Xcode and run `NearButFarMac` on the Mac.
3. Run `NearButFarPhone` on an iPhone. Choose a signing team and grant Bluetooth and camera access when asked.
4. Open **Settings** from the Mac menu bar panel and select **Pair iPhone**. Scan the one-use QR in the iPhone app, then approve the pairing request on the Mac.
5. Turn on presence monitoring in the Mac menu. The app reports only authenticated presence; Lock now and Unlock remain unavailable.

The simulator can check compilation and the status screen, but it cannot validate BLE range, QR pairing across devices, or iOS background behavior. The Mac's local CSV log is at `~/Library/Application Support/NearButFar/ble-log.csv`; the phone keeps a local BLE event log.

## Validation status

- The monitoring-epoch regression check passes: challenge IDs continue increasing, so an old delayed acknowledgement cannot count as fresh presence after monitoring resumes.
- Rust tests and the Xcode test scheme pass; the Mac and iPhone simulator targets build. The signed iPhone app was installed and launched on `roasted ginger`.
- The status-first unavailable screen was visually reviewed in the simulator. Physical QR enrollment, pairing recovery, monitoring behavior, and one-second cadence still need a device walkthrough before relying on background presence.
- The user-reported overnight locked-phone run remains uninstrumented; exact duration and missed-response telemetry were not recorded. Ten varied-orientation range trials, Bluetooth-unavailable checks, and the exact 60-second boundary ordering also remain pending.
- Issue #2 remains open while the supported macOS lock request and trustworthy lock-state confirmation are unresolved.

See [the approved design](docs/superpowers/specs/2026-11-23-near-but-far-app-design.md), [Issue #1 notes](docs/issues/001-one-second-ble-rssi-sampling.md), [Issue #2 plan](docs/superpowers/plans/2026-11-23-issue-2-pairing-monitoring.md), and [status-first UI plan](docs/superpowers/plans/2026-11-23-status-first-ui-ux.md).

## Prototype evidence

The earlier unauthenticated prototype recorded 1,834 acknowledgements from `-84` to `-28 dBm`, three missed responses, nine weak-signal events, ten recoveries, and three log-only `would_lock` events at 60 seconds. A later `-70 dBm` sample recovered at the same whole-second timestamp as expiry, so the order remains unresolved. These logs are historical feasibility evidence; unauthenticated prototype traffic is not used as application presence and never locks the Mac.
