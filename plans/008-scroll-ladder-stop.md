# Plan 008: Stop scroll escalation after any plausible movement and bound verification

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**: `git diff --stat 0110ffb..HEAD -- Sources/BackgroundComputerUse/Actions/Scroll/ScrollRouteService.swift Sources/BackgroundComputerUse/API/APIDocumentation.swift Tests/BackgroundComputerUseTests/ScrollLadderPolicyTests.swift Tests/BackgroundComputerUseTests/APIDocumentationTests.swift`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.
>
> **Required working-tree baseline**: run `git status --short`, then confirm each of these paths is either listed there or differs in `git diff --name-only 0110ffb..HEAD`: `Sources/BackgroundComputerUse/API/Router.swift`, `Sources/BackgroundComputerUse/App/BackgroundComputerUseControlBridge.swift`, `Sources/BackgroundComputerUseControlShared/CodeSignatureIdentity.swift`, `Sources/BackgroundComputerUse/Runtime/RuntimeExecutionQueue.swift`, `Sources/BackgroundComputerUse/Actions/TypeText/AdaptiveTextDispatcher.swift`, `Sources/BackgroundComputerUse/StatePipeline/InteractionToken.swift`, `Sources/BackgroundComputerUse/Runtime/Process/BoundedProcessRunner.swift`, `skills/background-computer-use/scripts/bcu-request.py`, `Tests/BackgroundComputerUseTests/InteractionTokenTests.swift`, and `Tests/BackgroundComputerUseTests/RuntimeExecutionQueueTests.swift`. STOP if any is absent from both checks.

## Status

- **Priority**: P1
- **Effort**: M
- **Risk**: MED
- **Depends on**: none
- **Category**: bug
- **Planned at**: commit `0110ffb`, 2026-09-02
## Why this matters
One scroll request can currently dispatch several page actions, scrollbar writes, wheel events, and even act on multiple candidate panes whenever the first real movement is delayed or below the strong-evidence threshold. The same route may perform up to 33 post-dispatch full-tree captures, each paired with a screenshot, while comparing every attempt against stale pre-route state. This plan makes escalation fail-safe: only bounded proof of no effect permits another mutation; verified movement returns success; any plausible but unproven movement stops as `verifier_ambiguous`. A route-wide deadline and six-capture cap bound cost while an evolving baseline prevents one strategy’s delayed effect from being credited to another.
## Current state
- `Sources/BackgroundComputerUse/Actions/Scroll/ScrollRouteService.swift` owns both the outer candidate loop and inner strategy ladder. The outer loop tries up to three candidates and returns only on success:
```swift
// ScrollRouteService.swift:203-214
if axStrategies.isEmpty == false {
    for candidate in candidates.prefix(3) {
        let result = executeCandidate(
            candidate,
            mode: .backgroundSafeAXLadder,
            strategies: axStrategies,
            capture: capture,
            requestedNode: requestedNode,
            direction: request.direction,
            pages: pages,
            cursorRequest: request.cursor
        )
```
- `executeCandidate` captures its baseline once, then dispatches every strategy unless one reaches strong success:
```swift
// ScrollRouteService.swift:453-478
for strategy in strategies {
    let attempt = attempt(
        strategy: strategy,
        mode: mode,
        candidate: candidate,
        direction: direction,
        pages: pages,
        window: capture.envelope.response.window,
        resolvedContainer: resolvedContainer
    )
    transports.append(attempt.transport)

    guard attempt.didDispatch else {
        continue
    }

    let verificationReads = rereadAndVerify(
        mode: mode,
        beforeCapture: capture,
        beforeLiveSnapshot: beforeLiveSnapshot,
        beforeWindowImage: beforeWindowImage,
        requestedNode: requestedNode,
        containerNode: candidate.node,
        direction: direction,
        pages: pages
    )
```
- `rereadAndVerify` grants each dispatched strategy three cumulative waits and three complete rereads/screenshots:
```swift
// ScrollRouteService.swift:940-944
for (offset, delay) in rereadDelaysMilliseconds.enumerated() {
    sleepRunLoop(Double(delay) / 1_000.0)
    let afterCapture = try? targetResolver.reread(after: beforeCapture)
    let afterWindowImage = CGWindowCaptureService.captureImage(window: beforeCapture.envelope.response.window)
    let matchedContainer = afterCapture.flatMap { locateVerificationNode(containerNode, in: $0) }
```
- The same original `capture` is also passed to targeted-wheel and post-to-PID paging (`ScrollRouteService.swift:254-315`) after the AX ladder may already have dispatched. The route does not preserve a clean strategy-local baseline.
- `summarizeVerification` already distinguishes strong success, likely wrong-pane ambiguity, definite no movement, and other ambiguity (`ScrollRouteService.swift:1148-1211`). Its `definitelyNoMovement` test requires every observed delta/image ratio to stay below thresholds (`ScrollRouteService.swift:1183-1193`), but the caller treats all non-success classifications as escalation permission.
- `LiveContainerSnapshot` contains scrollbar values and visible character range (`ScrollRouteService.swift:20-24`), and `compareWindowImages` already supplies target-region and full-window change ratios. These are the cheap probes to run before another full projection.
- There is no scroll behavior test file: the only current scroll tests are DTO/schema checks in `APIDocumentationTests.swift:87-114` and strict request-field checks in `HardenedAgentAPITests.swift:63-67,103-112`. A deterministic policy/runner seam must be introduced.
- The repository requires read-act-read, verifier-first classifications, and reporting uncertainty rather than hiding it (`openspec/project.md:14`). Swift tests use `Testing`, `@Test`, and `#expect`, not XCTest (`openspec/project.md:7-9`).
## Commands you will need
| Purpose | Command | Expected on success |
|---|---|---|
| Focused ladder tests | `swift test --filter ScrollLadderPolicyTests` | exit 0; all selected tests pass |
| API docs tests | `swift test --filter APIDocumentationTests` | exit 0; all selected tests pass |
| Full suite | `swift test` | exit 0; full suite passes |
| Changed files | `git status --short` | only baseline work plus this plan’s in-scope changes are present |
## Scope
**In scope** (the only files you should modify):
- `Sources/BackgroundComputerUse/Actions/Scroll/ScrollRouteService.swift`
- `Sources/BackgroundComputerUse/API/APIDocumentation.swift`
- `Tests/BackgroundComputerUseTests/ScrollLadderPolicyTests.swift` (create)
- `Tests/BackgroundComputerUseTests/APIDocumentationTests.swift`
- `plans/README.md` (status row only)

**Out of scope** (do NOT touch, even though related):
- Scroll request/response DTO fields and RouteRegistry field names; this plan changes internal escalation semantics, not the wire shape.
- Scroll transport generation, page/delta magnitude, candidate scoring, and foreground activation behavior.
- Global AX capture batching and screenshot implementation; those have separate performance plans.
- Click’s escalation implementation; copy its three-way principle, not its types or code.
- Live app launch/install scripts and unauthorized real UI scrolling.

## Git workflow

- Branch: `advisor/008-scroll-ladder-stop`
- Make one logical commit after focused tests: `fix: stop scroll ladder on plausible movement`
- Do NOT push or open a PR unless the operator instructed it.
- Preserve all pre-existing working-tree changes.

## Steps
### Step 1: Introduce a deterministic three-way ladder control seam
At file scope in `ScrollRouteService.swift`, change `StrategyAttemptOutcome` and the new control types from `private` to internal only where tests need them. Add:
```swift
enum ScrollLadderDisposition: Equatable {
    case noDispatch
    case provedNoEffect
    case success
    case ambiguous
}

struct ScrollLadderRunResult {
    let terminalStrategy: ScrollStrategyDTO?
    let disposition: ScrollLadderDisposition
}

enum ScrollLadderControl {
    static func run(
        strategies: [ScrollStrategyDTO],
        step: (ScrollStrategyDTO) -> ScrollLadderDisposition
    ) -> ScrollLadderRunResult {
        var sawProvedNoEffect = false
        for strategy in strategies {
            let disposition = step(strategy)
            switch disposition {
            case .noDispatch:
                continue
            case .provedNoEffect:
                sawProvedNoEffect = true
            case .success, .ambiguous:
                return ScrollLadderRunResult(terminalStrategy: strategy, disposition: disposition)
            }
        }
        return ScrollLadderRunResult(
            terminalStrategy: nil,
            disposition: sawProvedNoEffect ? .provedNoEffect : .noDispatch
        )
    }
}
```

Add `ScrollLadderPolicyTests.swift` with closure/counter tests for: no-dispatch advances; proved-no-effect advances; a delayed success returned from strategy 1 dispatches strategy 1 once and never invokes strategy 2; ambiguous strategy 1 never invokes strategy 2. Compare `terminalStrategy?.rawValue` because `ScrollStrategyDTO` is not `Equatable`. No AX or image objects belong in these tests.

**Verify**: `swift test --filter ScrollLadderPolicyTests` → exit 0; runner call-count and terminal-disposition tests pass.

### Step 2: Add one route-wide verification budget

Add an internal value type with an injected monotonic clock:

```swift
struct ScrollVerificationBudget {
    let maxFullCaptures: Int
    let deadlineUptimeNanoseconds: UInt64
    var fullCapturesUsed = 0

    static func live(now: UInt64 = DispatchTime.now().uptimeNanoseconds) -> Self {
        .init(maxFullCaptures: 6,
              deadlineUptimeNanoseconds: now + 2_000_000_000)
    }

    mutating func reserveFullCapture(now: UInt64 = DispatchTime.now().uptimeNanoseconds) -> Bool {
        guard fullCapturesUsed < maxFullCaptures, now < deadlineUptimeNanoseconds else { return false }
        fullCapturesUsed += 1
        return true
    }

    func canWait(now: UInt64 = DispatchTime.now().uptimeNanoseconds) -> Bool {
        now < deadlineUptimeNanoseconds
    }
}
```

Create one `var verificationBudget = .live()` in `scroll(request:)` after the initial capture and pass it `inout` through every AX candidate, targeted wheel, and paging execution. The initial pre-route capture does not consume this post-dispatch budget. Add deterministic tests for the sixth reservation succeeding, seventh failing, and reservations at/after the deadline failing.

**Verify**: `swift test --filter ScrollLadderPolicyTests` → exit 0; budget count/deadline tests pass without sleeping.

### Step 3: Replace per-strategy full rereads with cheap-first bounded verification

Replace `rereadAndVerify` with `verifyAfterDispatch`, returning a private `ScrollPostDispatchVerification` whose fields are `reads: [ScrollVerificationReadDTO]`, `verification: ScrollVerificationSummaryDTO`, `provedNoEffect: Bool`, and `latestBaseline: ScrollVerificationBaseline`. Its parameters must match the complete call shown in Step 4, including `inout ScrollVerificationBudget`.

Add `ScrollVerificationBaseline` with fields `capture: AXActionStateCapture`, `windowImage: CGImage?`, and `nextReadOrdinal: Int`. `executeCandidate` relocates the requested/container nodes in that capture and samples its live element immediately before each dispatch. For each delay 80/180/320 ms, while `budget.canWait()`:

1. Read `captureLiveContainerSnapshot` from the already-resolved live container.
2. Capture the current window image and compare it with the baseline image/viewport.
3. If scrollbar/range direction proves movement, stop as success without a full projection.
4. If pixels show plausible movement but do not meet strong direction/pane proof, stop as ambiguous without dispatching again.
5. Do not project after the first or second static cheap sample. Only after all cheap samples through the 320 ms wait remain static/inconclusive, call `reserveFullCapture`; if granted, do one `targetResolver.reread(after: baseline.capture)` and run the existing semantic/frame/text checks. If the deadline expires or reservation is denied first, stop ambiguous with evidence `route-wide verification budget exhausted before no-effect could be proved`.

Do not perform a full projection on every delay. One dispatched attempt uses at most one full projection; an unavailable full projection is ambiguity, not permission for a second mutation. Across the route, the cap remains six.

Define plausible movement conservatively as any nonzero live scrollbar/range delta, same-label shift at least 1 px, visible text/labels change, target-region image ratio at least 0.012, or full-window ratio at least 0.018. Existing stronger thresholds in `verifyRead` still produce success. Wrong-pane likelihood is always ambiguous, never proved-no-effect.

Only classify `.provedNoEffect` when a full projection was obtained and every cheap/full signal satisfies the existing static thresholds. Missing capture/image evidence is ambiguous, not no effect.

**Verify**: `swift test --filter ScrollLadderPolicyTests` → exit 0 after adding pure policy cases for strong evidence → success, plausible movement → ambiguous, complete static evidence → proved no effect, missing evidence → ambiguous, and budget exhaustion → ambiguous.

### Step 4: Carry the latest baseline through every candidate and transport

Create the initial `ScrollVerificationBaseline` once from `capture`, one initial window image, and read ordinal 1. Change `executeCandidate` to take `baseline: inout ScrollVerificationBaseline` and `budget: inout ScrollVerificationBudget`; before each dispatch, relocate that candidate against `baseline.capture` and take its strategy-local live snapshot. Never pass the immutable original capture as the comparison source after a dispatch.

Drive each candidate’s strategy list through `ScrollLadderControl.run`. The closure must append transport/evidence and return:

```swift
guard attempt.didDispatch else { return .noDispatch }
let outcome = verifyAfterDispatch(mode: mode, baseline: baseline, resolvedContainer: resolvedContainer, requestedNode: requestedNode, containerNode: candidate.node, direction: direction, budget: &budget)
baseline = outcome.latestBaseline
switch outcome.verification.classification {
case .success: return .success
case .verifierAmbiguous: return .ambiguous
case .unsupported where outcome.provedNoEffect: return .provedNoEffect
default: return .ambiguous
}
```

Update `CandidateExecutionResult` to carry the terminal disposition and latest state token; the `inout` baseline already carries capture/image state. At every outer decision point, `.success` must execute the existing success `response` argument list from `ScrollRouteService.swift:225-247`; `.ambiguous` must immediately execute the final `response` shape from lines 361-383 using that result’s classification, failure domain, verification, reads, and latest token; only `.noDispatch` or `.provedNoEffect` may continue to another candidate/transport. Do not create an incomplete response helper.

Before acting on another candidate, relocate its node/target in `baseline.capture`; if relocation fails after a prior dispatch, return ambiguous rather than resolving against the original capture. This prevents a delayed prior effect from becoming a later transport’s evidence or moving a stale pane.

**Verify**: `swift test --filter ScrollLadderPolicyTests` → exit 0; delayed success, ambiguity, proved-no-effect escalation, and exhausted-budget stop cases pass with exact dispatch counts.

### Step 5: Preserve response evidence and document the safer behavior

Keep the existing public `transports`, `verificationReads`, `postStateToken`, `verification`, `winningMode`, and `winningStrategy` fields. Ensure route-wide read ordinals increase monotonically rather than restarting at one per strategy. For budget exhaustion, missing evidence, and plausible movement, return `classification: verifier_ambiguous`, `failureDomain: .verification` (or `.targeting` for existing wrong-pane evidence), and retain every transport/read gathered so far. Never call an ambiguous dispatch “unsupported.”

Update `APIDocumentation.swift` scroll usage: success requires verified movement; `verifier_ambiguous` means plausible movement or exhausted verification stopped the ladder and the caller must reread before any retry; only bounded proof of no effect permits internal escalation. Add a matching assertion in `APIDocumentationTests`.

**Verify**: `swift test --filter APIDocumentationTests && swift test --filter ScrollLadderPolicyTests` → exit 0; agent-facing semantics and policy tests pass.

### Step 6: Run the integrated regression gate

Run the full suite once. Do not run `script/start.sh`, install the app, or perform live scrolls.

**Verify**: `swift test` → exit 0; the full suite passes.

## Test plan

- New `ScrollLadderPolicyTests.swift` uses injected step closures and clocks; it never requires Accessibility, Screen Recording, or real sleeps.
- Runner cases: no dispatch advances; proven no effect advances; delayed effect from strategy 1 stops before strategy 2; plausible movement stops immediately.
- Budget cases: six reservations max, deadline rejection, and exhausted budget maps to ambiguity.
- Evidence-policy cases: strong movement success, wrong-pane/plausible movement ambiguity, complete static evidence no-effect, missing evidence ambiguity.
- `APIDocumentationTests` locks the retry guidance exposed to agents.
- Verification: `swift test --filter ScrollLadderPolicyTests && swift test --filter APIDocumentationTests` → all selected tests pass; then `swift test` passes.

## Done criteria

- [ ] Another strategy/candidate/opaque transport runs only after no dispatch or bounded proof of no effect.
- [ ] Any strong movement returns success; any plausible/unavailable/budget-exhausted evidence returns `verifier_ambiguous` and stops.
- [ ] Every comparison uses the latest clean baseline, not the original pre-route capture after a dispatch.
- [ ] No route performs more than six post-dispatch full projection captures or verifies beyond the two-second deadline.
- [ ] Cheap live-container/image checks run before a full projection.
- [ ] Verification read ordinals and response evidence cover the whole route monotonically.
- [ ] Focused policy/docs tests and full `swift test` exit 0.
- [ ] No file outside Scope is modified by this plan; `plans/README.md` is updated.

## STOP conditions

Stop and report back (do not improvise) if:

- Scroll transport dispatch has moved out of `executeCandidate` or candidates no longer share the route entry flow shown above.
- Existing live scrollbar/range and image-diff probes cannot be sampled without a full projection.
- The implementation cannot distinguish “proved static” from “evidence missing”; never treat missing evidence as no effect.
- Carrying the latest capture requires changing public DTOs or target identity semantics.
- A focused test or the full suite fails twice after one reasonable fix attempt.
- Any required baseline path is absent from both working-tree and post-`0110ffb` committed changes.

## Maintenance notes

- The safety invariant is more important than recovery rate: an ambiguous dispatch may already have moved content, so a second mutation is unsafe.
- The six-capture/two-second budget is route-wide. If tuned later, retain deterministic boundary tests and never restore per-strategy budgets.
- Reviewers should trace all exits from AX candidate, targeted-wheel, and paging lanes; none may continue on ambiguity.
- A future live-smoke plan should measure native and Electron latency separately and may tighten cheap-probe thresholds, but must not weaken the three-way stop rule.
