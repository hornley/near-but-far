# iPhone pairing encryption timeout: findings and recovery

Date: 2026-11-28
Related issue: [#2](https://github.com/hornley/near-but-far/issues/2)
Status: pairing recovered after removing the iPhone's saved Bluetooth entry for the Mac. No Mac app permission reset was needed.

## Observed failure

After scanning a fresh Mac QR, the physical iPhone stays at **Connecting to Mac**. The Mac shows no incoming approval request.

The phone records repeated `connect_failed domain=CBErrorDomain code=15` events, without a successful `connected` event during the failed attempts. The installed iPhoneOS SDK maps code 15 to `CBErrorEncryptionTimedOut`.

The failure occurs before service discovery and the app's secure enrollment handshake. The Mac approval card requires an authenticated enrollment request, so it cannot appear at this stage. The corrected phone status now reflects that boundary.

## Correlated system evidence

On the Mac, the app recorded Bluetooth on and advertising started at **2026-11-27 22:53:35 Asia/Manila (14:53:35 UTC)**. The system Bluetooth daemon then recorded:

| Mac local time | Evidence |
| --- | --- |
| 22:53:41.249 | `Failed to encrypt connection STATUS 761. (status=65535)` |
| 22:53:41.251 | Disconnected from the physical iPhone due to `MIC failure` |
| 22:53:41.252 | `Bad or missing keys, re-cloud pairing` |
| 22:53:44–52 | The same failure sequence repeats |

The phone recorded encryption-timeout failures at **14:53:42, 14:53:45, 14:53:49, and 14:53:52 UTC**, matching this sequence. Device identifiers are omitted here.

These records strongly implicate the system Bluetooth pairing/encryption state between the Mac and iPhone. They do not establish which device has incorrect keys, why the state changed, or whether a Bluetooth restart will repair it. Status 761 is preserved as observed rather than assigned an undocumented meaning.

After the Mac Bluetooth cycle, the user was advised to cycle iPhone Bluetooth and scan a fresh code, then reported scanning. The phone logged `connect_failed domain=CBErrorDomain code=15` at `2026-11-27T15:23:41Z` and repeatedly from `15:25:39Z` through `15:26:00Z`. At the matching Mac local times (`23:23:33` through `23:25:59`, UTC+08), `bluetoothd` again reported `Failed to encrypt connection STATUS 761`, `MIC failure`, and `Bad or missing keys, re-cloud pairing`. The phone log does not confirm whether its Bluetooth radio was toggled off and back on, and the reported scan did not repair the connection.

## Mac Bluetooth permission check

- `Sources/Mac/Info.plist` contains `NSBluetoothAlwaysUsageDescription`; the bundle identifier is `com.nearbutfar.mac`.
- `MacPeripheral` creates a `CBPeripheralManager`. macOS manages permission prompting; the app has no separate custom permission dialog.
- `peripheralManagerDidUpdateState` handles `.unauthorized` and reports **Bluetooth access denied — monitoring unavailable**.
- A read-only check of the user's TCC database found `kTCCServiceBluetoothAlways` for `com.nearbutfar.mac` with `auth_value=2` (allowed).
- TCC runtime logs show authorization checks for the installed app. Its runtime activity confirms Bluetooth on and successful advertising startup.
- The installed Mac app is signed with an Apple Development identity. The source's notify/write characteristics do not request GATT encryption permissions.

Once permission is saved, a prompt on every launch is not expected. The reason earlier builds repeatedly prompted is undetermined; the absence of a new prompt does not indicate permission denial. Resetting privacy permission is not supported as a fix by the current evidence.

## Keychain authorization prompt

The screenshot shows macOS asking `NearButFarMac` to access a generic-password item in the `com.nearbutfar.identity` Keychain service. That service is used by `MacPairedIdentityStore` for the Mac's local private pairing identity (`mac-local-v1`) and, when present, the paired phone identity (`paired-phone-v1`). The screenshot names the service but not the account, so it does not identify which item triggered this particular prompt.

The current Pair iPhone action first checks for a saved phone identity, then loads or creates the Mac's local identity and creates the one-use pairing offer. A Keychain denial or read failure on this path prevents the QR from being created; the UI should show **Could not create a secure pairing code. Check Keychain access and try again.** At app launch, the coordinator checks the paired-phone item, but the local private identity is read when pairing starts. This makes the prompt relevant to starting enrollment and displaying a fresh QR.

If a QR is visibly displayed by the current Mac process, its identity read and offer creation succeeded for that attempt, so Keychain authorization is not blocking that QR. The iPhone activity copied for this check has no explicit `qr_accepted` event, so it cannot confirm whether the post-relaunch connection failures followed that QR.

The Keychain prompt and Bluetooth permission are separate macOS authorizations. If this prompt is denied, it can explain failure to create the QR, but it does not explain `CBErrorEncryptionTimedOut` once CoreBluetooth attempts a radio connection. The phone's recorded failures and the earlier Mac `bluetoothd` MIC/key errors occur at the Bluetooth encryption layer before the app handshake. A later phone attempt after the coordinator-lifetime build was launched is described below; no matching Mac system-log rows were available for that attempt.

The current installed app is signed as `com.nearbutfar.mac` with Apple Development team `L4J95GK2UU`, CDHash `242502dec403ae99f9fa8b2128431e24b853d128`. The existing Keychain ACL metadata includes older app hashes and a partition entry for this same team. This makes app authorization history a reasonable explanation for why Keychain asked again, but it does not establish the exact cause of the prompt or show that the current app was denied. The source currently maps Keychain errors to a generic unavailable status and does not log the underlying `OSStatus`, so there is no app-side record here to distinguish denial from another Keychain failure.

Do not share the login keychain password in chat. If this dialog appears again, verify that its requesting app is the installed Near But Far app before deciding whether to allow access. **Always Allow** is the Keychain choice for persisting that app's access to this item, which can stop repeat prompts; it only addresses Keychain authorization, not Bluetooth code 15. No Keychain item was deleted or reset during this investigation.

## Review of previous changes

- Issue #13's slider commits (`5a90a9e`, `d75d689`) do not change Bluetooth transport or pairing.
- The right-click Quit change (`533a762`) moved `MacCoordinator` ownership from the app into the hosted popover view. This can delay Bluetooth initialization until the view loads. The hosting controller and popover are retained when closed; source inspection did not establish coordinator destruction on close. The correlated attempt confirms advertising had started before the failure, so this change is not established as the cause.
- Core BLE connection/characteristic code has no committed changes after `18b02fe` on November 25. That commit only reordered Bluetooth-state event delivery in `MacPeripheral` relative to its previous version.
- The current diagnostic changes correct phone status timing and retain error domain/code. Connection failures predate those changes.
- The public-sharing cleanup (`782431e`) removed the saved iPhone development team after failures had already begun.

### Relevant history audit

- `533a762` replaced SwiftUI `MenuBarExtra` with a custom status item. It put `MacCoordinator` in the popover panel's `@StateObject`, which could defer Bluetooth initialization until the panel was evaluated. This was a plausible Mac lifecycle regression. A later experiment moved the coordinator into the app-retained controller; the installed process logged advertising at launch, but did not resolve the phone's pre-`didConnect` encryption timeout.
- `0afe92e` changed the Mac product/executable name to **Near But Far** and restored the Mac/iPhone icons. A product/signing change can affect whether macOS asks for Keychain authorization, but it does not change BLE transport. The screenshot was from another version, so its displayed app name cannot identify the current process.
- `782431e` removed `DEVELOPMENT_TEAM` from the iPhone target settings. The Bluetooth failures were already present before that commit. A signing/team mismatch could affect Keychain access to the iPhone's saved identity, but it would not produce the recorded CoreBluetooth encryption timeout. The phone's log reaches `scan_started` and `connect_failed`, so secure storage did not stop those attempts.
- The Issue #13 commits only change the slider mapping. The authenticated Mac battery message adds a record type used after a secure session is established. Neither change runs before the link-encryption failure. No committed change after the earlier pairing implementation changed the BLE service UUID, GATT characteristic permissions, or the phone's CoreBluetooth connect call.

### Installed build check

- Mac: the running process is PID 47111 from `/Users/hornley/Applications/Near But Far.app/Contents/MacOS/Near But Far`. Its signature is Apple Development team `L4J95GK2UU`, CDHash `aa3787847316f6458d50d949fbeb15ad2c709a72`, signed at `2026-11-28 01:19:40` (+08:00). It launched at `01:23:04` after installation. Its executable hash matches the fresh Debug build. The installed icon resource is present, and the app log records Bluetooth on and advertising at `01:24:13`.
- iPhone: `devicectl` sees **Near But Far 1.0 (1)** installed at `com.nearbutfar.phone`, and process 10588 is running it. The fresh Debug build installed successfully to the physical iPhone over its connected Xcode device tunnel. `devicectl` does not expose a binary hash; version/build labels remain `1.0 (1)`.
- Both current Debug targets built successfully from this worktree with team `L4J95GK2UU`. The Mac icon resource and iPhone compiled asset catalog are present. The earlier Mac build failure was due to a temporarily full volume; at this build it had 14 GiB free. No existing DerivedData or iOS DeviceSupport caches were deleted, and the root main checkout's staged project edit was left untouched.

### Mac coordinator reversion

The worktree source and newly installed Mac app now restore the original ownership: `MacMenuBarPanel` creates `MacCoordinator` with `@StateObject`, and `MacMenuBarController` no longer owns or injects it. This is the build currently running on the Mac.

## Coordinator lifetime experiment

An earlier experiment moved `MacCoordinator` from `MacMenuBarPanel`'s `@StateObject` into the app-retained `MacMenuBarController`. Spec-compliance, code-quality, and final reviews passed for that experiment. It was subsequently reverted; that app-lifetime variant is no longer installed.

The current restored Mac build and iPhone diagnostic build both built and installed successfully. The Mac app launched and logs Bluetooth on and advertising. A later fresh QR attempt against the reverted build still failed before application connection because of a CoreBluetooth encryption error; the confirmed recovery is recorded below.

## Confirmed recovery

The Mac's saved Bluetooth entry for the iPhone (`Hornley`) was forgotten first. A subsequent fresh attempt still failed: the phone logged `connect_failed domain=CBErrorDomain code=15` from `2026-11-27T17:50:42Z` through `17:50:55Z`. At the matching local time, Mac `bluetoothd` recorded a successful LE connection followed by encryption status 761, a MIC failure, and “Bad or missing keys, re-cloud pairing.” The `Hornley` entry was absent from the Mac's saved Bluetooth devices list.

The user then removed the saved Mac entry (`hornley`) from the iPhone's Bluetooth settings and reported that this fixed pairing. The phone log confirms the transition: `scan_started` at `2026-11-27T17:58:17Z`, `connected` at `17:58:18Z`, and `authenticated_session_ready` at `17:58:24Z`. The Mac received acknowledgements beginning at `17:58:25Z` and continuing through at least `17:59:58Z`. This confirms a working authenticated session after clearing the iPhone-side saved Bluetooth relationship. The exact internal key state that caused the MIC failure is not exposed by these logs.

## Verification and remaining work

- The currently running Mac process (PID 47111) is the newly installed build, signed with team `L4J95GK2UU`; its source restores coordinator ownership to `MacMenuBarPanel`.
- The Mac's Bluetooth TCC permission remains allowed (`kTCCServiceBluetoothAlways`, `auth_value=2`). Neither the Mac Bluetooth permission nor Keychain permissions were reset.
- Restarting `bluetoothd` and forgetting the saved Mac-side `Hornley` entry did not fix the connection by themselves. Removing the saved Mac entry on the iPhone did; the physical logs then showed connection, authenticated session readiness, and continuing Mac acknowledgements.
- The app's saved identity reconnect without another approval has not been separately verified.
- No app identity was deleted, and no signing, icon, or source-code change was made as part of the recovery.

Related documents: [approved design](../superpowers/specs/2026-11-27-iphone-pairing-connection-status-design.md) and [implementation plan](../superpowers/plans/2026-11-27-iphone-pairing-connection-status.md).
