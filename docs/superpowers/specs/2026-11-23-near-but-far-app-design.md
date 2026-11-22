# Near But Far app design

**Status:** Approved by user on 2026-11-23

**Scope:** [Issue #1](https://github.com/hornley/near-but-far/issues/1), [Issue #2](https://github.com/hornley/near-but-far/issues/2), then the approved status-first UI/UX pass.

## Problem

The current app is a BLE prototype: it sends unauthenticated five-second challenges and logs “would lock,” but does not lock or confirm the Mac’s lock state. Issue #1 asks for faster status updates; issue #2 adds monitoring and phone controls. A one-second sampling cadence must not accidentally shorten the existing five-second loss/retry timing, and an unauthenticated presence signal must not be allowed to keep the Mac falsely marked nearby. The current research has not established a supported local mechanism that both requests a secure macOS lock and confirms the resulting state, so lock actions remain unavailable.

## Usage (caller’s view)

The Mac menu-bar UI reads one status model and changes the persisted monitoring preference through it. The iPhone UI reads separate values for its local presence estimate, the Mac’s monitoring readiness, and the Mac lock observation. It displays **Lock now** and **Unlock** as disabled while the corresponding capability is unavailable, with a short explanation. Neither view handles BLE frames, keys, or timer rules.

```swift
Toggle("Presence monitoring", isOn: $model.monitoringEnabled)
Text(model.monitoringStatus.description)

Text(phone.presenceEstimate.description)
Text(phone.macLockObservation.description)
Button("Lock now") { phone.lockNow() }
    .disabled(!phone.canLockNow)
Button("Unlock") { }
    .disabled(true)
```

## Shape

Keep a single coordinator on each device. CoreBluetooth objects remain transport adapters. A shared authenticated session verifies all operational messages—presence, status, commands, and results—before app policy sees them. Small value types own timing and presence transitions; the coordinator owns the monitoring preference, pairing lifecycle, and effective status. This keeps state ordering in one place without spreading policy across Bluetooth callbacks.

| Component | Responsibility |
| --- | --- |
| `MacPeripheral` / `PhoneCentral` | CoreBluetooth discovery, connection, subscription, reads, writes, and bounded frame transport. They do not decide whether the Mac is nearby or locked. |
| `PeerSession` (shared) | Pairing handshake, peer identity checks, authenticated encryption, replay rejection, and message framing. Only verified domain messages leave this boundary. |
| `ChallengeSchedule` (shared) | One outstanding logical challenge; one-second sampling opportunity; five-second response deadline and same-challenge retry. |
| `PresenceTracker` (shared) | Pure threshold, grace-period, and recovery state using injected monotonic time. No BLE or lock APIs. |
| `MacCoordinator` | Owns pairing and monitoring state, accepts verified messages, and exposes Mac status to the menu-bar UI. Persists user intent, not an active countdown. |
| `PhoneModel` | Owns phone-side presence estimate, Mac-reported status, and action availability for the status-first screen. |
| Lock capability gate | Reports whether secure lock request and trustworthy confirmation are available. It defaults to unavailable; no implementation is selected by this spec. |

New files stay in the existing Xcode targets. Do not add a general event bus, cloud service, or one actor per feature. CoreBluetooth callbacks and coordinator state changes use the existing main-queue model. Async completions carry a connection or operation generation so stale callbacks cannot overwrite newer state.

### Timing and presence rules

- While connected and active, issue a new challenge about once per second after the previous one is acknowledged. iOS may throttle or suspend background work; the app must not promise one-second background readings.
- Keep one logical challenge outstanding. If it is unanswered, start the Mac’s loss timer after five seconds and retry that same challenge on the five-second retry schedule. A queued notification is not proof it was delivered.
- Keep the iPhone’s ten-second no-challenge fallback and disconnect estimate. Its countdown is local and may differ from the Mac’s.
- Preserve the experimental `-70 dBm` threshold and 60-second grace period. A fresh sample at or below the threshold starts the timer; a stronger fresh sample clears it. RSSI is not distance. Missing RSSI, reconnecting alone, or Bluetooth being unavailable does not confirm recovery.
- If a fresh stronger sample and expiry are observed at the same monotonic time, apply the sample first. A lock request already sent cannot be undone by a later recovery.
- If the iPhone disconnects during a weak-signal countdown, preserve the original start time and show **Signal lost**. If the connection drops before a weak sample, start the local estimate on the disconnect callback or after ten seconds without a challenge. When iPhone Bluetooth is unavailable, show **Unavailable** and do not infer that the Mac is away.
- Serialize iPhone RSSI reads. CoreBluetooth does not identify which read produced a late callback, so do not overlap reads or attach a stale RSSI value to a new challenge.
- Use monotonic time for deadlines and countdowns. Use wall-clock time for displayed timestamps and logs.

### Pairing and trust

1. The user opens a pairing window on the unlocked Mac. It lasts two minutes and displays a one-use QR code.
2. The iPhone scans it with camera access and completes a handshake with the Mac. The Mac requires local approval before saving the peer.
3. Store the long-lived device identities in device-only Keychain storage. Consume and erase the QR secret after enrollment; never write it to logs.
4. Permit one paired iPhone at a time. “Forget phone” revokes that identity; pairing a replacement revokes the old phone. The QR is only for setup, not everyday reconnects.
5. Use a maintained implementation of a published handshake and authenticated-encryption protocol. Do not invent cryptography. Select the library only after confirming Swift, macOS 14, and iOS 17 support, maintenance, license, and test vectors. If no suitable implementation is available, authenticated pairing and operational presence stay unavailable.

BLE service identifiers and RSSI are discovery and signal hints, not identity. Reject malformed, oversized, unauthenticated, stale, and replayed frames. There is no unauthenticated operational fallback. Authentication does not prove physical distance or prevent relaying a genuine paired device.

### Monitoring and lock safety

- Persist the user’s monitoring preference. Turning it off stops automatic presence policy and clears its active countdown; it never unlocks a Mac that is already locked.
- Turning monitoring on, launching the Mac app, or recovering from Mac Bluetooth unavailability starts in **Waiting for authenticated iPhone**. Require fresh authenticated presence before arming a new monitoring period; never restore an old countdown and immediately lock from stale state.
- If the phone reconnects during an active loss countdown, the countdown remains until a stronger fresh RSSI sample confirms recovery.
- If Bluetooth is unavailable on the Mac, report **Monitoring unavailable**, not **iPhone away**. If monitoring is enabled while lock capability is unavailable, continue to label effective protection as unavailable. Presence tracking may still inform the user, but the UI must not imply the Mac is protected.
- Until a supported secure lock request and trustworthy lock observation are documented and validated, do not issue manual or automatic lock requests. Keep **Lock now** disabled and show why. At countdown expiry, report **Lock unavailable**; do not claim success or show a confirmed locked state.
- Keep **Unlock** unavailable until a documented macOS mechanism preserves local authentication. Do not add an unlock message to the wire protocol. Proximity never unlocks the Mac.
- The phone may show a Mac lock state only after the Mac reports a trustworthy observation over the authenticated session. BLE write success, shortcut acceptance, display sleep, or a process exit is not lock confirmation.
- This issue scope does not add a stay-awake power assertion or a custom lock screen.

The current absence of a lock backend means issue #2’s successful Lock now criterion remains unmet. Keep issue #2 open until that capability is proven or the issue is explicitly rescoped.

## UI/UX direction

Use the selected **status-first** direction. The iPhone’s primary card shows its local presence estimate; below it, show pairing/monitoring readiness and the Mac lock observation as separate facts. Keep the latest RSSI and `-70 dBm` test threshold visible where relevant. Use **Nearby**, **Weak signal**, **Signal lost**, and **Unavailable** for presence; never label a phone-side estimate **Locked** or **Unlocked**. Keep the activity log below the main status. Do not add a graph, distance estimate, cloud account, or extra navigation for this scope.

Show the disabled lock actions with their reasons in text and VoiceOver labels; do not rely on color alone. Bluetooth loss, pairing expiry/revocation, and camera denial need clear recovery steps. The Mac menu-bar UI shows the monitoring preference and whether monitoring is effectively available.

## Acceptance criteria

### Issue #1

- While the iPhone app is active and connected, challenges and fresh RSSI readings occur at roughly one-second intervals.
- The five-second Mac missed-response and retry timing and the ten-second iPhone fallback remain unchanged.
- The threshold and 60-second countdown behave as specified above; a stronger fresh sample cancels the countdown.
- Background sampling and battery/CPU impact are measured during physical validation and documented without promising a fixed iOS background cadence.

### Issue #2 and pairing

- The Mac exposes a persistent monitoring On/Off preference. Off stops automatic presence policy and does not unlock the Mac.
- A new monitoring period starts by waiting for fresh authenticated presence; a restart or Bluetooth recovery does not reuse stale presence.
- The QR is single-use, expires after two minutes, and establishes one revocable phone identity. Replacement revokes the previous phone.
- All operational BLE messages are authenticated and replay-protected; unauthenticated devices cannot affect presence or status.
- Lock now and Unlock remain disabled under the current capability findings. No manual or automatic lock command is sent, and the UI explains the limitation.

### Status-first UI/UX

- The phone UI separates its own presence estimate from Mac monitoring readiness and confirmed lock observation.
- The phone never reports a Mac lock state it cannot verify. RSSI is shown as signal strength, never as distance.
- Pairing, Bluetooth-unavailable, disconnected, weak-signal, and countdown-expiry states are understandable and accessible.

## Validation carried forward

The prototype handoff still lists the 30-minute background-and-locked-phone run, ten varied-orientation range trials, out-of-range-before-weak-sample behavior, Bluetooth-unavailable screens, and exact 60-second boundary ordering as pending. Keep them pending until performed. They do not block starting implementation, but automatic locking remains unavailable until the reliability checks and lock-confirmation gate pass. Also compare battery and CPU use at the one-second cadence.

## Alternatives and tradeoffs

- **Separate actor for pairing, presence, and commands:** rejected for this scope. It isolates state, but introduces asynchronous hand-offs and competing state owners for one Mac and one phone. The coordinator provides a smaller interface and clearer ordering.
- **Put policy directly in `MacPeripheral`:** rejected because issue #2 would combine CoreBluetooth transport, persistent preference, pairing, and lock decisions in the same object. A transport adapter should not be able to treat a raw acknowledgement as authorization.
- **Persist countdown/session state:** rejected in favor of waiting for fresh authenticated presence after restart. This avoids acting on stale observations.
- **Use the QR as a permanent credential:** rejected. The durable trust is the pinned device identity; the QR secret is consumed and erased during setup.

We accept that one-second sampling may increase battery and CPU use in exchange for quicker active-screen feedback. We also accept that the monitoring UI can report presence while secure locking remains unavailable, provided it never implies active protection.

## Open questions and risks

- Which maintained Swift library meets the handshake and platform requirements without a custom protocol?
- Can a supported macOS mechanism both request the secure lock screen and provide a trustworthy lock-state observation under the app’s permission and distribution model?
- Will iOS keep the BLE exchange reliable during the deferred 30-minute locked-phone run and repeated range trials?

## Implementation order

1. Implement issue #1 timing and RSSI behavior.
2. Implement the safe issue #2 scope: authenticated QR pairing, revocation, persisted monitoring preference, and disabled lock controls with clear availability status.
3. Apply the status-first UI/UX pass and run the requested deslop cleanup.
4. Update `README.md` and `spec.md` to distinguish implemented behavior from the prototype and keep physical checks and lock capability gates visible.

The implementation sequence is documented in the [issue #1 plan](../plans/2026-11-23-issue-1-rssi-sampling.md), [issue #2 plan](../plans/2026-11-23-issue-2-pairing-monitoring.md), and [status-first UI/UX plan](../plans/2026-11-23-status-first-ui-ux.md).
