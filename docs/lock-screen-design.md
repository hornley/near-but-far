# App Screen Design

## Selected direction: Quiet Graphite app screen

A calm, minimal app-owned screen on a near-black graphite background with a subtle soft glow. The layout shows the Mac's time and date, a simple lock symbol, and the message **“Mac is locked”** with **“Use Touch ID or password to return.”** The card opens macOS's Local Authentication prompt; the app never collects a password.

The screen does not reveal the lock reason, account name, notifications, or app previews. The project mark is lowercase `nbt`; it is not shown on the lock screen in the approved mockup, to keep the screen quiet and system-like.

## Security and interaction

This implemented screen is an app-level deterrent, not macOS's secure lock screen. The Mac menu's **Lock now** activates it and shows whether the app screen is Active or Inactive. Local return uses the card's macOS Local Authentication prompt; there is no Mac menu Unlock button. The authenticated iPhone can activate or dismiss it, and a fresh authenticated phone return can dismiss an away-triggered screen. The app uses full-screen AppKit presentation options to cover the desktop and suppress common shortcuts while it is active. macOS handles local authentication. The overlay can still be stopped through other system or physical means. The app does not observe or change macOS's secure lock state.

The mockup's time and date are illustrative. The app screen uses the Mac's locale and clock settings. See the [app screen protection design](superpowers/specs/2026-11-24-app-screen-protection-design.md) for behavior and limits.
