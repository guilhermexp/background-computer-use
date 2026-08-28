# BCU Engine Parity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Match or exceed native Codex Computer Use for macOS background text, paste, click latency, and truthful action evidence.

**Architecture:** Keep the existing PID/window-verifier architecture and add an adaptive text strategy, a clipboard-safe paste route, condition-based settling, and route performance telemetry. Every fallback is gated by an exact reread so BCU gains native completion behavior without duplicating partial input.

**Tech Stack:** Swift 6.2, Swift Testing, AppKit Accessibility, CoreGraphics, NSPasteboard, existing loopback API and signed smoke harness.

**Spec:** `docs/plans/2026-08-27-bcu-macos-product-parity-design.md`

## Global Constraints

- macOS 14 minimum; no new third-party dependency.
- Keep exact PID/window identity and all current foreground checks.
- Dispatch is never proof of effect.
- Target-bound `AXTextOperation` is preferred when advertised; Unicode runs only if the complete
  baseline remains unchanged after preparation.
- Partial or ambiguous text changes fail closed without a second dispatch.
- Clipboard contents are restored on every exit path.
- Replace fixed waits only with bounded condition-based evidence; never remove settle bounds.
- Every production behavior starts with a failing test.
- Do not commit or push without explicit authorization.

---

### Task 1: OpenSpec and adaptive text decision seam

**Files:**
- Create: `openspec/changes/reach-macos-engine-parity/proposal.md`
- Create: `openspec/changes/reach-macos-engine-parity/tasks.md`
- Create: `openspec/changes/reach-macos-engine-parity/specs/action-verification/spec.md`
- Create: `Sources/BackgroundComputerUse/Actions/TypeText/AdaptiveTextFallback.swift`
- Create: `Tests/BackgroundComputerUseTests/AdaptiveTextFallbackTests.swift`

**Interfaces:**
- Produces: `AdaptiveTextFallbackDecision` with `acceptAX`, `fallbackUnicode`, and `failClosed`.
- Produces: `AdaptiveTextFallback.decide(baseline:expected:observed:axStatus:)`.

- [x] **Step 1: Write the strict OpenSpec delta**

Require exact AX acceptance, unchanged-baseline Unicode fallback, partial-change fail-closed behavior,
single fallback maximum, foreground preservation, and timing evidence.

- [x] **Step 2: Write failing planner tests**

```swift
@Test func unchangedIgnoredAXWriteFallsBackOnce() {
    #expect(
        AdaptiveTextFallback.decide(
            baseline: "",
            expected: "hello",
            observed: "",
            axStatus: .success
        ) == .fallbackUnicode
    )
}

@Test func partialAXWriteNeverFallsBack() {
    #expect(
        AdaptiveTextFallback.decide(
            baseline: "",
            expected: "hello",
            observed: "hel",
            axStatus: .success
        ) == .failClosed(reason: .partialMutation)
    )
}

@Test func exactAXWriteNeedsNoFallback() {
    #expect(
        AdaptiveTextFallback.decide(
            baseline: "",
            expected: "hello",
            observed: "hello",
            axStatus: .success
        ) == .acceptAX
    )
}
```

- [x] **Step 3: Verify RED**

Run `swift test --filter AdaptiveTextFallbackTests` and require compile failure for the missing seam.

- [x] **Step 4: Implement the pure decision**

Compare complete strings, not previews. An AX error with an unchanged baseline may use Unicode only
when the target is a verified text entry and WindowServer preparation succeeded; carry that eligibility
as a boolean input rather than reading global state inside the planner.

- [x] **Step 5: Verify GREEN**

Run the focused suite and `git diff --check`.

### Task 2: Integrate ordered target-bound and Unicode fallbacks

**Files:**
- Modify: `Sources/BackgroundComputerUse/Actions/TypeText/TypeTextRouteService.swift`
- Modify: `Sources/BackgroundComputerUse/Contracts/TextActionContracts.swift`
- Modify: `Sources/BackgroundComputerUse/API/RouteRegistry.swift`
- Modify: `Sources/BackgroundComputerUse/API/APIDocumentation.swift`
- Create: `Tests/BackgroundComputerUseTests/AdaptiveTypeTextRouteTests.swift`

**Interfaces:**
- Adds response fields `strategiesAttempted: [String]` and `fallbackReason: String?`.
- Preserves `TypeTextBackgroundSafetyDTO` and exact verification evidence.

- [x] **Step 1: Write failing route-level tests with injected transports**

Inject AX write, target-bound preparation, live rereads, and Unicode dispatch closures into a focused
`AdaptiveTextDispatcher`. Require the WebKit lane to complete as
`ax_write -> immediate_reread -> ax_text_operation -> final_reread`, require the compatible focus-only
lane to reach Unicode once, and require zero Unicode calls after partial mutation.

```swift
#expect(trace == ["ax_write", "reread", "unicode", "reread"])
#expect(result.exactValueMatch)
#expect(result.strategiesAttempted == ["ax_value", "pid_unicode"])
```

- [x] **Step 2: Verify RED**

Run `swift test --filter AdaptiveTypeTextRouteTests` and require missing dispatcher/fields.

- [x] **Step 3: Implement immediate AX reread and fallback**

After the AX value/selection write, read the same live element immediately. Call the pure planner. On
fallback, attempt the exact element's advertised `AXTextOperation` and reread. Only while the complete
baseline remains unchanged, set the exact element focused, confirm foreground is unchanged, post the
original request text once to the PID, and reread. Do not post the expected full value; Unicode inserts
only the requested delta at the prepared selection.

- [x] **Step 4: Keep the final verifier authoritative**

The existing post-capture relocation and exact value/selection checks still decide success. Immediate
rereads only select the strategy and may never directly return success.

- [x] **Step 5: Verify GREEN**

Run adaptive, background-safety, public-contract, and documentation tests.

### Task 3: Add clipboard-safe paste

**Files:**
- Create: `Sources/BackgroundComputerUse/Actions/Paste/PasteboardSnapshot.swift`
- Create: `Sources/BackgroundComputerUse/Actions/Paste/PasteRouteService.swift`
- Create: `Sources/BackgroundComputerUse/Contracts/PasteContracts.swift`
- Modify: `Sources/BackgroundComputerUse/API/RouteRegistry.swift`
- Modify: `Sources/BackgroundComputerUse/API/APIDocumentation.swift`
- Modify: `Sources/BackgroundComputerUse/API/Router.swift`
- Modify: `Sources/BackgroundComputerUse/Runtime/RuntimeServices.swift`
- Modify: `Sources/BackgroundComputerUse/App/BackgroundComputerUseRuntime.swift`
- Create: `Tests/BackgroundComputerUseTests/PasteRouteTests.swift`

**Interfaces:**
- Produces: `PasteRequest(window:target:content:format:confirm:)`.
- Produces: `PasteFormatDTO.text | markdown | html`.
- Produces: `PasteboardSnapshot.capture()` and `restore()` preserving all item representations.

- [x] **Step 1: Write failing pasteboard round-trip tests**

Seed multiple pasteboard items with plain text, HTML, and custom binary data. Capture, replace, and
restore; assert item count, types, and bytes match exactly.

- [x] **Step 2: Verify RED**

Run `swift test --filter PasteRouteTests` and require missing route/contracts.

- [x] **Step 3: Implement snapshot and format encoding**

Use `NSPasteboardItem.types` and `data(forType:)`. Markdown publishes both markdown and plain-text
representations. HTML publishes HTML plus a plain-text fallback. Restoration executes in `defer`.

- [x] **Step 4: Implement the read-act-read route**

Resolve and prepare the exact text target, capture foreground, write the temporary pasteboard, post
Command-V to the target PID, restore clipboard, reread target state, and require foreground
preservation. Secure-field and sensitive-content confirmation gates remain authoritative.

- [x] **Step 5: Wire and document all five route surfaces**

Add RouteRegistry, Router/action-lane, RuntimeServices, public facade, and strict schema coverage.

- [x] **Step 6: Verify GREEN**

Run paste, route-wiring, strict-decode, debug-redaction, and public-facade tests.

### Task 4: Condition-based settling and performance telemetry

**Files:**
- Create: `Sources/BackgroundComputerUse/Actions/Shared/ConditionedActionWait.swift`
- Create: `Sources/BackgroundComputerUse/Contracts/ActionPerformanceContracts.swift`
- Modify: `Sources/BackgroundComputerUse/Actions/TypeText/TypeTextRouteService.swift`
- Modify: `Sources/BackgroundComputerUse/Actions/Click/ClickRouteService.swift`
- Modify: `Sources/BackgroundComputerUse/Contracts/TextActionContracts.swift`
- Modify: `Sources/BackgroundComputerUse/Contracts/ClickActionContracts.swift`
- Create: `Tests/BackgroundComputerUseTests/ConditionedActionWaitTests.swift`

**Interfaces:**
- Produces: `ConditionedActionWait.poll(intervalMs:deadlineMs:sample:isSatisfied:)`.
- Produces: `ActionPerformanceDTO(resolveMs:captureMs:preparationMs:transportMs:settleMs:verificationMs:totalMs:)`.

- [x] **Step 1: Write failing deterministic-clock tests**

Use an injected clock/sleeper. Require immediate exit on the first satisfying sample, bounded timeout,
and no busy loop.

- [x] **Step 2: Verify RED**

Run `swift test --filter ConditionedActionWaitTests`.

- [x] **Step 3: Implement bounded polling**

Use 25 ms default intervals and route-specific evidence. Type waits for exact same-element value or a
stable unchanged baseline used by the fallback planner. Click waits for target/focus/modal/local-pixel
evidence. The existing 350 ms becomes the deadline, not an unconditional sleep.

- [x] **Step 4: Add telemetry without changing verdicts**

Measure each route stage with monotonic time and encode finite sanitized doubles. Documentation names
every field and states that lower latency never bypasses verification.

- [x] **Step 5: Verify GREEN**

Run conditioned-wait, type, click-verification, contract, and documentation suites.

### Task 5: Mac-only benchmark and signed smoke

**Files:**
- Modify: `script/smoke_runtime.py`
- Modify: `script/test_smoke_runtime.py`
- Create: `script/benchmark_mac_parity.py`
- Modify: `skills/background-computer-use/SKILL.md`
- Modify: `openspec/changes/reach-macos-engine-parity/tasks.md`

**Interfaces:**
- Benchmark emits JSON with per-run samples, p50, p95, completions, verifier honesty, and foreground identity.

- [x] **Step 1: Add deterministic benchmark-stat tests**

Test percentile calculation and failure classification with fixed samples.

- [x] **Step 2: Extend the real fixture**

Include an input that ignores AX value writes but accepts focused Unicode, formatted paste targets,
idempotent buttons, duplicate browser instances, and opaque visual controls.

- [x] **Step 3: Run ten warm signed-app trials**

Require adaptive type p50 <= 650 ms/p95 <= 1,100 ms and semantic click p50 <= 600 ms/p95 <= 1,000 ms,
with the external foreground PID unchanged and zero false-success verdicts.

- [x] **Step 4: Run final engine gates**

Run release build, full Swift suite, Python tests/compile, OpenSpec strict, signed smoke, benchmark, and
worker/process cleanup checks. Record literal results in the change tasks.
