# Near But Far app design

**Superseded implementation note (2026-11-24):** The app-screen design now replaces this document's disabled lock-control and unavailable-state guidance. The current app has a separate app-screen state and does not observe or change macOS secure-lock state.


**Status:** Approved by user on 2026-11-23

**Implementation status (2026-11-23):** The current branch implements one-use QR pairing, pinned device identities, authenticated BLE sessions, persistent monitoring preference, and the status-first UI. Physical pairing and monitoring validation remain pending. Lock now and Unlock stay disabled because a supported request and trustworthy lock-state confirmation are not established.

**Updated decisions (2026-11-23):** Keep a one-use QR as the pairing UX; do not use the one-minute short-code option. The QR carries a high-entropy setup secret, expires after two minutes, and is consumed after pairing. Snow 0.10.0's tag contains the eight remediations validated by Trail of Bits; the exact release was not fully audited, and two informational findings were not among those validated fixes. Its Rust-to-Swift C ABI integration passed review and builds for macOS 14 and iOS 17, so implementation stays on those minimum targets. Pairing and authenticated BLE presence are implemented on this branch; physical validation remains pending. Do not use the historical prototype's unauthenticated messages as protection.

**iPhone UI refresh (2026-11-24):** The user approved the complete visual screen atlas and this written specification on 2026-11-24. This addendum records its screen inventory and maps each screen to the current iPhone and Mac state models. No app code is changed by this spec step.

**Scope:** [Issue #1](https://github.com/hornley/near-but-far/issues/1), [Issue #2](https://github.com/hornley/near-but-far/issues/2), then the approved status-first UI/UX pass.

## Problem

The starting app was a BLE prototype that sent unauthenticated challenges and logged “would lock,” but did not lock or confirm the Mac’s lock state. Issue #1 asks for faster status updates; issue #2 adds authenticated monitoring and phone controls. A one-second sampling cadence must not accidentally shorten the existing five-second loss/retry timing, and an unauthenticated presence signal must not be allowed to keep the Mac falsely marked nearby. The current research has not established a supported local mechanism that both requests a secure macOS lock and confirms the resulting state, so lock actions remain unavailable.

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
- The Mac owns and persists the configurable signal threshold (default `-70 dBm`, allowed range `-90...-50 dBm`) and sends it over the authenticated session. The iPhone stores the last authenticated value, applies it to its local estimate, and displays it read-only. Until a value arrives in the current session, label a cached value as last synced; if no cached value exists, show a waiting/unavailable state. Keep the 60-second grace period. A fresh sample at or below the threshold starts the timer; a stronger fresh sample clears it. RSSI is not distance. Missing RSSI, reconnecting alone, or Bluetooth being unavailable does not confirm recovery.
- If a fresh stronger sample and expiry are observed at the same monotonic time, apply the sample first. A lock request already sent cannot be undone by a later recovery.
- If the iPhone disconnects during a weak-signal countdown, preserve the original start time and show **Signal lost**. If the connection drops before a weak sample, start the local estimate on the disconnect callback or after ten seconds without a challenge. When iPhone Bluetooth is unavailable, show **Unavailable** and do not infer that the Mac is away.
- Serialize iPhone RSSI reads. CoreBluetooth does not identify which read produced a late callback, so do not overlap reads or attach a stale RSSI value to a new challenge.
- Use monotonic time for deadlines and countdowns. Use wall-clock time for displayed timestamps and logs.

### Pairing and trust

1. The user opens a pairing window on the unlocked Mac. It lasts two minutes and displays a one-use QR code.
2. The iPhone scans it with camera access and completes a handshake with the Mac. The Mac requires local approval before saving the peer.
3. Store the long-lived device identities in device-only Keychain storage. Consume and erase the QR secret after enrollment; never write it to logs.
4. Permit one paired iPhone at a time. “Forget phone” revokes that identity; pairing a replacement revokes the old phone. The QR is only for setup, not everyday reconnects.
5. Use a maintained implementation of a published handshake and authenticated-encryption protocol. Do not invent cryptography. Select the library only after confirming supported Swift/platform versions, maintenance, license, production suitability, and test vectors. Keep the approved macOS 14 and iOS 17 minimums. If no suitable implementation supports them, authenticated pairing and operational presence stay unavailable until a qualifying library is found.

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

Use the approved **status-first** direction and minimalist copy. Match the approved iPhone Home reference with no extra top inset below the navigation bar, then show a centered **PHONE PRESENCE** card with a subtle outline, large status title, and one signal/threshold summary line. Follow it with three single-line rows for Pairing, Mac monitoring, and Mac lock state, then prominent side-by-side disabled Lock now and Unlock capsule buttons about 64 pt high with one short explanation. Use thin separators between the three rows and compact spacing between groups. Do not add a separate signal card or stacked detail paragraphs. These are separate facts from `PhoneModel`; never derive one from another or add a state the model cannot report. Recent activity is available from the top-right menu and does not appear on Home.

The top-right menu contains **Pair a Mac**, **Scan again**, and **Recent activity**. Pair a Mac opens the existing camera and one-use QR flow. Scan again retries the existing BLE scan/reconnect behavior. Recent activity opens a dedicated screen and returns to Home. The activity screen reads the phone’s existing locally persisted `PhoneCentral.events`; it does not aggregate the Mac’s CSV log. The current event store contains timestamped Bluetooth, scan, connection, restoration, QR error/expiry, and secure-session events, but does not record RSSI or presence-transition history. Sample RSSI, countdown, or pairing-success rows in the visual atlas are placeholders: the app must not display them as real activity unless the implementation first records those events.

### iPhone screen inventory and state mapping

The screens below cover the states exposed by `PhonePresenceState`, `PhoneMacStatus`, `PairingScannerState`, and the current connection model. A state changes the relevant row or pairing sheet; it does not create a new navigation structure.

| Screen or state | Presentation and source |
| --- | --- |
| Home — Waiting for Mac | Show the current connection phase as its supporting line. Do not claim that an authenticated Mac status is missing when the app is still scanning or connecting. |
| Home — Nearby | Show the latest RSSI, when available, and the authenticated Mac threshold as read-only. Distinguish the current session value from a last-synced cached value and waiting/unavailable states. Label RSSI as signal strength, never distance. |
| Home — Weak signal | Show the local 60-second countdown and explain that the signal is at or below the test threshold. |
| Home — Signal lost | Show the local countdown and make clear that the phone has no fresh response. Reconnection alone does not confirm recovery. |
| Home — Lock unavailable | At countdown expiry, say that no lock request was sent and the Mac was not locked. |
| Home — Unavailable | Use only when the phone’s Bluetooth state is unavailable or unauthorized. A disconnect after presence was armed uses Signal lost; a pre-session connection phase remains Waiting for Mac. |
| Pairing menu | Provide Pair a Mac, Scan again, and Recent activity. Pair a Mac starts the camera flow; local approval remains on the Mac. |
| QR scanning | Show the camera preview, a short instruction to scan the one-use QR displayed by the Mac, and Cancel. Use the existing QR payload, two-minute Mac expiry, and secure handshake. |
| Waiting for Mac approval | Show one concise status and the single next step: approve this phone on the Mac and keep this screen open. Do not show the Mac fingerprint on the phone. |
| Pairing complete | Confirm that this phone is paired, then return to Home where live connection state is shown. |
| Pairing recovery — not paired / expired / QR mismatch | State the problem once and provide the existing scan or rescan action. Do not suggest a short code or reuse an expired QR. |
| Pairing recovery — Mac identity mismatch | Say the saved pairing is unchanged and offer Retry connection. Do not silently replace the pinned identity. |
| Pairing recovery — camera unavailable | Direct the user to iPhone Settings for camera access and offer Try camera again. |
| Pairing recovery — secure storage unavailable | Explain that pairing cannot continue and direct the user to restart the app; do not show a retry action that the model cannot perform. |
| Pairing recovery — Bluetooth unavailable | Direct the user to enable Bluetooth in Settings. Resume the existing pairing flow once Bluetooth is available. |
| Pairing recovery — paired, reconnecting | Say that the Mac is saved and the app is waiting for a secure connection; offer the existing Retry connection action when available. |
| Recent activity — empty / populated | Show the existing local phone events in reverse chronological order or a clear empty state. Keep the screen read-only; do not invent RSSI, presence, pairing-completion, or Mac-log entries. |

The approved Signal lost screen requires a local countdown to survive a disconnect that occurs during a weak-signal countdown, and the product rules start a local estimate when the connection drops before a weak sample. The current `PhoneModel.didDisconnect` resets its tracker and countdown state. The implementation plan must correct that state transition before presenting the designed Signal lost countdown; changing only the view would show a false state.

The home screen’s **Mac monitoring** row reflects the authenticated status sent by the Mac: Off, Waiting for authenticated iPhone, Nearby, Weak signal, Signal lost, Unavailable, or Lock unavailable. Show Off only after an authenticated `.unavailable` status is received; before the first status and after disconnect, show Unavailable. `PhoneModel.macStatus` currently uses `.unavailable` both as its initial/reset value and for a received Off status, while the view infers Off from `sessionReady`. The implementation plan must add the smallest state needed to distinguish “no status received” from “Mac reported Off.” The separate **Mac lock state** row remains unavailable. **Lock now** and **Unlock** stay visibly disabled with concise explanations and accessible labels; neither action sends a command.

The Mac owns and persists the editable threshold, default `−70 dBm` in the allowed `−90...−50 dBm` range. It sends the value as an authenticated operational message when a secure session becomes ready, before monitoring statuses or challenges, and after setting changes. The iPhone stores the last authenticated value for its local estimate and displays it read-only. It labels a value as current only after receipt in the current secure session; a cached value while disconnected is labeled last synced, and an active session awaiting delivery shows a waiting state.

The iPhone home screen keeps the compact reference layout without an inline activity disclosure. Its status card combines local presence with the latest RSSI and authenticated Mac threshold; the three following rows show pairing, authenticated Mac monitoring, and Mac lock-state observation. Pairing and recovery details stay concise, while the status card retains the countdown and critical no-lock-request message when applicable. Recent activity is a separate screen opened from the top-right menu. The Mac status-first home and settings screen provide the editable threshold. Keep Mac state meanings aligned with `MacCoordinator` and peer messages.

Use concise, state-specific copy with one next step on pairing and recovery screens. Preserve native camera and Bluetooth permission prompts. Use text and VoiceOver labels in addition to color. Do not add a distance estimate, graph, cloud account, lock-state claim, or phone-side threshold control.

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

- The phone home screen keeps local presence, pairing, authenticated Mac monitoring status, Mac lock observation, signal strength, and disabled actions separate.
- Each of the six local presence states and every pairing recovery state maps to an existing model value or connection phase; the UI does not invent a success, failure, or permission state.
- The top-right menu opens Pair a Mac, Scan again, and Recent activity. Recent activity uses the existing local phone event store, with no invented signal history or Mac events.
- The phone never reports a Mac lock state it cannot verify. Lock now and Unlock remain disabled and send no command. RSSI is shown as signal strength, never as distance.
- The one-use QR flow, Mac-side approval, two-minute expiry, pinned identity, and retry/cancel behavior remain unchanged.
- The Mac persists its `−70 dBm` default threshold within the `−90...−50 dBm` range and sends it over the authenticated session. The iPhone displays the received value read-only, distinguishes current-session from last-synced data, and waits clearly when no value is available.
- Pairing, Bluetooth-unavailable, disconnected, weak-signal, and countdown-expiry states are understandable and accessible without relying on color alone.

## Validation carried forward

The prototype handoff still lists the 30-minute background-and-locked-phone run, ten varied-orientation range trials, out-of-range-before-weak-sample behavior, Bluetooth-unavailable screens, and exact 60-second boundary ordering as pending. Keep them pending until performed. They do not block starting implementation, but automatic locking remains unavailable until the reliability checks and lock-confirmation gate pass. Also compare battery and CPU use at the one-second cadence.

## Alternatives and tradeoffs

- **Separate actor for pairing, presence, and commands:** rejected for this scope. It isolates state, but introduces asynchronous hand-offs and competing state owners for one Mac and one phone. The coordinator provides a smaller interface and clearer ordering.
- **Put policy directly in `MacPeripheral`:** rejected because issue #2 would combine CoreBluetooth transport, persistent preference, pairing, and lock decisions in the same object. A transport adapter should not be able to treat a raw acknowledgement as authorization.
- **Persist countdown/session state:** rejected in favor of waiting for fresh authenticated presence after restart. This avoids acting on stale observations.
- **Use the QR as a permanent credential:** rejected. The durable trust is the pinned device identity; the QR secret is consumed and erased during setup.

We accept that one-second sampling may increase battery and CPU use in exchange for quicker active-screen feedback. We also accept that the monitoring UI can report presence while secure locking remains unavailable, provided it never implies active protection.

## Open questions and risks

- Can the pinned Snow release build behind the narrow Rust-to-Swift C ABI on the current macOS 14 and iOS 17 targets? **Yes.** The reviewed integration spike built macOS arm64/x86_64, iOS device arm64, and iOS simulator arm64/x86_64.
- Can a supported macOS mechanism both request the secure lock screen and provide a trustworthy lock-state observation under the app’s permission and distribution model?
- Will iOS keep the BLE exchange reliable during the deferred 30-minute locked-phone run and repeated range trials?

## Implementation order

1. Implement issue #1 timing and RSSI behavior.
2. Implement the safe issue #2 scope: authenticated QR pairing, revocation, persisted monitoring preference, and disabled lock controls with clear availability status.
3. Apply the status-first UI/UX pass and run the requested deslop cleanup.
4. Update `README.md` and `spec.md` to distinguish implemented behavior from the prototype and keep physical checks and lock capability gates visible.

The implementation sequence is documented in the [issue #1 plan](../plans/2026-11-23-issue-1-rssi-sampling.md), [issue #2 plan](../plans/2026-11-23-issue-2-pairing-monitoring.md), and [status-first UI/UX plan](../plans/2026-11-23-status-first-ui-ux.md).
