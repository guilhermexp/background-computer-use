# Plan 004: Add a sanitized real-application AX fixture corpus and route orchestration seam

> **Executor instructions**: Follow this plan step by step. Run every verification command and confirm the expected result before moving to the next step. If anything in the "STOP conditions" section occurs, stop and report — do not improvise. When done, update the status row for this plan in `plans/README.md` unless a reviewer told you they maintain the index. Do not launch or install BCU, Electron, or any target application until the operator explicitly authorizes the live-recording step.
>
> **Drift check (run first)**: `git diff --stat 0110ffb..HEAD -- Package.swift Sources/BackgroundComputerUse/StatePipeline/AXPipelineV2/State Sources/BackgroundComputerUse/Actions/Shared/AXActionTargetResolver.swift Sources/BackgroundComputerUse/Actions/TypeText/TypeTextRouteService.swift Sources/BackgroundComputerUse/Actions/Click/ClickRouteService.swift Tests/BackgroundComputerUseTests`
> If any in-scope file changed since this plan was written, compare the "Current state" excerpts against the live code before proceeding; on a mismatch, treat it as a STOP condition. Also run `git status --short` and `git log --oneline 0110ffb..HEAD -- Sources/BackgroundComputerUse/API/Router.swift Sources/BackgroundComputerUse/App/BackgroundComputerUseControlBridge.swift Sources/BackgroundComputerUseControlShared/CodeSignatureIdentity.swift Sources/BackgroundComputerUse/Runtime/RuntimeExecutionQueue.swift Sources/BackgroundComputerUse/Actions/TypeText/AdaptiveTextDispatcher.swift Sources/BackgroundComputerUse/StatePipeline/InteractionToken.swift Sources/BackgroundComputerUse/Runtime/Process/BoundedProcessRunner.swift skills/background-computer-use/scripts/bcu-request.py Tests/BackgroundComputerUseTests/InteractionTokenTests.swift Tests/BackgroundComputerUseTests/RuntimeExecutionQueueTests.swift`. Every named baseline fix must be either modified in the working tree or present in a post-`0110ffb` commit; otherwise STOP.

## Status

- **Priority**: P1
- **Effort**: L
- **Risk**: MED
- **Depends on**: `plans/002-ci-and-verify-gate.md`
- **Category**: tests
- **Planned at**: commit `0110ffb`, 2026-09-02

## Why this matters

The green Swift suite mostly tests mutation policies through injected closures, while the failures observed on Electron involved real AX topology, asynchronous renderer state, and window-chrome churn. A sanitized recorded corpus makes those real tree shapes deterministic and safe to commit. A narrow capture/transport seam then lets tests drive the actual read-act-read route orchestration without touching live Accessibility or posting real input.

## Current state

- `Package.swift:85-98` declares the test target at `Tests/BackgroundComputerUseTests` with no resources. Therefore the requested repository-level `Tests/Fixtures/AX` cannot be referenced by `.copy("Fixtures")` without moving the target root; use `Tests/BackgroundComputerUseTests/Fixtures/AX` instead:
  ```swift
  .testTarget(
      name: "BackgroundComputerUseTests",
      dependencies: [
          "BackgroundComputerUse",
          "BackgroundComputerUseControlShared",
          "BackgroundComputerUseControl",
          "BackgroundComputerUseLockedShared",
          "BackgroundComputerUseLockedBroker",
          "BCUAuthorizationPlugin",
          "BackgroundComputerUseLockedInstaller",
          .product(name: "Testing", package: "swift-testing"),
      ],
      path: "Tests/BackgroundComputerUseTests"
  )
  ```
- `StatePipelineExperiment.swift:456-474` already creates and returns a Codable fixture from every resolved live capture:
  ```swift
  let fixture = AXPipelineV2Fixture(
      generatedAt: Time.iso8601String(from: generatedAt),
      scenarioID: scenarioID,
      targetPID: resolved.app.processIdentifier,
      includeMenuBar: includeMenuBar,
      menuMode: effectiveMenuMode,
      maxNodes: maxNodes,
      window: window,
      rawCapture: rawCapture,
      platformProfile: platformProfile,
      menuPresentation: menuContext.menuPresentation,
      notes: responseNotes
  )
  ```
- `StatePipelineExperiment.swift:477-598` already has `replayFixture`, `loadFixture`, and atomic `saveFixture`; none is wired to test resources or a developer exporter.
- `AXPipelineV2Contracts.swift:275-310` shows the raw node payload. Sensitive text can occur in `roleDescription`, `title`, `placeholder`, `description`, `help`, `identifier`, `domIdentifier`, `url`, `valueDescription`, `value.preview`, nested identity/refetch signatures, action labels/descriptions, and `textExtraction` text variants. Preserve indices, depth, child links, roles/subroles, geometry, action raw names, parameterized attributes, booleans, `isValueSettable`, interaction traits, and truncation.
- `AdaptiveTextFallbackTests.swift:71-90` models Electron lag with a hand-authored string queue and injected closures; it never drives `TypeTextRouteService`.
- `AXActionTargetResolver.swift:120-185` owns the live boundary: its initializer accepts only `executionOptions`; `capture(...)` resolves a live window and `reread(after:imageMode:)` calls `capture` again.
- `TypeTextRouteService.swift:14-26` and `ClickRouteService.swift:214-221` construct `AXActionTargetResolver` internally. Click also constructs `NativeBackgroundClickTransport` at line 212, preventing scripted captures/fake transport injection.
- `WindowStatePayloadParityTests.swift:313-404` replays a synthetic, hand-built fixture. Use its DTO-construction style only for sanitizer unit tests; recorded regression tests must load JSON resources.
- Project rules in `openspec/project.md:13-15` require Actions to consume StatePipeline (never reverse), every mutating route to follow capture → validate → resolve → gate → cursor → dispatch → reread/verify, and a dispatched transport never to substitute for verifier evidence. Background failures must be reported rather than hidden by stealing focus.
- Tests use Swift Testing (`import Testing`, `@Suite`, `@Test`, `#expect`, `#require`) per `openspec/project.md:7-9`; do not add XCTest.

## Commands you will need

| Purpose | Command | Expected on success |
|---|---|---|
| Focused sanitizer tests | `swift test --filter AXFixtureSanitizerTests` | exit 0; all sanitizer tests pass |
| Recorded replay tests | `swift test --filter RecordedAXRouteRegressionTests` | exit 0; all seven fixture cases pass on a 512 KiB thread |
| Orchestration test | `swift test --filter RecordedAXActionOrchestrationTests` | exit 0; one delayed-commit test passes with one dispatch |
| Fixture JSON validation | `python3 -m json.tool Tests/BackgroundComputerUseTests/Fixtures/AX/electron-deep-tree.json >/dev/null` | exit 0 |
| Final gate | `swift test` | exit 0; all tests, including the new suites, pass |

## Scope

**In scope** (the only files you should modify):
- `Package.swift`
- `Sources/BackgroundComputerUse/StatePipeline/AXPipelineV2/State/AXFixtureSanitizer.swift` (create)
- `Sources/BackgroundComputerUse/StatePipeline/AXPipelineV2/State/StatePipelineExperiment.swift`
- `Sources/BackgroundComputerUse/Actions/Shared/AXActionTargetResolver.swift`
- `Sources/BackgroundComputerUse/Actions/TypeText/TypeTextRouteService.swift`
- `Sources/BackgroundComputerUse/Actions/Click/ClickRouteService.swift`
- `Tests/BackgroundComputerUseTests/AXFixtureSanitizerTests.swift` (create)
- `Tests/BackgroundComputerUseTests/RecordedAXRouteRegressionTests.swift` (create)
- `Tests/BackgroundComputerUseTests/RecordedAXActionOrchestrationTests.swift` (create)
- `Tests/BackgroundComputerUseTests/Fixtures/AX/*.json` (create the seven named corpus files below)

**Out of scope** (do NOT touch):
- Any authenticated or unauthenticated HTTP fixture-export route, RouteRegistry entry, public DTO field, or runtime facade method.
- Real AX or real keyboard/mouse transports in tests.
- Whole-response snapshots; they are brittle across projection improvements.
- `Tests/Fixtures/Apps/BCUElectronFixture/` and live regression scripts; those belong to plan 005.
- Production retry/fallback policy changes in `AdaptiveTextDispatcher`; this plan adds orchestration coverage, not another settle algorithm.

## Git workflow

- Branch: `advisor/004-real-app-ax-fixture-corpus`
- Commit logical units with the repository’s conventional style, for example `test: add sanitized AX fixture corpus` and `refactor: inject action capture boundary`.
- Do not push or open a PR unless the operator instructs it.

## Steps

### Step 1: Add a fail-closed, fixed-placeholder fixture sanitizer

Create `AXFixtureSanitizer.swift`. Avoid manually rebuilding every DTO: encode `StatePipelineFixture` with `JSONSupport.encoder`, recursively sanitize the JSON object, re-encode, and decode the same type. Use one constant `"<redacted>"`. Replace string values under exactly these keys: `roleDescription`, `title`, `placeholder`, `description`, `help`, `identifier`, `domIdentifier`, `url`, `urlHost`, `value`, `valueDescription`, `preview`, `valuePreview`, `text`, `attributedText`, `selectedText`, `selectedAttributedText`, `label`, `sourceTitle`, `sourceURL`, `bundlePath`, `activeTopLevelTitle`, `activePathTitles`, `pathTitles`, `notes`, `note`, `warnings`, and `metadata`. If `value` holds the nested `ValueSummaryDTO` object rather than a string, recurse into it so `preview` is still redacted. For an array keyed by one of those names, preserve its count and replace every string member. Preserve `bundleID`, `scenarioID`, roles, subroles, paths/indices, node IDs/fingerprints, frames, actions, settable flags, and booleans. Throw if the sanitized object cannot round-trip:

```swift
enum AXFixtureSanitizer {
    static let placeholder = "<redacted>"
    static func sanitize(_ fixture: StatePipelineFixture) throws -> StatePipelineFixture
}
```

In `AXFixtureSanitizerTests.swift`, build a small fixture containing a sentinel such as `PRIVATE_FIXTURE_SENTINEL` in every sensitive family, recursively assert that no encoded string contains it, and assert exact preservation of `role`, `subrole`, `frameAppKit`, `secondaryActions`, `availableActions[].rawName`, `parameterizedAttributes`, `isValueSettable`, `interactionTraits`, `childIndices`, and `rawCapture.truncated`.

**Verify**: `swift test --filter AXFixtureSanitizerTests` → exit 0; the sentinel-leak and structural-preservation tests pass.

### Step 2: Export only sanitized fixtures from explicit debug builds

In `captureResolvedWindow`, after constructing `fixture` and before returning it, call a private `exportFixtureIfRequested(_:)` only inside `#if DEBUG`. Read `BCU_FIXTURE_EXPORT_DIR`; do nothing when absent. Reject an empty or relative path with a new descriptive `StatePipelineExperimentError.invalidFixtureExportDirectory`. Sanitize before any write, generate an opaque collision-free filename (`UUID().uuidString.lowercased() + ".json"`), and call existing `saveFixture`. Let enabled-export failures propagate: a developer who explicitly enabled capture must not receive a false-success request while no fixture was written. Never write the unsanitized fixture, even temporarily.

Add a unit test that supplies an export directory through an injectable environment lookup/file writer helper (do not mutate process-global environment in parallel tests), verifies the saved JSON contains the placeholder and no sentinel, and verifies the disabled helper performs no write.

**Verify**: `swift test --filter AXFixtureSanitizerTests` → exit 0; enabled, disabled, relative-path, and no-unsanitized-write cases pass.

### Step 3: Wire and record the initial real-app corpus

Apply this exact `Package.swift` shape (the comma after `path` is required):

```diff
-            path: "Tests/BackgroundComputerUseTests"
+            path: "Tests/BackgroundComputerUseTests",
+            resources: [.copy("Fixtures")]
```

Create these files: `electron-deep-tree.json` (Electron/VS Code or kanwas with a chat textarea and roughly 70 AX levels); `electron-window-chrome-flap-a.json` and `electron-window-chrome-flap-b.json` (two immediate consecutive captures without user interaction); `safari-textarea.json` (Safari page with focused textarea); `finder-window.json` (Finder list window); `textedit-document.json` (TextEdit document with insertion point); and `system-settings.json` (System Settings detail page). Each capture must use `maxNodes: 6500`, omit screenshots, and keep the exporter’s sanitized JSON unchanged except for renaming the file.

Live recording is operator-authorized: start a DEBUG runtime with `BCU_FIXTURE_EXPORT_DIR="$PWD/.build/ax-fixture-export"`, use `skills/background-computer-use/scripts/bcu-request.py POST /v1/list_apps '{}'`, resolve the chosen PID through `/v1/list_windows`, then call `/v1/get_window_state` for its window. For the flap pair call state twice without touching the app. Inspect committed JSON mechanically for `"<redacted>"`; never replace placeholders with real text. Stop the runtime after recording.

**Verify**: `python3 -c 'import json,pathlib; p=pathlib.Path("Tests/BackgroundComputerUseTests/Fixtures/AX"); fs=sorted(p.glob("*.json")); assert len(fs)==7; [json.loads(f.read_text()) for f in fs]; assert all("<redacted>" in f.read_text() for f in fs)'` → exit 0 with exactly seven decodable sanitized fixtures.

### Step 4: Replay every real tree under the production-small stack constraint

Create `RecordedAXRouteRegressionTests.swift`. Load each fixture with `Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "AX")`, then `StatePipelineExperiment().loadFixture(at:)` and `replayFixture(_:imageMode: .omit)`. Run replay on a dedicated thread with the same 512 KiB stack size as Network.framework workers:

```swift
let finished = DispatchSemaphore(value: 0)
nonisolated(unsafe) var result: Result<StatePipelineEnvelope, Error>?
let thread = Thread {
    result = Result { StatePipelineExperiment().replayFixture(fixture, imageMode: .omit) }
    finished.signal()
}
thread.stackSize = 512 * 1024
thread.start()
finished.wait()
let envelope = try #require(result).get()
```

Assert: replay completes for all seven; `response.tree.truncated == fixture.rawCapture.truncated`; every projected node whose `displayRole == "text entry area"` has a nonempty `nodeID`; and the two flap fixtures have identical `interactionToken`. For the deep Electron and Safari fixtures, adapt the replay response to a minimal `GetWindowStateResponse` with zeroed performance and no OCR/debug, then call `FindElementsRouteService.response(from:request:)` with `FindElementsRequest(window: fixture.window.windowID, role: "text entry area", text: AXFixtureSanitizer.placeholder)`. Assert at least one match and a nonempty `nodeID`; do not duplicate the service's private matching algorithm or expect the redacted original word “Composer”.

**Verify**: `swift test --filter RecordedAXRouteRegressionTests` → exit 0; stack, truncation, node identity, flap-token, and composer-query invariants pass.

### Step 5: Inject captures and fake transports at the existing action boundary

In `AXActionTargetResolver.swift`, define `AXActionStateProviding` with the exact existing `capture(windowID:includeMenuBar:menuPathComponents:webTraversal:maxNodes:imageMode:includeCursorOverlay:)` and `reread(after:imageMode:)` signatures. Move current live code into `LiveAXActionStateProvider`; let `AXActionTargetResolver` store `any AXActionStateProviding` and default it in its initializer. Keep target matching/resolution on `AXActionTargetResolver`.

Add optional injection parameters without changing production call sites:

```swift
AXActionTargetResolver.init(
    executionOptions: ActionExecutionOptions = .visualCursorEnabled,
    stateProvider: any AXActionStateProviding = LiveAXActionStateProvider()
)
TypeTextRouteService.init(
    executionOptions: ActionExecutionOptions = .visualCursorEnabled,
    backgroundTextPreparation: BackgroundTextPreparation = .live,
    foregroundApplication: @escaping @Sendable () -> ForegroundApplicationSnapshot? = ForegroundApplicationSnapshot.capture,
    foregroundFallbackCoordinator: ForegroundFallbackCoordinator? = nil,
    targetResolver: AXActionTargetResolver? = nil,
    actionRuntime: TypeTextActionRuntime = .live
)
ClickRouteService.init(
    executionOptions: ActionExecutionOptions = .visualCursorEnabled,
    ocrRecognitionService: OCRRecognitionService = .live,
    targetResolver: AXActionTargetResolver? = nil,
    coordinateTransport: NativeBackgroundClickTransport = NativeBackgroundClickTransport(),
    performAXAction: @escaping (String, AXUIElement) -> AXError = AXActionRuntimeSupport.performAction
)
```

`TypeTextActionRuntime` is an internal closure bundle for `readTextState` and the existing high-level `dispatchText` operation; extract the current private `TextDispatchResult` to file scope so a fake can return it. Do not abstract policy or DTOs. In the test provider, replay JSON into `AXActionStateCapture`, map projected canonical indices to inert `AXUIElementCreateApplication(getpid())` handles, and never invoke those handles because fake transport/runtime closures intercept I/O.

Add `RecordedAXActionOrchestrationTests.delayedElectronCommitRereadsTwiceWithoutRedispatch`: scripted captures are baseline pre-capture, baseline first reread, expected-text second reread; fake type transport increments `dispatchCount` and reports one accepted AX dispatch; post-dispatch verification polls rereads until expected projected value appears. Assert `dispatchCount == 1`, no Unicode/fallback dispatch, exactly two rereads, and final `classification == .success`. The reread loop must never call transport again.

**Verify**: `swift test --filter RecordedAXActionOrchestrationTests` → exit 0; delayed commit consumes two rereads and exactly one dispatch.

### Step 6: Run the complete deterministic gate

Run focused suites first, then the full suite once. Confirm only in-scope files changed and no exported working files or private values were committed.

**Verify**: `swift test` → exit 0; all existing and new tests pass with no live app or Accessibility permission.

## Test plan

- `AXFixtureSanitizerTests`: sensitive scalar/array redaction, structural preservation, disabled export, absolute-path enforcement, and sanitized-only write.
- `RecordedAXRouteRegressionTests`: seven resource loads, 512 KiB projection, truthful truncation, text-entry node identity, Electron flap token equality, and real find-elements response matching.
- `RecordedAXActionOrchestrationTests`: baseline → stale baseline → delayed expected state with one transport dispatch and verifier-first success.
- Model Swift Testing style after `AdaptiveTextFallbackTests.swift`; model fixture construction after `WindowStatePayloadParityTests.swift:313-404`.
- Verification: `swift test --filter 'AXFixtureSanitizerTests|RecordedAXRouteRegressionTests|RecordedAXActionOrchestrationTests'` → all new tests pass.

## Done criteria

- [ ] Exactly seven sanitized JSON fixtures exist under `Tests/BackgroundComputerUseTests/Fixtures/AX` and load through `Bundle.module`.
- [ ] No raw title, value, URL, path, identifier, extracted text, note, warning, or action label survives sanitizer tests.
- [ ] Every fixture replays on a `512 * 1024`-byte thread stack; truncation and node-ID invariants pass.
- [ ] Electron chrome-flap fixtures produce identical interaction tokens.
- [ ] TypeText delayed-commit orchestration dispatches once and verifies after two rereads; Click and TypeText constructors accept fake capture/transport dependencies.
- [ ] `swift test` exits 0 without live AX access.
- [ ] `git status --short` shows no files outside Scope, apart from the required pre-existing baseline changes named in the drift check.
- [ ] `plans/README.md` marks plan 004 DONE.

## STOP conditions

Stop and report back (do not improvise) if:
- Any baseline file named in the drift check is neither modified nor committed after `0110ffb`.
- SwiftPM rejects resource files outside the target root; do not move the entire test target to satisfy the stale `Tests/Fixtures/AX` lead.
- The sanitizer would need to preserve user text for a regression assertion; change the assertion to structural metadata instead.
- The operator does not authorize launching a DEBUG BCU runtime and target apps for corpus recording, or required Accessibility/Screen Recording permissions are unavailable.
- A test seam starts changing the public HTTP contract or requires real AX/input I/O in deterministic tests.
- A verification command fails twice after a reasonable fix attempt.

## Maintenance notes

- When fixture DTO fields are added, update the sensitive-key allowlist test before recording new fixtures; default review posture is that new free-form strings are sensitive.
- Keep recorded assertions invariant-based. Exact rendered text, node counts, timestamps, and full JSON snapshots will make harmless projection improvements expensive.
- Review the seam for abstraction creep: only capture/reread and route transport I/O are injectable; target resolution and outcome policy remain production code.
- A later StatePipeline cleanup may move `loadFixture`/`saveFixture`/`replayFixture`; migrate these callers rather than recreating aliases.
