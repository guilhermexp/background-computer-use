# Plan 006: Settle accepted AX writes before paste fallback and set-value verification

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**: `git diff --stat 0110ffb..HEAD -- Sources/BackgroundComputerUse/Actions/Shared Sources/BackgroundComputerUse/Actions/TypeText/AdaptiveTextDispatcher.swift Sources/BackgroundComputerUse/Actions/Paste/AdaptivePasteDispatcher.swift Sources/BackgroundComputerUse/Actions/SetValue/SetValueRouteService.swift Tests/BackgroundComputerUseTests/AdaptiveTextFallbackTests.swift Tests/BackgroundComputerUseTests/AdaptivePasteDispatcherTests.swift Tests/BackgroundComputerUseTests/SetValueWriteSettleTests.swift`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.
>
> **Required working-tree baseline**: run `git status --short`, then confirm each of these paths is either listed there or differs in `git diff --name-only 0110ffb..HEAD`: `Sources/BackgroundComputerUse/API/Router.swift`, `Sources/BackgroundComputerUse/App/BackgroundComputerUseControlBridge.swift`, `Sources/BackgroundComputerUseControlShared/CodeSignatureIdentity.swift`, `Sources/BackgroundComputerUse/Runtime/RuntimeExecutionQueue.swift`, `Sources/BackgroundComputerUse/Actions/TypeText/AdaptiveTextDispatcher.swift`, `Sources/BackgroundComputerUse/StatePipeline/InteractionToken.swift`, `Sources/BackgroundComputerUse/Runtime/Process/BoundedProcessRunner.swift`, `skills/background-computer-use/scripts/bcu-request.py`, `Tests/BackgroundComputerUseTests/InteractionTokenTests.swift`, and `Tests/BackgroundComputerUseTests/RuntimeExecutionQueueTests.swift`. These fixes are part of the baseline, especially the async-write settle code this plan generalizes. STOP if any is absent from both checks.

## Status

- **Priority**: P1
- **Effort**: S/M
- **Risk**: LOW
- **Depends on**: none
- **Category**: bug
- **Planned at**: commit `0110ffb`, 2026-09-02

## Why this matters

Chromium and WebKit can synchronously accept an Accessibility text mutation while their renderer and AX cache still expose the old value. Paste currently interprets one stale reread as proof that the mutation did nothing and sends Command-V, which can insert the content twice. `set_value` has the related honesty defect: it waits a fixed 350 ms, samples once, and can report `effect_not_verified` just before the accepted write becomes visible. This plan gives all accepted AX value writes the same bounded, conditioned 25 × 20 ms settle behavior already proven in `type_text`, without waiting after rejected writes or hiding divergent values.

## Current state

- `Sources/BackgroundComputerUse/Actions/TypeText/AdaptiveTextDispatcher.swift` — contains the working async-renderer settle policy that this plan will rename and share:

```swift
// AdaptiveTextDispatcher.swift:39-50
struct AdaptiveTextSettle: Sendable {
    let maxReads: Int
    let wait: @Sendable () -> Void

    static let live = AdaptiveTextSettle(maxReads: 25, wait: { usleep(20_000) })
    /// One read, no waiting: for tests that model the fallback chain, not the renderer lag.
    static let immediate = AdaptiveTextSettle(maxReads: 1, wait: {})
}
```

```swift
// AdaptiveTextDispatcher.swift:65-74
let axStatus = writeAX()
var immediateObservedValue = readValue()
if axStatus == .success {
    var reads = 1
    while immediateObservedValue == baseline, immediateObservedValue != expected, reads < settle.maxReads {
        settle.wait()
        immediateObservedValue = readValue()
        reads += 1
    }
}
```

- `Sources/BackgroundComputerUse/Actions/Paste/AdaptivePasteDispatcher.swift` — one immediate stale read falls through to the clipboard transport:

```swift
// AdaptivePasteDispatcher.swift:31-58
guard performTargetBoundOperation() else {
    return AdaptivePasteDispatchResult(
        transportSucceeded: performClipboardPaste(),
        strategiesAttempted: [.axTextOperation, .temporaryClipboardCommandV],
        observedValue: nil
    )
}

let observed = readValue()
if observed == expected {
    return AdaptivePasteDispatchResult(
        transportSucceeded: true,
        strategiesAttempted: [.axTextOperation],
        observedValue: observed
    )
}
guard observed == baseline else {
    return AdaptivePasteDispatchResult(
        transportSucceeded: false,
        strategiesAttempted: [.axTextOperation],
        observedValue: observed
    )
}
return AdaptivePasteDispatchResult(
    transportSucceeded: performClipboardPaste(),
    strategiesAttempted: [.axTextOperation, .temporaryClipboardCommandV],
    observedValue: observed
)
```
- `Sources/BackgroundComputerUse/Actions/Paste/PasteRouteService.swift:170-207` passes closures for the accepted `AXTextOperation` and same-element `readTextState`; the dispatcher is already the correct seam, so the route needs no new timing logic.
- `Sources/BackgroundComputerUse/Actions/SetValue/SetValueRouteService.swift` uses an unconditional delay and one same-element sample:
```swift
// SetValueRouteService.swift:304-317
let axResult = AXActionRuntimeSupport.setValue(coercedValue, on: liveElement.element)
let rawStatus = AXActionRuntimeSupport.rawStatusString(for: axResult)
AXCursorTargeting.finishSetValue(cursor: cursor)

sleepRunLoop(settleDelay)

let afterSameElementValue = AXActionRuntimeSupport.readValueEvidence(liveElement.element)
let postCapture: AXActionStateCapture?
do {
    postCapture = try targetResolver.reread(after: capture)
} catch {
    postCapture = nil
    notes.append("Post-write reread failed: \(error).")
}
```
- `Tests/BackgroundComputerUseTests/AdaptivePasteDispatcherTests.swift:28-47` already asserts that a permanently unchanged AX operation invokes clipboard fallback exactly once, but it does not model delayed renderer visibility.
- `Tests/BackgroundComputerUseTests/AdaptiveTextFallbackTests.swift:70-111` is the exact test pattern: baseline reads become expected after several polls, and a never-landing write reaches one fallback only.
- The project contract says: “RouteService read-act-read: capture … dispatch … reread/verify … response com classificação verifier-first” and “Erro de background é reportado, nunca escondido roubando foco” (`openspec/project.md:14`). The settle only delays a fallback or verdict; an accepted transport remains evidence to verify, not proof of effect.
- Swift is in version 6 language mode. Tests use Swift Testing (`import Testing`, `@Test`, `#expect`) rather than XCTest (`openspec/project.md:7-9`).
## Commands you will need
| Purpose | Command | Expected on success |
|---|---|---|
| Focused text tests | `swift test --filter AdaptiveTextFallbackTests` | exit 0; all selected tests pass |
| Focused paste tests | `swift test --filter AdaptivePasteDispatcherTests` | exit 0; all selected tests pass |
| Focused set-value tests | `swift test --filter SetValueWriteSettleTests` | exit 0; all selected tests pass |
| Final suite | `swift test` | exit 0; the full suite passes |
| Baseline check | `git status --short` | only baseline work plus this plan’s in-scope changes are present |
## Scope
**In scope** (the only files you should modify):
- `Sources/BackgroundComputerUse/Actions/Shared/AXWriteSettle.swift` (create)
- `Sources/BackgroundComputerUse/Actions/TypeText/AdaptiveTextDispatcher.swift`
- `Sources/BackgroundComputerUse/Actions/Paste/AdaptivePasteDispatcher.swift`
- `Sources/BackgroundComputerUse/Actions/SetValue/SetValueRouteService.swift`
- `Tests/BackgroundComputerUseTests/AdaptiveTextFallbackTests.swift`
- `Tests/BackgroundComputerUseTests/AdaptivePasteDispatcherTests.swift`
- `Tests/BackgroundComputerUseTests/SetValueWriteSettleTests.swift` (create)
- `plans/README.md` (status row only)
**Out of scope** (do NOT touch, even though related):
- `PasteRouteService.swift` transport ordering, clipboard transactions, click/focus preparation, and swallowed nested-route errors.
- `TypeTextRouteService.swift`’s later 350 ms verification poll; this plan shares only the pre-fallback accepted-write settle. Plan 007 owns type-text outcome honesty.
- Public request/response DTO shapes and RouteRegistry fields; the behavior changes but the wire contract does not.
- Live app launch/install scripts and live Chrome/Electron smoke runs.
## Git workflow
- Branch: `advisor/006-settle-before-fallback-paste-setvalue`
- Make one logical commit after all focused tests pass: `fix: settle accepted AX writes before fallback`
- Do NOT push or open a PR unless the operator instructed it.
- Preserve all pre-existing working-tree changes; do not stage or rewrite unrelated baseline files.
## Steps
### Step 1: Generalize the proven type-text settle policy without changing its behavior
Create `Actions/Shared/AXWriteSettle.swift`, move the settle policy there, and rename it cleanly from `AdaptiveTextSettle` to `AXWriteSettle`. Do not leave a typealias. Give it one generic polling operation so paste and set-value do not copy the loop:

```swift
import Foundation

/// Bounded settling for an AX write accepted before a renderer/cache exposes its effect.
struct AXWriteSettle: Sendable {
    let maxReads: Int
    let wait: @Sendable () -> Void

    static let live = AXWriteSettle(maxReads: 25, wait: { usleep(20_000) })
    static let immediate = AXWriteSettle(maxReads: 1, wait: {})

    func poll<Observation>(
        read: () -> Observation,
        while shouldWait: (Observation) -> Bool
    ) -> Observation {
        var observed = read()
        var reads = 1
        while shouldWait(observed), reads < maxReads {
            wait()
            observed = read()
            reads += 1
        }
        return observed
    }
}
```

In `AdaptiveTextDispatcher.dispatch`, change `settle` to `AXWriteSettle = .live`. Replace the inlined loop with:

```swift
let immediateObservedValue: String?
if axStatus == .success {
    immediateObservedValue = settle.poll(read: readValue) {
        $0 == baseline && $0 != expected
    }
} else {
    immediateObservedValue = readValue()
}
```

Rename the three existing test constructions from `AdaptiveTextSettle` to `AXWriteSettle`, preserving their current `maxReads` values (10, 5, and 10) and `wait: {}` closures. This must preserve exactly one read for rejected writes and at most 25 reads over 480 ms for an accepted unchanged live write.

**Verify**: `swift test --filter AdaptiveTextFallbackTests` → exit 0; the existing async-renderer, never-lands, and rejected-write read-count tests all pass.

### Step 2: Settle accepted AXTextOperation paste before Command-V

Add `settle: AXWriteSettle = .live` to `AdaptivePasteDispatcher.dispatch` immediately after `readValue`. Only after `performTargetBoundOperation()` returns true, replace `let observed = readValue()` with:

```swift
let observed = settle.poll(read: readValue) {
    $0 == baseline && $0 != expected
}
```

Do not wait when the target-bound operation was unavailable/rejected. Preserve existing decisions after polling: exact expected value accepts AX; a divergent non-baseline value fails closed without clipboard; only a value that remained baseline for the full bound receives one Command-V fallback.

Pass `.immediate` from the three existing dispatcher tests so they remain instant. Add these tests to `AdaptivePasteDispatcherTests.swift`, mirroring `AdaptiveTextFallbackTests.swift:70-111`:

- `acceptedAXWriteWaitsForAsyncRendererBeforeEscalating`: reads `old, old, old, new`; use `AXWriteSettle(maxReads: 10, wait: {})`; assert only `.axTextOperation`, no clipboard call, and observed `new`.
- `acceptedAXWriteThatNeverLandsStillFallsBackOnce`: return `old` until the clipboard closure runs; use five reads; assert strategies are `[.axTextOperation, .temporaryClipboardCommandV]`, read count is at least five, and clipboard count is exactly one.
- Keep `partialTargetBoundMutationFailsClosedWithoutClipboard`; add a second queued value after the divergent value and assert it is not consumed, proving divergence stops the poll and remains evidence.

**Verify**: `swift test --filter AdaptivePasteDispatcherTests` → exit 0; all existing and three strengthened/new cases pass without real sleeps.

### Step 3: Replace set-value’s fixed sleep with the same conditioned poll

Remove `settleDelay`. Add `private let settle: AXWriteSettle`, and extend the initializer with `settle: AXWriteSettle = .live` while preserving the existing default for `executionOptions`.

Add an internal static test seam on `SetValueRouteService`:

```swift
static func settledSameElementValue(
    baseline: SetValueObservedValueDTO?,
    expected: AXActionCoercedValue,
    settle: AXWriteSettle,
    readValue: () -> SetValueObservedValueDTO?
) -> SetValueObservedValueDTO? {
    settle.poll(read: readValue) { observed in
        observedValueEquals(observed, baseline) && expected.matches(observed) == false
    }
}
```

Implement `static func observedValueEquals(_ lhs: SetValueObservedValueDTO?, _ rhs: SetValueObservedValueDTO?) -> Bool` in the same type by comparing all seven evidence fields (`kind`, `preview`, `stringValue`, `boolValue`, `integerValue`, `doubleValue`, `truncated`). Keep it internal so the test can exercise the set-value decision directly; do not add JSON fields or use JSON encoding as equality.

At the dispatch site, poll only when AX accepted the write:

```swift
let afterSameElementValue: SetValueObservedValueDTO?
if axResult == .success {
    afterSameElementValue = Self.settledSameElementValue(
        baseline: beforeLiveValue,
        expected: coercedValue,
        settle: settle,
        readValue: { AXActionRuntimeSupport.readValueEvidence(liveElement.element) }
    )
} else {
    afterSameElementValue = AXActionRuntimeSupport.readValueEvidence(liveElement.element)
}
```

Then perform the existing projection reread. Returning the first non-baseline value is deliberate: an unexpected/partial mutation is evidence and must not be overwritten while waiting for a later value.

Create `SetValueWriteSettleTests.swift` with Swift Testing cases:

- `acceptedWritePollsUntilExpectedValueAppears`: baseline `old`, reads `old, old, new`, expected `.string("new")`; assert result is `new` and read count is three.
- `divergentWriteStopsAndPreservesEvidence`: baseline `old`, reads `old, partial, new`; assert result is `partial` and the third sample remains unread.
- `unchangedWriteStopsAtBound`: five baseline samples and `maxReads: 5`; assert exactly five reads and baseline result.

**Verify**: `swift test --filter SetValueWriteSettleTests` → exit 0; all three deterministic tests pass with `wait: {}`.

### Step 4: Run the integrated regression gate and clean up the rename

Search all source and tests for `AdaptiveTextSettle`; remove every stale reference rather than adding compatibility aliases. Run the full suite once. Do not run a live runtime or Chrome smoke for this plan.

**Verify**: `grep -R "AdaptiveTextSettle" Sources Tests` → exit 1 with no matches; then `swift test` → exit 0 and the full suite passes.

## Test plan

- `AdaptiveTextFallbackTests.swift`: existing type-text polling behavior survives the clean rename.
- `AdaptivePasteDispatcherTests.swift`: delayed accepted AX mutation does not escalate; never-landing mutation falls back exactly once; divergence fails closed immediately.
- `SetValueWriteSettleTests.swift`: expected, divergent, and exhausted observations exercise the smallest pure seam used by the live route.
- All waits are injected no-ops. No test depends on Chromium, pasteboard state, timers, or Accessibility permission.
- Verification: `swift test --filter AdaptiveTextFallbackTests && swift test --filter AdaptivePasteDispatcherTests && swift test --filter SetValueWriteSettleTests` → all selected tests pass.

## Done criteria

- [ ] `AXWriteSettle.live` remains exactly 25 reads maximum with 20 ms between reads; `.immediate` remains one read and no wait.
- [ ] Type-text, paste, and set-value all use `AXWriteSettle`; `AdaptiveTextSettle` has no remaining references or alias.
- [ ] Paste invokes Command-V only after an accepted AX operation remains at baseline through the bound; expected/divergent observations never invoke it.
- [ ] Set-value has no fixed 350 ms sleep and preserves the first divergent same-element observation.
- [ ] Rejected AX writes are read once and never pay the settle wait.
- [ ] The three focused test suites and `swift test` exit 0.
- [ ] No file outside Scope is modified by this plan; baseline changes remain intact.
- [ ] `plans/README.md` status row is updated.

## STOP conditions

Stop and report back (do not improvise) if:

- The type-text working-tree fix does not contain `maxReads: 25`, `usleep(20_000)`, and the baseline-conditioned loop shown above.
- `AdaptivePasteDispatcher` is no longer the sole decision point between accepted `AXTextOperation` and Command-V.
- `SetValueRouteService` no longer has same-element evidence before its projection reread.
- Implementing the settle requires changing a public request/response field or adding another fallback transport.
- A focused test or the full suite fails twice after one reasonable fix attempt.
- Any required baseline path is absent from both working-tree and post-`0110ffb` committed changes.

## Maintenance notes

- The 25 × 20 ms values intentionally match the measured async Chromium AX cache behavior and the already-landed type-text fix. Change them once in `AXWriteSettle`, with delayed-read regression tests for all three consumers.
- Reviewers should scrutinize the read count boundary (`maxReads` includes the first immediate read) and verify that divergent observations stop rather than being polled away.
- This plan does not claim an accepted AX status proves the effect. It only prevents premature escalation/classification while the same element still reports the baseline.
- Clipboard transaction safety, set-value projection cost, and type-text foreground/caret outcome honesty are separate concerns and remain deferred to their dedicated plans.
