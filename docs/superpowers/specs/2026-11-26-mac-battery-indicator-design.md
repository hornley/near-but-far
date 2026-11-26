# Mac Battery Indicator Design

**Status:** Approved by the user on 2026-11-26.

**Issue:** [#6 — Show Mac battery percentage on the lock screen and in the iPhone app](https://github.com/hornley/near-but-far/issues/6).

## Goal and limits

Show the Mac's current battery percentage at a glance on NearButFar's app-owned Mac screen and in the iPhone app. The app screen remains separate from macOS's secure lock screen and does not read or change macOS lock state.

The value is the Mac's battery level, not the iPhone's. The feature does not change presence detection, app-screen activation, authentication, or lock behavior.

## Visual design

Keep the existing Quiet Graphite treatment and the Mac screen's time, date, and authentication card.

- **Mac app screen:** Put a small, outlined battery icon with the percentage inside it near the top center of the screen. Leave clearance below the top edge for a MacBook camera notch. Do not add a “Mac” label or a separate battery card. Keep the clock, date, and authentication card in their current hierarchy.
- **iPhone home screen:** Show the same percentage-in-battery icon, smaller than the Mac version, centered directly below the RSSI reading. Do not add a “Mac” label, an extra card, or a separate meter.
- Use a quiet neutral outline and readable percentage. Do not rely on color to communicate the battery level.
- The icon is informational and is not interactive.

## Data and freshness

- Read the Mac's current battery percentage from macOS's power-source information.
- Send the initial value, subsequent changes, and a refresh at least once per minute through the existing authenticated Mac–iPhone session. Do not send battery data over the unauthenticated BLE discovery path or couple it to the one-second RSSI cadence.
- The Mac screen uses the local reading. The iPhone displays the authenticated Mac reading for the active session.
- When the Mac has no readable battery level, show an em dash inside the icon. If the phone session disconnects or no authenticated refresh arrives for two minutes, replace the last percentage with an em dash until a fresh value arrives. Do not present an old percentage as current.
- VoiceOver announces “Mac battery, [percentage] percent” for a valid value, and “Mac battery unavailable” for the em-dash state.

## Approaches considered

1. **Small centered icon near the top (selected):** Matches the user's reference, keeps the percentage visible, and avoids competing with the clock and authentication card. The phone uses the same symbol at a smaller size below RSSI.
2. **Battery row inside the Mac authentication card:** More prominent, but adds content to the card that is meant to focus on returning to the Mac.
3. **Top-right labeled badge:** Easy to identify, but adds text and does not match the requested centered, minimalist treatment.

## Acceptance criteria

- The Mac app screen shows the current Mac percentage inside a small battery icon centered near the top, with space for a camera notch and no “Mac” label.
- The iPhone home screen shows the Mac percentage inside a smaller battery icon centered directly below the RSSI value, with no extra “Mac” text or card.
- The Mac display updates when its reported battery percentage changes. A fresh reading is sent when the authenticated session starts and at least once per minute; changed values are delivered through that session.
- An unavailable, disconnected, or stale reading is not displayed as a current percentage; the icon shows an em dash until a fresh value is available.
- VoiceOver identifies the battery value or unavailable state.
- The existing clock, date, authentication card, RSSI display, and app-screen behavior remain intact. The feature does not claim to observe or control macOS's secure lock state.
- The top placement clears the camera notch on notched Mac displays and remains centered on displays without a notch.
