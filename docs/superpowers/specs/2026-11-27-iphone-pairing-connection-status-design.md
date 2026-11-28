# iPhone Pairing Connection Status and Error Evidence

**Status:** Approved by the user on 2026-11-27 via `$workflow-plan`, following the earlier selection of the recommended approach.

**Issue:** [#2 — Add secure pairing and Mac monitoring controls; gate remote lock](https://github.com/hornley/near-but-far/issues/2).

## Goal

Make the iPhone distinguish connecting to the Mac from waiting for Mac approval. Record the Bluetooth connection error locally so a failed physical pairing can be fixed from its actual cause. Preserve the current one-time Mac approval policy.

## Evidence

On 2026-11-27, a fresh physical QR scan was followed by six `connect_failed` events and no `connected` event. The Mac was advertising, but its pairing view showed no incoming request.

`PhoneCentral.acceptScannedPayload` currently sets `.waitingForMacApproval` immediately after validating the QR, before it scans or connects. Its `didFailToConnect` callback records only the generic `connect_failed` event and discards the CoreBluetooth error. The Mac shows the approval card only after the secure pairing session emits a candidate.

## Selected design

After accepting a valid QR, show **Connecting to Mac** while the phone scans, connects, discovers the pairing service, and starts the secure enrollment request. Change the phone status to **Waiting for Mac approval** only after CoreBluetooth reports successful writes for the enrollment request. Keep the Mac's approval card gated on the existing authenticated candidate event.

When CoreBluetooth calls `didFailToConnect`, store the error domain and numeric code in the phone's existing local activity log. Do not log the QR payload, setup secret, identity key, or other pairing material. Keep the existing retry and pairing security behavior.

## Approaches considered

1. **Correct the phone status and log the transport error (selected).** This preserves the approved pairing protocol while exposing the real connection phase and enough local evidence to diagnose the failure.
2. **Ask for approval on every connection.** This conflicts with the existing one-time approval policy and does not repair a connection that fails before the secure session.
3. **Reset stored identities or change transports.** This is broader and may discard trusted pairing state without evidence that storage or transport choice caused the current failure.

## Scope

Change the iPhone enrollment connection and status/logging only as needed to restore the fresh pairing flow. Do not change QR format or lifetime, key storage, the secure protocol, the one-time Mac approval policy, established reconnect behavior, RSSI monitoring, app icons, or Xcode signing settings.

## Acceptance criteria

- Scanning a valid QR shows **Connecting to Mac**, not an approval claim.
- The phone shows **Waiting for Mac approval** only after CoreBluetooth reports successful writes for the secure enrollment request.
- A failed CoreBluetooth connection adds its error domain and code to the phone's local activity log without pairing secrets.
- A fresh physical pairing reaches the Mac approval card; approving it completes the authenticated pairing on both devices.
- The Mac continues to ask for approval once for a new or replacement phone; normal authenticated reconnects do not ask again.
- Existing retry behavior and pairing identity rules remain unchanged.
- The iPhone target builds and the complete pairing flow is verified on the connected physical iPhone.
