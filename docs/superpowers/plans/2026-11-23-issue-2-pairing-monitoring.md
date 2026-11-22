# Issue #2 Pairing and Monitoring Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `subagent-driven-development` or an equivalent task-by-task execution workflow to implement this plan.

**Goal:** Pair one iPhone securely, expose a persistent Mac monitoring preference, and represent lock capabilities without claiming or issuing an unverified lock.

**Architecture:** A shared authenticated session protects every operational BLE frame. `MacCoordinator` owns pairing, monitoring preference, and effective readiness; `MacPeripheral` and `PhoneCentral` remain transport adapters. This plan deliberately adds no executable Lock or Unlock message because the supported lock-and-confirmation capability is unresolved.

**Tech Stack:** Swift, CoreBluetooth, Core Image on macOS, AVFoundation on iOS, Security/Keychain, SwiftUI, Xcode targets for macOS 14 and iOS 17.

---

**Sequence:** Second phase, after [issue #1 sampling](2026-11-23-issue-1-rssi-sampling.md). The approved design is [Near But Far app design](../specs/2026-11-23-near-but-far-app-design.md). If no suitable maintained protocol library is found, stop this phase before implementing custom cryptography or retaining unauthenticated operational traffic.

## Files

- Create shared `Sources/Shared/PeerSession.swift` and `Sources/Shared/PeerIdentity.swift` for handshake/session messages and verified domain messages.
- Create `Sources/Mac/PairedIdentityStore.swift` and `Sources/Mac/PairingView.swift`; extend `Sources/Mac/MacCoordinator.swift` with pairing and monitoring ownership established in issue #1.
- Create `Sources/iOS/PairedIdentityStore.swift` and `Sources/iOS/PairingScannerView.swift`; extend `Sources/iOS/PhoneModel.swift` with authenticated peer and Mac-reported status.
- Modify `Sources/Shared/BLEProtocol.swift`, `Sources/Mac/MacPeripheral.swift`, and `Sources/iOS/PhoneCentral.swift` to carry bounded authenticated frames and route only verified messages to app policy.
- Modify `Sources/Mac/NearButFarMacApp.swift`, `Sources/iOS/NearButFarPhoneApp.swift`, and `Sources/iOS/Info.plist` for the monitoring control, pairing entry points, and camera usage text.
- Modify `NearButFar.xcodeproj/project.pbxproj` to add all new sources to the correct targets.

## Tasks

### Task 1: Select an existing protocol implementation

**Files:** No source changes until this gate passes.

- [ ] Compare maintained Swift libraries for a published authenticated handshake and encryption protocol. Confirm macOS 14 and iOS 17 support, license, maintenance, and test vectors.
- [ ] Record the selected library and its key/session APIs in the implementation change before writing the adapter.
- [ ] If no library qualifies, stop this plan. Keep pairing incomplete, effective monitoring unavailable, and all operational BLE messages disabled; do not invent a protocol or preserve the public frames as a fallback.

### Task 2: Add the shared verified-message boundary

**Files:** `Sources/Shared/PeerSession.swift`, `Sources/Shared/PeerIdentity.swift`, `Sources/Shared/BLEProtocol.swift`, `NearButFar.xcodeproj/project.pbxproj`

- [ ] Define the shared message model with pairing, challenge, acknowledgement, presence, and Mac status cases. Do not define Lock or Unlock cases.
- [ ] Keep message creation inside the session boundary:

```swift
struct VerifiedMessage {
    let peerID: UUID
    let sessionID: Data
    let message: PeerMessage
    fileprivate init(peerID: UUID, sessionID: Data, message: PeerMessage)
}

final class PeerSession {
    func receive(_ frame: Data) throws -> VerifiedMessage?
    func seal(_ message: PeerMessage) throws -> [Data]
    func invalidate()
}
```

- [ ] Bind protocol version, peer role, session identity, direction, and monotonically increasing frame counters into authenticated data. Reject malformed, oversized, wrong-role, stale, and replayed frames before returning a `VerifiedMessage`.
- [ ] Fragment ciphertext only after sealing. Reassemble with one explicit maximum message size, fragment count, buffer count, and timeout; reject incomplete or expired frames.
- [ ] Add the new shared files to the explicit Xcode project groups and targets.

### Task 3: Store identities and implement Mac enrollment

**Files:** `Sources/Mac/PairedIdentityStore.swift`, `Sources/Mac/MacCoordinator.swift`, `Sources/Mac/PairingView.swift`, `Sources/Mac/MacPeripheral.swift`, `Sources/Mac/NearButFarMacApp.swift`, `NearButFar.xcodeproj/project.pbxproj`

- [ ] Store the Mac private identity in the macOS Keychain. Do not log keys, pairing secrets, or encrypted frame contents.
- [ ] Add an explicit pairing action on the unlocked Mac. Generate a cryptographically random 256-bit one-use QR secret and a QR payload containing protocol version, the Mac’s public identity, and that secret; generate it with `CIQRCodeGenerator` and expire the pairing window after two minutes. Never place a private key in the QR.
- [ ] Complete the selected handshake with the scanning phone. Show the Mac a short fingerprint derived from the candidate public key for local approval; do not use the Bluetooth device name as identity. Save exactly one phone identity after approval. Consume and erase the QR secret on success, cancel, or expiry.
- [ ] Add **Forget phone** and replacement flow. Revoking or replacing a phone invalidates its session immediately; replacement requires explicit confirmation.
- [ ] Route operational notifications and writes only for the pinned `CBCentral`. A second or unauthenticated subscriber cannot replace the trusted phone.
- [ ] Keep `MacCoordinator` as the only owner of monitoring preference, pairing status, and effective readiness. Transport callbacks pass verified domain messages to it.

### Task 4: Implement iPhone enrollment and session storage

**Files:** `Sources/iOS/PairedIdentityStore.swift`, `Sources/iOS/PairingScannerView.swift`, `Sources/iOS/PhoneModel.swift`, `Sources/iOS/PhoneCentral.swift`, `Sources/iOS/Info.plist`, `NearButFar.xcodeproj/project.pbxproj`

- [ ] Add a SwiftUI QR scanner backed by `AVCaptureMetadataOutput` configured for QR codes. Add `NSCameraUsageDescription` explaining that camera access is used only to pair with the Mac.
- [ ] Store the phone identity in device-only Keychain storage accessible after first unlock (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`) so background CoreBluetooth callbacks can authenticate. A reinstall or replacement requires pairing again.
- [ ] Represent scanner states explicitly: unpaired, scanning, waiting for Mac approval, paired, expired, revoked, and camera unavailable. Give each failure a next step.
- [ ] Pass every received frame through `PeerSession`. Only verified presence/status messages update `PhoneModel`; a failed authentication never updates presence or readiness.

### Task 5: Add monitoring preference and safety states

**Files:** `Sources/Mac/MacCoordinator.swift`, `Sources/Mac/NearButFarMacApp.swift`, `Sources/Shared/PresenceTracker.swift`, `Sources/iOS/PhoneModel.swift`

- [ ] Persist only the monitoring preference in `UserDefaults`; keep session keys, active challenge, and countdown in memory.
- [ ] On enable, app launch, or Mac Bluetooth recovery, enter **Waiting for authenticated iPhone** and arm only after fresh authenticated presence. On disable, clear the countdown and pause automatic policy without unlocking or unpairing.
- [ ] On Mac Bluetooth unavailable, clear the active monitoring epoch and report unavailable, never away. After recovery, require fresh authenticated presence.
- [ ] With the current lock findings, report effective protection unavailable. Keep **Lock now** and **Unlock** disabled, add no lock/unlock wire cases, and send no lock request at countdown expiry; show **Lock unavailable**.
- [ ] Keep issue #2 open because its successful Lock now acceptance remains unmet until a supported request and trustworthy confirmation mechanism are validated.

### Task 6: Build and perform pairing/monitoring walkthroughs

**Files:** No additional source files.

- [ ] Build the Mac target with `xcodebuild build -project NearButFar.xcodeproj -scheme NearButFarMac -destination 'platform=macOS'`.
- [ ] Build the phone simulator target with `xcodebuild build -project NearButFar.xcodeproj -scheme NearButFarPhone -destination 'platform=iOS Simulator,name=iPhone 15 Pro Max' CODE_SIGNING_ALLOWED=NO`.
- [ ] Walk through QR success, two-minute expiry, cancellation, local approval, Forget phone, and replacement pairing on devices.
- [ ] Confirm unauthenticated, malformed, and replayed frames do not change presence, monitoring status, or peer identity. Confirm no secrets appear in CSV or phone logs.
- [ ] Confirm the monitoring preference survives restart while active countdown/session state does not; Bluetooth unavailable is never shown as the phone being away.
- [ ] Confirm Lock now and Unlock remain disabled and no lock/unlock frame is emitted.

## Gate for the next phase

Proceed to the status-first UI plan only after the authenticated message path and model state exist. If the crypto dependency gate fails, stop before pairing or effective monitoring; report the blocker instead of shipping an unauthenticated path.
