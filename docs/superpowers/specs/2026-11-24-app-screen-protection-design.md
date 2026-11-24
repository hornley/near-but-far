# App Screen Protection Design

**Status:** The app-overlay direction was approved by the user on 2026-11-24. This detailed spec is ready for user review before implementation.

**Scope:** Re-scope Issue #2's unavailable Lock now and Unlock controls to operate an app-owned screen overlay. This replaces the earlier requirement that the app invoke and confirm macOS's secure lock screen. It does not change Issue #1 sampling intervals, the five-second response/retry timing, the ten-second phone fallback, the configured signal threshold, or the 60-second away grace period.

## Goal and limits

When monitoring decides the paired iPhone is away, show a full-screen screen that discourages someone from casually using the Mac. The screen also opens immediately when the user taps **Lock now** on the iPhone.

This is app-level screen protection. It does not lock the macOS session or protect files from a determined person. macOS can still be restarted, and someone with sufficient access can stop the app. The UI and protocol must not report that macOS itself is locked.

## Visual design

Use the supplied Quiet Graphite samples, also described in [the lock screen design](../../lock-screen-design.md): a near-black background, a centered rounded card, the Mac's current time and date, a simple lock icon, **Mac is locked**, and **Use Touch ID or password to return.** Adapt the card to the display size and locale. Show it on every active Mac display.

The card is an accessible control that opens macOS's Local Authentication prompt. The app never draws a password field or receives the password. **Mac is locked** is the selected name for the app screen; the phone UI labels this state **App screen active** so it remains distinct from a macOS lock-state observation.

## Approaches considered

1. **Plain full-screen window:** Simple, but leaves common app-switching and Force Quit controls available. It does not meet the requested deterrence.
2. **macOS secure lock screen:** Stronger protection, but no supported local-app request and confirmation path was found in the Apple APIs reviewed. Apple's documented Device Lock command is an MDM endpoint requiring Mac supervision and a management access right.
3. **Full-screen AppKit kiosk presentation (selected):** Show an app-owned overlay and use documented presentation options to suppress common exits while it is active. This fits the requested behavior while keeping its weaker protection explicit.

## Behavior

### Showing the screen

- An authenticated **Lock now** request from the paired iPhone shows the overlay immediately.
- When monitoring is enabled, the existing Mac presence tracker shows it after the existing 60-second weak-signal or connection-loss grace period expires.
- A fresh stronger RSSI sample before expiry cancels the pending automatic screen.
- Bluetooth unavailable is not proof that the phone is away and does not trigger the overlay.
- If Bluetooth becomes unavailable while the overlay is already active, keep the overlay active; only local authentication can dismiss it until a secure phone session returns.
- Turning monitoring off stops future automatic triggers. It does not dismiss an overlay already showing.

### Dismissing the screen

Provide all three approved paths:

1. **Unlock on iPhone:** An authenticated message from the paired phone dismisses the overlay.
2. **Phone returns:** A fresh authenticated RSSI sample above the Mac's current threshold dismisses an overlay that was triggered by absence. Reconnecting by itself is not enough. A manual lock can auto-dismiss after a complete away-then-return transition. If the phone is already weak or disconnected when the manual lock is activated, return is already armed; if it is nearby, the Mac arms return after observing a weak or disconnected state while the screen is active. This prevents the next routine sample from undoing a manual lock immediately.
3. **Touch ID or password on Mac:** Activating the screen's card opens `LocalAuthentication` with the system's device-owner authentication policy. macOS handles the prompt. A cancelled, unavailable, or failed authentication leaves the overlay active. macOS may offer another supported system factor such as Apple Watch.

If the secure phone session is unavailable, phone controls cannot change the screen. Local authentication remains available. A new BLE connection without a fresh strong sample never clears it.

### AppKit presentation

Show a borderless full-screen overlay on each active display. While it is active, use `NSApplication.presentationOptions` to hide the Dock and menu bar and request the documented kiosk restrictions for app switching, Force Quit, Apple-menu actions, hiding the app, and session-termination panels. Restore the app's prior presentation options after dismissal. Ignore ordinary keyboard input in the overlay; the Local Authentication prompt is the only local credential path.

These options suppress common exits while the app is active. They do not prevent every system-level or physical way to stop the app, including a restart or external process termination. The overlay state stays in memory; after the app restarts, monitoring follows the existing fresh-authenticated-presence startup rule.

## State and message ownership

- `MacCoordinator` owns the app-screen state and decides when monitoring transitions show or dismiss the screen.
- A Mac-side overlay controller owns the AppKit windows and presentation options. It presents the state; it does not decide whether the phone is nearby.
- `PeerSession` carries authenticated app-screen commands and state. Use app-screen terminology in the wire protocol; do not add messages that claim to lock or unlock the macOS session.
- `PhoneModel` stores the last authenticated app-screen state. Replace the iPhone's **Mac lock state** row with **App screen** and show Active, Inactive, or Unavailable. Keep **Lock now** and **Unlock** enabled only when the authenticated session can carry the command. Explain in the phone UI that these buttons control the app screen, not macOS's secure lock.
- An unauthenticated, malformed, replayed, or stale message cannot change the screen state. On disconnect, show App screen as Unavailable on the phone; do not infer that the Mac dismissed it.

## Acceptance criteria

- Automatic screen activation follows the existing presence threshold and 60-second grace period. A fresh recovery sample before expiry prevents activation.
- The paired iPhone can activate and dismiss the screen through authenticated commands, and the phone shows the Mac's authenticated app-screen state.
- A fresh return sample dismisses an away-triggered screen; reconnect alone does not. A manual lock made while the phone is already nearby remains active until explicit unlock, local authentication, or a complete away-then-return transition.
- The supplied design adapts to each active display. Ordinary pointer and keyboard input cannot reach applications behind the overlay while it is visible.
- On supported macOS versions, verify the documented AppKit kiosk restrictions for Command-Tab, Force Quit, and the session-termination panel. Clearly record any routes that remain available.
- VoiceOver can focus and activate the card. Local authentication uses the system prompt, and no app code reads, stores, or logs a password. Cancelling or failing authentication leaves the screen active.
- The phone never presents the app overlay as proof that macOS's secure lock screen is active.
- Physical BLE sampling, pairing, reconnection, and Bluetooth-unavailable checks remain required before relying on automatic screen changes.

## References

- [NSApplication.PresentationOptions](https://developer.apple.com/documentation/appkit/nsapplication/presentationoptions-swift.struct)
- [LAPolicy.deviceOwnerAuthentication](https://developer.apple.com/documentation/localauthentication/lapolicy/deviceownerauthentication)
- [Apple Device Lock command](https://developer.apple.com/documentation/devicemanagement/device-lock-command)
