# iPhone Pairing Connection Diagnostics Implementation Plan

> **For agentic workers:** Use `workflow-implementation` to execute this plan. Delegate all coding tasks to the assigned implementation worker. Keep the coordinator responsible for branch integration, physical-device operations, and shared app state.

**Approved specification:** [iPhone Pairing Connection Status and Error Evidence](../specs/2026-11-27-iphone-pairing-connection-status-design.md), approved by the user on 2026-11-27.

**Issue:** [#2 — Add secure pairing and Mac monitoring controls; gate remote lock](https://github.com/hornley/near-but-far/issues/2). Issue #2 remains open for its broader scope.

**Goal:** Show the actual iPhone enrollment phase, capture CoreBluetooth connection error domain and code locally, then use that evidence to fix the fresh-pairing failure without changing the one-time Mac approval policy.

**Architecture:** `PhoneCentral` owns CoreBluetooth connection and write completion. `PeerSession` marks when it has generated the encrypted `pairingPrepared` enrollment request, so the phone can distinguish that request from the earlier Noise handshake writes. The iPhone pairing view reflects the phase. The Mac continues to present approval only after its existing authenticated candidate event. The current issue is upstream of that event: the phone recorded repeated `connect_failed` callbacks and no successful connection.

**Tech stack:** Swift 5, SwiftUI, CoreBluetooth, the existing Snow-backed `PeerSession`, Xcode, macOS 14 and iOS 17 minimums. Use the shared `NearButFarMac` and `NearButFarPhone` schemes.

## Current evidence and Mac-side check

- `PhoneCentral.acceptScannedPayload` currently changes the pairing state to `.waitingForMacApproval` before the BLE connection and secure request have completed.
- `didFailToConnect` currently records only `connect_failed` and drops the supplied `Error`.
- The Mac approval view is reached only after an authenticated pairing candidate arrives. A connection failure before that event explains why the phone waited while the Mac showed no request.
- `Sources/Mac/Info.plist` contains `NSBluetoothAlwaysUsageDescription`. The shared `NearButFarMac` Xcode scheme exists and references the `NearButFarMac` target. Prior runtime evidence showed Bluetooth powered on and the Mac advertising.
- There is no current evidence that the Mac privacy string or scheme caused the missing request. Keep Mac permission, entitlement, signing, and scheme edits out of this implementation unless new device evidence identifies one as the cause; a change outside the approved scope returns to `workflow-spec` first.

## Branch and ownership

- Work in an isolated implementation worktree based on the approved pairing branch.
- Before source edits, reconcile the branch with the latest `origin/main`; it is currently two commits behind. Preserve the pairing spec and plan during integration.
- The root main checkout has separate user signing edits in `NearButFar.xcodeproj/project.pbxproj`. Do not overwrite, stage, or import those edits as part of this work.
- Do not edit app icon assets or Xcode signing settings. The approved behavior change does not require new Xcode file membership.
- Coding owner: implementation worker, GPT 6 Luna, Medium reasoning. Review owner: independent reviewer, GPT 6.1 Sol, Low reasoning. Coordinator owns physical device use, app installation, branch integration, and the shared pairing attempt.
- Do not add or run automated tests for this plan. Validate with builds and the physical pairing flow.

## Dependency order

```text
Task 1: Sync branch
    ├── Task 2: Phone status and local error diagnostics
    └── Task 3: Static Mac permission/scheme confirmation (read-only)
              \                 /
               Task 4: Build and install diagnostic apps
                         ↓
               Task 5: Reproduce and read phone log
                         ↓
               Task 6: Evidence-based transport correction (if indicated)
                         ↓
               Task 7: Integrated review
                         ↓
               Task 8: Final build, install, and physical pairing verification
```

Tasks 2 and 3 can proceed together after Task 1 because Task 3 is read-only and owns no editable files. Device actions and pairing attempts remain coordinator-owned and sequential.

## Tasks

### Task 1: Reconcile the implementation branch

**Owner:** Coordinator. **Dependencies:** None. **Files:** Git branch state only; retain the approved spec and plan.

- Bring the pairing branch up to date with `origin/main` before code work.
- Resolve any conflict while preserving the approved spec and the branch's existing commits.
- Confirm the root main checkout's signing edits remain untouched.

**Acceptance criteria:** The implementation worktree contains the latest main changes and the approved pairing documents, with no unrelated signing or icon changes.

### Task 2: Make phone pairing status truthful and retain error metadata

**Owner:** Coding worker — GPT 6 Luna, Medium reasoning. **Dependencies:** Task 1. **Files:** `Sources/Shared/PeerSession.swift`, `Sources/iOS/PhoneCentral.swift`, `Sources/iOS/PairingScannerView.swift`, `Sources/iOS/NearButFarPhoneApp.swift`, and `Sources/iOS/RecentActivityView.swift` only if existing presentation needs to render the new state or fields.

- Add a connecting phase for an accepted QR and keep it active through scanning, connection, service and characteristic discovery, Noise handshake, and writes for the secure enrollment request.
- Expose from `PeerSession` when the encrypted `pairingPrepared` request has been generated. Do not infer this boundary from an empty write queue after the earlier handshake writes.
- Transition both the pairing state and connection-status text to **Waiting for Mac approval** only after CoreBluetooth reports successful writes for every fragment queued for that request. Keep both connecting until then.
- On `didFailToConnect`, append the error domain and numeric code to the existing local activity log. Keep the existing 200-event limit and do not log QR payloads, secrets, identity keys, or other pairing material.
- Preserve retry behavior, pairing identity rules, session authentication, and the Mac's authenticated-candidate approval gate.

**Acceptance criteria:** The QR flow displays **Connecting to Mac** throughout the Noise handshake and until all fragments of the encrypted `pairingPrepared` request receive successful write callbacks; only then do both pairing status surfaces display **Waiting for Mac approval**. A failed connection log contains domain and numeric code and no pairing secrets. Existing behavior outside this phase remains unchanged.

### Task 3: Confirm Mac Bluetooth configuration

**Owner:** Coordinator or read-only reviewer. **Dependencies:** Task 1; may run alongside Task 2. **Files:** Read only: `Sources/Mac/Info.plist`, `NearButFar.xcodeproj/xcshareddata/xcschemes/NearButFarMac.xcscheme`, Mac target build settings, and existing Mac Bluetooth activity state.

- Confirm the shared `NearButFarMac` scheme references the Mac target and `Sources/Mac/Info.plist` contains the Bluetooth usage description.
- Do not reset TCC state or change entitlements, Info.plist, signing, or scheme settings without evidence and an approved spec revision.

**Acceptance criteria:** The shared scheme targets the Mac app and the Bluetooth usage-description key is present. Runtime permission and advertising are confirmed during Task 4.

### Task 4: Build and install diagnostic versions

**Owner:** Coordinator. **Dependencies:** Tasks 2 and 3. **Files:** Build products only.

- Build the `NearButFarMac` scheme for macOS and install/launch it using the existing signing identity.
- Build the `NearButFarPhone` scheme for the connected physical iPhone, `roasted ginger` (iPhone 15 Pro Max, UDID `1F42F0DE-CE66-5720-83BB-29705BEB4EF3`), and install/launch it.
- Keep app icons and signing configuration unchanged.

**Acceptance criteria:** Both updated apps launch. CoreBluetooth reports powered on and the Mac advertises; otherwise record the denied/unavailable state as diagnostic evidence. The phone's pairing screen can display the connecting phase.

### Task 5: Reproduce once and inspect local evidence

**Owner:** Coordinator; physical-device state is shared. **Dependencies:** Task 4. **Files:** Existing local iPhone activity log only; no source edits.

- Start a fresh one-use QR on the Mac and scan it with the unlocked iPhone.
- Observe the Mac and phone UI through the connection attempt.
- Read the phone's local recent-activity entries and capture the error domain/code plus adjacent connection events. Do not copy pairing secrets into notes or issue comments.

**Acceptance criteria:** The phone remains in **Connecting to Mac** until the secure request is sent. The local log supplies the concrete CoreBluetooth error for the failed phase, or successful request writes transition to **Waiting for Mac approval** and produce the existing Mac candidate event.

### Task 6: Correct the evidenced transport cause

**Owner:** Coding worker — GPT 6 Luna, Medium reasoning. **Dependencies:** Task 5. **Files:** Only the source file(s) proven relevant by the captured error, expected to be within `Sources/iOS/PhoneCentral.swift`, `Sources/Mac/MacPeripheral.swift`, `Sources/Shared/BLEProtocol.swift`, or `Sources/Shared/PeerSession.swift`.

- Trace the recorded failure to its first failing boundary and make the narrowest correction consistent with the approved spec.
- Keep the QR format, setup-secret lifetime, identity storage, authenticated protocol, one-time approval behavior, established reconnect flow, icons, and signing settings unchanged.
- If the evidence points to an unapproved Mac permission/entitlement/signing change, QR or key-storage change, or protocol redesign, stop and return through `workflow-spec` rather than expanding this task.

**Acceptance criteria:** The root cause is named with the observed error evidence. The fix permits the secure enrollment request to reach the Mac while retaining existing authentication and approval gates.

### Task 7: Review and integrate the complete change

**Owner:** Independent reviewer — GPT 6.1 Sol, Low reasoning; coordinator integrates. **Dependencies:** Task 6. **Files:** Read-only review of all changed source and documentation files.

- Review state timing, callback ordering, stale callback handling, local-log privacy, retry behavior, and the unchanged one-time approval gate.
- Check the complete diff for accidental icon, signing, QR, identity, or unrelated changes.
- Resolve findings in the implementation task and re-review the corrected diff before device verification.

**Acceptance criteria:** No unresolved correctness or scope findings remain in the integrated diff.

### Task 8: Build, install, and verify fresh pairing on both devices

**Owner:** Coordinator. **Dependencies:** Task 7. **Files:** Build products and this plan's execution record.

- Rebuild and install both `NearButFarMac` and `NearButFarPhone` after integration.
- On the physical iPhone and Mac, perform a fresh QR pairing and approve it once on the Mac. Confirm authenticated pairing completes on both devices.
- Reconnect using the saved identity and confirm it does not ask for Mac approval again.
- If the pairing still fails, preserve the phone's local error evidence and do not claim end-to-end success. Record verified results and remaining limits in the execution record below; do not restore the project handoff removed by the public-sharing change.

**Acceptance criteria:** Both targets build and launch; fresh pairing reaches and completes the single Mac approval; normal authenticated reconnect does not show another approval request; the execution record reports only observed device results.

## Final review checklist

- The UI reports **Connecting to Mac** through the Noise handshake and until successful writes for the encrypted `pairingPrepared` request, then reports **Waiting for Mac approval**.
- Failed connection records include CoreBluetooth domain and numeric code locally without pairing secrets.
- Mac approval remains tied to the existing authenticated candidate event and happens once for a new/replacement phone.
- Mac permission, scheme, signing, app icons, QR format, identity storage, and secure protocol are unchanged unless a separately approved spec says otherwise.
- Both Mac and physical iPhone builds/installations and the fresh-pair/reconnect behavior are recorded with actual outcomes.

## Execution record

- **Branch sync:** merged `origin/main` at `a3cea5a` via merge commit `f12acb4`. The upstream public-sharing cleanup was preserved, including removal of `docs/project-handoff.md` and hard-coded iPhone team settings. The separate root main checkout's staged Xcode project edit remains untouched.
- **Mac configuration:** `xcodebuild -list` reports the `NearButFarMac` scheme and target. The shared scheme references that target, and `Sources/Mac/Info.plist` contains `NSBluetoothAlwaysUsageDescription`. The Mac's Bluetooth TCC permission remains allowed (`kTCCServiceBluetoothAlways`, `auth_value=2`). The installed app logged Bluetooth on and advertising; after the `bluetoothd` restart it again logged `Bluetooth resetting…`, `Bluetooth on`, and `advertising_started` at `2026-11-27T17:38:06Z` through `17:38:08Z`. The Mac Bluetooth permission and Keychain permissions were not reset.
- **Physical iPhone availability:** `xcrun devicectl list devices` reports `roasted ginger`, iPhone 15 Pro Max (`1F42F0DE-CE66-5720-83BB-29705BEB4EF3`), as connected.
- **Build/install:** The signed `NearButFarMac` app and physical-device `NearButFarPhone` app were rebuilt and installed from this worktree. The Mac app icon and iPhone asset catalog remain present. For this PR, `NearButFarMac` built for macOS and `NearButFarPhone` built for iOS Simulator with code signing disabled; both builds succeeded. No automated tests were run, consistent with this plan.
- **Failure evidence:** After the Mac-side saved `Hornley` entry was forgotten, the next phone attempts still failed with `CBErrorDomain code=15` from `2026-11-27T17:50:42Z` to `17:50:55Z`. At the matching local time, Mac `bluetoothd` logged a successful LE connection followed by encryption status 761, a MIC failure, and “Bad or missing keys, re-cloud pairing.”
- **Physical pairing recovery:** The user removed the saved `hornley` Mac entry from the iPhone's Bluetooth settings. The phone then logged `scan_started` at `2026-11-27T17:58:17Z`, `connected` at `17:58:18Z`, and `authenticated_session_ready` at `17:58:24Z`. The Mac recorded acknowledgements beginning at `17:58:25Z` and continuing through at least `17:59:58Z`. This confirms authenticated physical pairing after clearing the iPhone-side saved Bluetooth relationship.
- **Coordinator ownership:** The app-lifetime experiment was reverted. Current source and installed Mac app own `MacCoordinator` in `MacMenuBarPanel` as a `@StateObject`; the controller retains the hosting controller. The successful pairing followed removal of the iPhone-side saved Bluetooth entry, so no coordinator ownership change was needed to resolve the failure.
- **Remaining verification:** Reconnect using the saved app identity without another Mac approval has not been separately tested. Issue #2 remains open for its broader lock-capability scope.

Update this section only with observed branch, build, installation, diagnostic-log, and physical-pairing results. Do not include QR payloads, setup secrets, or identity keys.
