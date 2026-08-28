# BCU Single Transient Activity Card Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace persistent per-window activity panels with one reusable card that hides two seconds after the latest action.

**Architecture:** Add a small generation-based presentation state beside the existing PiP controller. The controller owns one optional panel, replaces its content for every activity, and permits only the latest scheduled dismissal to hide it.

**Tech Stack:** Swift 6, AppKit `NSPanel`, SwiftUI, Swift Testing.

**Spec:** `docs/plans/2026-08-27-bcu-single-transient-activity-card-design.md`

## Global Constraints

- Keep `ActivityHistoryStore` unchanged; only floating presentation becomes transient.
- The card remains nonactivating and must not change the foreground app.
- Exactly one panel may exist for activity presentation.
- Hide two seconds after the latest activity; stale timers must have no effect.
- No new dependency, commit, or push.

---

### Task 1: Generation-based presentation state

**Files:**
- Modify: `Sources/BackgroundComputerUseControl/PiPWindowController.swift`
- Test: `Tests/BackgroundComputerUseTests/ActivityControlTests.swift`

**Interfaces:**
- Produces: `ActivityPiPPresentationState.present(_:) -> UInt64`
- Produces: `ActivityPiPPresentationState.dismiss(generation:) -> Bool`
- Consumes: existing `ActivityEnvelope`

- [x] **Step 1: Write failing tests**

Add tests proving that presenting activities from two different windows retains only the newest activity, that a stale generation cannot dismiss it, and that the latest generation can dismiss it.

- [x] **Step 2: Verify RED**

Run: `swift test --filter ActivityControlTests`

Expected: compilation fails because `ActivityPiPPresentationState` does not exist.

- [x] **Step 3: Implement the minimal state**

Add an internal value type with one optional `activity`, a monotonically increasing `generation`, `present(_:)`, and guarded `dismiss(generation:)`.

- [x] **Step 4: Verify GREEN**

Run: `swift test --filter ActivityControlTests`

Expected: all `ActivityControlTests` pass.

### Task 2: Reuse and auto-hide one real panel

**Files:**
- Modify: `Sources/BackgroundComputerUseControl/PiPWindowController.swift`

**Interfaces:**
- Consumes: `ActivityPiPPresentationState`
- Produces: `PiPWindowController.update(_:)` with one reusable panel and a two-second latest-generation dismissal

- [x] **Step 1: Replace the dictionary**

Replace `[String: Entry]` with one optional `Entry`, update its model and content size for every action, and position only that panel.

- [x] **Step 2: Schedule guarded dismissal**

Cancel the prior `DispatchWorkItem`, schedule a new one at `2.0` seconds, call `presentation.dismiss(generation:)`, and `orderOut(nil)` only when it returns `true`.

- [x] **Step 3: Run focused and full gates**

Run `swiftformat` on the modified Swift files, `swift test --filter ActivityControlTests`, then `swift test`.

Expected: formatting clean and all 314+ tests pass.

### Task 3: Signed Release visual verification

**Files:**
- No source changes expected.

**Interfaces:**
- Consumes: signed universal app produced by `script/build_and_run.sh`

- [x] **Step 1: Build and launch Release**

Run: `BACKGROUND_COMPUTER_USE_RELEASE_BUILD=1 script/build_and_run.sh run`

- [x] **Step 2: Exercise rapid actions**

Run multiple verified actions against the smoke fixture while sampling BCU windows through Accessibility.

- [x] **Step 3: Verify visible lifecycle**

Require exactly one `330`-point-wide activity panel while actions are arriving and zero BCU activity panels more than two seconds after the last action. Verify the foreground PID remains unchanged.
