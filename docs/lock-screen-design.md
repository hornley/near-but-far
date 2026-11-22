# Lock Screen Design

## Selected direction: Quiet Graphite

A calm, minimal lock screen on a near-black graphite background with a subtle soft glow. The layout shows the time and date, a simple lock symbol, and the generic message **“Mac is locked”** with **“Use Touch ID or password to return.”**

The screen does not reveal the lock reason, account name, notifications, or app previews. The project mark is lowercase `nbt`; it is not shown on the lock screen in the approved mockup, to keep the screen quiet and system-like.

## Security and interaction

The T3 mockup is a visual reference only. A working app must invoke macOS's secure lock screen rather than rely on a custom full-screen window. macOS handles authentication; keyboard and trackpad cannot access the previous session until authentication succeeds.

The mockup's time and date are illustrative. A real lock screen should use the Mac's locale and clock settings.
