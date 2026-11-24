# Mac Pairing Menu Reliability Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

Project workflow requires the `workflow-implementation` stage, which delegates every coding task to a subagent; do not execute this plan inline.

**Goal:** Keep Home, Settings, Pair iPhone, and its Forget/Replace confirmations in one predictable menu-bar panel.

**Architecture:** `NearButFarMacApp` owns a small route state for Home, Settings, and Pair iPhone. Pairing remains in `MacCoordinator`; opening or closing a page does not mutate the saved identity except through the existing explicit pairing-cancel path. A single in-panel confirmation state selects Forget or Replace, and Cancel clears that state without calling either destructive operation.

**Tech Stack:** Swift 5, SwiftUI, AppKit, XCTest, Xcode.

---

**Approved spec:** `docs/superpowers/specs/2026-11-24-mac-pairing-menu-reliability-design.md`.

**Issue:** [#2 — Add secure pairing and Mac monitoring controls; gate remote lock](https://github.com/hornley/near-but-far/issues/2).

**Plan status:** Ready for workflow implementation. Several files named below already contain uncommitted app-screen work. Treat those existing hunks as the starting state, preserve them, and make no task-level commits or whole-file staging. The workflow pull-request stage must review and stage the final combined change deliberately.

## Files and responsibilities

- Create `Sources/Mac/PairingMenuState.swift` — pure route and confirmation state shared by the menu view and its tests.
- Modify `Sources/Mac/NearButFarMacApp.swift` — render one active menu page, route Pair iPhone from Settings, and remove the sheet presentation.
- Modify `Sources/Mac/PairingView.swift` — render its existing paired/QR/request states within the menu panel, add an in-panel Forget/Replace confirmation, and report page-close actions to its parent.
- Modify `Sources/Mac/MacCoordinator.swift` — keep pairing side effects and QR lifecycle; remove sheet/dialog presentation flags and return a typed result when a phone is already paired.
- Modify `Tests/NearButFarTests.swift` — verify route exclusivity, Cancel behavior, and that a destructive action is returned only after explicit confirmation.
- Modify `NearButFar.xcodeproj/project.pbxproj` — add `PairingMenuState.swift` to the Mac and test targets.
- Modify `docs/project-handoff.md` — record the completed menu behavior and any visible UI checks that remain pending.

`NearButFarMacApp.swift`, `MacCoordinator.swift`, `Tests/NearButFarTests.swift`, `NearButFar.xcodeproj/project.pbxproj`, and `docs/project-handoff.md` already have uncommitted changes from the approved app-screen work. Never use plain `git add <path>` for these files during this plan: it would also stage their existing changes. Keep implementation changes in the working tree and let the workflow pull-request stage handle commit preparation after reviewing the combined diff.

## Task 1: Define and test route and confirmation state

**Files:** Create `Sources/Mac/PairingMenuState.swift`; modify `Tests/NearButFarTests.swift` and `NearButFar.xcodeproj/project.pbxproj`.

- [ ] **Step 1: Add tests for canceled and confirmed actions**

Add these tests to `NearButFarTests` before defining `MacMenuState`:

```swift
func testCancelingForgetOrReplaceLeavesPairingPageAndReturnsNoAction() {
    for confirmation in [PairingConfirmation.forgetPhone, .replacePhone] {
        var state = MacMenuState()
        state.openPairing(returningTo: .settings)
        state.requestConfirmation(confirmation)

        state.cancelConfirmation()

        XCTAssertEqual(state.page, .pairing)
        XCTAssertNil(state.confirm())
    }
}

func testConfirmationReturnsItsActionOnlyOnce() {
    var state = MacMenuState()
    state.openPairing(returningTo: .settings)
    state.requestConfirmation(.replacePhone)

    XCTAssertEqual(state.confirm(), .replacePhone)
    XCTAssertNil(state.confirm())
    XCTAssertEqual(state.page, .pairing)
}

func testClosingPairingReturnsToOriginAndDiscardsConfirmation() {
    var state = MacMenuState()
    state.openPairing(returningTo: .settings)
    state.requestConfirmation(.forgetPhone)

    state.closePairing()

    XCTAssertEqual(state.page, .settings)
    XCTAssertNil(state.confirmation)
}

func testSettingsCannotReplaceThePairingPage() {
    var state = MacMenuState()
    state.openPairing(returningTo: .settings)

    state.showSettings()

    XCTAssertEqual(state.page, .pairing)
}
```

- [ ] **Step 2: Run the focused test target and verify the new tests fail to compile**

Run:

```bash
xcodebuild test -project NearButFar.xcodeproj -scheme NearButFarTests -destination 'platform=macOS' -only-testing:NearButFarTests
```

Expected: the build fails because `PairingConfirmation` and `MacMenuState` do not exist yet.

- [ ] **Step 3: Implement the pure menu state type**

Create `Sources/Mac/PairingMenuState.swift` with this API and behavior:

```swift
enum MacMenuPage: Equatable {
    case home
    case settings
    case pairing
}

enum PairingConfirmation: Equatable {
    case forgetPhone
    case replacePhone
}

struct MacMenuState: Equatable {
    private(set) var page: MacMenuPage = .home
    private(set) var pairingReturnPage: MacMenuPage = .settings
    private(set) var confirmation: PairingConfirmation?

    mutating func showHome() {
        guard page != .pairing else { return }
        page = .home
    }

    mutating func showSettings() {
        guard page != .pairing else { return }
        page = .settings
    }

    mutating func openPairing(returningTo page: MacMenuPage) {
        pairingReturnPage = page
        confirmation = nil
        self.page = .pairing
    }

    mutating func requestConfirmation(_ confirmation: PairingConfirmation) {
        guard page == .pairing else { return }
        self.confirmation = confirmation
    }

    mutating func cancelConfirmation() {
        confirmation = nil
    }

    mutating func confirm() -> PairingConfirmation? {
        defer { confirmation = nil }
        return confirmation
    }

    mutating func closePairing() {
        confirmation = nil
        page = pairingReturnPage
    }
}
```

- [ ] **Step 4: Add the state source to both Xcode targets and run the focused tests**

Register the new file in the Mac app target and `NearButFarTests` target in the explicit project file. Run:

```bash
xcodebuild test -project NearButFar.xcodeproj -scheme NearButFarTests -destination 'platform=macOS' -only-testing:NearButFarTests
```

Expected: the test target builds and the four route/confirmation tests pass.

- [ ] **Step 5: Review the incremental state-model changes without staging shared files**

Review the new `PairingMenuState.swift` file and only the newly added test and project-membership hunks. Keep the changes unstaged because the test and project files already contain unrelated app-screen work.

## Task 2: Render Home, Settings, and Pair iPhone as one menu page

**Files:** Modify `Sources/Mac/NearButFarMacApp.swift` and `Sources/Mac/PairingView.swift`.

- [ ] **Step 1: Replace the Home/Settings boolean with the tested route state**

In `NearButFarMacApp`, replace `@State private var showingSettings = false` with `@State private var menuState = MacMenuState()`. Render one page from `menuState.page`:

```swift
switch menuState.page {
case .home:
    homeView
case .settings:
    settingsView
case .pairing:
    PairingView(
        coordinator: coordinator,
        menuState: $menuState,
        onClose: closePairing,
        onRequestPairing: requestPairing
    )
}
```

Render that page below a single route-aware header inside the existing MenuBarExtra content:

```swift
@ViewBuilder
private var pageHeader: some View {
    HStack {
        Text(pageTitle).font(.headline)
        Spacer()
        switch menuState.page {
        case .home:
            Button("Settings") { menuState.showSettings() }
        case .settings:
            Button("Back") { menuState.showHome() }
        case .pairing:
            Button("Back") { closePairing() }
        }
        Button { NSApp.keyWindow?.close() } label: {
            Image(systemName: "xmark")
        }
        .accessibilityLabel("Close Near But Far")
    }
}

private var pageTitle: String {
    switch menuState.page {
    case .home: return "Near But Far"
    case .settings: return "Settings"
    case .pairing: return "Pair iPhone"
    }
}
```

Keep one shared menu-bar frame of 380 points so the existing PairingView content fits without creating a second window. Put the title and navigation controls in one parent page header; remove PairingView's current duplicate title/Close row. Show Settings on Home, Back on Settings, and Back on Pair iPhone. Pair iPhone's Back action returns to its recorded origin. The menu's separate Close control closes the menu-bar panel. Do not show Settings while Pair iPhone is active.

- [ ] **Step 2: Route Settings to Pair iPhone without presenting a sheet**

Build Pair iPhone navigation through these parent helpers:

```swift
private func openPairing() {
    menuState.openPairing(returningTo: .settings)
    requestPairing()
}

private func requestPairing() {
    coordinator.requestPairing()
}

private func closePairing() {
    coordinator.dismissPairingDetails()
    menuState.closePairing()
}
```

Make the Pair iPhone button in Settings call `openPairing()`. Pass `requestPairing` and `closePairing` to PairingView for its Create/Replace and Back/QR Cancel actions. Make the Settings header button call `menuState.showSettings()` and the Settings Back button call `menuState.showHome()`. Remove `.sheet(isPresented: pairingSheetBinding)` and delete `pairingSheetBinding`.

- [ ] **Step 3: Remove presentation state from the coordinator**

Remove `@Published var isPairingPresented` and every assignment to it from `MacCoordinator`. Refactor `dismissPairingDetails()` to:

```swift
func dismissPairingDetails() {
    if pairingOffer != nil || candidateID != nil {
        cancelPairing()
    }
}
```

Remove the presentation assignment from `cancelPairing()`, `beginPairing()`, error paths, and asynchronous pairing events. Keep the QR offer, expiry task, pending request, secure session, and identity storage in the coordinator.

- [ ] **Step 4: Keep QR cancel and Pair iPhone close distinct from confirmation Cancel**

Give `PairingView` a parent `onClose` callback. The callback calls `coordinator.dismissPairingDetails()` to preserve existing QR/request cleanup, then `menuState.closePairing()` to return to Settings. The QR workflow’s Cancel button uses this callback. The Forget/Replace confirmation’s Cancel button must only call `menuState.cancelConfirmation()` and must leave `menuState.page == .pairing`.

- [ ] **Step 5: Build and review the single-panel route**

Run:

```bash
xcodebuild build -project NearButFar.xcodeproj -scheme NearButFarMac -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
```

Expected: `** BUILD SUCCEEDED **`; Home, Settings, and PairingView compile as mutually exclusive menu pages.

Review only the incremental menu-route edits in `NearButFarMacApp.swift`, `PairingView.swift`, and `MacCoordinator.swift`. Keep them unstaged because all three files already contain approved app-screen work.

## Task 3: Use one in-panel Forget/Replace confirmation

**Files:** Modify `Sources/Mac/PairingMenuState.swift`, `Sources/Mac/PairingView.swift`, `Sources/Mac/MacCoordinator.swift`, and `Tests/NearButFarTests.swift`.

- [ ] **Step 1: Add a typed pairing request result and a single confirmation state**

Add this result type to `Sources/Mac/PairingMenuState.swift` beside `PairingConfirmation`:

```swift
enum PairingRequestResult: Equatable {
    case pairingStarted
    case replacementConfirmationRequired
    case unavailable
}
```

Replace `MacCoordinator.requestPairing()` with this result-returning flow:

```swift
func requestPairing() -> PairingRequestResult {
    guard pairingCapability.isAvailable else {
        pairingStatus = pairingAvailabilityMessage
        return .unavailable
    }
    do {
        if try identityStore.pairedIdentity() != nil {
            return .replacementConfirmationRequired
        }
        return beginPairing() ? .pairingStarted : .unavailable
    } catch {
        pairingStatus = "Could not read the paired phone from Keychain."
        pairingCapability = .unavailable("Secure identity storage is unavailable.")
        return .unavailable
    }
}
```

Make `beginPairing() -> Bool` return `true` after successfully creating the QR offer and expiry task, and return `false` from its existing error path. Preserve its current status messages and two-minute expiry behavior. Neither method sets menu visibility or presents a dialog.

- [ ] **Step 2: Route Forget and Replace requests to the one state value**

Update the existing `requestPairing()` helper in `NearButFarMacApp` and keep passing it to PairingView as `onRequestPairing`:

```swift
private func requestPairing() {
    switch coordinator.requestPairing() {
    case .pairingStarted, .unavailable:
        break
    case .replacementConfirmationRequired:
        menuState.requestConfirmation(.replacePhone)
    }
}
```

Use the same helper when opening Pair iPhone from Settings. Change the Forget button to call `menuState.requestConfirmation(.forgetPhone)`. Remove `requestForgetPhone()`, `isConfirmingReplacement`, `isConfirmingForget`, and the two `.confirmationDialog` modifiers.

- [ ] **Step 3: Render the confirmation inside PairingView**

Add `@Binding var menuState: MacMenuState` to PairingView. When `menuState.confirmation` is set, show a confirmation panel in place of the ordinary pairing contents; otherwise show the existing QR, pending-request, paired-phone, or unpaired content. Keep the parent route header visible above either state. Use distinct titles, explanation, and destructive button labels for Forget and Replace. Replace copy must state that the existing phone loses access and a new QR code will be created.

Use these exact strings so the two actions stay distinguishable:

```swift
private func confirmationTitle(for action: PairingConfirmation) -> String {
    switch action {
    case .forgetPhone: return "Forget this phone?"
    case .replacePhone: return "Replace the paired iPhone?"
    }
}

private func confirmationMessage(for action: PairingConfirmation) -> String {
    switch action {
    case .forgetPhone: return "The phone will need to be paired again before it can reconnect."
    case .replacePhone: return "The existing phone will lose access before a new pairing code is created."
    }
}

private func destructiveTitle(for action: PairingConfirmation) -> String {
    switch action {
    case .forgetPhone: return "Forget phone"
    case .replacePhone: return "Forget current phone and continue"
    }
}
```

The button handlers must follow this pattern:

```swift
Button("Cancel", role: .cancel) {
    menuState.cancelConfirmation()
}

Button(destructiveTitle(for: action), role: .destructive) {
    guard let action = menuState.confirm() else { return }
    switch action {
    case .forgetPhone:
        coordinator.forgetPhone()
    case .replacePhone:
        coordinator.confirmReplacementAndPair()
    }
}
```

After Forget, remain on Pair iPhone and show the no-phone-paired state. After Replace, remain on Pair iPhone and show the new QR offer or the coordinator’s existing error status.

- [ ] **Step 4: Test both confirmation outcomes and page preservation**

Extend `NearButFarTests` with assertions that `.forgetPhone` and `.replacePhone` are returned only after `confirm()`, that a canceled confirmation returns `nil`, and that confirm/cancel never changes the active `.pairing` page. Run:

```bash
xcodebuild test -project NearButFar.xcodeproj -scheme NearButFarTests -destination 'platform=macOS' -only-testing:NearButFarTests
```

Expected: all route/confirmation tests pass. Do not test Forget or Replace against the user’s saved Keychain identity; any destructive-path integration check must use an isolated disposable identity store.

- [ ] **Step 5: Review the confirmation flow without staging shared files**

Review that the new action mapping occurs only after `menuState.confirm()` returns an action, and that Cancel only calls `menuState.cancelConfirmation()`. Keep the changes unstaged because the modified Swift and test files already contain approved app-screen work.

## Task 4: Verify the flow and update the handoff

**Files:** `Sources/Mac/NearButFarMacApp.swift`, `Sources/Mac/PairingView.swift`, `Sources/Mac/MacCoordinator.swift`, `Tests/NearButFarTests.swift`, `docs/project-handoff.md`.

- [ ] **Step 1: Run full automated checks for the Mac app**

Run:

```bash
git diff --check
xcodebuild test -project NearButFar.xcodeproj -scheme NearButFarTests -destination 'platform=macOS'
xcodebuild build -project NearButFar.xcodeproj -scheme NearButFarMac -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
```

Expected: `git diff --check` prints no whitespace errors, the existing XCTest suite passes, and the Mac target prints `** BUILD SUCCEEDED **`.

- [ ] **Step 2: Walk through non-destructive menu interactions with Computer Use**

With the Mac app’s UI accessible, open Settings → Pair iPhone with a phone already paired. Confirm that the Replace prompt stays inside the same panel. Cancel it and verify that the paired-phone view remains visible. Open Forget, cancel, and verify the same result. Confirm that Settings cannot open on top of Pair iPhone, and use Back/Close to return to Settings. Do not click either destructive confirmation on the user’s real pairing.

If the menu-bar app still returns Computer Use error `-10005`, record the visible walkthrough as blocked and retain the passing unit/build results without claiming the GUI acceptance passed.

- [ ] **Step 3: Update the project handoff with observed status**

Add this Issue #2 pairing-menu entry to `docs/project-handoff.md`:

> The Mac pairing menu uses one panel for Home, Settings, Pair iPhone, and its confirmations. Canceling Forget or Replace returns to the paired-phone view without changing the saved identity.

Record the Computer Use walkthrough as passed only if it was visibly completed. If Computer Use returns `-10005`, record that it remains pending; do not claim the phone identity was forgotten or replaced unless that was verified with an isolated disposable identity.

- [ ] **Step 4: Review the final diff and leave commit preparation to the workflow PR stage**

Review the incremental changes to confirm they stay within pairing/menu presentation and the handoff, while preserving the approved app-screen work already in the same files. Run `git diff --check` on the full working tree; report any existing unrelated failures separately. Do not stage or commit the handoff file by path because it already contains app-screen edits. The workflow pull-request stage will prepare the final commit after the full combined diff is reviewed.

```bash
rg -n "isPairingPresented|isConfirmingReplacement|isConfirmingForget|pairingSheetBinding|\\.sheet\\(" Sources/Mac
```

Expected: no pairing presentation flags, duplicate confirmation flags, pairing-sheet binding, or pairing sheet remain in the Mac menu source.

## Acceptance checklist

- [ ] Home, Settings, Pair iPhone, and confirmation content appear one at a time inside the menu-bar panel; Pair iPhone is not a sheet.
- [ ] Cancel on Forget or Replace returns to the paired-phone view in the same panel without changing the saved identity or creating a QR offer.
- [ ] Forget changes the saved identity only through its explicit confirmation; afterward Pair iPhone reports no phone paired.
- [ ] Replace changes the saved identity and begins a fresh one-use QR offer only through its explicit confirmation.
- [ ] Closing Pair iPhone is separate from confirmation Cancel; closing an active QR or pending request follows the existing cleanup and secret-erasure path.
- [ ] The focused state tests, full XCTest suite, and Mac build pass.
- [ ] Computer Use visibly confirms the interaction, or its `-10005` blocker is recorded accurately.
