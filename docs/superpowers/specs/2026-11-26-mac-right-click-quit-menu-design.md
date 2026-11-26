# Mac Right-Click Quit Menu Design

**Status:** Approved by the user on 2026-11-26 via `$workflow-plan approved`.

**Issue:** [#8 — Add a right-click menu with a Quit action](https://github.com/hornley/near-but-far/issues/8).

## Goal

Let users quit Near But Far from a compact menu opened by right-clicking its macOS menu bar icon, while preserving the current app panel on left-click.

## Current behavior

`NearButFarMacApp` uses SwiftUI `MenuBarExtra` with window style. Left-click opens a panel that contains the presence-monitoring toggle, connection status, app-screen action and state, Settings navigation, and Pair iPhone flow. The app screen observes `NSApplication.willTerminateNotification` and dismisses its overlay, restoring the previous presentation options.

## Selected design

Use an AppKit `NSStatusItem` to route the two mouse buttons to separate actions. Left-click presents the existing SwiftUI panel in an `NSPopover`. Right-click opens a native `NSMenu` containing one item labeled **Quit**. Selecting it calls the normal application termination path so the existing termination observer can dismiss the app-screen overlay and restore macOS presentation options.

Keep a single long-lived `MacCoordinator` and menu state while the popover opens and closes. Opening or dismissing the panel must not restart monitoring, reset pairing state, or create another status item. Give the status item an accessible name, and provide an accessibility action that opens the Quit menu. The native menu item keeps Quit available to keyboard and assistive-technology users once the menu is open.

## Approaches considered

1. **AppKit status item with a SwiftUI popover and native right-click menu (selected):** Preserves the current left-click panel and provides the separate Quit-only menu. It requires explicit ownership of the status item, popover, and click routing.
2. **SwiftUI `MenuBarExtra` with menu style:** Provides a native menu with less custom event handling. It associates one menu with the status item and does not provide the requested separate left- and right-click behaviors, so the current window-style panel would need to be redesigned.

## Scope

This change covers the macOS menu bar item and its presentation and termination behavior. The right-click menu contains only **Quit**. Existing panel content, settings, pairing, monitoring, iPhone behavior, and app-screen policy remain as they are.

## Acceptance criteria

- Left-clicking the menu bar icon opens the existing SwiftUI panel with its current controls and navigation.
- Right-clicking the menu bar icon opens a native menu with exactly one item, **Quit**.
- Selecting **Quit** terminates the app through normal AppKit application termination.
- Normal termination invokes the existing app-screen cleanup, closing overlay windows and restoring the saved presentation options.
- Opening and dismissing the popover preserves the same coordinator, monitoring session, pairing state, and menu navigation state.
- The status item has a clear accessibility name and an accessibility action to open the Quit menu; the native Quit action is accessible from that menu.
- The macOS target builds, and a visible walkthrough confirms left-click, right-click, and Quit behavior.

## Risks and safeguards

- Replacing `MenuBarExtra` can change panel lifetime or dismiss behavior. Keep one controller and one SwiftUI root for the status item, and verify the existing panel's controls and navigation after the move.
- AppKit status items can show the wrong menu if click routing is not explicit. Test left- and right-click separately and assert that the context menu has only the Quit item.
- A forced process exit would bypass lifecycle cleanup. Use AppKit's normal termination action and verify the existing `willTerminateNotification` observer still runs.
