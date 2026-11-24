# Mac Pairing Menu Reliability Design

**Status:** Approved by the user via `$workflow-plan` on 2026-11-24.

**Issue:** [#2 — Add secure pairing and Mac monitoring controls; gate remote lock](https://github.com/hornley/near-but-far/issues/2).

## Goal

Make pairing, settings, and confirmation interactions predictable in the Mac menu-bar app. Keep those views in one panel so they cannot overlap. Cancelling a Forget or Replace confirmation returns to the paired-phone view and leaves the saved identity unchanged.

## Evidence and current structure

The supplied recording shows the Replace confirmation, then the menu panel disappears around the time the pointer is near Cancel. When Pair iPhone is opened again, it shows the paired phone and its Forget and Replace actions. Later, Settings appears layered over Pair iPhone.

The implementation currently presents PairingView as a sheet from MenuBarExtra, changes the underlying Home/Settings content separately, and attaches two confirmation dialogs to the same PairingView. See `Sources/Mac/NearButFarMacApp.swift` and `Sources/Mac/PairingView.swift`.

The recording does not show a destructive action being confirmed, so it does not establish whether forgetting or replacing the identity succeeds.

## Selected design

Use one menu-bar panel with a single active page: Home, Settings, or Pair iPhone. Present Pair iPhone as a page inside the MenuBarExtra content rather than as a sheet. This makes Settings and Pair iPhone mutually exclusive.

Replace the two independent confirmation flags with one confirmation state that identifies Forget or Replace. Render the confirmation inside the same panel, with a clear destructive action and a Cancel action. Cancel clears the confirmation state and leaves Pair iPhone showing the current phone. It does not dismiss the panel or touch Keychain state.

The Forget action removes the saved phone identity only after explicit confirmation and leaves the user on Pair iPhone with no phone paired. The Replace action removes the old identity and starts a new QR pairing only after explicit confirmation. Its message must explain that the existing phone loses access and a new setup code will be created.

Closing Pair iPhone remains a separate navigation action. If a temporary QR offer or pending pairing request exists, use the existing pairing cancellation path and erase the setup secret. If no offer or request is active, closing the page does not alter the paired identity.

The Settings button is unavailable while Pair iPhone is the active page. The Pair iPhone page has a clear back/close action to return to its originating menu page. This avoids opening Settings on top of an active pairing or confirmation page.

## Approaches considered

1. **Keep the sheet and consolidate dialogs.** Smallest change, but Settings can still open over Pair iPhone and the pairing view remains a separate presentation.
2. **Use one menu-bar page route and one in-panel confirmation state (selected).** Addresses both the visible overlap and the confusing Cancel behavior while keeping existing coordinator-owned pairing state.
3. **Move pairing to a separate app window.** Gives explicit window ownership, but adds window lifecycle and focus behavior without improving this menu flow.

## Scope

This change is limited to Mac menu navigation and pairing confirmation behavior. It does not change the pairing protocol, QR lifetime, key storage, phone app, BLE monitoring, app-screen behavior, or macOS lock claims.

## Acceptance criteria

- Home, Settings, Pair iPhone, and a pairing confirmation are shown one at a time in the menu-bar panel.
- Opening Pair iPhone does not create a second panel or sheet.
- Canceling Forget returns to the paired-phone view in the same panel; the phone remains paired.
- Canceling Replace returns to the paired-phone view in the same panel; the phone remains paired and no QR code is created.
- Confirming Forget clears the saved identity and leaves Pair iPhone open with no phone paired.
- Confirming Replace clears the old identity and starts a fresh one-use QR pairing flow.
- Closing Pair iPhone is separate from Cancel. Closing during an active QR offer or pending request follows existing cancellation and secret-erasure behavior.
- The destructive actions are explicit and cannot occur from Cancel, navigation, or closing the menu.
- The Mac target builds. Automated checks cover the confirmation state transitions where practical; a visible walkthrough confirms the user-facing flow when the menu-bar app is accessible to computer-use automation.

## Risks and safeguards

- A route change could accidentally start another QR offer. Keep pairing-session data in `MacCoordinator` and make page navigation presentation-only.
- Forget and Replace have different outcomes. Keep their commands separate and test that Cancel invokes neither.
- A QR offer may expire while its page is hidden. Existing expiry behavior remains authoritative; returning to Pair iPhone displays the coordinator's current status.
- Computer Use currently times out when attaching to the menu-bar app with `-10005`. Automated checks and builds can proceed, but visible confirmation remains unverified until that bridge works.
