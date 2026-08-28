# BCU Activity Card Preference and Layout Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let users disable the transient activity card and remove the empty title-bar inset above its content.

**Architecture:** Extend the existing Control view model and `UserDefaults` wiring with an enabled-by-default activity-card preference. The PiP controller becomes enable-aware and hides immediately when disabled, while history remains upstream and unchanged. SwiftUI consumes the existing full-size panel area instead of respecting the invisible title-bar safe area.

**Tech Stack:** Swift 6, SwiftUI, AppKit `NSPanel`, `UserDefaults`, Swift Testing.

**Spec:** `docs/plans/2026-08-28-bcu-activity-card-preference-and-layout-design.md`

## Global Constraints

- The preference key is `BCUActivityCardEnabled` and defaults to `true` only when absent.
- Disabling hides immediately, cancels pending dismissal, and blocks later cards.
- Activity history remains recorded regardless of the presentation preference.
- Re-enabling waits for the next activity; it never resurrects old content.
- Keep one card, latest-action replacement, two-second auto-hide, nonactivation, and foreground preservation.
- Preserve the incumbent card styling while removing only the invisible title-bar inset.
- No new dependency, commit, or push.

---

### Task 1: Preference and presentation contracts

**Files:**
- Create: `Sources/BackgroundComputerUseControl/ActivityCardPreference.swift`
- Modify: `Sources/BackgroundComputerUseControl/ControlViewModel.swift`
- Modify: `Sources/BackgroundComputerUseControl/PiPWindowController.swift`
- Test: `Tests/BackgroundComputerUseTests/ControlViewModelTests.swift`
- Test: `Tests/BackgroundComputerUseTests/ActivityControlTests.swift`

**Interfaces:**
- Produces: `ControlViewModel.activityCardEnabled: Bool`
- Produces: `ControlViewModel.setActivityCardEnabled(_:)`
- Produces: `ActivityCardPreference.isEnabled(in:) -> Bool`
- Produces: `ActivityPiPPresentationState.setEnabled(_:)`
- Changes: `ActivityPiPPresentationState.present(_:) -> UInt64?`

- [x] **Step 1: Write RED view-model tests**

Prove that a missing persisted key defaults to enabled, persisted false stays false, the initial preference is observable, and changing it updates the model and invokes the callback exactly once with the selected value.

- [x] **Step 2: Write RED presentation tests**

Prove that disabling clears current presentation, blocks a new presentation, invalidates the old dismissal generation, and re-enabling permits only a later activity.

- [x] **Step 3: Verify RED**

Run: `swift test --filter 'ControlViewModelTests|ActivityControlTests'`

Expected: compilation fails because the new preference and enable-aware presentation interfaces do not exist.

- [x] **Step 4: Implement minimal contracts and verify GREEN**

Add the observable preference/callback to the view model and enable state/generation invalidation to presentation state. Run the same focused filter and require all tests to pass.

### Task 2: Runtime persistence and immediate hide

**Files:**
- Modify: `Sources/BackgroundComputerUseControl/BCUControlRuntime.swift`
- Modify: `Sources/BackgroundComputerUseControl/PiPWindowController.swift`

**Interfaces:**
- Consumes: `BCUActivityCardEnabled` from `UserDefaults`
- Produces: `PiPWindowController.setEnabled(_:)`

- [x] **Step 1: Load enabled-by-default preference**

Use `UserDefaults.object(forKey:) as? Bool ?? true`, create the PiP controller with that value, and pass it into `ControlViewModel`.

- [x] **Step 2: Persist and apply changes**

The callback writes `UserDefaults`, and `PiPWindowController.setEnabled(false)` cancels pending dismissal and orders the current panel out immediately.

- [x] **Step 3: Preserve history boundary**

Keep `history.append(activity)` unconditional and let only `pipController.update(activity)` suppress presentation.

### Task 3: Settings toggle and compact top layout

**Files:**
- Modify: `Sources/BackgroundComputerUseControl/SettingsView.swift`
- Modify: `Sources/BackgroundComputerUseControl/PiPWindowController.swift`

**Interfaces:**
- Consumes: `ControlViewModel.activityCardEnabled`
- Consumes: `ControlViewModel.setActivityCardEnabled(_:)`

- [x] **Step 1: Add settings toggle**

Add `Mostrar cartão de atividades` with an accessibility hint that disabling keeps history but removes floating cards.

- [x] **Step 2: Remove invisible title-bar inset**

Make `ActivityPiPView` consume the full safe area while preserving its current `14`-point internal padding and top-leading content order.

- [x] **Step 3: Run source gates**

Run SwiftFormat on changed Swift files, focused tests, then the full Swift suite and Python helper suite.

### Task 4: Signed Release visual and persistence QA

**Files:**
- No source changes expected.

**Interfaces:**
- Consumes: signed universal Release from `script/build_and_run.sh`

- [x] **Step 1: Build, sign, install, and launch Release**

Run `BACKGROUND_COMPUTER_USE_RELEASE_BUILD=1 script/build_and_run.sh run` and verify deep signature plus arm64/x86_64 slices.

- [x] **Step 2: Verify enabled layout and lifecycle**

With the setting enabled, run verified actions, capture the real panel, verify content starts directly inside the 14-point padding, observe at most one card, and observe zero after more than two seconds.

- [x] **Step 3: Verify disabled and persisted behavior**

Disable through the real settings control, confirm an existing card hides immediately and later actions create zero cards while history still grows. Relaunch and confirm disabled persists. Re-enable, relaunch, and confirm enabled persists and the next action creates one transient card.
