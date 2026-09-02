# Plan 010: Reject stale state tokens before positional mutations

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**: `git diff --stat 0110ffb..HEAD -- Sources/BackgroundComputerUse/Actions/Shared/AXActionTargetResolver.swift Sources/BackgroundComputerUse/Actions/Click/ClickRouteService.swift Sources/BackgroundComputerUse/Actions/Scroll/ScrollRouteService.swift Sources/BackgroundComputerUse/Actions/SecondaryAction/SecondaryActionRouteService.swift Sources/BackgroundComputerUse/Actions/Paste/PasteRouteService.swift Sources/BackgroundComputerUse/Actions/TypeText/TypeTextRouteService.swift Sources/BackgroundComputerUse/Actions/SetValue/SetValueRouteService.swift Sources/BackgroundComputerUse/Actions/Text/TextRouteService.swift Sources/BackgroundComputerUse/Actions/PressKey/PressKeyRouteService.swift Sources/BackgroundComputerUse/API/Router.swift Sources/BackgroundComputerUse/API/RouteRegistry.swift Sources/BackgroundComputerUse/API/APIDocumentation.swift Tests/BackgroundComputerUseTests/StaleStateTokenTests.swift Tests/BackgroundComputerUseTests/AgentAPICorrectnessTests.swift Tests/BackgroundComputerUseTests/APIDocumentationTests.swift openspec/changes/stale-state-token-fails-closed plans/README.md`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.
>
> Also run `git status --short` and `git diff --name-only 0110ffb..HEAD`. The union must show the baseline fixes in `API/Router.swift`, `App/BackgroundComputerUseControlBridge.swift`, `BackgroundComputerUseControlShared/CodeSignatureIdentity.swift`, `Runtime/RuntimeExecutionQueue.swift`, `Actions/TypeText/AdaptiveTextDispatcher.swift`, `StatePipeline/InteractionToken.swift`, `Runtime/Process/BoundedProcessRunner.swift`, `skills/background-computer-use/scripts/bcu-request.py`, `InteractionTokenTests.swift`, and `RuntimeExecutionQueueTests.swift`. STOP if any is neither committed after `0110ffb` nor present as a working-tree change.

## Status

- **Priority**: P1
- **Effort**: M
- **Risk**: MED
- **Depends on**: none
- **Category**: bug
- **Planned at**: commit `0110ffb`, 2026-09-02

## Why this matters

A caller can send a `display_index` from an inspected tree together with that tree’s `stateToken`, but the runtime currently warns on mismatch and resolves the index against a newer capture anyway. When tree lines move, a mutating route can act on a different node. This plan turns the advertised snapshot token into an actual optimistic-concurrency gate for `display_index`, while deliberately preserving current behavior for omitted tokens, targetless actions, `node_id`, and content-derived `refetch_fingerprint` targets.

## Current state

- `Sources/BackgroundComputerUse/Actions/Shared/AXActionTargetResolver.swift:187-198` converts every nonempty mismatch into a warning:
  ```swift
  guard suppliedStateToken != liveStateToken else { return [] }
  return [
      "Supplied stateToken did not match the live pre-action recapture; targeting continued against the current AXPipelineV2 state.",
  ]
  ```
- `AXActionTargetResolver.swift:219-235` then resolves the requested target against the new capture. `display_index` reads the new line mapping; `node_id` and `refetch_fingerprint` each require exactly one matching node.
- `AXRawCaptureService.swift:903-915` builds `refetchFingerprint` from role, subrole, role description, title, description, placeholder, help, identifier, and URL host. It is designed for content-derived matching across captures, so a stale token remains warning-only for this kind.
- `AXRawCaptureService.swift:943-953` constructs `nodeID` from the current traversal path (`"n:" + path`). Despite that positional implementation detail, this plan intentionally follows the required compatibility rule: stale `node_id` proceeds with the warning. Do not widen the breaking change beyond `display_index`.
- Confirmed mutating `stateTokenWarnings` call sites, all before target resolution/dispatch:
  - click — `ClickRouteService.swift:246-249` (`request.target` is optional; x/y and OCR are possible)
  - scroll — `ScrollRouteService.swift:99-102`
  - paste — `PasteRouteService.swift:36-39`
  - type_text — `TypeTextRouteService.swift:39-42` (target is optional)
  - set_value — `SetValueRouteService.swift:21-24`
  - perform_secondary_action — `SecondaryActionRouteService.swift:57-60`
  - select_text — `TextRouteService.swift:51-54`
  - press_key — `PressKeyRouteService.swift:24-31` (no semantic target; retain warning/note)
- OCR anchors are out of this state-token rule: `APIDocumentation.swift:29-31` documents their separate `interactionToken` identity/geometry guard. Do not duplicate that policy.
- `Router.swift:498-525` sends non-decoding errors to `errorResponse`; `Router.swift:822-973` has no stale-target case, so a new resolver error would currently become HTTP 500 `internal_error`.
- `APIDocumentation.swift:24-26` says `stateToken` lets stale-target checks “compare” state, but does not promise rejection or recovery. Lines 44-48 incorrectly call `node_id` stable; update this wording while preserving the required warning-only behavior.
- `RouteRegistry.swift:87-95` declares `/v1/routes` the machine-readable contract. Its seven target-bearing mutation schemas currently describe `stateToken` as an unqualified optional string.
- No existing route test constructs a stale state-token mutation. `AgentAPICorrectnessTests.swift:157-182` is the existing direct Router error-mapping pattern, and `APIDocumentationTests.swift:23-42` inspects published route errors.
- Repository rule from `openspec/project.md:14-15`: validate `stateToken` before `resolveTarget`, and keep RouteRegistry/APIDocumentation synchronized with the public DTO/error contract.

## Commands you will need

| Purpose | Command | Expected on success |
|---|---|---|
| Guard and route matrix | `swift test --filter StaleStateTokenTests` | exit 0; every route case passes |
| Router mapping | `swift test --filter RuntimeCorrectnessTests` | exit 0; stale error maps to 409 |
| API documentation | `swift test --filter APIDocumentationTests` | exit 0; exact routes publish stale error |
| Existing OCR freshness | `swift test --filter WebReliabilityTests` | exit 0; OCR interaction-token guard remains green |
| OpenSpec | `openspec validate stale-state-token-fails-closed --strict` | exit 0 when CLI exists |
| Final suite | `swift test` | exit 0; complete suite passes |

## Scope

**In scope** (the only files you should modify):
- `Sources/BackgroundComputerUse/Actions/Shared/AXActionTargetResolver.swift`
- `Sources/BackgroundComputerUse/Actions/Click/ClickRouteService.swift`
- `Sources/BackgroundComputerUse/Actions/Scroll/ScrollRouteService.swift`
- `Sources/BackgroundComputerUse/Actions/SecondaryAction/SecondaryActionRouteService.swift`
- `Sources/BackgroundComputerUse/Actions/Paste/PasteRouteService.swift`
- `Sources/BackgroundComputerUse/Actions/TypeText/TypeTextRouteService.swift`
- `Sources/BackgroundComputerUse/Actions/SetValue/SetValueRouteService.swift`
- `Sources/BackgroundComputerUse/Actions/Text/TextRouteService.swift`
- `Sources/BackgroundComputerUse/Actions/PressKey/PressKeyRouteService.swift`
- `Sources/BackgroundComputerUse/API/Router.swift`
- `Sources/BackgroundComputerUse/API/RouteRegistry.swift`
- `Sources/BackgroundComputerUse/API/APIDocumentation.swift`
- `Tests/BackgroundComputerUseTests/StaleStateTokenTests.swift` (create)
- `Tests/BackgroundComputerUseTests/AgentAPICorrectnessTests.swift`
- `Tests/BackgroundComputerUseTests/APIDocumentationTests.swift`
- `openspec/changes/stale-state-token-fails-closed/proposal.md` (create)
- `openspec/changes/stale-state-token-fails-closed/tasks.md` (create)
- `openspec/changes/stale-state-token-fails-closed/specs/action-targeting/spec.md` (create)
- `plans/README.md` (status row only)

**Out of scope** (do NOT touch, even though related):
- Reclassifying stale `node_id` as an error; the requested behavior is warning-only.
- Changing refetch fingerprint generation or uniqueness semantics.
- OCR anchor freshness, which remains governed by `interactionToken`.
- Making `stateToken` mandatory. Omission/blank input remains accepted.
- Any action dispatch, effect verification, or fallback ladder beyond inserting the pre-dispatch gate.

## Git workflow

- Branch: `advisor/010-stale-state-token-fails-closed`
- Commit logical units with observed style, e.g. `fix: reject stale positional action targets` and `docs: document stale state recovery`.
- Do not push or open a PR unless the operator explicitly instructs it.

## Steps

### Step 1: Specify the stale-target contract

Create OpenSpec slug `stale-state-token-fails-closed`. The delta must say: a supplied nonblank mismatching token plus `target.kind=display_index` SHALL produce HTTP 409 `stale_state_token` before resolution or mutation; equal/omitted tokens are unchanged; mismatching `node_id` and `refetch_fingerprint` retain a warning; targetless press_key/type_text and coordinate click remain warning-only; OCR remains under interactionToken. Include a recovery scenario requiring a fresh get_window_state and fresh display index.

**Verify**: `if command -v openspec >/dev/null; then openspec validate stale-state-token-fails-closed --strict; else echo 'openspec unavailable: validation skipped and must be noted'; fi` → strict validation exits 0, or the explicit skip line prints.

### Step 2: Replace the warning helper with a typed validation gate

Extend `AXActionTargetResolverError` without including either opaque token value:

```swift
enum AXActionTargetResolverError: Error, CustomStringConvertible, Equatable, Sendable {
    case unresolvedTarget(String)
    case staleStateToken(targetKind: ActionTargetKindDTO)
}
```

Extend `description` with a constant stale-token sentence naming only `targetKind.rawValue`; never interpolate supplied/live token values.

Replace `stateTokenWarnings` with `validateStateToken`. Use a small internal request protocol so each route passes its real request and cannot accidentally omit its target:

```swift
protocol ActionStateTokenRequest {
    var stateToken: String? { get }
    var stateTokenTarget: ActionTargetRequestDTO? { get }
}

func validateStateToken(
    for request: any ActionStateTokenRequest,
    liveStateToken: String
) throws -> [String] {
    guard let supplied = request.stateToken?.trimmingCharacters(in: .whitespacesAndNewlines),
          supplied.isEmpty == false,
          supplied != liveStateToken else { return [] }
    if request.stateTokenTarget?.kind == .displayIndex {
        throw AXActionTargetResolverError.staleStateToken(targetKind: .displayIndex)
    }
    return ["Supplied stateToken did not match the live pre-action recapture; targeting continued only because the target is not display_index."]
}
```

Add internal conformances/computed `stateTokenTarget` for Click, Scroll, PerformSecondaryAction, Paste, TypeText, SetValue, SelectText, and PressKey requests. PressKey returns nil; optional-target TypeText/Click forward their optional target. Do not place this Actions-layer policy in Contracts, which is the leaf layer. Create `StaleStateTokenTests.swift` now with direct guard cases for missing, blank, equal, stale display-index, stale node/refetch, and targetless requests; Step 6 extends the same suite with the complete route matrix.

**Verify**: `swift test --filter StaleStateTokenTests` → initial guard tests compile; missing/equal/refetch/node/targetless cases pass and stale display-index cases throw.

### Step 3: Make validation the executable boundary around every post-capture action

Add this internal orchestration seam beside the resolver:

```swift
enum ActionStateTokenPreflight {
    static func execute<Output>(
        resolver: AXActionTargetResolver,
        request: any ActionStateTokenRequest,
        liveStateToken: String,
        afterValidation: ([String]) throws -> Output
    ) throws -> Output {
        let warnings = try resolver.validateStateToken(
            for: request,
            liveStateToken: liveStateToken
        )
        return try afterValidation(warnings)
    }
}
```

Give `AXActionTargetResolver` an internal `captureOverride` closure (default nil); `capture(...)` must return its fixture before touching WindowServer/AX when present. Give each affected service initializer an internal `targetResolver: AXActionTargetResolver? = nil` parameter and store `targetResolver ?? AXActionTargetResolver(executionOptions: executionOptions)`. Production call sites remain unchanged. This is the only test seam; do not inject mutation transports or add global hooks.

At each confirmed call site, enter `ActionStateTokenPreflight.execute` immediately after capture and move the entire remaining target resolution, safety, cursor preparation, dispatch, and response construction into `afterValidation`. The closure may append warnings, but no resolver or mutation call may remain before it. This gives tests an injected mutation callback whose call count proves stale input stops the route, rather than merely proving the helper throws. PressKey appends its existing mismatch note inside the closure; coordinate Click, nil-target TypeText, OCR, node, and refetch paths enter the closure normally. Delete `stateTokenWarnings` after all callers migrate; do not retain an alias.

**Verify**: `swift test --filter StaleStateTokenTests` → the seven concrete request types throw before their injected post-validation callbacks; warning-only cases call the callback exactly once.

### Step 4: Add HTTP 409 mapping with safe recovery text

In `Router.errorResponse`, add a typed case before the default:

```swift
case AXActionTargetResolverError.staleStateToken:
    .json(
        ErrorResponse(
            error: "stale_state_token",
            message: "The supplied stateToken no longer matches the live pre-action state, so display_index cannot be resolved safely.",
            requestID: requestID,
            recovery: [
                "Call POST /v1/get_window_state for the same window.",
                "Choose a target from that new response and retry with its stateToken.",
                "Do not reuse the stale display_index.",
            ]
        ),
        statusCode: 409,
        reasonPhrase: "Conflict"
    )
```

Do not echo supplied/live tokens. Extend `RuntimeCorrectnessTests` in `AgentAPICorrectnessTests.swift` using its direct `Router(auth: .disabled).errorResponse(...)` pattern; assert status 409, exact error code, preserved requestID, and recovery containing both fresh state and no-reuse instructions.

**Verify**: `swift test --filter RuntimeCorrectnessTests` → stale mapping test passes and existing screenshot/internal error mappings remain green.

### Step 5: Publish the precise contract through `/v1/routes`

Update the `stateToken` concept to say nonblank mismatch rejects `display_index` before mutation and recovery is a fresh read. Update target concept text: `display_index` is tied to one rendered tree; `node_id` is accepted across recapture with a warning for compatibility, not promised stable; `refetch_fingerprint` is content-derived and uniquely resolved in the current capture.

In each target-bearing mutation request schema (click, scroll, perform_secondary_action, type_text, paste, set_value, select_text), describe the 409 rule on `stateToken`/target. Keep PressKey’s field description warning-only. In `APIDocumentation.errors(for:)`, append this route error only for those seven routes:

```swift
RouteErrorDTO(
    statusCode: 409,
    error: "stale_state_token",
    meaning: "A nonblank stateToken did not match the live capture and display_index cannot be rebound safely.",
    recovery: ["Read the window again and use the new stateToken and target."]
)
```

Extend `APIDocumentationTests` with an exact set assertion: the seven routes contain `stale_state_token`; press_key, read_text, get_window_state, and find_elements do not.

**Verify**: `swift test --filter APIDocumentationTests` → route catalog publishes the exact 409 matrix and corrected concept text.

### Step 6: Add real request coverage for every affected route

Create `StaleStateTokenTests.swift` with Swift Testing. Decode concrete route DTOs from these minimal bodies so strict wire decoding and target extraction are both exercised:

```swift
func decode<T: Decodable>(_ type: T.Type, _ body: String) throws -> T {
    try JSONSupport.decoder.decode(type, from: Data(body.utf8))
}

let cases: [(RouteID, () throws -> any ActionStateTokenRequest)] = [
    (.click, { try decode(ClickRequest.self, #"{"window":"w","stateToken":"old","target":{"kind":"display_index","value":7}}"#) }),
    (.scroll, { try decode(ScrollRequest.self, #"{"window":"w","stateToken":"old","target":{"kind":"display_index","value":7},"direction":"down"}"#) }),
    (.performSecondaryAction, { try decode(PerformSecondaryActionRequest.self, #"{"window":"w","stateToken":"old","target":{"kind":"display_index","value":7},"action":"Show menu"}"#) }),
    (.typeText, { try decode(TypeTextRequest.self, #"{"window":"w","stateToken":"old","target":{"kind":"display_index","value":7},"text":"x"}"#) }),
    (.paste, { try decode(PasteRequest.self, #"{"window":"w","stateToken":"old","target":{"kind":"display_index","value":7},"content":"x","format":"text"}"#) }),
    (.setValue, { try decode(SetValueRequest.self, #"{"window":"w","stateToken":"old","target":{"kind":"display_index","value":7},"value":"x"}"#) }),
    (.selectText, { try decode(SelectTextRequest.self, #"{"window":"w","stateToken":"old","target":{"kind":"display_index","value":7},"text":"x"}"#) }),
]
```

First test the shared seam with decoded requests and an `afterValidation` counter: stale display-index throws with counter zero; node/refetch/targetless/equal/omitted/blank cases call it once with expected warnings. Then execute each of the seven actual service methods using its injected resolver and a deliberately empty capture fixture whose live token is `"new"` (copy the safe `AXUIElementCreateSystemWide`/`ResolvedWindowTarget` construction pattern from `WindowStatePayloadParityTests.swift:496-634`). With stale `"old"` plus display-index, each service must throw `staleStateToken(.displayIndex)`; if target resolution runs first, the empty fixture returns an ordinary unresolved-target response and the test fails. This proves placement in the real callsite without source-text scanning, WindowServer, or mutation.

**Verify**: `swift test --filter StaleStateTokenTests && swift test --filter WebReliabilityTests` → all seven route requests reject stale indices and OCR’s existing interaction-token behavior is unchanged.

### Step 7: Run the final gate and update the index

Run the full suite once. Inspect `git status --short`, confirm only Scope files changed, and set plan 010 to `DONE` in `plans/README.md`. Do not run live smoke; no running app is needed for this pre-dispatch policy.

**Verify**: `swift test && git status --short` → full suite passes; only in-scope files plus pre-existing baseline changes are listed.

## Test plan

- `StaleStateTokenTests`: shared-callback matrix plus all seven actual service methods with an injected empty capture; stale display-index must throw before that empty capture can produce an unresolved-target response, while warning-only cases enter the continuation once.
- `RuntimeCorrectnessTests`: typed resolver error maps to HTTP 409 with safe requestID/recovery and no token values.
- `APIDocumentationTests`: exact route error matrix and stateToken/target concept wording.
- `WebReliabilityTests`: existing stale OCR interaction-token rejection remains unchanged.
- Full verification: `swift test` → complete suite passes.

## Done criteria

- [ ] Every nonblank mismatching `display_index` request fails at the shared route preflight before the injected target-resolution/mutation continuation.
- [ ] HTTP response is 409 `stale_state_token` with fresh-read recovery and no opaque token values.
- [ ] All seven target-bearing mutation route requests are covered by concrete DTO tests.
- [ ] Omitted/blank/equal tokens are unchanged.
- [ ] Stale `node_id` and `refetch_fingerprint` continue with a warning; PressKey remains targetless warning-only.
- [ ] OCR anchor interaction-token behavior is unchanged.
- [ ] `/v1/routes` documents the exact rule and route error matrix.
- [ ] OpenSpec strict validation passes when available; `swift test` exits 0.
- [ ] No out-of-scope files are newly modified; plan 010 index row is `DONE`.

## STOP conditions

Stop and report back (do not improvise) if:

- Current-state excerpts no longer match the live code.
- Validation cannot run after capture but before every resolution/safety/dispatch path.
- A proposed helper would make `stateToken` mandatory or reject `node_id`, `refetch_fingerprint`, OCR, coordinates, or targetless actions.
- A 409 response would include either opaque token value.
- Any affected service cannot be covered by a concrete decoded request at the shared guard seam.
- A focused verification fails twice after one reasonable correction.

## Maintenance notes

- The warning-only `node_id` decision is deliberate compatibility scope, even though current IDs are traversal-path-derived. Revisit only through a separate contract change.
- Any future target kind must explicitly choose between matching-state enforcement, independent freshness protection, or warning-only behavior.
- Reviewers should verify guard placement, not just the helper: it must precede every possible mutation.
- Keep the error code/recovery stable because agents use `/v1/routes` programmatically.
