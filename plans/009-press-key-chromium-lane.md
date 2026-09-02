# Plan 009: Make `press_key` work honestly on Chromium and Electron

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**: `git diff --stat 0110ffb..HEAD -- Sources/BackgroundComputerUse/Actions/PressKey/PressKeySemanticPlanner.swift Sources/BackgroundComputerUse/Actions/PressKey/PressKeyDispatchCoordinator.swift Sources/BackgroundComputerUse/Actions/PressKey/PressKeyRouteService.swift Sources/BackgroundComputerUse/Contracts/PressKeyActionContracts.swift Sources/BackgroundComputerUse/API/RouteRegistry.swift Sources/BackgroundComputerUse/API/APIDocumentation.swift Tests/BackgroundComputerUseTests/PressKeySemanticPlannerTests.swift Tests/BackgroundComputerUseTests/PressKeyDispatchCoordinatorTests.swift Tests/BackgroundComputerUseTests/PressKeyParserTests.swift Tests/BackgroundComputerUseTests/HardenedAgentAPITests.swift Tests/BackgroundComputerUseTests/APIDocumentationTests.swift openspec/changes/press-key-chromium-lane plans/README.md`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.
>
> Also run `git status --short` and `git diff --name-only 0110ffb..HEAD`. The union must show the baseline fixes in `API/Router.swift`, `App/BackgroundComputerUseControlBridge.swift`, `BackgroundComputerUseControlShared/CodeSignatureIdentity.swift`, `Runtime/RuntimeExecutionQueue.swift`, `Actions/TypeText/AdaptiveTextDispatcher.swift`, `StatePipeline/InteractionToken.swift`, `Runtime/Process/BoundedProcessRunner.swift`, `skills/background-computer-use/scripts/bcu-request.py`, `InteractionTokenTests.swift`, and `RuntimeExecutionQueueTests.swift`. STOP if any is neither committed after `0110ffb` nor present as a working-tree change.

## Status

- **Priority**: P1
- **Effort**: L
- **Risk**: HIGH
- **Depends on**: plans/007-type-text-outcome-honesty.md
- **Category**: bug
- **Planned at**: commit `0110ffb`, 2026-09-02

## Why this matters

`press_key` has semantic implementations only for Command-F and Command-A; every other key eventually becomes pid-directed `CGEvent` delivery. Chromium/Electron discard that background delivery, so observed `command+a` and `delete` calls returned `effect_not_verified` with `opaque_renderer_focus_unconfirmed`. This plan adds only semantics that can be proven against one exact text target or one unambiguous pressable submit control, then uses the already-guarded foreground protocol for keys with no safe AX equivalent. It never dispatches a second transport after a first transport may have mutated state.

## Current state

- `Sources/BackgroundComputerUse/Actions/PressKey/PressKeyRouteService.swift:79-102` has exactly two semantic intents; its raw-key branch is:
  ```swift
  case .rawKey:
      break
  }
  ```
  The next statement calls `attemptNativeKeyDelivery`, so every other parsed key reaches native delivery.
- `PressKeyRouteService.swift:403-456` performs WindowServer preflight and then calls `postKeySequence`; `PressKeyRouteService.swift:890-924` posts every modifier/key event with `event.postToPid(pid)`.
- `PressKeyRouteService.swift:269-329` already implements Command-A by resolving one focused/unambiguous text entry, writing `kAXSelectedTextRangeAttribute`, rereading the same element, and falling back only when the exact selection does not verify.
- `PressKeyRouteService.swift:33-57` evaluates `RuntimeSafetyPolicy` against the raw request string before parsing. `RuntimeSafetyPolicy.swift:86-99` recognizes only strings containing `command` plus Delete/Backspace, while the parser accepts aliases such as `meta`; therefore `meta+delete` can bypass confirmation today. Parse first, then evaluate the normalized `parsed.dto.normalized` so every Command alias requires `confirm=true`.
- `PressKeyRouteService.swift:823-830` normalizes `return` and `kp_enter`, but not the common spelling `enter`; `PressKeyParserTests.swift:39-45` currently asserts that `Enter` throws while `Return` succeeds.
- `TypeTextRouteService.swift:911-935` demonstrates the target-bound renderer lane: require `AXTextOperation` in parameterized attribute names, read `AXSelectedTextMarkerRange`, construct `AXTextOperationPayload.replacing`, then call the parameterized attribute.
- `TypeTextRouteService.swift:1180-1209` computes an exact replacement with `NSString`, validates the selected range, and returns the exact value plus caret range. Reuse this UTF-16 convention; do not index Swift `String` with integer offsets.
- `AdaptiveTextDispatcher.swift:39-73` explains and implements the required settle: Chromium can acknowledge `AXValue` before the renderer/AX cache reflects it, so accepted writes poll up to 25 reads at 20 ms rather than immediately escalating.
- `ForegroundFallbackCoordinator.swift:32-87` permits background execution, elevates the target only when the original foreground is unchanged, and blocks when a third app wins. Lines 90-111 restore only while the target is still frontmost.
- `PressKeyActionContracts.swift:121-136` currently ends at `verification` and `postScreenshot`; it has none of the TypeText telemetry fields. `TextActionContracts.swift:178-194` names the aligned fields `strategiesAttempted`, `fallbackReason`, `foregroundFallbackUsed`, and `foregroundRestored`.
- `RouteRegistry.swift:673-684` documents `press_key` request/confirm policy; `RouteRegistry.swift:1053-1070` documents its response but not the four new telemetry fields.
- Repository rules in `openspec/project.md:13-15`: “Actions consome StatePipeline/Cursor, não o contrário”; action routes follow capture → state validation → target resolution → safety → dispatch → reread/verify; background errors are reported rather than hidden by stealing focus; `/v1/routes` must match real DTO fields.
- Measured recon context: deep Electron trees reached about 70 levels; Chromium applied AX value writes asynchronously; pid-directed key events did not produce a verified effect; a TypeText foreground fallback reported `foregroundRestored: false`. Plan 007 must be complete before this plan relies on foreground restoration classification.

## Commands you will need

| Purpose | Command | Expected on success |
|---|---|---|
| Focused planner tests | `swift test --filter PressKeySemanticPlannerTests` | exit 0; all semantic plan cases pass |
| Dispatch coordinator tests | `swift test --filter PressKeyDispatchCoordinatorTests` | exit 0; every plan invokes at most one mutation lane |
| Existing parser/evidence tests | `swift test --filter PressKeyParserTests` | exit 0; parser and verification tests pass |
| Contract tests | `swift test --filter PressKeyVerificationTests` | exit 0; response telemetry encodes correctly |
| API docs tests | `swift test --filter APIDocumentationTests` | exit 0; press_key docs match DTO |
| OpenSpec | `openspec validate press-key-chromium-lane --strict` | exit 0 when CLI exists |
| Final suite | `swift test` | exit 0; complete suite passes |

## Scope

**In scope** (the only files you should modify):
- `Sources/BackgroundComputerUse/Actions/PressKey/PressKeySemanticPlanner.swift` (create)
- `Sources/BackgroundComputerUse/Actions/PressKey/PressKeyDispatchCoordinator.swift` (create)
- `Sources/BackgroundComputerUse/Actions/PressKey/PressKeyRouteService.swift`
- `Sources/BackgroundComputerUse/Contracts/PressKeyActionContracts.swift`
- `Sources/BackgroundComputerUse/API/RouteRegistry.swift`
- `Sources/BackgroundComputerUse/API/APIDocumentation.swift`
- `Tests/BackgroundComputerUseTests/PressKeySemanticPlannerTests.swift` (create)
- `Tests/BackgroundComputerUseTests/PressKeyParserTests.swift`
- `Tests/BackgroundComputerUseTests/PressKeyDispatchCoordinatorTests.swift` (create)
- `Tests/BackgroundComputerUseTests/HardenedAgentAPITests.swift`
- `Tests/BackgroundComputerUseTests/APIDocumentationTests.swift`
- `openspec/changes/press-key-chromium-lane/proposal.md` (create)
- `openspec/changes/press-key-chromium-lane/tasks.md` (create)
- `openspec/changes/press-key-chromium-lane/specs/press-key/spec.md` (create)
- `plans/README.md` (status row only)

**Out of scope** (do NOT touch, even though related):
- General click, scroll, paste, and TypeText dispatch behavior.
- New private WindowServer transports or broad key-to-AX heuristics.
- Synthesizing Return into multiline fields; it can insert data and is not equivalent to form submission.
- Live app launch/install scripts. A live Electron smoke requires separate operator authorization.

## Git workflow

- Branch: `advisor/009-press-key-chromium-lane`
- Commit logical units with the observed style, e.g. `feat: add semantic press key delivery` and `docs: specify press key fallback contract`.
- Do not push or open a PR unless the operator explicitly instructs it.

## Steps

### Step 1: Record the public behavior as an OpenSpec change

Create slug `press-key-chromium-lane` with `proposal.md`, `tasks.md`, and `specs/press-key/spec.md`. Specify SHALL requirements for: exact target-bound delete/backspace; unambiguous Return/Enter press; guarded foreground fallback; restoration telemetry; destructive-key confirmation; and “after any possible mutation, no second transport.” Include scenarios for selected deletion, backward/forward composed-character deletion, ambiguous submit controls, user foreground change, failed restoration, and AX write accepted without settled proof. The final task must say: run `swift test`; run strict OpenSpec validation if installed; run live smoke only with operator authorization.

**Verify**: `if command -v openspec >/dev/null; then openspec validate press-key-chromium-lane --strict; else echo 'openspec unavailable: validation skipped and must be noted'; fi` → strict validation exits 0, or the explicit skip line prints.

### Step 2: Add a pure semantic planner before changing dispatch

Create `PressKeySemanticPlanner.swift` with value-only inputs and outputs. Keep AX objects out of the planner. Use this target shape:

```swift
enum PressKeyReturnCandidateKind: Equatable, Sendable {
    case focusedSingleLineField
    case defaultButton
    case explicitFormSubmit
}

struct PressKeyReturnCandidate: Equatable, Sendable {
    let id: String
    let kind: PressKeyReturnCandidateKind
}

struct PressKeySemanticTargetState: Equatable, Sendable {
    let value: String?
    let selection: TypeTextSelectionRangeDTO?
    let isSingleLine: Bool
    let supportsTextOperation: Bool
    let supportsSelectedMarkerRange: Bool
    let valueSettable: Bool
    let returnCandidates: [PressKeyReturnCandidate]
}

enum PressKeySemanticPlan: Equatable, Sendable {
    case selectAll(expected: TypeTextSelectionRangeDTO)
    case replace(range: NSRange, expectedValue: String, expectedSelection: TypeTextSelectionRangeDTO)
    case press(PressKeyReturnCandidate)
    case guardedForeground(reason: String)
    case noEffect(reason: String)
}
enum PressKeySemanticPlanner {
    static func plan(
        parsed: ParsedPressKeyChord,
        target: PressKeySemanticTargetState?,
        rendererBacked: Bool
    ) -> PressKeySemanticPlan
}
```

For a nonempty selection, both delete keys replace that range with `""`. With a caret, Backspace deletes the previous composed character and Delete deletes the next composed character; compute the `NSRange` with `NSString.rangeOfComposedCharacterSequence(at:)` so surrogate pairs are never split. At start/end boundaries return `.noEffect`, not a foreground key. If exact value/range input is unavailable or neither a complete text-operation capability nor `valueSettable` is present, choose `.guardedForeground` before any AX write. Command-A returns the full UTF-16 range. Return/Enter may return `.press` only when exactly one candidate exists and it is either the focused single-line field itself exposing AXPress, the window’s AXDefaultButton, or one AXButton with AXPress explicitly linked from that focused field through `kAXLinkedUIElementsAttribute`. Zero or multiple candidates use `.guardedForeground`; never infer submit from free-form button labels.

Write `PressKeySemanticPlannerTests.swift` in Swift Testing style. Cover selected Backspace/Delete, caret Backspace, forward Delete, emoji composed characters, both boundaries, Command-A, unique default button, ambiguous two-button submission, multiline Return, and a raw renderer key.

**Verify**: `swift test --filter PressKeySemanticPlannerTests` → tests compile and pass without Accessibility permission or a live app.

### Step 3: Dispatch the semantic plans with one-mutation safety

In `PressKeyRouteService`, gather the focused/unambiguous text target and live text state once. Build `(PressKeyReturnCandidate, AXUIElement)` pairs from only three exact relationships in the requested window: `kAXDefaultButtonAttribute`; AXPress on the focused single-line field itself; and `kAXLinkedUIElementsAttribute` from that field filtered to `kAXButtonRole` plus AXPress. Give only value descriptors to the planner and retain a request-local `[String: AXUIElement]` map for dispatch. Reject candidates outside the requested pid/window and require `.only` before AXPress. Do not classify candidates by title text.

Implement the plan cases:

```swift
switch plan {
case let .replace(range, expectedValue, expectedSelection):
    // Prepare the exact range, then attempt one mutation transport.
case let .selectAll(expected):
    // Keep the current selected-range semantic lane.
case let .press(candidate):
    // Resolve candidate.id in the request-local map and AXPress that exact element.
case let .guardedForeground(reason):
    // Use ForegroundFallbackCoordinator, dispatch once, then restore/verify.
case let .noEffect(reason):
    // Return effect_not_verified with no transport attempt.
}
```

For replacement, choose the transport before touching selection. If parameterized `AXTextOperation` and selected-marker support are advertised, set the selected range, poll until the exact range is visible, read its marker, and perform the one paired text operation. If marker/range proof disappears after selection preparation, fail closed; do not switch to AXValue. If the parameterized capability is absent before preparation, choose one `AXValue` replacement plus expected caret write instead. Treat range preparation plus its paired text operation as one planned semantic lane, then poll the same element with `AdaptiveTextSettle` timing. Once either text mutation call is made, never post a key or use the alternative text transport. A divergent or unreadable value after an accepted call is `verifier_ambiguous`; unchanged after the bounded settle is `effect_not_verified`; neither permits a second transport.

Normalize `enter` to `return` in `PressKeyParser` and update the existing parser test. Move the destructive-key gate after successful parsing and evaluate `parsed.dto.normalized`, not `request.key`; add `meta+delete`, `cmd+backspace`, and `super+delete` confirmation-policy tests. Parsing failure still returns unsupported before any dispatch.

Create `PressKeyDispatchCoordinator.swift` and make `PressKeyRouteService` enter transports only through it:

```swift
enum PressKeySemanticAttemptDisposition: Equatable, Sendable {
    case notAttempted
    case attempted
    case possiblyMutated
}

enum PressKeyDispatchCoordinator {
    static func execute(
        plan: PressKeySemanticPlan,
        performSemantic: (PressKeySemanticPlan) -> PressKeySemanticAttemptDisposition,
        performForeground: () -> PressKeySemanticAttemptDisposition
    ) -> PressKeySemanticAttemptDisposition
}

struct PressKeyForegroundDispatchResult: Equatable, Sendable {
    let dispatchAttempted: Bool
    let dispatchSucceeded: Bool
    let restoreAttempted: Bool
    let foregroundRestored: Bool
}

enum PressKeyForegroundDispatch {
    static func execute(
        prepare: () -> ForegroundPreparationMode,
        targetIsFrontmost: () -> Bool,
        postKeySequence: () -> Bool,
        restore: () -> Bool
    ) -> PressKeyForegroundDispatchResult
}
```

For `.selectAll`, `.replace`, and `.press`, call `performSemantic` exactly once and never call `performForeground`, regardless of returned disposition. For `.guardedForeground`, call only `performForeground` once; that closure must delegate to `PressKeyForegroundDispatch.execute`. The foreground state machine posts exactly once only after `.foregroundFallback` preparation and a same-target frontmost check, then attempts restore exactly once after any post attempt. `.background`, `.blockedByUserChange`, or a failed frontmost check post nothing. For `.noEffect`, call neither lane. Create `PressKeyDispatchCoordinatorTests.swift` with counters for every plan/result and foreground preparation branch; assert semantic/foreground/post/restore counts and returned telemetry, including `.possiblyMutated`, post failure, and restore failure.

**Verify**: `swift test --filter PressKeyParserTests && swift test --filter PressKeySemanticPlannerTests && swift test --filter PressKeyDispatchCoordinatorTests` → parser/planner pass and every semantic plan proves the one-lane invariant.

### Step 4: Replace unsafe pid-only fallback with the guarded foreground protocol

Capture `ForegroundApplicationSnapshot` before action preparation. For any `.guardedForeground` plan, call `ForegroundFallbackCoordinator.prepare(original:targetPID:backgroundPrepared:false)`. Dispatch no event unless preparation reports foreground fallback and the target pid is still frontmost immediately before `postKeySequence`. Post exactly one key sequence, reread for route-specific evidence, and call `restore` once. Honor Plan 007’s outcome rule: a failed required restoration cannot report success, and a third-app user switch is never overridden.
Delete the unconditional raw-key path that reaches `attemptNativeKeyDelivery` after semantic failure. Route all semantic/foreground selection through `PressKeyDispatchCoordinator`; a semantic operation that returns `.attempted` or `.possiblyMutated` must return immediately and can never reach foreground delivery. Keep strategy order visible in a trace, for example `ax_selected_text_range`, `ax_text_operation`, `ax_value`, `ax_press`, `foreground_cgevent`.

**Verify**: `swift test --filter ForegroundFallbackCoordinatorTests && swift test --filter PressKeyDispatchCoordinatorTests` → preparation safety passes; injected counters prove one selected lane, at most one key sequence, and exactly one restore attempt after posting.

### Step 5: Align the PressKey response and route catalog

Add these required fields to `PressKeyResponse` using the exact TypeText names and types:

```swift
public let strategiesAttempted: [String]
public let fallbackReason: String?
public let foregroundFallbackUsed: Bool
public let foregroundRestored: Bool
```

Extend `HardenedAgentAPITests.PressKeyVerificationTests` to encode a response/evidence fixture and assert all four fields and exact names while retaining the existing `effectClassification` assertions. Extend `APIDocumentationTests` to require the documented fields.

**Verify**: `swift test --filter PressKeyVerificationTests && swift test --filter APIDocumentationTests` → encoded DTO and `/v1/routes` both expose the four aligned fields.

### Step 6: Run the full non-live gate and update the index

Run the complete suite once. Do not run `script/start.sh`, `ensure-runtime.sh`, or `script/smoke_runtime.py`. Inspect `git status --short`, confirm only Scope files changed, and set plan 009 to `DONE` in `plans/README.md`.

**Verify**: `swift test && git status --short` → all tests pass; status lists only in-scope implementation/spec/test files plus pre-existing baseline changes.

## Test plan

- `PressKeySemanticPlannerTests`: every pure case named in Step 2, including UTF-16 composed-character boundaries and ambiguous submit controls.
- `PressKeyParserTests`: Enter alias, existing Backspace aliases, Command-F/Command-A intents, and existing native-effect evidence rules.
- `ForegroundFallbackCoordinatorTests`: run the existing user-switch, activation, timeout, and restoration cases unchanged; PressKey-specific selection is covered by the pure planner suite.
- `APIDocumentationTests`: exact `/v1/routes` request/response fields and retry guidance.
- `PressKeyDispatchCoordinatorTests`: injected semantic/foreground counters for every plan and result, proving no semantic attempt reaches a second transport and guarded foreground posts once.
- `PressKeyVerificationTests`/`HardenedAgentAPITests`: transport/effect classification and the four response telemetry fields.
- Final verification: `swift test` → complete suite passes.

## Done criteria

- [ ] Delete/Backspace edit exactly one selected range or composed character and settle against an exact expected value.
- [ ] Return/Enter AXPress occurs only for one unambiguous single-line/default/form-submit candidate.
- [ ] No code dispatches a second transport after AXTextOperation, AXValue, AXPress, or CGEvent may have mutated state.
- [ ] Injected coordinator tests prove every route plan selects zero or one mutation lane.
- [ ] Raw/no-safe-semantic keys use guarded foreground preparation and verified restoration, never the old unconditional pid-only lane.
- [ ] Command-Delete and Command-Backspace still require `confirm=true`.
- [ ] `PressKeyResponse` and `/v1/routes` expose all four aligned telemetry fields.
- [ ] `openspec validate press-key-chromium-lane --strict` passes when available.
- [ ] `swift test` exits 0.
- [ ] No out-of-scope files are newly modified; plan 009 index row is `DONE`.

## STOP conditions

Stop and report back (do not improvise) if:

- Current-state excerpts no longer match the live code.
- Plan 007 is not complete or foreground restoration can still report success while `foregroundRestored` is false.
- If an operator-authorized Chromium probe shows `AXTextOperation` or `AXSelectedTextMarkerRange` is unavailable, STOP before implementing that branch and report the capability result. Resume only with the already-specified single AXValue replacement plus `AdaptiveTextSettle` and exact verification; never substitute a native key retry.
- A safe Return implementation would require guessing among multiple buttons, traversing outside the requested window, or posting text into a multiline field.
- Any implementation path would post a fallback after an AX call may already have mutated text.
- A focused verification fails twice after one reasonable correction.

## Maintenance notes

- Reviewers should trace every planner result to exactly zero or one mutation transport and verify the no-second-transport invariant.
- Keep strategy strings stable after publication; they are agent-facing contract data.
- Renderer behavior is OS/app-version sensitive. A future live characterization may add a proven semantic key, but must add planner cases and evidence before widening the lane.
- Live Electron verification is intentionally deferred until an operator authorizes launching the signed app and test target.
