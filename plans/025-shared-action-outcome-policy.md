# Plan 025: Enforce one verifier-first outcome policy across actions

> **Executor instructions**: Follow this plan step by step. Run every verification command and confirm the expected result before moving to the next step. If a STOP condition occurs, stop and report; do not improvise. When done, update this plan's row in `plans/README.md` unless a reviewer owns the index.
>
> **Drift check (run first)**: `git diff --stat 0110ffb..HEAD -- Sources/BackgroundComputerUse/Actions Sources/BackgroundComputerUse/Contracts Sources/BackgroundComputerUse/API Tests/BackgroundComputerUseTests openspec/changes`
> Plan 007 must already be complete. Compare its foreground-restoration changes and every excerpt below with live code; expected plan-007 drift is acceptable, any unexplained mismatch is a STOP condition.
>
> **Required baseline check**: Run `git status --short`. The planning baseline includes fixes in `API/Router.swift`, `App/BackgroundComputerUseControlBridge.swift`, `BackgroundComputerUseControlShared/CodeSignatureIdentity.swift`, `Runtime/RuntimeExecutionQueue.swift`, `Actions/TypeText/AdaptiveTextDispatcher.swift`, `StatePipeline/InteractionToken.swift`, `Runtime/Process/BoundedProcessRunner.swift`, `skills/background-computer-use/scripts/bcu-request.py`, `InteractionTokenTests.swift`, and `RuntimeExecutionQueueTests.swift`. Each must be committed or still modified; STOP if operator work was reverted or lost.

## Status

- **Priority**: P2
- **Effort**: M
- **Risk**: MED
- **Depends on**: `plans/007-type-text-outcome-honesty.md`
- **Category**: tech-debt
- **Planned at**: commit `0110ffb`, 2026-09-02

## Why this matters

`ActionClassificationDTO` is shared, but each route independently decides what evidence earns `success`. Secondary action currently reports success when AX merely accepts dispatch and no verifier exists, directly violating the product rule that transport dispatch is never proof of effect. A small pure policy will make the success and foreground-safety invariants executable, while route services remain responsible for gathering evidence and wording route-specific summaries.

## Current state

- The common public vocabulary has four states and common failure domains:

```swift
// Contracts/TextActionContracts.swift:3-17
public enum ActionClassificationDTO: String, Encodable, Sendable {
    case success
    case unsupported
    case effectNotVerified = "effect_not_verified"
    case verifierAmbiguous = "verifier_ambiguous"
}
public enum ActionFailureDomainDTO: String, Encodable, Sendable {
    case targeting
    case unsupported
    case coercion
    case transport
    case verification
    case backgroundSafety = "background_safety"
    case appSpecificSemantics = "app_specific_semantics"
}
```

- `TypeTextOutcomePolicy` is route-local and currently ignores the foreground argument:

```swift
// Actions/TypeText/TypeTextOutcomePolicy.swift:36-55
static func classifySemanticDispatch(
    exactValueMatch: Bool,
    exactSelectionMatch: Bool?,
    targetRelocated: Bool,
    postStateTokenAvailable: Bool,
    foregroundPreserved _: Bool
) -> TypeTextOutcomeDecision {
    if exactValueMatch {
        // lines 44-51 omitted
        return TypeTextOutcomeDecision(
            classification: .success,
            failureDomain: nil,
            summary: "The targeted text dispatch matched the expected inserted value after reread."
        )
```

  The pre-plan-007 test `BackgroundTextSafetyTests.swift:47-58` even expects exact verification to win after foreground fallback. Plan 007 must reverse that assumption before this plan starts.

- Secondary action has the concrete policy bug:

```swift
// Actions/SecondaryAction/SecondaryActionRouteService.swift:389-424
if verification.observedEffect {
    // lines 390-392 omitted
    return response(
        classification: .success,
        failureDomain: nil,
        summary: "The secondary action '\(requestedAction.label)' produced the expected post-state effect.",
        // remaining response arguments omitted
    )
}
if axResult == .success {
    return response(
        classification: .success,
        failureDomain: nil,
        summary: "The secondary action '\(requestedAction.label)' was accepted by AX. No stronger effect-specific verifier was available.",
        // remaining response arguments omitted
    )
```

```swift
// SecondaryActionRouteService.swift:447-451
if axResult == .attributeUnsupported || axResult == .actionUnsupported {
    return response(
        classification: .effectNotVerified,
        failureDomain: .transport,
        summary: "The action was attempted with AX action '\(binding.rawName)', AX returned \(transport.rawAXStatus), and no verified effect was observed. Review the returned post-state or request a screenshot to inspect the visible UI state.",
```

  Its public outcome already has honest diagnostic values `accepted_without_verifier` and `ax_accepted_no_verifier` (`Contracts/SecondaryActionContracts.swift:34-53`); those remain, while top-level classification changes to `effect_not_verified` and `ok=false`.

- Set-value derives the same decision separately:

```swift
// Actions/SetValue/SetValueRouteService.swift:418-466
if verification.exactValueMatch {
    return response(
        classification: .success,
        failureDomain: nil,
        summary: "The direct AX value write matched the requested value after reread.",
        // remaining response arguments omitted
    )
}
// lines 440-461 omitted
if verification.targetRelocated == false || postStateToken == nil {
    return response(
        classification: .verifierAmbiguous,
        failureDomain: .verification,
```

- Paste derives foreground, transport, clipboard, and verifier precedence inline (`PasteRouteService.swift:326-350`); click separately maps `verified` to success (`ClickRouteService.swift:1245-1247` and `1744-1747`); press-key separately maps `verifiedEffect` (`PressKeyRouteService.swift:551-558`). Their response builders independently derive `ok`, for example set-value `:523-529`, secondary action `:577-583`, click `:2832-2838`, and type-text `:1151-1155`.

- Press-key is intentionally different: `PressKeyRouteService.swift:660-693` exposes transport-level `ok` and maps top-level classification to `PressKeyEffectClassificationDTO`. `RouteRegistry.swift:1055-1068` documents this. Preserve that public `ok` meaning; centralize only its top-level classification decision.

- Scroll keeps a route-specific enum:

```swift
// Contracts/ScrollActionContracts.swift:3-9
public enum ScrollActionClassificationDTO: String, Encodable, Sendable {
    case success
    case boundary
    case unsupported
    case unresolved
    case verifierAmbiguous = "verifier_ambiguous"
}
```

  Its response currently uses `ok: classification == .success` (`ScrollRouteService.swift:1879-1905`). Keep `boundary` and `unresolved`; use an explicit adapter for common policy decisions rather than changing the public enum.

- `openspec/project.md:13-15` requires read-act-read and verifier-first classification. A background error is reported, never hidden by stealing focus; `GET /v1/routes` is the public contract source of truth.
- Live context to preserve in tests/review: Electron AX value writes may settle asynchronously; Chromium can discard PID-directed background events; `press_key` may correctly return `effect_not_verified` with `opaque_renderer_focus_unconfirmed`; a type-text foreground fallback has been observed with `foregroundRestored: false`. None of those may become success through transport acceptance.

## Commands you will need

| Purpose | Command | Expected on success |
|---|---|---|
| Baseline | `git status --short` | operator work remains intact |
| Policy tests | `swift test --filter ActionOutcomePolicyTests` | selected tests pass |
| Type text | `swift test --filter BackgroundTextSafetyTests` | selected tests pass |
| Click | `swift test --filter VerificationHonestyTests` | selected tests pass |
| Paste | `swift test --filter PasteRouteTests` | selected tests pass |
| Press key | `swift test --filter PressKeyVerificationTests` | selected tests pass |
| API docs | `swift test --filter APIDocumentationTests` | selected tests pass |
| OpenSpec | `which openspec && openspec validate centralize-action-outcome-policy --strict` | passes when CLI exists; otherwise skip and note absence |
| Final | `swift test` | all tests pass |

## Scope

**In scope** (only these files):
- Create `Sources/BackgroundComputerUse/Actions/Shared/ActionOutcomePolicy.swift`.
- `Actions/SecondaryAction/SecondaryActionRouteService.swift`
- `Actions/SetValue/SetValueRouteService.swift`
- `Actions/TypeText/TypeTextOutcomePolicy.swift` and `TypeTextRouteService.swift`
- `Actions/Click/ClickIntentVerifier.swift` and `ClickRouteService.swift`
- `Actions/Paste/PasteRouteService.swift`
- `Actions/PressKey/PressKeyRouteService.swift`
- `Actions/Scroll/ScrollRouteService.swift`
- `API/RouteRegistry.swift` and `APIDocumentation.swift`
- Create `Tests/BackgroundComputerUseTests/ActionOutcomePolicyTests.swift`; update `BackgroundTextSafetyTests.swift`, `VerificationHonestyTests.swift`, `PasteRouteTests.swift`, `HardenedAgentAPITests.swift`, and `APIDocumentationTests.swift` only where their route's observable decision changes.
- Create `openspec/changes/centralize-action-outcome-policy/{proposal.md,tasks.md,specs/action-outcome-honesty/spec.md}`.

**Out of scope**:
- Public classification enums/field names, transport ladders, settle timing, verifier thresholds, target resolution, or cursor behavior.
- Scroll's `boundary`/`unresolved` vocabulary.
- Press-key's documented transport-level `ok` and nested effect classification.
- New route orchestration abstractions; this policy consumes facts only.
- Live smoke or foreground activation.

## Git workflow

- Branch: `advisor/025-shared-action-outcome-policy`.
- Commit the policy/tests first, then one route migration per commit; observed style example: `fix: make BCU foreground fallback retry-safe`.
- Do not push/open a PR without operator instruction; never discard existing changes.

## Steps

### Step 1: Specify the behavior correction

Create the OpenSpec change. It SHALL state: `success` requires a dispatched action plus `proved_effect`; AX/native acceptance alone is `effect_not_verified`; a used foreground fallback that is not restored is never success; no response field is added/removed. Include secondary-action scenarios for verified effect, accepted-without-verifier, and failed transport, plus foreground-restoration scenarios.

**Verify**: `if which openspec >/dev/null 2>&1; then openspec validate centralize-action-outcome-policy --strict; else echo 'SKIP: openspec CLI absent'; fi` → strict validation passes, or the explicit skip line is recorded.

### Step 2: Add the pure policy and exhaustive invariant tests

Create these internal Sendable types (do not put them in Contracts):

```swift
enum ActionVerifierResult: Sendable {
    case unavailable, provedEffect, provedNoEffect, ambiguous
}
struct ActionOutcomeFacts: Sendable {
    let didDispatch: Bool
    let verifier: ActionVerifierResult
    let targetRelocated: Bool?
    let postStateAvailable: Bool
    let foregroundPreserved: Bool?
    let foregroundFallbackUsed: Bool
    let foregroundRestored: Bool?
}
enum ActionOutcomeSummaryKey: String, Sendable {
    case effectVerified, dispatchFailed, verifierUnavailable, effectNotObserved
    case verifierAmbiguous, targetRelocationAmbiguous, postStateUnavailable
    case foregroundNotPreserved, foregroundNotRestored
}
struct ActionOutcomeDecision: Sendable {
    let classification: ActionClassificationDTO
    let failureDomain: ActionFailureDomainDTO?
    let summaryKey: ActionOutcomeSummaryKey
    var ok: Bool { classification == .success }
}
enum ActionOutcomePolicy {
    static func decide(_ facts: ActionOutcomeFacts) -> ActionOutcomeDecision
}
```

Decision precedence: used fallback not restored → `effectNotVerified/backgroundSafety`; measured foreground not preserved → same; not dispatched → `effectNotVerified/transport`; dispatched + proved effect → `success/nil`; ambiguous or missing post-state/relocation without proof → `verifierAmbiguous/verification`; unavailable or proved-no-effect → `effectNotVerified/verification`. A proved effect never overrides a foreground failure. Unsupported preflight remains route-owned because the supplied facts cannot distinguish policy rejection from unsupported capability.

Tests must cover every branch plus a table/cartesian invariant asserting no facts produce success unless `didDispatch`, `.provedEffect`, foreground is not false, and a used fallback has `foregroundRestored == true`.

**Verify**: `swift test --filter ActionOutcomePolicyTests` → all policy cases pass.

### Step 3: Migrate secondary action first and document the fix

Wrap the verifier's DTO with an internal availability/result so generic labels can report `.unavailable` without parsing evidence strings. Feed observed effect as `.provedEffect`, an applicable verifier with no effect as `.provedNoEffect`, missing/unstable reread as `.ambiguous`, and generic no-verifier as `.unavailable`. Keep `accepted_without_verifier`/`ax_accepted_no_verifier`, but use the policy decision: `classification=effect_not_verified`, `failureDomain=verification`, `ok=false`. Map `summaryKey` to existing route-specific wording in one switch.

Update the secondary route note and API guide to say accepted AX dispatch is diagnostic only. Add a pure regression test around the extracted facts/decision adapter; it must not require a live AX element.

**Verify**: `swift test --filter ActionOutcomePolicyTests && swift test --filter APIDocumentationTests && swift test` → regression/docs and the full suite pass before the next route.

### Step 4: Migrate every remaining route, one at a time

Do not batch edits. Complete each numbered migration and its focused existing suite plus full-suite gate before touching the next:

1. **Set-value** — map exact match to proved effect, failed/unsupported AX status to not-dispatched transport failure, absent post state/relocation to ambiguous, and completed mismatch to proved no effect; use `decision.ok`.
   **Verify**: `swift test --filter RuntimeFacadePublicAPITests && swift test --filter APIDocumentationTests && swift test` → public wiring/docs and full suite pass.
2. **Type-text** — after plan 007, replace route-local classification with facts from adaptive attempt, exact value/selection, relocation/token, background safety, and restoration. Keep foreground recovery separate and route summaries keyed by `summaryKey`.
   **Verify**: `swift test --filter BackgroundTextSafetyTests && swift test` → type-text policy and full suite pass.
3. **Click** — keep `ClickIntentVerifier.assess/verified`; feed both semantic and coordinate paths' dispatch, intent evidence, post-capture, relocation, and foreground facts into the policy; use `decision.ok`.
   **Verify**: `swift test --filter VerificationHonestyTests && swift test` → click evidence and full suite pass.
4. **Paste** — map exact value plus clipboard restoration to proved effect, failed transport to not-dispatched, mismatch to proved no effect, missing refreshed target to ambiguous, and existing background-safety evidence to foreground facts.
   **Verify**: `swift test --filter PasteRouteTests && swift test` → paste and full suite pass.
5. **Press-key** — map semantic selection/search/native verification to common facts, but preserve `effectClassification` and transport-level `ok`. Assert dispatched-without-effect is top-level `effect_not_verified` and nested `dispatched_no_observed_effect`.
   **Verify**: `swift test --filter PressKeyVerificationTests && swift test` → press-key and full suite pass.
6. **Scroll** — preserve explicit `.boundary`/preflight `.unresolved`; map policy `.success/.unsupported/.verifierAmbiguous` directly and `.effectNotVerified` to `.verifierAmbiguous` because scroll has no equivalent public value. Test proved movement, ambiguous read, unavailable/no effect, and no dispatch.
   **Verify**: `swift test --filter APIDocumentationTests && swift test --filter ActionOutcomePolicyTests && swift test` → scroll docs/adapter and full suite pass.

### Step 5: Remove duplicate decisions and run the final gate

Search all migrated routes. `classification == .success` may remain only for documented route-specific adapters; duplicated post-dispatch classification ladders must be gone.

**Verify**: `git grep -n 'accepted by AX. No stronger effect-specific verifier' -- Sources || true` → no success wording remains; `swift test` → all tests pass.

## Test plan

- New table-driven `ActionOutcomePolicyTests` covers all precedence and invariant combinations without AX/AppKit runtime state.
- Secondary regression asserts AX accepted + verifier unavailable is not success.
- Existing `BackgroundTextSafetyTests`, `VerificationHonestyTests`, `PasteRouteTests`, and `PressKeyVerificationTests` remain route-specific evidence tests.
- Scroll adapter tests preserve boundary/unresolved and cover all shared outputs.
- No live smoke: this is deterministic classification policy, and launching a signed app is outside scope.

## Done criteria

- [ ] All seven routes derive post-dispatch top-level classification through `ActionOutcomePolicy`.
- [ ] No policy result is success without dispatch + proved effect.
- [ ] Used-but-unrestored foreground fallback and measured foreground loss cannot be success.
- [ ] Secondary AX acceptance without verifier encodes `effect_not_verified`, `failureDomain=verification`, `ok=false` while retaining its diagnostic outcome fields.
- [ ] Scroll and press-key public route-specific semantics remain unchanged except the intended honesty rule.
- [ ] Route-specific summaries and verifier evidence remain in route services.
- [ ] OpenSpec validation passes when available and `/v1/routes` documents the correction.
- [ ] `swift test` exits 0; no live app was launched.
- [ ] Only in-scope files and the plan index status changed.

## STOP conditions

Stop and report if plan 007 is incomplete; a migration needs a public enum/field change beyond the specified secondary behavior fix; a verifier cannot distinguish unavailable from proved-no-effect without changing its internal result; press-key transport-level `ok` would change; scroll would need a new public classification; or focused verification fails twice.

## Maintenance notes

- `ActionOutcomePolicy` is an evidence-to-verdict function, not action middleware. Never move capture, dispatch, waits, thresholds, summaries, or DTO construction into it.
- New action routes should gather explicit facts and use the policy for post-dispatch classification; unsupported preflight stays route-owned.
- Reviewer focus: precedence of foreground restoration over verified effect, secondary no-verifier behavior, and preservation of press-key/scroll public semantics.
