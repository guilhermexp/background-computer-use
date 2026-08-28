# BCU Foreground Fallback and Retry Safety Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make BCU complete text and launch actions through a controlled foreground fallback without hiding text side effects or causing automatic duplicate retries.

**Architecture:** Exact AX transports remain background-first. A shared injected foreground coordinator permits one target-PID foreground fallback, conditionally restores the original app, and never overrides a third-app user transition. Type responses expose mandatory retry/fallback telemetry, launch success is based on the resolved app outcome, and the activity panel is structurally nonactivating.

**Tech Stack:** Swift 6.2, AppKit, ApplicationServices, Swift Testing, Python unittest, OpenSpec, signed macOS runtime smoke

**Spec:** `docs/plans/2026-08-28-bcu-foreground-fallback-and-retry-safety-design.md`

## Global Constraints

- Preserve background operation whenever an exact target-bound transport works.
- Completion has priority when the exact target requires foreground input.
- Dispatch text at most once per request.
- Any attempted text transport makes blind retry unsafe.
- A user transition to an unrelated third app wins over BCU restoration.
- Do not change click, paste, scroll, Locked Use, or unrelated UI behavior.
- Use Swift Testing, never XCTest.
- Do not commit or push until the user explicitly authorizes it for this correction.

---

### Task 1: Public retry and foreground-fallback contract

**Files:**
- Create: `Sources/BackgroundComputerUse/Actions/TypeText/TypeTextAttemptTelemetry.swift`
- Modify: `Sources/BackgroundComputerUse/Contracts/TextActionContracts.swift:168`
- Modify: `Sources/BackgroundComputerUse/Contracts/LaunchAppContracts.swift:22`
- Modify: `Sources/BackgroundComputerUse/API/RouteRegistry.swift:766`
- Modify: `Sources/BackgroundComputerUse/API/RouteRegistry.swift:1035`
- Modify: `Sources/BackgroundComputerUse/API/APIDocumentation.swift:143`
- Modify: `Sources/BackgroundComputerUse/API/APIDocumentation.swift:254`
- Test: `Tests/BackgroundComputerUseTests/BackgroundTextSafetyTests.swift`
- Test: `Tests/BackgroundComputerUseTests/LaunchAppPolicyTests.swift`

**Interfaces:**
- Produces: `TypeTextAttemptTelemetry(dispatchSucceeded: Bool?, strategiesAttempted: [AdaptiveTextStrategy])`.
- Produces: `TypeTextAttemptTelemetry.retrySafe: Bool`.
- Produces required `TypeTextResponse.retrySafe`, `foregroundFallbackUsed`, and `foregroundRestored` fields.
- Produces required `LaunchAppResponse.foregroundFallbackUsed` and `foregroundRestored` fields.

- [ ] **Step 1: Write RED telemetry and route-schema tests**

```swift
@Test
func dispatchedOpaqueUnicodeIsNeverRetrySafe() {
    let attempt = TypeTextAttemptTelemetry(
        dispatchSucceeded: true,
        strategiesAttempted: [.pidUnicode]
    )

    #expect(attempt.retrySafe == false)
}

@Test
func blockedBeforeAnyTransportRemainsRetrySafe() {
    let attempt = TypeTextAttemptTelemetry(
        dispatchSucceeded: nil,
        strategiesAttempted: []
    )

    #expect(attempt.retrySafe)
}

@Test
func typeTextRouteDocumentsRetryAndForegroundFallback() throws {
    let route = try #require(
        RouteRegistry.publicRoutes().first { $0.id == RouteID.typeText.rawValue }
    )
    let fields = route.response.fields

    #expect(fields.contains { $0.name == "retrySafe" && $0.type == "boolean" && $0.required })
    #expect(fields.contains { $0.name == "foregroundFallbackUsed" && $0.type == "boolean" && $0.required })
    #expect(fields.contains { $0.name == "foregroundRestored" && $0.type == "boolean" && $0.required })
}
```

- [ ] **Step 2: Verify RED**

Run: `swift test --filter BackgroundTextSafetyTests`

Expected: compilation fails because `TypeTextAttemptTelemetry` and the three response fields do not exist.

- [ ] **Step 3: Implement the minimal additive contract**

```swift
struct TypeTextAttemptTelemetry: Equatable, Sendable {
    let dispatchSucceeded: Bool?
    let strategiesAttempted: [AdaptiveTextStrategy]

    var retrySafe: Bool {
        dispatchSucceeded != true && strategiesAttempted.isEmpty
    }
}
```

Add the required fields to the two response DTOs and their route schemas. Document that
`retrySafe=false` requires a fresh read and forbids blind repetition. Update success signals so
foreground preservation is preferred telemetry rather than an absolute launch/text success gate.

- [ ] **Step 4: Verify GREEN**

Run: `swift test --filter BackgroundTextSafetyTests`

Expected: all focused tests pass.

- [ ] **Step 5: Record the checkpoint without committing**

Run: `git status --short && git diff --check`

Expected: only Task 1 contract, documentation, and test files are changed; no commit or push.

---

### Task 2: Shared controlled foreground coordinator

**Files:**
- Create: `Sources/BackgroundComputerUse/Actions/Shared/ForegroundFallbackCoordinator.swift`
- Modify: `Sources/BackgroundComputerUse/Actions/Shared/ForegroundApplicationSnapshot.swift`
- Create: `Tests/BackgroundComputerUseTests/ForegroundFallbackCoordinatorTests.swift`

**Interfaces:**
- Produces: `ForegroundPreparationMode.background`, `.foregroundFallback`, `.blockedByUserChange`.
- Produces: `ForegroundPreparationOutcome(mode: ForegroundPreparationMode, foregroundBeforeDispatch: ForegroundApplicationSnapshot?)`.
- Produces: `ForegroundFallbackCoordinator.prepare(original:targetPID:backgroundPrepared:)`.
- Produces: `ForegroundFallbackCoordinator.restore(original:targetPID:fallbackUsed:) -> Bool`.

- [ ] **Step 1: Write RED coordinator tests**

```swift
@Test
func failedBackgroundPreparationActivatesExactTargetOnce() {
    let original = ForegroundApplicationSnapshot(pid: 10, bundleID: "user")
    let target = ForegroundApplicationSnapshot(pid: 20, bundleID: "target")
    let harness = ForegroundHarness(current: original, target: target)
    let coordinator = harness.makeCoordinator()

    let outcome = coordinator.prepare(
        original: original,
        targetPID: target.pid,
        backgroundPrepared: false
    )

    #expect(outcome.mode == .foregroundFallback)
    #expect(harness.activatedPIDs == [target.pid])
}

@Test
func thirdAppTransitionBlocksWithoutActivation() {
    let original = ForegroundApplicationSnapshot(pid: 10, bundleID: "user")
    let third = ForegroundApplicationSnapshot(pid: 30, bundleID: "third")
    let harness = ForegroundHarness(current: third)

    let outcome = harness.makeCoordinator().prepare(
        original: original,
        targetPID: 20,
        backgroundPrepared: true
    )

    #expect(outcome.mode == .blockedByUserChange)
    #expect(harness.activatedPIDs.isEmpty)
}

@Test
func restoreDoesNotOverrideThirdApp() {
    let original = ForegroundApplicationSnapshot(pid: 10, bundleID: "user")
    let third = ForegroundApplicationSnapshot(pid: 30, bundleID: "third")
    let harness = ForegroundHarness(current: third)

    #expect(harness.makeCoordinator().restore(
        original: original,
        targetPID: 20,
        fallbackUsed: true
    ) == false)
    #expect(harness.activatedPIDs.isEmpty)
}
```

`ForegroundHarness` is an `@unchecked Sendable` test double protected by `NSLock`; it changes
`current` to its configured target only when the injected activation closure is called.

- [ ] **Step 2: Verify RED**

Run: `swift test --filter ForegroundFallbackCoordinatorTests`

Expected: compilation fails because the coordinator types are absent.

- [ ] **Step 3: Implement the minimal coordinator**

```swift
enum ForegroundPreparationMode: Equatable, Sendable {
    case background
    case foregroundFallback
    case blockedByUserChange
}

struct ForegroundPreparationOutcome: Equatable, Sendable {
    let mode: ForegroundPreparationMode
    let foregroundBeforeDispatch: ForegroundApplicationSnapshot?
}
```

The injected live activation closure resolves `NSRunningApplication(processIdentifier:)` and calls
`activate(options: [])`. `prepare` accepts an unchanged original foreground as background, accepts an
already-frontmost target as fallback, activates the exact target once when background preparation
failed, and blocks an unrelated third app. `restore` activates the original PID only while the target
is still frontmost.

- [ ] **Step 4: Verify GREEN**

Run: `swift test --filter ForegroundFallbackCoordinatorTests`

Expected: all coordinator tests pass.

- [ ] **Step 5: Record the checkpoint without committing**

Run: `git status --short && git diff --check`

Expected: Task 2 adds only the shared coordinator and its focused tests.

---

### Task 3: One-shot type_text foreground fallback

**Files:**
- Modify: `Sources/BackgroundComputerUse/Actions/TypeText/TypeTextRouteService.swift:24-947`
- Modify: `Sources/BackgroundComputerUse/Actions/TypeText/BackgroundTextPreparation.swift`
- Modify: `Tests/BackgroundComputerUseTests/AdaptiveTypeTextRouteTests.swift`
- Modify: `Tests/BackgroundComputerUseTests/BackgroundTextSafetyTests.swift`

**Interfaces:**
- Consumes: `ForegroundFallbackCoordinator` and `TypeTextAttemptTelemetry` from Tasks 1–2.
- Produces: `TextDispatchResult.foregroundFallbackUsed` and `foregroundBeforeDispatch`.
- Produces: every response with truthful `retrySafe`, `foregroundFallbackUsed`, and `foregroundRestored`.

- [ ] **Step 1: Write RED one-shot and classification-policy tests**

```swift
@Test
func opaqueUnicodeAttemptReportsItsStrategyAndBlocksRetry() {
    let attempt = TypeTextAttemptTelemetry(
        dispatchSucceeded: true,
        strategiesAttempted: [.pidUnicode]
    )

    #expect(attempt.strategiesAttempted == [.pidUnicode])
    #expect(attempt.retrySafe == false)
}

@Test
func exactAXFastPathNeverPreparesForegroundFallback() {
    var preparationCalls = 0
    let result = AdaptiveTextDispatcher.dispatch(
        baseline: "",
        expected: "hello",
        fallbackEligible: true,
        writeAX: { .success },
        readValue: { "hello" },
        performTargetBoundFallback: { .unavailable },
        prepareUnicodeFallback: {
            preparationCalls += 1
            return true
        },
        postUnicode: { true }
    )

    #expect(result.strategiesAttempted == [.axValue])
    #expect(preparationCalls == 0)
}
```

Add a pure `TypeTextOutcomePolicy` test asserting that exact value/selection verification returns
`.success` even when `foregroundPreserved=false`, while a dispatched opaque result returns
`.verifierAmbiguous` and never a retryable no-op.

- [ ] **Step 2: Verify RED**

Run: `swift test --filter AdaptiveTypeTextRouteTests && swift test --filter BackgroundTextSafetyTests`

Expected: the new outcome-policy assertions fail because foreground safety still overrides verified
text and opaque dispatch telemetry is still empty.

- [ ] **Step 3: Remove unconditional target-window preparation**

Delete the route-level `targetOnlyFocusAndKeyWindow` call that currently runs before every semantic
text strategy. Keep AX value and `AXTextOperation` target-bound. Move background preparation into
`prepareUnicodeFallback`, after the unchanged-baseline rereads prove Unicode is eligible.

Pass the exact window number into `dispatchText`. Use `ForegroundFallbackCoordinator.prepare` inside
the Unicode preparation closure. Return false without posting when the coordinator reports
`.blockedByUserChange`.

- [ ] **Step 4: Make opaque and semantic dispatch outcomes honest**

For AX-opaque input, record `[.pidUnicode]` before the post. After any attempted strategy, compute
`retrySafe` through `TypeTextAttemptTelemetry`. A successful opaque post returns
`verifier_ambiguous` whether it remained background or used foreground fallback, with the summary
“Text was dispatched; reread before continuing and do not retry blindly.”

For semantic targets, remove the `backgroundSafety.foregroundPreserved` early return from
`classifyResult`; exact value and selection evidence decide success. Restore the original app only
after verification, and only through the coordinator's conditional restore rule.

- [ ] **Step 5: Verify GREEN**

Run: `swift test --filter AdaptiveTypeTextRouteTests`

Run: `swift test --filter BackgroundTextSafetyTests`

Expected: both focused suites pass, Unicode call counts remain bounded at one, and the exact AX lane
never invokes foreground preparation.

- [ ] **Step 6: Record the checkpoint without committing**

Run: `git diff --check && git status --short`

Expected: only TypeText production/tests plus Task 1–2 files are changed.

---

### Task 4: Launch completion with conditional restoration

**Files:**
- Modify: `Sources/BackgroundComputerUse/Actions/LaunchApp/LaunchAppRouteService.swift:119-216`
- Modify: `Tests/BackgroundComputerUseTests/LaunchAppPolicyTests.swift`

**Interfaces:**
- Consumes: `ForegroundFallbackCoordinator` from Task 2.
- Produces: launch success independent of foreground preservation after the signed app PID is resolved.
- Produces truthful `foregroundFallbackUsed` and `foregroundRestored` response fields.

- [ ] **Step 1: Replace the old RED foreground-failure expectation**

```swift
@Test
func completedLaunchRestoresOriginalForegroundAndRemainsSuccess() throws {
    let launcher = StubLaunchTransport(resultPID: 800)
    let foreground = LaunchForegroundHarness(originalPID: 100, targetPID: 800)
    let service = LaunchAppRouteService(
        resolver: StubLaunchResolver(identity: identity, existingPID: nil),
        authorizer: StubLaunchAuthorizer(decision: .alwaysAllow),
        launcher: launcher,
        windowProvider: { _ in
            foreground.observeTargetActivation()
            return ["w_800"]
        },
        foregroundPID: foreground.capturePID,
        activatePID: foreground.activate
    )

    let response = try service.launchApp(
        request: LaunchAppRequest(bundleID: identity.bundleID, appPath: nil, sessionID: "session")
    )

    #expect(response.ok)
    #expect(response.classification == .success)
    #expect(response.foregroundFallbackUsed)
    #expect(response.foregroundRestored)
    #expect(response.foregroundPIDAfter == 100)
}
```

Add a second test where the foreground becomes PID 900 after launch; assert BCU does not activate PID
100 and reports `foregroundRestored=false`.

- [ ] **Step 2: Verify RED**

Run: `swift test --filter LaunchAppPolicyTests`

Expected: compilation fails because restoration dependencies and response fields are absent, then the
old implementation fails by returning `effect_not_verified`.

- [ ] **Step 3: Implement completion-first launch classification**

Sample foreground immediately after window discovery. When it equals the launched target and differs
from the original PID, mark fallback used and conditionally restore through `activatePID`. Sample the
final foreground after restoration. Return `.success` for a resolved allowed app even when restoration
is not possible; retain the foreground telemetry and never relaunch an existing PID.

- [ ] **Step 4: Verify GREEN**

Run: `swift test --filter LaunchAppPolicyTests`

Expected: all launch tests pass, including no relaunch and third-app preservation.

- [ ] **Step 5: Record the checkpoint without committing**

Run: `git diff --check && git status --short`

Expected: launch changes remain limited to the route, contract/schema from Task 1, and tests.

---

### Task 5: Activity card that cannot activate BCU Control

**Files:**
- Modify: `Sources/BackgroundComputerUseControl/PiPWindowController.swift:86-145`
- Modify: `Tests/BackgroundComputerUseTests/ActivityControlTests.swift`

**Interfaces:**
- Produces: internal `ActivityPanel: NSPanel` with `canBecomeKey == false` and `canBecomeMain == false`.
- Preserves: one card, latest activity replacement, two-second dismissal, and the existing preference.

- [ ] **Step 1: Write the RED AppKit panel test**

```swift
@Test @MainActor
func activityPanelCannotBecomeKeyOrMain() {
    let panel = ActivityPanel.make(frame: NSRect(x: 0, y: 0, width: 330, height: 130))

    #expect(panel.canBecomeKey == false)
    #expect(panel.canBecomeMain == false)
    #expect(panel.ignoresMouseEvents)
    panel.close()
}
```

- [ ] **Step 2: Verify RED**

Run: `swift test --filter ActivityControlTests`

Expected: compilation fails because `ActivityPanel` does not exist.

- [ ] **Step 3: Implement the nonactivating panel**

Create an internal `NSPanel` subclass/factory that uses the current visual style, overrides key/main
eligibility to false, sets `ignoresMouseEvents=true`, and never calls `NSApp.activate`. Keep the
existing update/dismiss/reposition behavior and one reusable panel instance.

- [ ] **Step 4: Verify GREEN**

Run: `swift test --filter ActivityControlTests`

Expected: all activity-card lifecycle and panel nonactivation tests pass.

- [ ] **Step 5: Record the checkpoint without committing**

Run: `git diff --check && git status --short`

Expected: no activity-card layout, timing, or preference regression.

---

### Task 6: OpenSpec, agent guidance, smoke policy, and final qualification

**Files:**
- Create: `openspec/changes/fix-foreground-fallback-retry-safety/proposal.md`
- Create: `openspec/changes/fix-foreground-fallback-retry-safety/tasks.md`
- Create: `openspec/changes/fix-foreground-fallback-retry-safety/specs/action-verification/spec.md`
- Modify: `skills/background-computer-use/SKILL.md`
- Modify: `script/smoke_runtime.py`
- Modify: `script/test_smoke_runtime.py`
- Modify: `docs/parity-completion-audit.md`

**Interfaces:**
- Produces: `type_text_retry_contract_is_valid(payload)` in the Python smoke policy.
- Produces: strict requirement that `dispatchSucceeded=true` implies `retrySafe=false` and a nonempty
  strategy list.
- Preserves: Safari's exact target-bound background lane and adds controlled fallback evidence.

- [ ] **Step 1: Write RED Python retry-contract tests**

```python
def test_dispatched_text_requires_non_retryable_named_strategy(self):
    self.assertTrue(type_text_retry_contract_is_valid({
        "dispatchSucceeded": True,
        "strategiesAttempted": ["pid_unicode"],
        "retrySafe": False,
    }))
    self.assertFalse(type_text_retry_contract_is_valid({
        "dispatchSucceeded": True,
        "strategiesAttempted": [],
        "retrySafe": True,
    }))
```

- [ ] **Step 2: Verify RED**

Run: `python3 -m unittest script/test_smoke_runtime.py`

Expected: import or assertion failure because `type_text_retry_contract_is_valid` is absent.

- [ ] **Step 3: Add OpenSpec and caller guidance**

The OpenSpec delta SHALL define background-first fallback, one text dispatch, retry safety,
conditional restoration, and nonactivating activity presentation. Update the skill so callers never
repeat `type_text` when `retrySafe=false`; they reread the window and continue from observed state.

- [ ] **Step 4: Implement Python smoke policy and preserve background proof**

```python
def type_text_retry_contract_is_valid(payload: dict) -> bool:
    attempted = payload.get("strategiesAttempted", [])
    dispatched = payload.get("dispatchSucceeded") is True
    return not dispatched or (bool(attempted) and payload.get("retrySafe") is False)
```

Keep the Safari `ax_value + ax_text_operation` lane requiring exact foreground preservation. Add a
separate controlled-fallback assertion that accepts verified success or dispatched opaque ambiguity,
but always requires truthful retry telemetry.

- [ ] **Step 5: Verify focused documentation and Python gates**

Run: `python3 -m unittest script/test_smoke_runtime.py script/test_smoke_control.py script/test_benchmark_mac_parity.py`

Run: `openspec validate fix-foreground-fallback-retry-safety --strict`

Expected: all Python tests pass and OpenSpec reports the change valid.

- [ ] **Step 6: Run formatter and complete Swift gates once**

Run: `swiftformat --lint Sources Tests`

Run: `swift build -c release`

Run: `swift test`

Expected: formatter and release build exit 0; all Swift tests pass with no new failure.

- [ ] **Step 7: Build/install the signed universal app and run live smoke**

Run: `script/build_and_run.sh build`

Run: `script/smoke_runtime.py`

Verify separately on the real paused Termio/Codex prompt: one `type_text` call, one visual reread, no
automatic retry, and one Return only after the single prompt is confirmed. Hold Codex Desktop
frontmost during the background lane; in the fallback lane verify any elevation is bounded and the
prior app is restored unless the user selected a third app.

Expected: existing signed smoke remains green; no duplicated prompt; every dispatched text result has
`retrySafe=false` and a nonempty strategy list; the activity card never makes BCU Control frontmost.

- [ ] **Step 8: Request independent review and fix Critical/Important findings**

Review the complete working-tree diff against this plan and the design. Require evidence for dispatch
count, foreground transitions, conditional restore, API schema, and the live trace before accepting
the change.

- [ ] **Step 9: Report status without committing or pushing**

Run: `git status --short --branch && git diff --check`

Expected: a clean diff check and only the approved B1/B2 files. Report that commit/push remain pending
explicit authorization.
