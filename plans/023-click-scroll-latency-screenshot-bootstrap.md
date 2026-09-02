# Plan 023: Bound click latency and avoid redundant screenshot/bootstrap work

> **Executor instructions**: Follow this plan step by step. Run every verification command and confirm the expected result before moving to the next step. If anything in the "STOP conditions" section occurs, stop and report — do not improvise. This is a live-characterization plan: do not run the signed app or live harness until the operator explicitly authorizes it. When done, update the status row for this plan in `plans/README.md` — unless a reviewer dispatched you and told you they maintain the index.
>
> **Required working-tree baseline**: Before the drift check, run `git diff --name-only 0110ffb..HEAD -- Sources/BackgroundComputerUse/API/Router.swift Sources/BackgroundComputerUse/App/BackgroundComputerUseControlBridge.swift Sources/BackgroundComputerUseControlShared/CodeSignatureIdentity.swift Sources/BackgroundComputerUse/Runtime/RuntimeExecutionQueue.swift Sources/BackgroundComputerUse/Actions/TypeText/AdaptiveTextDispatcher.swift Sources/BackgroundComputerUse/StatePipeline/InteractionToken.swift Sources/BackgroundComputerUse/Runtime/Process/BoundedProcessRunner.swift skills/background-computer-use/scripts/bcu-request.py Tests/BackgroundComputerUseTests/InteractionTokenTests.swift Tests/BackgroundComputerUseTests/RuntimeExecutionQueueTests.swift` and `git status --short --` with the same paths. Each named file must appear in at least one output (committed after `0110ffb` or still modified/untracked). If any is absent, STOP; this plan assumes those fixes, including adaptive Chromium text settling and the 64 MiB request thread.
>
> **Drift check (run first)**: `git diff --stat 0110ffb..HEAD -- Sources/BackgroundComputerUse/Actions/Click Sources/BackgroundComputerUse/Actions/TypeText Sources/BackgroundComputerUse/Actions/Shared/AXActionTargetResolver.swift Sources/BackgroundComputerUse/Actions/Shared/ConditionedActionWait.swift Sources/BackgroundComputerUse/Cursor Sources/BackgroundComputerUse/Screenshot Sources/BackgroundComputerUse/Contracts/ScreenshotCoordinateContract.swift Sources/BackgroundComputerUse/API/RouteRegistry.swift Sources/BackgroundComputerUse/API/APIDocumentation.swift Tests/BackgroundComputerUseTests script/live_regression.py`
> If any in-scope file changed since this plan was written, compare the "Current state" excerpts against the live code before proceeding; on a mismatch, treat it as a STOP condition.

## Status

- **Priority**: P2
- **Effort**: L
- **Risk**: HIGH
- **Depends on**: `plans/008-scroll-ladder-stop.md`, `plans/005-live-smoke-honesty.md`
- **Category**: perf
- **Planned at**: commit `0110ffb`, 2026-09-02

## Why this matters

The slow click path repeatedly recaptures a thousands-node AX tree and screenshot while also stacking fixed transport, cursor, settle, and renderer-bootstrap delays. A single no-effect coordinate click can perform twelve full rereads just to retry a point hit-test; base64 screenshots also pay a disk write that their consumer did not request. These changes remove redundant work without weakening verifier honesty, and a live Electron oracle stops the work immediately if success rate drops.

## Current state

- `Sources/BackgroundComputerUse/Actions/Click/ClickRouteService.swift` owns the click read-act-read waterfall.
  - `:238-245`: every click begins with a full `targetResolver.capture`.
  - `:1433-1439`: coordinate dispatch synchronously calls `AXCursorTargeting.prepareClick`.
  - `:1471-1487`: after target focus, it performs another full `targetResolver.reread`, then captures a baseline image and relocates the target.
  - `:1624-1643`: escalation retries up to 12 times, sleeps 50 ms, and performs a full reread on every attempt before `pressAXElement`.
  - `:2189-2248`: `pressAXElement` already does a live app/system hit-test and only then falls back to captured nodes.
  - `:2257-2285`: `pressEligibleElement` checks PID, walks at most four ancestors, reads frame/actions/enabled, applies destructive-label confirmation, and dispatches `AXPress`.
  - `:2930-2965`: every 25 ms verification sample combines a full reread with `CGWindowCaptureService.captureImage` until the 350 ms deadline.
  - `:2858-2867`: `ActionPerformanceDTO` is returned, but every phase except `totalMs` is currently `nil`.
- `Sources/BackgroundComputerUse/Actions/Click/NativeBackgroundClickTransport.swift:120-134` waits 50 ms after focus and 30 ms after every event. Its five-event single click therefore waits 200 ms; a seven-event double click waits 260 ms.
- `Sources/BackgroundComputerUse/Cursor/CursorModels.swift:246-265` defines 55 ms press lead and at least 280 ms approach duration. `Cursor/AXCursorTargeting.swift:134-142` blocks for approach settlement, sets pressed, then sleeps the lead. The runtime facade defaults `visualCursor` to disabled and maps it to `ActionExecutionOptions` (`App/BackgroundComputerUseRuntime.swift:3-23`); enabled cursor choreography is presentation, not dispatch correctness.
- `Sources/BackgroundComputerUse/Actions/TypeText/AdaptiveTextDispatcher.swift:39-73` already waits up to 25 × 20 ms for asynchronous Chromium `AXValue` application. `TypeTextRouteService.swift:309-320` then performs a second independent poll of up to 350 ms. Its response already records `captureMs`, `preparationMs`, `transportMs`, `settleMs`, `verificationMs`, and `totalMs` (`:411-419`).
- `Sources/BackgroundComputerUse/Actions/Shared/AXActionTargetResolver.swift:129-155` resolves the window, calls `RendererAccessibilityBootstrap.prepare`, and then captures state; its capture API currently has no route deadline parameter.
- `Sources/BackgroundComputerUse/Screenshot/CGWindowCaptureService.swift:90-99` always requests `boundsIgnoreFraming | bestResolution`. `ScreenshotCaptureService.swift:137-169` then resizes to the model fit and PNG-encodes it.
  - `ScreenshotCaptureService.swift:180-204` optionally encodes a raw PNG but always writes the model PNG to the captures directory.
  - `:234-252` base64 mode additionally creates base64 copies; it currently returns both path and base64.
  - `Contracts/RouteRequestContracts.swift:273-315` exposes `imageMode` and `includeRawScreenshot`; raw Retina output is explicitly opt-in.
  - `Contracts/ScreenshotCoordinateContract.swift:317-325` declares `screenshot-coordinate-contract.v1` and separate model-facing/raw planes. `:349-399` derives scale from actual pixel dimensions.
  - `API/APIDocumentation.swift:61-68` says `path` returns paths and `base64` inlines bytes, but does not state that base64 also creates files.
- `Sources/BackgroundComputerUse/Actions/Click/RendererAccessibilityBootstrap.swift` gates first capture for likely renderers.
  - `:55-73`: an AX focused-element observer is installed, but its callback is empty.
  - `:99-106`: likely renderers block in a 100 ms poll for up to 5 seconds.
  - `:131-169`: each probe traverses up to 500 elements with `queue.removeFirst()` and separately reads role, URL, DOM identifier, and children.
- `Sources/BackgroundComputerUse/Contracts/ActionPerformanceContracts.swift:3-27` is the existing phase-timing DTO. Populate it; do not add a parallel timing schema.
- `openspec/project.md:13-15` requires `Actions` → `StatePipeline/Cursor` layering, read-act-read, verifier-first classification, and reporting background errors rather than stealing focus. It also makes `GET /v1/routes` the contract source of truth.
- Plan 005 provides `python3 script/live_regression.py --output <path>`. The JSON has top-level `passed`/`fullyQualified` and lane objects with `name`, `status` (`pass|fail|known_limitation`), `durationMs`, `classification`, foreground PIDs, and an oracle. A known limitation is not a pass, even when the overall honest run is allowed to exit 0.

## Commands you will need

| Purpose | Command | Expected on success |
|---|---|---|
| Unit click/AX | `swift test --filter 'ClickFocusEvidenceTests|AXPointPressEligibilityTests|ClickFastVerificationPolicyTests'` | exit 0; selected tests pass |
| Unit cursor/text | `swift test --filter 'CursorDisabledExecutionTests|AdaptiveTextFallbackTests|AdaptiveTypeTextRouteTests|ConditionedActionWaitTests'` | exit 0; selected tests pass |
| Unit screenshot | `swift test --filter 'CursorScreenshotCompositorTests|WebReliabilityTests'` | exit 0; selected tests pass |
| Pure Python policy | `python3 -m unittest script.test_smoke_runtime` | exit 0 |
| Live baseline (authorized only) | `python3 script/live_regression.py --output .build/live-before.json` | exit 0; JSON `passed` is true |
| Final suite | `swift test` | exit 0; all tests pass |

## Scope

**In scope** (the only files you should modify or create):
- `Sources/BackgroundComputerUse/Actions/Click/ClickRouteService.swift`
- `Sources/BackgroundComputerUse/Actions/Click/NativeBackgroundClickTransport.swift`
- `Sources/BackgroundComputerUse/Actions/Click/RendererAccessibilityBootstrap.swift`
- `Sources/BackgroundComputerUse/Actions/Shared/ActionLatencyDeadline.swift` (create)
- `Sources/BackgroundComputerUse/Actions/Shared/AXActionTargetResolver.swift`
- `Sources/BackgroundComputerUse/Actions/TypeText/TypeTextRouteService.swift`
- `Sources/BackgroundComputerUse/Actions/TypeText/AdaptiveTextDispatcher.swift`
- `Sources/BackgroundComputerUse/Cursor/AXCursorTargeting.swift`
- `Sources/BackgroundComputerUse/Screenshot/CGWindowCaptureService.swift`
- `Sources/BackgroundComputerUse/Screenshot/ScreenshotCaptureService.swift`
- `Sources/BackgroundComputerUse/API/RouteRegistry.swift`
- `Sources/BackgroundComputerUse/API/APIDocumentation.swift`
- `Tests/BackgroundComputerUseTests/ClickFocusEvidenceTests.swift`
- `Tests/BackgroundComputerUseTests/AXPointPressEligibilityTests.swift`
- `Tests/BackgroundComputerUseTests/ConditionedActionWaitTests.swift`
- `Tests/BackgroundComputerUseTests/AdaptiveTypeTextRouteTests.swift`
- `Tests/BackgroundComputerUseTests/CursorScreenshotCompositorTests.swift`
- `Tests/BackgroundComputerUseTests/WebReliabilityTests.swift`
- `script/live_regression.py` and `script/test_smoke_runtime.py`
- `openspec/changes/optimize-action-capture-latency/{proposal.md,tasks.md,specs/screenshot-output/spec.md}` (create)
- `plans/README.md` status row only

**Out of scope**:
- Scroll strategy/reread changes (plan 008 owns them); this plan may reuse its deadline helper but must not reopen its ladder.
- Changing click success criteria, treating dispatch as effect, loosening destructive confirmation, or foregrounding the target.
- Changing model-facing dimensions, fit rule, coordinate origin, or coordinate-contract v1 semantics.
- Capture-directory retention/pruning (plan 017 owns resource bounds).
- AX observer/process cache eviction (plan 017); this plan only makes readiness signaling useful.
- Private symbol replacement, OCR worker lifecycle, or server request deadlines.

## Git workflow

- Branch: `advisor/023-click-scroll-latency-screenshot-bootstrap`
- Use logical commits in the observed style, for example `perf: bound click capture and screenshot latency`.
- Do not push or open a PR unless the operator instructs it.

## Steps

### Step 1: Record a live baseline and make existing phase timings visible

After explicit operator authorization, run the plan-005 Electron fixture before changing code. Extend `script/live_regression.py` so each lane copies the route response's existing `performance` object verbatim into `lane.performance` (or `{}` when the route has none). Update `script.test_smoke_runtime` to require finite, non-negative numeric values for fields that are present; do not invent zeroes for absent phases.

Replace `ClickRouteTiming`'s start-only task local with `@TaskLocal static var context: Context?`, where `Context` is a per-request `final class` containing `startedAtNanoseconds` plus optional/accumulated phase milliseconds. Declare it `@unchecked Sendable` with a comment that the synchronous route mutates it only on its request execution thread; do not add locks to each timestamp. Time initial capture, target resolve, cursor/preparation, transport, settle, and final verification; return them through the existing `ActionPerformanceDTO`. Accumulate repeated work into its owning phase. Use `DispatchTime.now().uptimeNanoseconds`, not wall-clock `Date`.

Save three pre-change runs as `.build/live-before.json`, `.build/live-before-2.json`, and `.build/live-before-3.json`; ensure the first run's `fixture.pid` is a newly launched fixture process so it is the cold-bootstrap baseline. For every later live file, a baseline `pass` lane must remain `pass`; `known_limitation` never counts as success.

**Verify**: `python3 -m unittest script.test_smoke_runtime && python3 script/live_regression.py --output .build/live-before.json && python3 script/live_regression.py --output .build/live-before-2.json && python3 script/live_regression.py --output .build/live-before-3.json` → policy tests pass; all three authorized JSON files have `passed: true`, lane performance objects, and no strict lane failure.

### Step 2: Remove full-tree/screenshot work from click retry and polling

Keep the initial capture. Replace the post-focus full capture with only: (1) a live focused-element identity, (2) live target-local state needed by the verifier, and (3) one clean baseline window image. Do not let focus caused by transport become intent evidence.

Replace `waitForPostDispatchEvidence` with cheap acknowledgement polling (focused element, target enabled/value/selection where applicable, and window identity/title). Do not capture a screenshot or full projected tree inside the poll. At the first acknowledgement or the remaining settle deadline, take one terminal image and one full reread. Thus each dispatched verification attempt has at most one baseline and one terminal image, and one post-dispatch full capture.

In coordinate→AX escalation, call `AXActionRuntimeSupport.hitTest` on every retry and inspect only that live candidate/its four ancestors. Require same PID, enabled state, frame containing the point, and `AXPress`; retain destructive-label confirmation. Delete the `targetResolver.reread` from the 12-attempt closure and remove the captured-tree fallback from retries. After `.pressed`, perform exactly one full reread for final AX effect verification. A transport success remains insufficient for `classification=success`.

Add injected-closure tests that count calls: twelve unavailable hit-tests cause zero rereads; the first eligible candidate stops retries; wrong PID/disabled/out-of-frame/no-press candidates never dispatch; one successful AX press causes exactly one post-press reread; verification polling captures exactly one before/after image pair rather than one per sample.

Run the live harness to `.build/live-after-click.json`, then compare strict lanes:

```sh
python3 -c 'import json,sys; b=json.load(open(sys.argv[1])); a=json.load(open(sys.argv[2])); bp={x["name"] for x in b["lanes"] if x["status"]=="pass"}; ap={x["name"] for x in a["lanes"] if x["status"]=="pass"}; lost=sorted(bp-ap); assert a["passed"] and not lost, {"lostPassLanes":lost}' .build/live-before.json .build/live-after-click.json
```

**Verify**: `swift test --filter 'ClickFocusEvidenceTests|AXPointPressEligibilityTests|ClickFastVerificationPolicyTests'` → selected tests pass; authorized live comparison exits 0 and click `performance.captureMs`, `verificationMs`, and `totalMs` are recorded for before/after review.

### Step 3: Replace stacked sleeps with acknowledgements and one monotonic budget

Create `ActionLatencyDeadline` with an absolute uptime-nanosecond expiry, injected `now` for tests, `remainingMilliseconds`, and `clamped(milliseconds:)`. Initialize one at each click/type-text route entry; use a 5,000 ms compatibility ceiling and pass the same instance through `AXActionTargetResolver.capture`, renderer bootstrap, dispatch settle, optional retry, and final verification. Add an optional deadline parameter (default `nil` for unaffected routes) to the resolver rather than creating a second clock inside capture. The deadline is a soft scheduling bound and cannot preempt an in-flight AX call. If expired after dispatch, do not redispatch: perform the required final evidence read if possible and report `effect_not_verified` with a deadline warning.

Remove the unconditional 50 ms focus wait and 30 ms post-event waits in `NativeBackgroundClickTransport`: successful `preparedTargetWindow` is the focus acknowledgement, and posting remains ordered. Do not retain a spacing delay without a dated comment naming the measured app/event failure. Tests must assert event order and an empty wait trace.

Make visual coordinate-click choreography asynchronous like `prepareSemanticClick`: start approach, schedule pressed/release through `CursorRuntime.scheduleSemanticClickChoreography`, return immediately with movement `asynchronous_click_choreography`, and ensure `finishClick` does not schedule a second release. Cursor-disabled behavior remains unchanged.

In type-text, pass a deadline-clamped `AdaptiveTextSettle` into `AdaptiveTextDispatcher` so its Chromium duplicate-prevention polling and the route verifier consume one budget. Use `dispatchResult.finalObservedValue` as the first route-settle sample. If it already satisfies `ExactTextSettlePolicy`, return a zero-extra-poll settle result; otherwise poll only for the deadline's remaining time. Never remove the adaptive poll or fall back merely because the budget expired after a successful AX write.

Run three identical authorized fixtures as `.build/live-after-pacing-1.json`, `-2.json`, and `-3.json`; apply the Step 2 strict-lane comparator to each file before comparing medians. Compare median click/type-text `performance.transportMs`, `settleMs`, and `totalMs` against three baseline runs made before this step. Code-derived expected savings are about 200 ms per single coordinate transport, 260 ms per double transport, at least 335 ms of synchronous visual-cursor waiting when enabled, and up to 350 ms for already-settled text. These are removed waits, not measured route gains.

**Verify**: `swift test --filter 'ClickFocusEvidenceTests|CursorDisabledExecutionTests|AdaptiveTextFallbackTests|AdaptiveTypeTextRouteTests|ConditionedActionWaitTests'` → tests pass; authorized live comparison exits 0 and click/type-text `transportMs`, `settleMs`, and `totalMs` do not regress in median across three identical runs.

### Step 4: Capture only the requested screenshot resolution/output destination

Create an internal capture request enum with `.modelFacing(targetPixelSize:)` and `.rawRetina`. Model/evidence capture must omit `.bestResolution`, then draw the root and every attached surface directly into one context of the predicted model pixel size; raw capture includes `.bestResolution` and retains the source image before deriving the model image. Pass `ScreenshotFitRule.predictedModelSize` into `CGWindowCaptureService` so the model path does not first allocate a best-resolution composite. The returned model dimensions and scales must remain unchanged.

In `ScreenshotCaptureService`, write PNG files only for `imageMode == .path`. For `.base64`, return inline PNG bytes with `imagePath == nil` for both model and optional raw images; do not create a captures-directory file. Continue encoding raw PNG only when `includeRawRetinaCapture` is true.

Because base64 path presence is public behavior, create OpenSpec slug `optimize-action-capture-latency`. `proposal.md` must contain `## Why`, `## What Changes`, and `## Impact`; `tasks.md` must check off implementation/tests and end with `swift test`, strict OpenSpec validation, and the authorized live smoke; `specs/screenshot-output/spec.md` must add a SHALL requirement with scenarios: `path` returns a file path, `base64` returns inline bytes with nil paths and no file write, raw resolution is opt-in, and model dimensions/mapping stay v1. Update every `RouteRegistry` request field that accepts `imageMode` plus the global `APIDocumentation` concept. Do **not** bump `ScreenshotCoordinateContract.currentVersion`: output dimensions and coordinate semantics must remain byte-for-byte compatible. If that is impossible, STOP; a v2 migration is not authorized by this plan.

Tests must inject a solid image and temporary output directory/writer: path mode writes once; base64 mode writes zero times and has nil paths; omit captures/encodes/writes zero times; raw false selects nominal options; raw true selects best resolution; model dimensions, top-left origin, scale, and `screenshot-coordinate-contract.v1` remain identical.

Run three authorized identical `get_window_state` lanes to `.build/live-after-screenshot-1.json`, `-2.json`, and `-3.json`. Apply the Step 2 strict-lane comparator to every file, then compare median `performance.screenshotMs` against three matching pre-change runs. Expected pixel traffic is roughly 75% lower for a 2× Retina source when nominal capture is sufficient, but this is a code-derived estimate.

**Verify**: `swift test --filter 'CursorScreenshotCompositorTests|WebReliabilityTests' && if command -v openspec >/dev/null; then openspec validate optimize-action-capture-latency --strict; else echo 'SKIP: openspec not installed'; fi` → screenshot tests pass; OpenSpec reports valid or the explicit skip is printed; all three authorized strict-lane comparisons against `.build/live-before.json` exit 0.

### Step 5: Make renderer readiness event-driven and traversal linear

Add a retained per-process readiness signal next to each observer. Pass it as the AX notification refcon; the callback must only `signal()` a `DispatchSemaphore`—no AX calls in the callback. Pass the route's `ActionLatencyDeadline` through `AXActionTargetResolver.capture` into `prepare`. Probe immediately, then wait for notification or a 500 ms fallback interval until the smaller of remaining route time and the 5-second compatibility ceiling. A notification wakes a readiness probe immediately; renderers that emit no useful notification still get low-frequency fallback probes.

Rewrite `contentRendererTreeReady` with an integer queue cursor (`while cursor < queue.count`) rather than `removeFirst`. For each element, use one `AXUIElementCopyMultipleAttributeValues` request for role, URL, DOM identifier, and children; tolerate unsupported/partial values without converting readiness to true. Preserve max 500 elements and depth 10.

Factor traversal over an injected attribute-reader so tests can model a graph. Cover: observer signal wakes before fallback; no signal probes at 500 ms cadence and times out; a deep DOM identifier returns true; `view_` identifiers remain excluded; partial/malformed batched values return false; a 500-node graph visits each node once. Do not add observer eviction here.

Measure the first renderer capture in a fresh Electron fixture process to `.build/live-after-bootstrap.json`; compare `performance.captureMs` and `totalMs` with a fresh-process baseline, not a warm run. Run the exact Step 2 strict-lane comparator with `.build/live-before.json` and `.build/live-after-bootstrap.json`; STOP on any lost pass lane.

**Verify**: `swift test --filter AXPointPressEligibilityTests` → readiness tests pass; authorized fresh-process live comparison exits 0 and records first-capture timings.

### Step 6: Run the integrated gate once

Run all focused tests, pure Python policy tests, and the full Swift suite once. Run `./script/verify.sh --live` only with renewed operator authorization. Review before/after JSON: no baseline pass lane became fail or known limitation; `foregroundPIDBefore == foregroundPIDAfter` wherever the lane requires background safety; no success lacks oracle evidence.

**Verify**: `python3 -m unittest script.test_smoke_runtime && swift test` → all tests pass; authorized `./script/verify.sh --live` exits 0 with `passed: true`.

## Test plan

- Click tests: no full reread in hit-test retries, one reread after AX press, bounded cheap polling, one image pair, PID/geometry/action/safety rejection, verifier remains effect-based.
- Transport/deadline/cursor tests: event order without waits, absolute monotonic remaining time, expiry cannot cause redispatch, asynchronous visual cursor, disabled cursor unchanged.
- Type-text tests: dispatcher-observed exact value skips the second poll; stale value polls only remaining budget; Chromium duplicate-prevention settle remains.
- Screenshot tests: resolution flag, attached-surface consistency, path/base64/omit destinations, raw opt-in, v1 pixel/scale parity.
- Bootstrap tests: notification wake, low-frequency fallback, batched partial reads, index BFS, caps/depth.
- Live Electron regression: strict pass-lane set cannot shrink after any sub-part; timing fields are evidence, not hard thresholds.

## Done criteria

- [ ] No `targetResolver.reread` occurs inside the 12-attempt AX point retry.
- [ ] No screenshot or full tree capture occurs per 25 ms click verification sample.
- [ ] A successful AX press has exactly one final full reread; dispatch alone is never success.
- [ ] Native click transport has no undocumented fixed wait; enabled visual cursor no longer blocks dispatch.
- [ ] Type-text does not repeat a 350 ms settle after the dispatcher already observed the expected value.
- [ ] Model-only capture omits best resolution; base64 creates no screenshot files; raw remains opt-in.
- [ ] Coordinate-contract v1 dimensions/origin/scales are unchanged.
- [ ] Renderer bootstrap uses observer signaling, 500 ms fallback, batched attributes, and index BFS.
- [ ] Every baseline pass lane remains pass after each live checkpoint; all unit/full tests pass.
- [ ] No files outside Scope are modified, except the assigned `plans/README.md` row.

## STOP conditions

Stop and report back (do not improvise) if:

- Plan 005's live fixture/harness or plan 008's settled scroll behavior is absent.
- The operator does not authorize before/after live runs; this HIGH-risk timing change cannot be accepted on unit tests alone.
- Any baseline `pass` lane becomes `fail` or `known_limitation`, overall `passed` becomes false, foreground restoration regresses, or click success loses oracle evidence.
- Direct hit-testing cannot enforce PID, enabled, frame containment, press action, and confirmation without a full reread.
- Removing event spacing drops/reorders a live click. Revert that sub-part and report; do not guess a new sleep.
- Model pixel dimensions/scales change, attached surfaces misalign, or contract v1 would need reinterpretation.
- AX notifications do not wake the test semaphore safely or require AX work inside the callback.
- A verification command fails twice after one focused correction, or an out-of-scope file is required.

## Maintenance notes

- Keep performance fields phase-specific and monotonic; `nil` means not measured, never zero by convenience.
- A fixed input spacing is allowed only with a dated, reproducible measurement comment and a regression test for that exact event boundary.
- Notification delivery varies across Chromium/Electron versions; retain the low-frequency fallback and caps.
- Base64's no-file behavior is now contract documentation; future “both” output needs a new explicit mode, not a hidden write.
- Reviewers should scrutinize verifier baselines around focus-without-raise and ensure latency work never upgrades a transport acknowledgement into proof of user-visible effect.