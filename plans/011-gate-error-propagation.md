# Plan 011: Propagate gate failures without fallback or runtime crashes

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**: `git diff --stat 0110ffb..HEAD -- Sources/BackgroundComputerUse/Actions/Shared/ActionGateFailure.swift Sources/BackgroundComputerUse/Actions/Paste/PasteRouteService.swift Sources/BackgroundComputerUse/Actions/PressKey/PressKeyRouteService.swift Sources/BackgroundComputerUse/Runtime/RuntimeExecutionQueue.swift Sources/BackgroundComputerUse/Runtime/RuntimeCoordinator.swift Sources/BackgroundComputerUse/Runtime/RuntimeServices.swift Sources/BackgroundComputerUse/API/Router.swift Sources/BackgroundComputerUse/API/APIDocumentation.swift Tests/BackgroundComputerUseTests/ActionGateFailureTests.swift Tests/BackgroundComputerUseTests/PasteRouteTests.swift Tests/BackgroundComputerUseTests/PressKeyParserTests.swift Tests/BackgroundComputerUseTests/RuntimeExecutionQueueTests.swift Tests/BackgroundComputerUseTests/AgentAPICorrectnessTests.swift Tests/BackgroundComputerUseTests/APIDocumentationTests.swift openspec/changes/gate-error-propagation plans/README.md`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.
>
> Also run `git status --short` and `git diff --name-only 0110ffb..HEAD`. The union must show the baseline fixes in `API/Router.swift`, `App/BackgroundComputerUseControlBridge.swift`, `BackgroundComputerUseControlShared/CodeSignatureIdentity.swift`, `Runtime/RuntimeExecutionQueue.swift`, `Actions/TypeText/AdaptiveTextDispatcher.swift`, `StatePipeline/InteractionToken.swift`, `Runtime/Process/BoundedProcessRunner.swift`, `skills/background-computer-use/scripts/bcu-request.py`, `InteractionTokenTests.swift`, and `RuntimeExecutionQueueTests.swift`. STOP if any is neither committed after `0110ffb` nor present as a working-tree change.

## Status

- **Priority**: P2
- **Effort**: S
- **Risk**: LOW
- **Depends on**: none
- **Category**: bug
- **Planned at**: commit `0110ffb`, 2026-09-02

## Why this matters

Several pre-dispatch gates erase thrown causes with `try?`; PressKey can interpret a failed semantic window resolution as permission to use a less-specific key transport, and Paste collapses targeting/permission failures into generic output. Separately, a recoverable pthread creation/resource failure hits `precondition` and kills the runtime. This plan preserves sanitized error classes, permits continuation only for an explicit “semantic route absent” result, and turns worker unavailability into a retryable HTTP 503 instead of process termination.

## Current state

- `Sources/BackgroundComputerUse/Actions/Paste/PasteRouteService.swift:92-105` uses `try? resolveLiveElement` and returns only “Paste target could not be resolved to its live AX element,” losing the resolver error type.
- `PasteRouteService.swift:209-222` assigns `clickResponse = try? clickRouteService.click(...)`; lines 248-263 similarly assign `pressResponse = try? pressKeyRouteService.pressKey(...)`. Thrown nested-route errors become nil/false without a diagnostic. The PressKey call is inside `PasteTransaction.perform`, whose existing `PasteRouteTests.swift:57-79` proves failed dispatch still restores every original pasteboard byte.
- `PressKeyRouteService.swift:117-123` uses `try? resolveWindowElement`, appends a generic note, returns nil, and therefore reaches native delivery at lines 79-102. A failed targeting gate is not the same as “no search field/control exists.”
- `PressKeyRouteService.swift:181-184` is the actual recoverable semantic-absence case: the live window resolved, but no search/find control was found. Only this class may continue to another transport.
- `PressKeyRouteService.swift:290-295` catches Command-A live-element resolution, interpolates the raw error into a note, and returns nil; lines 315-329 also return nil after a selected-range mutation fails exact verification. Both paths can reach native Command-A even though the first is a gate failure and the second may already have mutated selection.
- `RuntimeExecutionQueue.swift:66-76` calls `pthread_attr_init(&attributes)` and `pthread_attr_setstacksize(&attributes, workerStackSize)` without checking either status. After `pthread_create`, it reaches the exact crash gate `precondition(created == 0, "pthread_create failed: \(created)")`; a recoverable EAGAIN therefore terminates the runtime.
- `RuntimeExecutionQueue.swift:29-55`, `RuntimeCoordinator.swift:4-10`, and `RuntimeServices.swift:183-190` are all `rethrows`. Queue infrastructure therefore cannot originate a typed recoverable error. `RuntimeServices.swift:54-58` is the one nonthrowing public service method (`listApps`) even though it also uses the queue, so the clean cutover must make it `throws` and add `try` at `Router.swift:126-132`.
- `RuntimeExecutionQueueTests.swift:5-35` already covers all scopes, 64 MiB stack size, deep recursion, and work-error propagation. It has no deterministic launch-failure seam.
- `Router.swift:498-525` routes non-decoding throws to `errorResponse`; `Router.swift:822-973` maps known typed errors and otherwise returns HTTP 500 `internal_error`. `AgentAPICorrectnessTests.swift:157-182` is the direct mapping-test exemplar.
- `APIDocumentation.swift:410-427` publishes `route_not_found` and `internal_error` as common errors; no route publishes `runtime_worker_unavailable`.
- Whole-source `try?` audit found these additional sites. Only the Paste line 300 and 305-306 sites are already in scope because they share the same route flow; the other seven are post-dispatch/capability evidence for route-owner changes. Their intended handling is recorded so nobody blindly converts them to throws:
  1. `ClickRouteService.swift:1209` — post-semantic-click poll capture; keep optional evidence, but retain the latest error as a verification warning and never dispatch again because of capture failure.
  2. `ClickRouteService.swift:1629` — freshness read before AX point escalation; on failure return an unavailable escalation result, not a press based on stale state.
  3. `ScrollRouteService.swift:942` — post-scroll capture; record unavailable evidence and stop escalation under the scroll no-second-mutation policy.
  4. `ScrollRouteService.swift:948-951` — post-scroll live resolution; leave projected/image evidence available, record the resolver type, and do not mutate again.
  5. `SetValueRouteService.swift:327` — post-write re-resolution; same-element evidence remains primary, resolver failure becomes a warning, never another write.
  6. `TypeTextRouteService.swift:348` — post-type re-resolution; same-element evidence remains primary, resolver failure is diagnostic only, never a fallback trigger.
  7. `TextRouteService.swift:172` — post-selection capture; mutation may have occurred, so capture failure must produce honest ambiguous verification rather than retry.
  8. `PasteRouteService.swift:300,305-306` — post-paste capture and refreshed live-element resolution both use `try?`; same-element settled value remains usable, each failure becomes a sanitized warning, and neither can trigger another paste.
- Repository rules from `openspec/project.md:14-15`: action routes are verifier-first read-act-read; background errors are reported rather than hidden; `/v1/routes` is the public contract source of truth.

## Commands you will need

| Purpose | Command | Expected on success |
|---|---|---|
| Gate classification | `swift test --filter ActionGateFailureTests` | exit 0; sanitized classes/dispositions pass |
| Paste restoration | `swift test --filter PasteRouteTests` | exit 0; nested failure still restores pasteboard |
| PressKey fallback policy | `swift test --filter PressKeyParserTests` | exit 0; only semantic absence permits fallback |
| Queue failure | `swift test --filter RuntimeExecutionQueueTests` | exit 0; EAGAIN throws without running work or crashing |
| Router mapping | `swift test --filter RuntimeCorrectnessTests` | exit 0; worker error maps to 503 |
| API docs | `swift test --filter APIDocumentationTests` | exit 0; 503 is published on queued routes |
| OpenSpec | `openspec validate gate-error-propagation --strict` | exit 0 when CLI exists |
| Final suite | `swift test` | exit 0; complete suite passes |

## Scope

**In scope** (the only files you should modify):
- `Sources/BackgroundComputerUse/Actions/Shared/ActionGateFailure.swift` (create)
- `Sources/BackgroundComputerUse/Actions/Paste/PasteRouteService.swift`
- `Sources/BackgroundComputerUse/Actions/PressKey/PressKeyRouteService.swift`
- `Sources/BackgroundComputerUse/Runtime/RuntimeExecutionQueue.swift`
- `Sources/BackgroundComputerUse/Runtime/RuntimeCoordinator.swift`
- `Sources/BackgroundComputerUse/Runtime/RuntimeServices.swift`
- `Sources/BackgroundComputerUse/API/Router.swift`
- `Sources/BackgroundComputerUse/API/APIDocumentation.swift`
- `Tests/BackgroundComputerUseTests/ActionGateFailureTests.swift` (create)
- `Tests/BackgroundComputerUseTests/PasteRouteTests.swift`
- `Tests/BackgroundComputerUseTests/PressKeyParserTests.swift`
- `Tests/BackgroundComputerUseTests/RuntimeExecutionQueueTests.swift`
- `Tests/BackgroundComputerUseTests/AgentAPICorrectnessTests.swift`
- `Tests/BackgroundComputerUseTests/APIDocumentationTests.swift`
- `openspec/changes/gate-error-propagation/proposal.md` (create)
- `openspec/changes/gate-error-propagation/tasks.md` (create)
- `openspec/changes/gate-error-propagation/specs/runtime-errors/spec.md` (create)
- `plans/README.md` (status row only)

**Out of scope** (do NOT touch, even though related):
- The seven audited optional evidence sites outside Paste/PressKey. Their intended handling is documented above for their route-owner changes.
- Changing action classification semantics after successful dispatch.
- Retrying pthread creation, reducing the 64 MiB worker stack, or replacing pthread with an operation pool.
- Exposing raw AX messages, window titles, captured text, token values, or other potentially sensitive error details.
- Live app launch/install/smoke scripts.

## Git workflow

- Branch: `advisor/011-gate-error-propagation`
- Commit logical units with observed style, e.g. `fix: preserve action gate failures` and `fix: report worker launch failure`.
- Do not push or open a PR unless the operator explicitly instructs it.

## Steps

### Step 1: Specify fail-closed gates and the public worker error

Create OpenSpec slug `gate-error-propagation`. Specify: permission/capture/AX/ambiguous targeting failures SHALL stop before a less-specific transport; only an explicit semantic-route-absent result MAY continue; post-dispatch verification failures SHALL not authorize another mutation; pthread init/stack/create failure SHALL throw `RuntimeExecutionQueueError.workerUnavailable(errno:)`; Router SHALL return 503 `runtime_worker_unavailable` with retry/restart recovery. Do not include raw request/target content in errors.

**Verify**: `if command -v openspec >/dev/null; then openspec validate gate-error-propagation --strict; else echo 'openspec unavailable: validation skipped and must be noted'; fi` → strict validation exits 0, or the explicit skip line prints.

### Step 2: Add one sanitized gate-failure classifier

Create `ActionGateFailure.swift` as a small value-only classifier shared by Paste and PressKey:

```swift
enum ActionGateFailureKind: String, Equatable, Sendable {
    case permission
    case capture
    case targeting
    case ambiguous
    case unexpected
}

struct ActionGateFailure: Equatable, Sendable {
    let kind: ActionGateFailureKind
    let errorType: String
    let summary: String

    var warning: String {
        "gate_failure kind=\(kind.rawValue) error_type=\(errorType)"
    }

    static func classify(_ error: Error, operation: String) -> ActionGateFailure
}
```

Map `DiscoveryError.accessibilityDenied` to permission; `DiscoveryError.appNotFound`/`windowNotFound` and `AXActionTargetResolverError` to targeting; and `StatePipelineExperimentError`/`CGWindowCaptureError` to capture. Reserve ambiguous for an existing typed ambiguous-target error if one reaches this seam; do not infer ambiguity by parsing an error message. Everything else is unexpected. `summary` is fixed per kind and operation, e.g. “Paste live-target resolution failed at the Accessibility gate; no mutation was attempted.” `errorType` is the unqualified Swift type name only. Never use `String(describing: error)` in an agent-facing summary/warning.

Add `ActionGateFailureTests` for every mapping, exact warning shape, and absence of an injected sensitive message.

**Verify**: `swift test --filter ActionGateFailureTests` → all type/classification/redaction cases pass.

### Step 3: Replace Paste gate-level `try?` with explicit fail-closed catches

At line 92, use `do/catch` to resolve the live element. On catch, classify it, append `failure.warning`, and return the existing targeting response with the sanitized summary.

Inside `performClipboardPaste`, replace nested Click and PressKey `try?` independently. Add `var nestedGateFailure: ActionGateFailure?` beside the existing optional responses:

```swift
do {
    clickResponse = try clickRouteService.click(request: clickRequest)
} catch {
    let failure = ActionGateFailure.classify(error, operation: "paste_focus_click")
    nestedGateFailure = failure
    directDiagnostic = failure.warning
    return false
}
```

For PressKey, catch inside `PasteTransaction.perform`, assign `nestedGateFailure`, set the sanitized warning, and return false so the transaction restores the pasteboard. When the route builds its final failed response, prefer `nestedGateFailure.summary` over the generic transport summary and include `nestedGateFailure.warning` exactly once. A thrown nested route never permits the next transport. A nonthrowing Click response may continue only if the existing exact-focus and foreground-preserved gate proves safety. Replace both post-dispatch optional reads at lines 300 and 305-306 with independent `do/catch` blocks classified as `paste_post_capture` and `paste_post_live_resolution`. On either failure, append one sanitized verification warning and keep `sameElementAfter` as primary evidence; do not retry capture, resolve, or paste.

Replace the two stored concrete nested services with internal injected throwing closures, defaulted in the initializer to closures over production `ClickRouteService` and `PressKeyRouteService` instances:

```swift
private let click: (ClickRequest) throws -> ClickResponse
private let pressKey: (PressKeyRequest) throws -> PressKeyResponse

init(
    executionOptions: ActionExecutionOptions = .visualCursorEnabled,
    foregroundApplication: @escaping @Sendable () -> ForegroundApplicationSnapshot? = ForegroundApplicationSnapshot.capture,
    click: ((ClickRequest) throws -> ClickResponse)? = nil,
    pressKey: ((PressKeyRequest) throws -> PressKeyResponse)? = nil
)
```

Construct each production service once in the initializer and assign `self.click = click ?? { try clickService.click(request: $0) }` and the equivalent PressKey closure. Extend `PasteRouteTests` with throwing sentinel closures: each nested gate failure records one sanitized diagnostic, invokes no later nested transport, returns failed dispatch, and restores pasteboard bytes exactly. Do not add mutable global hooks.

**Verify**: `swift test --filter PasteRouteTests && swift test --filter ActionGateFailureTests` → failure diagnostics are sanitized and failed dispatch restores the complete pasteboard.

### Step 4: Distinguish PressKey semantic absence from resolution failure

Replace both semantic live-resolution fail-open paths with explicit results. For Command-F’s window resolution and Command-A’s `resolveLiveElement` catch, classify the error and return a `PressKeyResponse` with `.effectNotVerified`, `.targeting`, no action/transport, no post token, and `failure.warning`. Never return nil from either catch. Keep nil/`.routeAbsent` only after a successful inspection proves no semantic candidate or required capability exists before any mutation.

Use a pure policy seam to make this distinction testable:

```swift
enum PressKeySemanticGateResult: Equatable, Sendable {
    case routeAbsent(reason: String)
    case failed(ActionGateFailure)

    var permitsFallback: Bool {
        if case .routeAbsent = self { return true }
        return false
    }
}
```

For Command-A, once `setSelectedTextRangeResult` is called, a nonexact reread is `.possiblyMutated`: return effect-not-verified with the raw AX status converted only through the existing safe status formatter, and never reach native Command-A. For Command-F/Command-A post-mutation refresh/reread failures, append sanitized verification warnings and return effect-not-verified when same-target evidence is insufficient. Add injected-policy tests for: absent candidate permits fallback; Command-F window resolution failure does not; Command-A live-element resolution failure does not; Command-A nonexact result after the set call does not; post-mutation ambiguity does not. Every failure case asserts the native-dispatch counter remains zero.

**Verify**: `swift test --filter PressKeyParserTests` → semantic gate policy cases and existing parser/effect tests pass.

### Step 5: Make worker launch failure typed and injectable

In `RuntimeExecutionQueue.swift`, add exactly:

```swift
enum RuntimeExecutionQueueError: Error, Equatable, Sendable {
    case workerUnavailable(errno: Int32)
}

protocol RuntimeWorkerRunning {
    func run(stackSize: Int, body: () -> Void) throws
}
```

Implement `POSIXRuntimeWorkerRunner`. Check `pthread_attr_init`; only destroy attributes after successful init. Check `pthread_attr_setstacksize`; destroy then throw on nonzero. Check `pthread_create`; throw `.workerUnavailable(errno: created)` instead of preconditioning and never force-unwrap a failed thread. A successful create must still `pthread_join` before the body pointer/non-escaping closure leaves scope. Keep create+join inside the synchronous runner; do not use a mutable static test hook.

Change `RuntimeExecutionQueue.sync` from `rethrows` to `throws` and add an internal overload accepting `any RuntimeWorkerRunning`, defaulting production to the POSIX runner. Change `RuntimeCoordinator.execute` and `RuntimeServices.execute` from `rethrows` to `throws`. Existing throwing route methods remain source-compatible; change `RuntimeServices.listApps()` to `throws` and the Router list-apps closure to `try services.listApps()`.

Update existing queue tests to use `try`. Add a fake runner that throws `.workerUnavailable(errno: EAGAIN)` without invoking body; assert the exact error and `workRan == false`. Also retain work-thrown error propagation and large-stack tests.

**Verify**: `swift test --filter RuntimeExecutionQueueTests` → all existing tests plus deterministic EAGAIN pass; the process does not abort.

### Step 6: Map and document retryable worker unavailability

Add this typed Router case before default:

```swift
case let RuntimeExecutionQueueError.workerUnavailable(errno):
    .json(
        ErrorResponse(
            error: "runtime_worker_unavailable",
            message: "The runtime could not start an isolated Accessibility worker (errno \(errno)).",
            requestID: requestID,
            recovery: [
                "Retry once after the current system resource pressure subsides.",
                "If it repeats, restart the signed BackgroundComputerUse runtime and keep this requestID for logs.",
            ]
        ),
        statusCode: 503,
        reasonPhrase: "Service Unavailable"
    )
```

`errno` is safe numeric process state; do not append work/request details. Add the direct Router mapping test to `RuntimeCorrectnessTests`, asserting 503, exact code, requestID, and nonempty recovery.

In `APIDocumentation.errors(for:)`, publish the 503 on the exact queue-backed set: every `RouteID` except `.health`, `.bootstrap`, and `.routes`. Implement this as `routeUsesExecutionQueue(_:)` with those three false cases and default true; do not claim the direct GET routes can return it. Add an exact set test in `APIDocumentationTests`.

**Verify**: `swift test --filter RuntimeCorrectnessTests && swift test --filter APIDocumentationTests` → Router and route catalog expose the same 503 contract.

### Step 7: Run the final non-live gate and update the index

Run the full suite once. Confirm no remaining `try?` at the Paste pre-dispatch gates, Paste post-capture/live-resolution sites, Command-F semantic window gate, or Command-A live-element gate by using the repository search tool (not a brittle test). Inspect `git status --short`, confirm only Scope files changed, and set plan 011 to `DONE` in `plans/README.md`.

**Verify**: `swift test && git status --short` → full suite passes; only in-scope files plus pre-existing baseline changes are listed.

## Test plan

- `ActionGateFailureTests`: typed classification, stable warning format, and redaction of sensitive error messages.
- `PasteRouteTests`: a failed nested dispatch restores all original pasteboard items/types/bytes; post-capture and refreshed-live-resolution failures keep same-element evidence, append sanitized diagnostics, and dispatch no second paste.
- `PressKeyParserTests`: explicit absence versus Command-F/Command-A resolution failure; only absence permits fallback; nonexact Command-A after the set call and post-mutation ambiguity leave native-dispatch count zero.
- `RuntimeExecutionQueueTests`: all scopes, 64 MiB stack, deep recursion, work error, successful injected runner, and EAGAIN without body execution.
- `RuntimeCorrectnessTests`: `workerUnavailable(EAGAIN)` maps to HTTP 503 with exact code/requestID/recovery.
- `APIDocumentationTests`: queue-backed routes publish the 503 and direct routes do not.
- Final verification: `swift test` → complete suite passes.

## Done criteria

- [ ] Paste live resolution and nested Click/PressKey throws retain sanitized error class and fail closed; both post-paste optional reads preserve same-element evidence plus diagnostics.
- [ ] PressKey falls through only for explicit semantic-route absence, never Command-F/Command-A resolution failure or any permission/AX failure.
- [ ] No second transport follows a possible Paste or PressKey mutation, including nonexact Command-A after its AX selected-range set.
- [ ] pthread attr init, stack-size setup, and create results are checked.
- [ ] EAGAIN throws `RuntimeExecutionQueueError.workerUnavailable(errno:)` without running work or crashing.
- [ ] Router returns 503 `runtime_worker_unavailable`; `/v1/routes` documents it on queue-backed routes.
- [ ] OpenSpec strict validation passes when available; `swift test` exits 0.
- [ ] No out-of-scope files are newly modified; plan 011 index row is `DONE`.

## STOP conditions

Stop and report back (do not improvise) if:

- Current-state excerpts no longer match the live code.
- An error category can only be inferred by matching localized/free-form error text.
- A catch would continue to another transport for anything except explicit semantic-route absence.
- The thread-runner abstraction can return before a successfully created pthread is joined; that would violate the non-escaping body lifetime.
- Queue errors cannot cross RuntimeCoordinator/RuntimeServices without changing public route signatures beyond `throws`.
- A response would expose captured UI text, target identity, token values, or raw AX error messages.
- A focused verification fails twice after one reasonable correction.

## Maintenance notes

- The eight audited optional-evidence sites are not licenses to ignore errors; preserve diagnostics without converting post-dispatch uncertainty into a retry.
- Review pthread lifetime and attribute cleanup closely. Init failure must not destroy uninitialized attributes; create failure must not join/unwrap a thread.
- Keep `runtime_worker_unavailable` retryable but bounded: callers should retry once, not spin under resource exhaustion.
- Any new semantic PressKey route must return explicit absent versus failed state; optional nil must never carry both meanings again.
