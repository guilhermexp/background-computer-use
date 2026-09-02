# Plan 007: Make type-text foreground and caret outcomes honest

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**: `git diff --stat 0110ffb..HEAD -- Sources/BackgroundComputerUse/Actions/TypeText Sources/BackgroundComputerUse/Actions/Shared/ForegroundFallbackCoordinator.swift Sources/BackgroundComputerUse/Actions/Shared/ForegroundLateRecovery.swift Sources/BackgroundComputerUse/Contracts/TextActionContracts.swift Sources/BackgroundComputerUse/API/RouteRegistry.swift Sources/BackgroundComputerUse/API/APIDocumentation.swift Tests/BackgroundComputerUseTests/BackgroundTextSafetyTests.swift Tests/BackgroundComputerUseTests/ForegroundFallbackCoordinatorTests.swift Tests/BackgroundComputerUseTests/APIDocumentationTests.swift openspec/changes/make-type-text-outcomes-honest`
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
A live Electron run returned `foregroundFallbackUsed: true` and `foregroundRestored: false` while the target remained frontmost, yet exact text evidence could still produce `success`. That violates BCU’s defining background-safety rule. The same run showed the opposite honesty problem: Chromium applied the exact requested value but reported its caret as `{location: 0, length: 0}`, causing a false failure. This plan makes unresolved restoration a `background_safety` ambiguity, preserves a genuine third-app user choice, and replaces the caret Boolean with an explicit matched/contradicted/unavailable-or-stale contract.
## Current state
- `Sources/BackgroundComputerUse/Actions/TypeText/TypeTextOutcomePolicy.swift` ignores foreground preservation and lets a caret mismatch override an exact value:
```swift
// TypeTextOutcomePolicy.swift:36-57
static func classifySemanticDispatch(
    exactValueMatch: Bool,
    exactSelectionMatch: Bool?,
    targetRelocated: Bool,
    postStateTokenAvailable: Bool,
    foregroundPreserved _: Bool
) -> TypeTextOutcomeDecision {
    if exactValueMatch {
        if exactSelectionMatch == false {
            return TypeTextOutcomeDecision(
                classification: .effectNotVerified,
                failureDomain: .verification,
                summary: "The text inserted exactly, but the expected caret or selection state did not verify."
            )
        }
        return TypeTextOutcomeDecision(
            classification: .success,
            failureDomain: nil,
            summary: "The targeted text dispatch matched the expected inserted value after reread."
        )
    }
```
- `Sources/BackgroundComputerUse/Actions/TypeText/TypeTextRouteService.swift:369-410` builds `exactSelectionMatch`, restores foreground, then computes background safety. `classifyResult` later passes only `backgroundSafety.foregroundPreserved` (`TypeTextRouteService.swift:1086-1092`), and the policy discards it.
- `Sources/BackgroundComputerUse/Actions/Shared/ForegroundFallbackCoordinator.swift` collapses materially different restore outcomes into `false`:
```swift
// ForegroundFallbackCoordinator.swift:90-111
func restore(
    original: ForegroundApplicationSnapshot?,
    targetPID: pid_t,
    fallbackUsed: Bool
) -> Bool {
    guard fallbackUsed,
          let original,
          original.pid != targetPID,
          foregroundApplication()?.pid == targetPID,
          activateApplication(original.pid)
    else {
        return false
    }
    switch waitForForeground(pid: original.pid, whilePID: targetPID) {
    case .reached:
        return true
    case .blockedByThirdApp, .timedOut:
        return false
    }
}
```
- The same coordinator already arms late recovery during preparation timeout (`ForegroundFallbackCoordinator.swift:75-85`). `ForegroundLateRecoveryRegistry.arm` creates a bounded session (`ForegroundLateRecovery.swift:69-92`), and live sessions expire after five seconds (`ForegroundLateRecovery.swift:111-148`). Reuse this mechanism; do not invent a timer or override third-app activation.
- The failure domain already exists; no enum case is needed:
```swift
// TextActionContracts.swift:10-18
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
- `TypeTextVerificationEvidenceDTO` currently exposes `exactSelectionMatch` and `exactSelectionMatchSource` (`TextActionContracts.swift:148-165`). Those fields cannot distinguish a genuine contradiction from absent or renderer-stale caret evidence.
- `AXActionTargetSnapshot` has no web-renderer flag (`AXActionTargetResolver.swift:18-46`). Do not add one. Exact target provenance is already available at `capture.envelope.semanticTree.nodes[target.primaryCanonicalIndex].flags`; `AXSemanticEnricher.swift:300-320` marks an `AXWebArea` and every descendant with `web_descendant`. This is narrower than treating every control in a browser window as web content.
- `Tests/BackgroundComputerUseTests/BackgroundTextSafetyTests.swift:47-58` currently codifies the bug as `exactSemanticVerificationWinsAfterForegroundFallback` with `foregroundPreserved: false` expecting success. `ForegroundFallbackCoordinatorTests.swift:259-299` proves timeout and third-app restore cases both currently return false.
- `RouteRegistry.textActionResponse` documents only `TypeTextResponse.verification | null` (`RouteRegistry.swift:1013-1050`), while `APIDocumentation.swift:255-260` says exact value or selection evidence is a success signal and foreground fields merely “report” impact.
- Repository rules require verifier-first outcomes and say “Erro de background é reportado, nunca escondido roubando foco” (`openspec/project.md:14`). `GET /v1/routes` must match every DTO field (`openspec/project.md:15`).
## Commands you will need
| Purpose | Command | Expected on success |
|---|---|---|
| Foreground tests | `swift test --filter ForegroundFallbackCoordinatorTests` | exit 0; all selected tests pass |
| Outcome/contract tests | `swift test --filter BackgroundTextSafetyTests` | exit 0; all selected tests pass |
| API docs tests | `swift test --filter APIDocumentationTests` | exit 0; all selected tests pass |
| OpenSpec CLI check | `which openspec` | path and exit 0, or no output and nonzero (documented skip) |
| OpenSpec validation | `openspec validate make-type-text-outcomes-honest --strict` | exit 0 when CLI is installed |
| Final suite | `swift test` | exit 0; full suite passes |
## Scope
**In scope** (the only files you should modify):
- `Sources/BackgroundComputerUse/Actions/Shared/ForegroundFallbackCoordinator.swift`
- `Sources/BackgroundComputerUse/Actions/TypeText/TypeTextOutcomePolicy.swift`
- `Sources/BackgroundComputerUse/Actions/TypeText/TypeTextRouteService.swift`
- `Sources/BackgroundComputerUse/Contracts/TextActionContracts.swift`
- `Sources/BackgroundComputerUse/API/RouteRegistry.swift`
- `Sources/BackgroundComputerUse/API/APIDocumentation.swift`
- `Tests/BackgroundComputerUseTests/ForegroundFallbackCoordinatorTests.swift`
- `Tests/BackgroundComputerUseTests/BackgroundTextSafetyTests.swift`
- `Tests/BackgroundComputerUseTests/APIDocumentationTests.swift`
- `openspec/changes/make-type-text-outcomes-honest/proposal.md` (create)
- `openspec/changes/make-type-text-outcomes-honest/tasks.md` (create)
- `openspec/changes/make-type-text-outcomes-honest/specs/type-text-outcome-honesty/spec.md` (create)
- `plans/README.md` (status row only)

**Out of scope** (do NOT touch, even though related):
- `ForegroundLateRecovery.swift`; use its existing five-second registry unchanged.
- `AXActionTargetSnapshot` and its public DTO; derive `web_descendant` from the semantic tree.
- Text delivery/fallback ordering, settle timings, `press_key`, click, and paste behavior.
- Changing `retrySafe`; any attempted text transport remains non-retry-safe.
- Launching/installing the runtime or running live Electron smoke without explicit operator authorization.

## Git workflow

- Branch: `advisor/007-type-text-outcome-honesty`
- Commit logical units with conventional messages, for example `fix: make type text outcomes foreground-safe` and `docs: specify type text caret verification`.
- Do NOT push or open a PR unless the operator instructed it.
- Preserve all baseline working-tree changes.

## Steps

### Step 1: Specify the public behavior before changing code

Create OpenSpec change `make-type-text-outcomes-honest` with the standard three artifacts. The proposal must state: failed restoration while the target remains frontmost becomes `verifier_ambiguous/background_safety`; a third app remains the user’s choice; and caret verification becomes a three-state response field. The delta spec must contain these exact requirements/scenarios:

```markdown
## MODIFIED Requirements
### Requirement: Type text success preserves background safety
A type_text action that used foreground fallback SHALL NOT return success while the target remains frontmost after restoration. It SHALL arm bounded late recovery for the original app and return verifier_ambiguous with failureDomain background_safety. If a third app became frontmost, BCU SHALL preserve that user choice and classify only from transport/effect evidence.
#### Scenario: Restore timeout leaves target frontmost
- **WHEN** foreground fallback dispatched text and restoration times out with the target still frontmost
- **THEN** late recovery is armed, classification is verifier_ambiguous, failureDomain is background_safety, foregroundRestored is false, and retrySafe remains false
#### Scenario: Third app wins during restoration
- **WHEN** a third app becomes frontmost during restoration
- **THEN** BCU does not reactivate the original app and does not downgrade otherwise exact text evidence solely for foreground preservation

### Requirement: Type text reports three-state caret evidence
TypeTextVerification SHALL expose caretVerification as matched, contradicted, or unavailable_or_stale and caretVerificationSource as a nullable string. It SHALL NOT expose exactSelectionMatch or exactSelectionMatchSource.
#### Scenario: Web renderer reports stale zero caret
- **WHEN** the exact value matches and a web_descendant target reports a nonmatching zero-length caret at location zero
- **THEN** classification is success, caretVerification is unavailable_or_stale, and warnings explain that the renderer caret is stale
#### Scenario: Native caret contradicts expected range
- **WHEN** the exact value matches but an available native caret differs from the expected range
- **THEN** classification is effect_not_verified with failureDomain verification and caretVerification contradicted
```

`tasks.md` must checklist the contract, coordinator, route policy, focused tests/docs, then a final `swift test`; it must also include strict OpenSpec validation and explicitly mark live smoke as operator-authorized only.

**Verify**: `which openspec` → if exit 0, run `openspec validate make-type-text-outcomes-honest --strict` and expect exit 0; if `which` is nonzero, record “OpenSpec CLI unavailable; strict validation skipped” in the change task notes and continue.

### Step 2: Return a typed restore outcome and arm recovery only when the target still owns foreground

In `ForegroundFallbackCoordinator.swift`, add internal enum `ForegroundRestoreOutcome: Equatable, Sendable` with cases `notRequired`, `restored`, `userChangedForeground`, `targetStillFrontmostRecoveryArmed`, and `foregroundUnknown`. Change `restore` to return it.

Implement this order exactly:

```swift
guard fallbackUsed, let original, original.pid != targetPID else { return .notRequired }
guard let current = foregroundApplication() else { return .foregroundUnknown }
guard current.pid == targetPID else { return .userChangedForeground }
guard activateApplication(original.pid) else {
    lateRecovery.arm(desired: original, targetPID: targetPID)
    return .targetStillFrontmostRecoveryArmed
}
switch waitForForeground(pid: original.pid, whilePID: targetPID) {
case .reached:
    return .restored
case .blockedByThirdApp:
    return .userChangedForeground
case .timedOut:
    guard let after = foregroundApplication() else { return .foregroundUnknown }
    guard after.pid == targetPID else { return .userChangedForeground }
    lateRecovery.arm(desired: original, targetPID: targetPID)
    return .targetStillFrontmostRecoveryArmed
}
```

Update coordinator tests: successful restore is `.restored`; no fallback is `.notRequired`; timeout with target still foreground expects `.targetStillFrontmostRecoveryArmed` and one `RecoveryRequest(original,target)`; third-app cases expect `.userChangedForeground` and no recovery request. Add a nil-after-timeout case for `.foregroundUnknown`.

**Verify**: `swift test --filter ForegroundFallbackCoordinatorTests` → exit 0; typed outcome, recovery arming, and third-app preservation tests pass.

### Step 3: Replace caret Boolean fields with a three-state contract

In `TextActionContracts.swift`, add:

```swift
public enum TypeTextCaretVerificationDTO: String, Encodable, Sendable {
    case matched
    case contradicted
    case unavailableOrStale = "unavailable_or_stale"
}
```

Replace `exactSelectionMatch: Bool?` and `exactSelectionMatchSource: String?` in `TypeTextVerificationEvidenceDTO` with required `caretVerification: TypeTextCaretVerificationDTO` and nullable `caretVerificationSource: String?`. This is a clean cutover; do not retain deprecated aliases.

In `TypeTextRouteService`, derive exact target provenance as:

```swift
let isWebContentTarget = capture.envelope.semanticTree.nodes.indices.contains(target.primaryCanonicalIndex)
    && capture.envelope.semanticTree.nodes[target.primaryCanonicalIndex].flags.contains("web_descendant")
```

Add `TypeTextOutcomePolicy.classifyCaret(expected: TypeTextSelectionRangeDTO?, sameElement: TypeTextSelectionRangeDTO?, resolvedElement: TypeTextSelectionRangeDTO?, exactValueMatch: Bool, isWebContentTarget: Bool) -> (verification: TypeTextCaretVerificationDTO, source: String?, warning: String?)`. Return `.matched` plus `same_live_element`/`refreshed_live_element` if either observed range exactly matches. Return `.unavailableOrStale` if no expected/observed range exists, or if the value is exact, the target is web content, and every available nonmatching range equals `{0,0}`. Otherwise return `.contradicted`. Only the known-stale web branch returns the warning specified below.

Use `.unavailableOrStale`/nil in the pre-dispatch failure evidence at `TypeTextRouteService.swift:284-301`. When the known web zero-caret rule fires, append warning `caret_unavailable_or_stale: exact value matched, but the web renderer reported a zero caret after AXValue set.`

**Verify**: `swift test --filter BackgroundTextSafetyTests` → exit 0 after tests are updated to compile with the new fields and policy input.

### Step 4: Make foreground safety take precedence in type-text classification

Use exact signatures `classifyOpaqueDispatch(attempt: TypeTextAttemptTelemetry, foregroundFallbackUsed: Bool, restoreOutcome: ForegroundRestoreOutcome)` and `classifySemanticDispatch(exactValueMatch: Bool, caretVerification: TypeTextCaretVerificationDTO, targetRelocated: Bool, postStateTokenAvailable: Bool, foregroundFallbackUsed: Bool, restoreOutcome: ForegroundRestoreOutcome)`. Remove the ignored `foregroundPreserved` parameters.

Before transport/effect classification, apply this common rule:

```swift
if foregroundFallbackUsed,
   restoreOutcome == .targetStillFrontmostRecoveryArmed || restoreOutcome == .foregroundUnknown {
    return TypeTextOutcomeDecision(
        classification: .verifierAmbiguous,
        failureDomain: .backgroundSafety,
        summary: "Text was dispatched, but foreground restoration could not be verified; bounded recovery is active when the target remained frontmost. Do not retry blindly."
    )
}
```

`.userChangedForeground` must not trigger that override. For an exact value, `.contradicted` remains `effect_not_verified/.verification`; `.matched` and `.unavailableOrStale` return success. Keep opaque successful dispatch ambiguous and failed dispatch in `.transport`. Do not change `TypeTextAttemptTelemetry.retrySafe`.

In all four restore call sites in `TypeTextRouteService`, replace Boolean short-circuiting with a typed ternary: line 252 uses `canRestoreForeground(attempt: attempt, verificationCompleted: false)` and `restore(original: foregroundBefore, targetPID: window.pid, fallbackUsed: dispatchResult.foregroundFallbackUsed)`; line 398 uses those same arguments with `verificationCompleted: true`; lines 651 and 700 use `verificationCompleted: true` and `restore(original: foregroundBefore, targetPID: dispatchWindow.pid, fallbackUsed: foregroundFallbackUsed)`. The false ternary branch is `.notRequired`. Then set `foregroundRestored = restoreOutcome == .restored`, append an explicit note for `.userChangedForeground`, and pass fallback/outcome into policy where classification is delegated.

Replace the old bug-preserving test with these policy cases in `BackgroundTextSafetyTests.swift`: restoration unresolved overrides exact text as `.verifierAmbiguous/.backgroundSafety`; third-app choice plus exact matched text remains success; web exact value plus stale caret succeeds; native contradicted caret remains `effect_not_verified/.verification`; all attempted transports remain `retrySafe == false`.

**Verify**: `swift test --filter BackgroundTextSafetyTests && swift test --filter ForegroundFallbackCoordinatorTests` → exit 0; all foreground and caret branches pass.

### Step 5: Make `/v1/routes` and operational documentation match the DTO

In `RouteRegistry.textActionResponse`, give the TypeText verification field the type `TypeTextVerification | null` and a description that names required `caretVerification` values and nullable `caretVerificationSource`; remove all mention of `exactSelectionMatch`. In `APIDocumentation.typeText`, state that success requires exact value evidence plus a non-contradicted caret, and that `foregroundFallbackUsed=true` with unresolved restoration returns `verifier_ambiguous/background_safety`; third-app choice is preserved.

Extend `BackgroundTextSafetyTests.typeTextRouteDocumentsRetryAndForegroundFallback` to assert the verification field description contains `caretVerification` and `unavailable_or_stale`. Add an `APIDocumentationTests` assertion that type-text success signals mention the caret field and foreground-restoration failure classification.

**Verify**: `swift test --filter APIDocumentationTests && swift test --filter BackgroundTextSafetyTests` → exit 0; route schema and operational documentation tests pass.

### Step 6: Run the integrated contract gate

Search for removed fields, validate OpenSpec when available, and run the full suite once. Do not run live smoke.

**Verify**: `grep -R "exactSelectionMatch" Sources Tests openspec/changes/make-type-text-outcomes-honest` → exit 1 with no matches; `swift test` → exit 0; `openspec validate make-type-text-outcomes-honest --strict` → exit 0 when `which openspec` succeeds, otherwise the documented skip remains.

## Test plan

- `ForegroundFallbackCoordinatorTests`: typed success/not-required/user-choice/unknown/recovery-armed outcomes and exact late-recovery request count.
- `BackgroundTextSafetyTests`: safety precedence, unchanged retry semantics, web stale zero caret, native caret contradiction, and route-schema parity.
- `APIDocumentationTests`: agent-facing success/retry guidance matches the new wire contract.
- No test launches an app, changes real foreground focus, or waits five seconds; use existing harnesses/spies.
- Verification: the three focused filters pass, then `swift test` passes.

## Done criteria

- [ ] Restore timeout/activation failure while target remains frontmost arms one existing bounded late-recovery session.
- [ ] A third app is never overridden and does not alone downgrade otherwise valid effect evidence.
- [ ] `TypeTextOutcomePolicy` has no ignored foreground argument.
- [ ] Exact web-renderer value plus stale `{0,0}` caret is success with `unavailable_or_stale` warning evidence.
- [ ] An available contradictory native caret remains `effect_not_verified/.verification`.
- [ ] `exactSelectionMatch` fields have zero source/test/spec references; RouteRegistry documents the replacement fields.
- [ ] `retrySafe` remains false after any transport attempt.
- [ ] Focused suites, full `swift test`, and available OpenSpec validation pass.
- [ ] No file outside Scope is modified by this plan; `plans/README.md` is updated.

## STOP conditions

Stop and report back (do not improvise) if:

- Foreground late recovery no longer has a bounded five-second lifetime or cannot be injected through `ForegroundLateRecoveryArming`.
- The semantic target’s canonical index cannot be mapped to `semanticTree.nodes[].flags`; do not fall back to classifying an entire browser window as web content.
- A third-app transition cannot be distinguished from target-still-frontmost timeout without changing unrelated foreground APIs.
- The contract already removed/renamed either caret field differently from this plan.
- Any focused verification fails twice after one reasonable fix attempt, or the change requires modifying an out-of-scope route.
- Any required baseline path is absent from both working-tree and post-`0110ffb` committed changes.

## Maintenance notes

- Review foreground precedence before value/caret precedence: background safety is part of the action outcome, not telemetry decoration.
- `unavailable_or_stale` is not a general license to ignore caret mismatches. The known-stale exception is exact value + exact `web_descendant` target + available nonmatching ranges all equal `{0,0}`.
- Late recovery must never fight a real third-app activation. Future coordinator changes should retain the typed outcome and corresponding harness cases.
- If Chromium later reports reliable carets, tighten the stale rule with measured evidence and update OpenSpec, RouteRegistry, and tests together.
