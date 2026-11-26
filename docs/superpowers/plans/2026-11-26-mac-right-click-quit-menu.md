# Mac Right-Click Quit Menu Implementation Plan

> **For agentic workers:** Use `workflow-implementation`. Implementation is subagent-only. Keep the code and review gates in the dependency order below.

**Goal:** Add a native Quit-only menu on right-click while preserving the current SwiftUI panel on left-click.

**Architecture:** An AppKit controller owns one `NSStatusItem`, a transient `NSPopover`, and a native `NSMenu`. The popover hosts the existing SwiftUI panel as one persistent root view, preserving `MacCoordinator` and `MacMenuState`. The right-click menu's Quit command uses normal app termination so the existing overlay cleanup notification runs.

**Tech Stack:** Swift, SwiftUI, AppKit, Xcode.

---

**Issue:** [#8 — Add a right-click menu with a Quit action](https://github.com/hornley/near-but-far/issues/8).

**Approved specification:** [Mac Right-Click Quit Menu Design](../specs/2026-11-26-mac-right-click-quit-menu-design.md), approved by the user on 2026-11-26.

**Plan status:** Ready for implementation. Implementation has not started.

**Change branch:** `t3/right-click-quit-menu`, based on `origin/main`.

**Dependency order:** Task 1 implements the cohesive status item and panel integration. Task 2 checks spec compliance. Task 3 reviews code quality after spec compliance passes. Task 4 performs integration, final review, and the specified validation. The implementation stays in one task because the AppKit status item, popover lifetime, app bootstrap, and SwiftUI state ownership must change together. No implementation tasks are ready to run in parallel.

## File ownership

| Task | Files owned |
| --- | --- |
| 1. Status item and panel integration | `Sources/Mac/NearButFarMacApp.swift`; create `Sources/Mac/MacMenuBarController.swift`; create `Sources/Mac/MacMenuBarPanel.swift`; `NearButFar.xcodeproj/project.pbxproj` |
| 2. Specification-compliance review | Read-only review of Task 1 files and the approved spec; no file ownership |
| 3. Code-quality review | Read-only review of Task 1 files; no file ownership |
| 4. Integration and final review | Read-only review of the complete diff; coordinator owns integration and validation, with no concurrent source edits |

## Task 1: Replace the SwiftUI menu-bar scene with a routed AppKit status item

**Owner:** Implementation worker — GPT-6 Luna, Medium reasoning, in an isolated worktree.

**Depends on:** None.

**Files:** `Sources/Mac/NearButFarMacApp.swift`; create `Sources/Mac/MacMenuBarController.swift`; create `Sources/Mac/MacMenuBarPanel.swift`; `NearButFar.xcodeproj/project.pbxproj`.

**Acceptance criteria:** The app creates one status item. Left-click opens the existing panel in a popover and preserves its controls, navigation, and state. Right-click opens a native menu containing exactly **Quit**. The status item exposes an accessible name and an accessibility action that opens the Quit menu. Selecting **Quit** uses normal AppKit termination.

- [ ] Move the existing panel content from `NearButFarMacApp.swift` into `MacMenuBarPanel.swift`. Keep the `MacCoordinator` and `MacMenuState` ownership in the single persistent panel root. Pass an `onClose` action into the panel so its close button asks the controller to close the popover.
- [ ] Add `MacMenuBarController` in `MacMenuBarController.swift`. It owns one `NSStatusItem`, one transient `NSPopover`, and one `NSMenu`; create and retain the SwiftUI hosting controller once so opening the popover does not recreate the coordinator or menu state. Anchor the popover to the status-item button and close it before showing the context menu.
- [ ] Route the status-item button's events explicitly with `sendAction(on:)`. Left mouse-up toggles the popover; right mouse-up opens the Quit menu. Control-click also opens the Quit menu. Use the current AppKit event type to choose the action:

  ```swift
  guard let event = NSApp.currentEvent else { return }
  switch event.type {
  case .rightMouseUp:
      showQuitMenu()
  case .leftMouseUp where event.modifierFlags.contains(.control):
      showQuitMenu()
  case .leftMouseUp:
      togglePopover()
  default:
      break
  }
  ```

  Present the native menu at the status-item button with `NSMenu.popUp(positioning:at:in:)` so it behaves as a context menu anchored to the icon.

- [ ] Build the Quit menu with one item and no separators or additional actions. Target the standard application termination selector:

  ```swift
  let quitItem = NSMenuItem(
      title: "Quit",
      action: #selector(NSApplication.terminate(_:)),
      keyEquivalent: "q"
  )
  quitItem.target = NSApp
  quitMenu.addItem(quitItem)
  ```

- [ ] Add an accessibility label to the status-item button and an accessibility custom action named **Show Quit menu** that calls the same menu-presentation method as right-click. Keep the native Quit menu item available to keyboard and assistive-technology users after it opens.
- [ ] Adapt `NearButFarMacApp.swift` to retain a `MacMenuBarAppDelegate` through `@NSApplicationDelegateAdaptor`; initialize the controller once in `applicationDidFinishLaunching(_:)`. Keep the app running when the popover closes, create no second status item or user-facing window, and preserve the existing accessory-app behavior.
- [ ] Register both new Swift files in the NearButFarMac target in `NearButFar.xcodeproj/project.pbxproj`.
- [ ] Self-review the complete implementation diff against the approved spec. Commit the feature as `feat: add right-click quit menu`.

## Task 2: Review specification compliance

**Owner:** Spec-compliance reviewer — GPT-6.1 Sol, Low reasoning.

**Depends on:** Task 1.

**Files:** Read-only review of the Task 1 files and the approved specification.

**Acceptance criteria:** Every approved acceptance criterion is represented in the code, and the implementation adds no extra right-click menu actions or unrelated behavior.

- [ ] Verify left-click still opens the existing panel and the panel retains its controls, navigation, coordinator, monitoring session, pairing state, and menu state.
- [ ] Verify right-click and Control-click open exactly one native menu item labeled **Quit**; verify the accessibility custom action opens the same menu.
- [ ] Verify the Quit item targets normal application termination and leaves the existing `willTerminateNotification` cleanup path intact.
- [ ] Report findings only. Route any required fix to a bounded follow-up for the implementation worker, then repeat this review before Task 3.

## Task 3: Review code quality

**Owner:** Code-quality reviewer — GPT-6.1 Sol, Low reasoning.

**Depends on:** Task 2 passing.

**Files:** Read-only review of `NearButFarMacApp.swift`, `MacMenuBarController.swift`, `MacMenuBarPanel.swift`, and the project-file changes.

**Acceptance criteria:** Click routing, ownership, event and popover lifetime, and accessibility wiring are clear and safe. The change creates one status item and does not restart monitoring when the popover opens or closes.

- [ ] Review event routing for left-click, right-click, Control-click, and the accessibility custom action.
- [ ] Review object ownership for the status item, controller, popover, hosting controller, and SwiftUI state so the controller and panel remain alive until app termination.
- [ ] Review app termination behavior and confirm the implementation calls AppKit's normal termination path.
- [ ] Report findings only. Route any correctness or maintainability fix to the implementation worker and repeat affected review gates before Task 4.

## Task 4: Integrate and complete final review

**Owner:** Coordinator for integration and validation; final reviewer — GPT-6.1 Sol, Low reasoning.

**Depends on:** Tasks 1–3 passing.

**Files:** Read-only final review across the approved spec and complete integrated diff; coordinator runs validation.

**Acceptance criteria:** The integrated change meets the approved spec, the macOS target builds, and a visible walkthrough confirms the panel and context-menu behavior.

- [ ] Review the integrated diff against every acceptance criterion and confirm there are no iOS, pairing-protocol, monitoring-policy, or app-screen behavior changes outside the approved scope.
- [ ] Build the Mac target with `xcodebuild build -project NearButFar.xcodeproj -scheme NearButFarMac -destination 'platform=macOS'`. Expected result: `BUILD SUCCEEDED`.
- [ ] With the Near But Far Mac app running and its app screen inactive, use the visible Mac app UI to confirm left-click opens the existing panel, its Settings and Pair iPhone navigation remains usable, right-click shows only **Quit**, and selecting **Quit** exits the app.
- [ ] Confirm the status item has the intended accessibility name and that the **Show Quit menu** accessibility action and native Quit item are exposed through accessibility inspection or VoiceOver.
- [ ] Review the existing `NSApplication.willTerminateNotification` observer and confirm its cleanup remains connected to normal Quit. Record any live cleanup limitation if the overlay state cannot be exercised through the new menu.
- [ ] Record the build and walkthrough results in the implementation handoff; leave pull request, merge, and release steps for their workflow stages.

## Spec coverage

- Separate left-click panel and right-click Quit menu: Tasks 1 and 2.
- One persistent coordinator, monitoring session, pairing state, and menu state: Tasks 1–3.
- Accessible status item, menu action, and Quit item: Tasks 1, 2, and 4.
- Normal termination and overlay cleanup: Tasks 1–4.
- Mac build and visible behavior walkthrough: Task 4.
