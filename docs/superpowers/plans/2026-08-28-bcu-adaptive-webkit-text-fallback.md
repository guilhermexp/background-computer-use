# BCU Adaptive WebKit Text Fallback Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restore verified background text on WebKit through target-bound AXTextOperation while retaining one exact-focus PID Unicode fallback for compatible surfaces.

**Architecture:** `AdaptiveTextDispatcher` receives a typed preparation result so telemetry distinguishes target-bound text operation from focus-only preparation. The route rereads the same element after every transport and allows PID Unicode only after an unchanged complete baseline, verified exact focus, and foreground preservation.

**Tech Stack:** Swift 6, AppKit Accessibility, Swift Testing, Python unittest, signed macOS smoke

**Spec:** `docs/plans/2026-08-28-bcu-adaptive-webkit-text-fallback-design.md`

## Global Constraints

- Dispatch never proves success; final exact value/selection verification remains authoritative.
- A partial or ambiguous mutation never receives another text dispatch.
- Strategy telemetry names only transports actually attempted.
- Safari smoke proves `ax_value + ax_text_operation`; Swift tests prove `ax_value + pid_unicode`.
- Foreground preservation and exact target focus remain fail-closed.

---

### Task 1: Typed adaptive fallback orchestration

**Files:**
- Modify: `Sources/BackgroundComputerUse/Actions/TypeText/AdaptiveTextDispatcher.swift`
- Modify: `Sources/BackgroundComputerUse/Actions/TypeText/TypeTextRouteService.swift`
- Modify: `Tests/BackgroundComputerUseTests/AdaptiveTypeTextRouteTests.swift`

**Interfaces:**
- Produces: `AdaptiveTextFallbackPreparation.failed`, `.focused`, and `.textOperation`.
- Produces telemetry sequences `[.axValue, .axTextOperation]` and `[.axValue, .pidUnicode]`.

- [x] **Step 1: Write the failing target-bound completion test**

Add a test where the first reread is the baseline, `prepareFallback` returns `.textOperation`, the
second reread is the exact expected value, and `postUnicode` is never called. Assert strategies are
`[.axValue, .axTextOperation]`.

- [x] **Step 2: Verify RED**

Run `swift test --filter AdaptiveTypeTextRouteTests`. Expected: compilation fails because
`.textOperation` and `.axTextOperation` are absent.

- [x] **Step 3: Implement the minimal typed strategy**

Add `axTextOperation`, restore the preparation strategy mapping, and let the dispatcher reread after
preparation before deciding whether Unicode is still eligible. In `TypeTextRouteService`, attempt
`AXTextOperation` only when advertised; otherwise prepare exact focus. Always verify focus and
foreground before allowing the PID Unicode closure.

- [x] **Step 4: Verify GREEN**

Run `swift test --filter AdaptiveTypeTextRouteTests` and require all focused strategy/partial mutation
tests to pass.

---

### Task 2: Honest contract and signed qualification

**Files:**
- Modify: `script/smoke_runtime.py`
- Modify: `script/test_smoke_runtime.py`
- Modify: `openspec/changes/reach-macos-engine-parity/specs/action-verification/spec.md`
- Modify: `docs/plans/2026-08-27-bcu-macos-product-parity-design.md`
- Modify: `docs/superpowers/plans/2026-08-27-bcu-engine-parity.md`
- Modify: `docs/parity-completion-audit.md`

**Interfaces:**
- Produces: `safari_adaptive_type_strategy_is_valid(payload)` requiring target-bound WebKit evidence.
- Preserves: a separate Swift-only PID Unicode orchestration proof.

- [x] **Step 1: Write the failing Safari smoke policy test**

The Python helper test accepts `ax_value + ax_text_operation` with `unchanged_ax_noop` and rejects a
PID-only payload as evidence for the Safari-specific fixture.

- [x] **Step 2: Verify RED**

Run `python3 -m unittest script/test_smoke_runtime.py`. Expected: the current PID-only helper policy
fails the Safari target-bound expectation.

- [x] **Step 3: Update implementation contract and evidence text**

Rename the helper for Safari, require `ax_text_operation` in that fixture, and update OpenSpec/design
to define ordered target-bound-then-Unicode behavior without claiming Safari accepted PID Unicode.

- [x] **Step 4: Run all gates and signed smoke**

Run formatter, `swift test`, all three Python test modules, strict OpenSpec validation, universal
Release build, signature/architecture checks, `script/smoke_runtime.py`, plug-in host smoke, and the
non-mutating Locked Use qualification. Require 30/30 signed smoke with the Safari adaptive lane
reporting `ax_text_operation`.

- [x] **Step 5: Complete the parent plan, review, commit, and publish**

Mark both plans complete, perform an all-working-tree review, commit every authorized BCU change, run
no-mistakes with the complete user intent, and push `feat/bcu-macos-product-parity` to `fork` without
installing Locked Use on the primary Mac.
