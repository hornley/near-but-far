# Issue #2 Pairing and Monitoring Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `subagent-driven-development` or an equivalent task-by-task execution workflow to implement this plan.

**Goal:** Pair one iPhone securely, expose a persistent Mac monitoring preference, and represent lock capabilities without claiming or issuing an unverified lock.

**Architecture:** A shared authenticated session protects every operational BLE frame. `MacCoordinator` owns pairing, monitoring preference, and effective readiness; `MacPeripheral` and `PhoneCentral` remain transport adapters. This plan deliberately adds no executable Lock or Unlock message because the supported lock-and-confirmation capability is unresolved.

**Tech Stack:** Swift, Rust with `snow` 0.10.0, a narrow C ABI, CoreBluetooth, Core Image on macOS, AVFoundation on iOS, Security/Keychain, SwiftUI, Xcode, and Cargo. Keep the existing macOS 14 and iOS 17 minimums unless the verified bridge requires a higher target; never exceed macOS 26 or iOS 27.

---

**Sequence:** Second phase, after [issue #1 sampling](2026-11-23-issue-1-rssi-sampling.md). The approved design is [Near But Far app design](../specs/2026-11-23-near-but-far-app-design.md). If no suitable maintained protocol library is found, stop this phase before implementing custom cryptography or retaining unauthenticated operational traffic.

## Files

- Create shared `Sources/Shared/PeerSession.swift`, `Sources/Shared/PeerIdentity.swift`, and `Sources/Shared/SnowBridge.swift` for session policy, identity values, verified domain messages, and the only Swift-to-Rust boundary.
- Create `Sources/Mac/PairedIdentityStore.swift` and `Sources/Mac/PairingView.swift`; extend `Sources/Mac/MacCoordinator.swift` with pairing and monitoring ownership established in issue #1.
- Create `Sources/iOS/PairedIdentityStore.swift` and `Sources/iOS/PairingScannerView.swift`; extend `Sources/iOS/PhoneModel.swift` with authenticated peer and Mac-reported status.
- Modify `Sources/Shared/BLEProtocol.swift`, `Sources/Mac/MacPeripheral.swift`, and `Sources/iOS/PhoneCentral.swift` to carry bounded authenticated frames and route only verified messages to app policy.
- Modify `Sources/Mac/NearButFarMacApp.swift`, `Sources/iOS/NearButFarPhoneApp.swift`, and `Sources/iOS/Info.plist` for the monitoring control, pairing entry points, and camera usage text.
- Create `Rust/NearButFarSession/Cargo.toml`, `Rust/NearButFarSession/src/lib.rs`, and a reproducible Apple XCFramework build script for the pinned Snow bridge.
- Generate a private C header/module map and link the Rust static library into the existing Xcode targets; do not commit generated build products.
- Modify `NearButFar.xcodeproj/project.pbxproj` to add all new sources to the correct targets.

## Tasks

### Task 1: Select an existing protocol implementation

**Files:** No source changes until this gate passes.

- [x] Compare maintained Swift and Apple-packaged libraries for a published authenticated handshake and encryption protocol. None passed the production-suitability gate.
- [x] Review `mcginty/snow` 0.10.0 as the current candidate. It is Apache-2.0 OR MIT licensed, follows Noise revision 34, includes vector support, and has an independently published Trail of Bits review funded by 1Password.
- [x] Map the audit report and its validated fixes to the exact pinned `snow` release. The Snow README still says it is unaudited; upstream PR 211 to update that statement remains open.
- [x] Build and review the narrow Rust-to-Swift bridge for macOS and iOS device/simulator targets. Keep pairing and operational messages disabled until this integration gate passes.

**Initial gate result (2026-11-23): blocked.** `trancee/noise-protocol` supports the earlier OS targets and documents Noise XX, but its Swift package applies unsafe build flags, so it cannot be consumed as a normal SwiftPM dependency. `rweather/noise-c` has vectors and an MIT license but is a reference implementation without supported Apple packaging and would require a custom build integration. `1amageek/swift-libp2p` requires macOS 26/iOS 26. The other Swift candidates checked lacked release/maintenance evidence or required newer OS versions. Sources: [trancee/noise-protocol](https://github.com/trancee/noise-protocol), [Apple SwiftPM unsafe flags](https://developer.apple.com/documentation/packagedescription/swiftsetting/unsafeflags%28_%3A_%3A%29), [Noise-C](https://github.com/rweather/noise-c), [swift-libp2p](https://github.com/1amageek/swift-libp2p).

**Swift and Apple package recheck (2026-11-23):** No candidate qualifies as a drop-in Swift package, even with higher minimum OS versions. [`1amageek/swift-libp2p`](https://github.com/1amageek/swift-libp2p) has a 0.5.0 release, macOS 26/iOS 26 support, and documented interop checks, but GitHub reports no license for the repository. Its separate [`swift-libp2p-noise`](https://github.com/swift-libp2p/swift-libp2p-noise) package explicitly says it is not production ready. [`swift-libp2p/swift-noise`](https://github.com/swift-libp2p/swift-noise) supports Apple platforms and official vectors, but its README calls it a proof of concept. [`stonygrey/torann`](https://github.com/stonygrey/torann) supports iOS 18/macOS 15 and includes shared vectors, but says it is not production ready. `trancee/noise-protocol` remains unsuitable for direct SwiftPM consumption because its package uses `unsafeFlags(["-O3"])` for a local C target. Sources: [swift-libp2p README](https://github.com/1amageek/swift-libp2p), [swift-libp2p package manifest](https://github.com/1amageek/swift-libp2p/blob/main/Package.swift), [swift-libp2p-noise warning](https://github.com/swift-libp2p/swift-libp2p-noise), [swift-noise README](https://github.com/swift-libp2p/swift-noise), [Torann README and package](https://github.com/stonygrey/torann), [trancee/noise-protocol Swift package](https://github.com/trancee/noise-protocol/blob/main/ios/Package.swift).

**Prior user decision (2026-11-23, superseded):** Keep the macOS 14 and iOS 17 minimum targets and wait for a qualifying maintained library.

**Current user decisions (2026-11-23):** Use one-use QR pairing instead of a one-minute manual code. The QR carries a temporary high-entropy secret, expires after two minutes, and is consumed and erased after pairing. Keep the macOS 14 and iOS 17 minimums; the reviewed bridge builds at both targets.

**Candidate review (2026-11-23):** `snow` 0.10.0 was selected for a bounded integration spike. 1Password's [review summary](https://1password.com/blog/strengthening-snow-for-the-open-source-community) says Trail of Bits spent four engineer-weeks reviewing Snow, found ten findings, and validated remediation for eight, including the medium-severity nonce flaw, invalid-PSK panic, and message-length enforcement. The [published report](https://github.com/trailofbits/publications/blob/master/reviews/2024-03-agilebits-snow-securityreview.pdf) is an independent review; the upstream [PR 211](https://github.com/mcginty/snow/pull/211) to update Snow's README remains open, explaining why the README still carries its earlier no-audit warning. Snow 0.10.0 is dual-licensed Apache-2.0/MIT, was released on 2025-07-19, and its release notes include the transport nonce fix.

**Audit-to-release check (2026-11-23):** The audited source revision is `009411d2035a77ece57b0a6873169de7693a0aa0` (the report's source tree identifies itself as 0.9.0). The eight remediations Trail of Bits validated are ancestors of the `v0.10.0` tag: deprecated the sodiumoxide resolver; bounded received message size; rejected trailing protocol-name components, duplicate PSK modifiers, and builder overwrites; returned errors for invalid PSK indices; avoided nonce advancement after authentication failure; and fixed cipher key-length handling. Snow 0.10.0 therefore contains those eight validated fixes. Findings 2 (pre-message ephemeral mixing) and 8 (ephemeral memory clearing) were informational and were not among the eight validated remediations. This establishes the report-to-release mapping; it does not mean the exact 0.10.0 release received a full audit. Sources: [Trail of Bits report](https://github.com/trailofbits/publications/blob/master/reviews/2024-03-agilebits-snow-securityreview.pdf), [Snow 0.10.0 release](https://github.com/mcginty/snow/releases/tag/v0.10.0), [1Password summary](https://1password.com/blog/strengthening-snow-for-the-open-source-community).

**Integration gate (2026-11-23): passed.** The audit-to-release mapping is verified. Snow 0.10.0 builds through the reviewed C ABI for macOS arm64/x86_64, iOS device arm64, and iOS simulator arm64/x86_64. Rust handshake/transport coverage, the generated C header, Swift import/linking, spec review, and code-quality review passed. The bridge is now used by the app's QR enrollment and pinned authenticated BLE session paths. This is not a full security audit; Snow's two informational findings were not among the validated remediations, and physical end-to-end validation remains open.

### Session bridge architecture selected for the integration spike

**Problem.** The app's protocol owners and lifecycle are Swift/CoreBluetooth. Snow's Noise handshake and transport state are Rust. The existing `MacCoordinator`, `MacPeripheral`, `PhoneCentral`, and `PhoneModel` already separate presence policy, radio transport, and presentation; the bridge must preserve those owners and keep every unauthenticated prototype frame outside production policy.

**Caller shape.** `MacCoordinator` and `PhoneCentral` pass complete, bounded records to one Swift `PeerSession`. `PeerSession` returns outbound records and typed events. Neither caller imports Snow or chooses a Noise pattern. Mac-local approval, QR lifetime, Keychain writes, revocation, and monitoring readiness remain Swift-owned.

**Selected shape.** Use a small Rust crate with Snow 0.10.0 behind a narrow C ABI, called only through `Sources/Shared/SnowBridge.swift`. Rust owns fixed-profile Noise handshakes, stateful seal/open operations, and bounded cryptographic state. Swift owns roles, expected identity pins, pairing state, QR expiration, local approval, typed-message validation, transport queues, and presence policy. Keep one opaque Rust `NoiseSession` per link and serialize calls on the existing main queue. The Rust session exposes start, handshake receive, seal, open, and idempotent close; it does not expose pattern strings, nonce setters, raw session keys, stateless transport, callbacks into Swift, or allocator-owned buffers.

```swift
@MainActor
final class PeerSession {
    init(role: PeerRole, store: PeerIdentityStore, intent: SessionIntent)
    func start(on link: LinkID) throws -> SessionEffects
    func receive(_ completeRecord: Data, from link: LinkID) throws -> SessionEffects
    func approvePairing(_ candidate: CandidateID) throws -> SessionEffects
    func send(_ message: PeerMessage, on link: LinkID) throws -> SessionEffects
    func close(_ link: LinkID)
}

enum PeerRole { case mac, phone }
enum SessionIntent { case enrollMac(PairingOffer), enrollPhone(ScannedOffer), reconnect }
struct LinkID: Hashable { let rawValue: UUID }
struct CandidateID: Hashable { let rawValue: UUID }
struct PeerPublicKey: Hashable { private let bytes: Data } // Exactly 32 bytes.

struct LocalIdentity {
    let id: UUID
    let publicKey: PeerPublicKey
    let privateKey: Data // Read from device-only Keychain storage.
}

struct PairedIdentity {
    let id: UUID
    let publicKey: PeerPublicKey
}

protocol PeerIdentityStore {
    func loadOrCreateLocalIdentity() throws -> LocalIdentity
    func pairedIdentity() throws -> PairedIdentity?
    func replacePairedIdentity(with candidate: PairedIdentity) throws
    func forgetPairedIdentity() throws
}

struct PairingOffer {
    let id: UUID
    let macPublicKey: PeerPublicKey
    let expiresAt: ContinuousClock.Instant
    private let secret: OneUseSecret
}

struct ScannedOffer {
    let id: UUID
    let macPublicKey: PeerPublicKey
    let expiresAt: ContinuousClock.Instant
    private let secret: OneUseSecret
    init(validating qrPayload: Data) throws
}

final class OneUseSecret {
    func withUnsafeBytes<R>(_ body: (UnsafeRawBufferPointer) throws -> R) rethrows -> R
    func invalidate()
}

struct OutboundRecord {
    let link: LinkID
    let bytes: Data
}

struct VerifiedMessage {
    let peerID: UUID
    let sessionID: Data
    let message: PeerMessage
    fileprivate init(peerID: UUID, sessionID: Data, message: PeerMessage)
}

enum PeerMessage: Equatable {
    case pairingPrepared
    case pairingAccepted
    case pairingComplete
    case challenge(sequence: UInt32)
    case acknowledgement(sequence: UInt32, rssi: Int16?)
    case status(MacStatus)
}

enum MacStatus: Equatable {
    case unavailable
    case waiting
    case nearby
    case weakSignal
    case signalLost
    case lockUnavailable
}

enum PeerSessionEvent {
    case candidate(CandidateID, peerStaticKey: Data)
    case ready(peerID: UUID, sessionID: Data)
    case received(VerifiedMessage)
    case closed(PeerSessionError)
    case pairingDisplayCleared
}

enum PeerSessionError: Error {
    case invalidState
    case malformedRecord
    case unsupportedVersion
    case authenticationFailed
    case wrongPeer
    case pairingExpired
    case cancelled
    case keychainUnavailable
    case transportLost
    case internalFailure
}

struct SessionEffects {
    let outbound: [OutboundRecord]
    let events: [PeerSessionEvent]
}
```

The Rust C ABI remains narrower than the Swift state machine. It uses only opaque handles and borrowed/input or Swift-owned/output buffers:

```rust
#[repr(C)]
pub struct NbfNoiseSession {
    _private: [u8; 0],
}

#[repr(C)]
pub struct NbfBytes {
    pub ptr: *const u8,
    pub len: usize,
}

#[repr(C)]
pub struct NbfOutput {
    pub ptr: *mut u8, // Storage is owned by Swift.
    pub capacity: usize,
    pub written: *mut usize,
}

#[repr(C)]
pub struct NbfConfig {
    pub role: u32, // 1 = phone initiator, 2 = Mac responder.
    pub mode: u32, // 1 = enrollment, 2 = pinned reconnect.
    pub local_private_key: NbfBytes, // Exactly 32 bytes.
    pub local_public_key: NbfBytes, // Exactly 32 bytes; Rust checks it matches the private key.
    pub expected_remote_static: NbfBytes, // Empty only for the Mac during enrollment.
    pub pairing_offer_id: NbfBytes, // Exactly 16 bytes for enrollment; empty for reconnect.
    pub pairing_psk: NbfBytes, // Exactly 32 bytes for enrollment; empty for reconnect.
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn nbf_session_new(
    config: *const NbfSessionConfig,
    out_session: *mut *mut NbfNoiseSession,
) -> i32 { /* implementation */ }

#[unsafe(no_mangle)]
pub unsafe extern "C" fn nbf_session_start(
    session: *mut NbfNoiseSession,
    output: NbfOutput,
    out_state: *mut u32,
) -> i32 { /* implementation */ }

#[unsafe(no_mangle)]
pub unsafe extern "C" fn nbf_session_receive(
    session: *mut NbfNoiseSession,
    input: NbfBytes,
    output: NbfOutput,
    out_state: *mut u32,
    out_peer_static: NbfOutput, // Swift supplies exactly 32 writable bytes.
    out_session_id: NbfOutput,  // Swift supplies exactly 32 writable bytes.
) -> i32 { /* implementation */ }

#[unsafe(no_mangle)]
pub unsafe extern "C" fn nbf_session_seal(
    session: *mut NbfNoiseSession,
    plaintext: NbfBytes,
    output: NbfOutput,
) -> i32 { /* implementation */ }

#[unsafe(no_mangle)]
pub unsafe extern "C" fn nbf_session_open(
    session: *mut NbfNoiseSession,
    ciphertext: NbfBytes,
    output: NbfOutput,
) -> i32 { /* implementation */ }

#[unsafe(no_mangle)]
pub unsafe extern "C" fn nbf_session_close(session: *mut NbfNoiseSession) -> i32 { /* implementation */ }
#[unsafe(no_mangle)]
pub unsafe extern "C" fn nbf_session_free(session: *mut NbfNoiseSession) { /* implementation */ }
```

The C header uses only `uint8_t`, `uint32_t`, `int32_t`, `size_t`, and forward-declared opaque structs. Rust allocates no memory for Swift to free and never retains a Swift pointer. Validate pointer/length pairs, maximum message sizes, output capacity, role, mode, and state before Snow can advance. A short output buffer must not mutate handshake or transport state. A malformed complete record, pin/authentication failure, unexpected message order, or failure after Snow state mutation poisons the session; local argument errors and short buffers remain retryable. Catch panics at each exported function. `SnowBridge.swift` owns every output `Data`, scopes input pointers to `Data.withUnsafeBytes`, and prevents double-free or use-after-free. `cbindgen` generates the private header, and the build checks generated output against the committed header/module map.

The candidate C ABI is the base because this project uses explicit Xcode targets and the bridge needs a small, stable byte-oriented surface. UniFFI would provide more ergonomic generated Swift types but adds a generator/runtime and package integration for little benefit at this boundary. Keep every unsafe pointer operation in `SnowBridge.swift` and one Rust FFI module. The UniFFI option remains the fallback if this boundary cannot be reviewed as small and safe.

The fixed enrollment profile is `Noise_XXpsk3_25519_ChaChaPoly_BLAKE2s`: the iPhone is the initiator, the Mac is the responder, and the QR's 32-byte one-use secret is the PSK at `psk3`. The phone checks the Mac static public key carried in the QR. After the Mac reads the final handshake message, it checks the QR PSK and learns the phone static key; local approval is still required before pinning that identity. The fixed reconnect profile is `Noise_XX_25519_ChaChaPoly_BLAKE2s` with the same phone-initiator/Mac-responder roles and both pinned static keys checked against stored identities. No PSK is reused for reconnects.

The canonical prologue binds purpose, offer, and identities. Enrollment uses the 8-byte ASCII domain `NBFPAIR1`, the 16-byte offer UUID in network byte order, and the Mac's 32-byte static public key. Reconnect uses `NBFRECN1`, then the Mac and phone static public keys in that order. The profile, roles, and prologue are fixed in Rust rather than selected by arbitrary caller strings. Noise handshake completion only proves the local handshake state; pairing is not confirmed to the phone until the Mac has accepted explicit local approval and sends a later authenticated application message that represents that decision. This confirmation and approval flow are outside this integration spike. The official [Noise specification](https://noiseprotocol.org/noise.html) defines XX and XXpsk3, including the PSK token at the end of the third message. Never substitute custom key exchange or nonce logic.

**Record flow.** Swift frames and reassembles complete Noise records before calling Rust. Rust rejects malformed or oversized records, poisons the affected session, and uses Snow's ordered stateful transport counters. Swift decodes only authenticated plaintext into `PeerMessage`, then creates `VerifiedMessage` inside `PeerSession`. `PhoneCentral` must not refresh presence before this point. Fragmentation occurs after sealing and has explicit record, fragment-count, buffer-count, and timeout caps. Any malformed or incomplete record, authentication failure, unexpected ordering, or pin mismatch closes that link and requires a fresh handshake. Do not add a nonce-skipping window or plaintext fallback.

**Enrollment.** The Mac creates a versioned QR payload with its public identity and a random 256-bit one-use secret. The local pairing lease is 120 seconds, measured monotonically; the QR is erased from UI and application-owned buffers on success, cancellation, or expiry. The phone's identity is pinned only after handshake confirmation and explicit approval on the unlocked Mac. Replacement revokes the old identity before new operational traffic can be accepted. Long-lived private identities remain in device-only Keychain storage. The QR secret never goes into Keychain, logs, CSV, or persisted UI state.

**Synthesis.** Candidate A's narrow C ABI is the base. The Swift project already builds explicit Xcode targets, and the Rust surface needs only an opaque session handle plus bounded byte operations. This avoids a generated binding runtime and package/codegen lifecycle for a small stable interface. Candidate B's UniFFI object mapping provides more ergonomic Swift types, but adds generated code, runtime dependencies, and copies without removing the need to audit the Rust session state. Keep every unsafe pointer operation in the single `SnowBridge.swift` wrapper and the single Rust FFI module, with fixed lengths, Swift-owned output buffers, no retained pointers, panic containment, and close-on-error behavior. Both candidates preserve Swift ownership and do not move Bluetooth policy into Rust. The cross-provider judge was unavailable because Claude and Grok providers are disabled; both design candidates ran on the available Codex GPT-6.1 Sol model, so this synthesis is the primary review.

**Accepted tradeoffs and risks.** The C ABI keeps package integration small but requires a manually reviewed unsafe boundary. Swift owns every input/output buffer; Rust may not retain a Swift pointer, return Rust-owned memory, or unwind across the ABI. Test the generated header against the declarations. Snow 0.10.0 stores PSKs and key material in ordinary internal buffers without a guaranteed zeroizing `Drop`; the app can avoid persistence, clear its own buffers, and destroy the session, but must not claim every memory copy was overwritten. Snow's ordered counter rejects replay, loss followed by a later record, or reordering; the first version will reconnect instead of accepting skipped counters. These limitations do not create Lock or Unlock messages or enable those actions.

**Implementation status.** Tasks 2–5 are implemented: the authenticated message boundary, Mac and iPhone identity stores, one-use QR enrollment, local Mac approval, replacement/forget handling, monitoring preference, and safety states are present. Task 6 remains for current builds, physical walkthroughs, and device validation.

The current Issue #1 sampling path runs over the authenticated session. Earlier unauthenticated prototype logs remain historical timing evidence only and do not represent current app presence.

### Task 2: Add the shared verified-message boundary

**Files:** `Sources/Shared/PeerSession.swift`, `Sources/Shared/PeerIdentity.swift`, `Sources/Shared/SnowBridge.swift`, `Sources/Shared/BLEProtocol.swift`, `Rust/NearButFarSession/src/lib.rs`, `Rust/NearButFarSession/include/NearButFarSession.h`, `NearButFar.xcodeproj/project.pbxproj`

#### Task 2 wire contract

- QR uses `nearbutfar://pair/v1/` followed by canonical, unpadded base64url for exactly 97 bytes: version `1` (1 byte), offer UUID in RFC 4122 byte order (16), Mac identity UUID (16), Mac static public key (32), and one-use PSK (32). The Mac's two-minute expiry is monotonic state held by the offer; the QR does not carry a clock value. The offer is consumed and its in-memory secret invalidated when Mac approval commits the pairing, or on cancellation/expiry.
- Each encrypted application plaintext starts with a 67-byte envelope: version (1), sender role (1), message type (1), sender identity UUID (16), recipient identity UUID (16), and the 32-byte Noise handshake hash. Validate all fields, including the expected role and both identity IDs, before producing a `VerifiedMessage`. The sender ID is the sender's `LocalIdentity.id`; the recipient ID must equal the local ID.
- Enrollment messages are phone `pairingPrepared`, Mac `pairingAccepted`, then phone and Mac `pairingComplete` confirmations. The phone's prepared envelope identifies its local identity. The Mac exposes a candidate for local approval only after the phone's static key and prepared envelope are authenticated. On approval the Mac stores that phone identity before sending accepted. The phone stores the QR-pinned Mac identity before sending its completion. The Mac sends its completion only after receiving the phone's completion; each side becomes ready only after the completion exchange. Reconnect sessions do not accept enrollment messages.
- A BLE fragment is at most 20 bytes for the minimum ATT MTU: magic `NB` (2), framing version `1` (1), per-direction record sequence (4, big-endian), fragment index (1), fragment count (1), complete record length (2, big-endian), and up to 9 record bytes. Record length is 1–1,024 bytes; count must equal `ceil(length / 9)` and therefore is at most 114. A `PeerSession` accepts one active link at a time, with one incomplete record per direction and at most 1,024 bytes of reassembly memory per direction. Fragments are accepted in order. An incomplete record expires after 30 seconds and closes the link. Duplicate, inconsistent, out-of-order, expired, oversized, or malformed fragments close the link. Snow remains responsible for authenticated transport ordering and replay rejection.
- The envelope and QR formats are versioned and reject unknown versions, wrong lengths, non-canonical base64url, unknown message types, mismatched roles/IDs/session hashes, and trailing data. Do not add lock or unlock messages.

- [x] Define `PeerIdentityStore`, `LocalIdentity`, `PairedIdentity`, `PairingOffer`, `ScannedOffer`, `PeerMessage`, `VerifiedMessage`, `OutboundRecord`, and `SessionEffects` as in the architecture sketch. Keep private key bytes and the QR secret out of public UI types.
- [x] Add `SnowBridge.swift` as the only Swift file importing the C module. It owns opaque handle lifetime, scopes every pointer to a `Data.withUnsafeBytes` call, provides Swift-owned output buffers, and maps only fixed numeric status codes to `PeerSessionError`.
- [x] Implement the Rust C ABI over Snow's stateful handshake/transport API. Pin `snow = "=0.10.0"`; compile only the fixed approved profiles. Bound inputs and outputs before state mutation, catch panics at every exported function, and poison a session after malformed records, pin/authentication failures, unexpected message order, or any state-changing failure. Keep invalid local arguments and short-buffer failures retryable without state mutation.
- [x] Keep message construction inside `PeerSession`; only authenticated session messages become `VerifiedMessage`:

```swift
struct VerifiedMessage {
    let peerID: UUID
    let sessionID: Data
    let message: PeerMessage
    fileprivate init(peerID: UUID, sessionID: Data, message: PeerMessage)
}

@MainActor
final class PeerSession {
    func start(on link: LinkID) throws -> SessionEffects
    func receive(_ completeRecord: Data, from link: LinkID) throws -> SessionEffects
    func approvePairing(_ candidate: CandidateID) throws -> SessionEffects
    func send(_ message: PeerMessage, on link: LinkID) throws -> SessionEffects
    func close(_ link: LinkID)
}
```

- [x] Use Snow's ordered stateful transport counters; do not implement or set nonces. Put message type, protocol version, session identity, and role inside the encrypted plaintext envelope, then validate them before constructing a `VerifiedMessage`.
- [x] Keep all Lock and Unlock cases, serialization, and send methods absent. At countdown expiry, return only `lockUnavailable` status.
- [x] Cap complete records at 1,024 bytes and fragments at 128. Reassemble ciphertext before calling Rust, with one incomplete record per direction/link, a finite timeout, and memory caps independent of declared counts. Reject duplicate-inconsistent, malformed, incomplete, or expired records and close the session on record-order or authentication failure.
- [x] Add the new Swift files to explicit Xcode groups/targets and link the Rust static library into both app targets without changing the current OS minimums unless the build proves a higher target is required.

**Task 2 implementation gate (2026-11-23): passed.** Spec-compliance and code-quality reviews passed. Rust handshake/transport tests and macOS, iOS Simulator, and test-bundle builds passed during the bridge spike. Tasks 3–5 now connect the bridge to QR enrollment, Keychain identities, authenticated BLE messages, monitoring policy, and status presentation.

### Task 3: Store identities and implement Mac enrollment

**Files:** `Sources/Mac/PairedIdentityStore.swift`, `Sources/Mac/MacCoordinator.swift`, `Sources/Mac/PairingView.swift`, `Sources/Mac/MacPeripheral.swift`, `Sources/Mac/NearButFarMacApp.swift`, `NearButFar.xcodeproj/project.pbxproj`

**Mac-side implementation status (2026-11-23):** The Mac has a Keychain identity store, one-use QR renderer and 120-second offer lifecycle, candidate fingerprint and approval handling, forget/replacement handling, and a bounded CoreBluetooth record path associated with one current `CBCentral`. Replies are fragmented back to that central only; local approval effects are sent through the session transport. Forget/replacement closes the active session and clears Mac-side presence state. Raw prototype acknowledgements are not passed to coordinator policy. The Pair iPhone window offers a fresh code after expiry or failure. Physical enrollment and recovery walkthroughs remain pending.

- [x] Store the Mac private identity in the macOS Keychain. Do not log keys, pairing secrets, or encrypted frame contents.
- [x] Add an explicit pairing action on the unlocked Mac. Generate a cryptographically random 256-bit one-use QR secret and a QR payload containing protocol version, the Mac’s public identity, and that secret; generate it with `CIQRCodeGenerator` and expire the pairing window after two minutes. Never place a private key in the QR.
- [x] Complete the selected handshake with the scanning phone. Show the Mac a short fingerprint derived from the candidate public key for local approval; do not use the Bluetooth device name as identity. Save exactly one phone identity after approval. Consume and erase the QR secret on success, cancel, or expiry.
- [x] Add **Forget phone** and replacement flow. Revoking or replacing a phone invalidates its session immediately; replacement requires explicit confirmation.
- [x] Route operational notifications and writes only for the pinned `CBCentral`. A second or unauthenticated subscriber cannot replace the trusted phone.
- [x] Keep `MacCoordinator` as the only owner of monitoring preference, pairing status, and effective readiness. Transport callbacks pass verified domain messages to it.

### Task 4: Implement iPhone enrollment and session storage

**Files:** `Sources/iOS/PairedIdentityStore.swift`, `Sources/iOS/PairingScannerView.swift`, `Sources/iOS/PhoneModel.swift`, `Sources/iOS/PhoneCentral.swift`, `Sources/iOS/Info.plist`, `NearButFar.xcodeproj/project.pbxproj`

- [x] Add a SwiftUI QR scanner backed by `AVCaptureMetadataOutput` configured for QR codes. Add `NSCameraUsageDescription` explaining that camera access is used only to pair with the Mac.
- [x] Store the phone identity in device-only Keychain storage accessible after first unlock (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`) so background CoreBluetooth callbacks can authenticate. A reinstall or replacement requires pairing again.
- [x] Represent scanner states explicitly: unpaired, scanning, waiting for Mac approval, paired, expired, QR mismatch, untrusted Mac, Bluetooth unavailable, and camera unavailable. Give each failure a next step. The phone keeps its saved Mac pin on connection or QR mismatch; it does not claim revocation without an authenticated revocation message.
- [x] Pass every received frame through `PeerSession`. Only verified presence/status messages update `PhoneModel`; a failed authentication never updates presence or readiness.

### Task 5: Add monitoring preference and safety states

**Files:** `Sources/Mac/MacCoordinator.swift`, `Sources/Mac/NearButFarMacApp.swift`, `Sources/Shared/PresenceTracker.swift`, `Sources/iOS/PhoneModel.swift`

- [x] Persist only the monitoring preference in `UserDefaults`; keep session keys, active challenge, and countdown in memory.
- [x] On enable, app launch, or Mac Bluetooth recovery, enter **Waiting for authenticated iPhone** and arm only after fresh authenticated presence. On disable, clear the countdown and pause automatic policy without unlocking or unpairing.
- [x] On Mac Bluetooth unavailable, clear the active monitoring epoch and report unavailable, never away. After recovery, require fresh authenticated presence.
- [x] With the current lock findings, report effective protection unavailable. Keep **Lock now** and **Unlock** disabled, add no lock/unlock wire cases, and send no lock request at countdown expiry; show **Lock unavailable**.
- [x] Keep issue #2 open because its successful Lock now acceptance remains unmet until a supported request and trustworthy confirmation mechanism are validated.

### Task 6: Build and perform pairing/monitoring walkthroughs

Task 6 is in progress. Rust tests and the 13-test Xcode scheme pass; Mac and iOS Simulator targets build, and the signed iPhone app was installed and launched on `roasted ginger`. QR enrollment and monitoring walkthroughs remain pending. Keep Issue #2 open pending a supported lock request and trustworthy confirmation.

**Files:** No additional source files.

- [x] Build the Mac target with `xcodebuild build -project NearButFar.xcodeproj -scheme NearButFarMac -destination 'platform=macOS'`.
- [x] Build the phone simulator target with `xcodebuild build -project NearButFar.xcodeproj -scheme NearButFarPhone -destination 'platform=iOS Simulator,name=iPhone 15 Pro Max' CODE_SIGNING_ALLOWED=NO`.
- [x] Build, install, and launch the signed phone app on the connected `roasted ginger` iPhone.
- [x] Run the Rust session tests and Xcode test scheme; confirm the lock and unlock actions remain disabled in the simulator UI.
- [ ] Walk through QR success, two-minute expiry, cancellation, local approval, Forget phone, and replacement pairing on devices.
- [ ] Confirm unauthenticated, malformed, and replayed frames do not change presence, monitoring status, or peer identity. Confirm no secrets appear in CSV or phone logs.
- [ ] Confirm the monitoring preference survives restart while active countdown/session state does not; Bluetooth unavailable is never shown as the phone being away.
- [ ] Confirm Lock now and Unlock remain disabled and no lock/unlock frame is emitted.

## Remaining gate

The authenticated message path, pairing flows, monitoring states, and status-first UI are implemented. Complete builds and physical pairing/monitoring checks before treating background presence as reliable. Issue #2 remains open until a supported lock request and trustworthy lock-state confirmation are validated or the issue is explicitly rescoped. Never fall back to unauthenticated BLE presence.
