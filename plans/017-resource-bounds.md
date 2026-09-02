# Plan 017: Bound capture artifacts and process-lifetime window resources

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**: `git diff --stat 0110ffb..HEAD -- Sources/BackgroundComputerUse/Screenshot/CaptureArtifactStore.swift Sources/BackgroundComputerUse/Screenshot/ScreenshotCaptureService.swift Sources/BackgroundComputerUse/StatePipeline/WindowStateService.swift Sources/BackgroundComputerUse/StatePipeline/WindowAnnotationService.swift Sources/BackgroundComputerUse/StatePipeline/AXPipelineV2/State/StatePipelineExperiment.swift Sources/BackgroundComputerUse/Actions/Shared/AXActionTargetResolver.swift Sources/BackgroundComputerUse/Actions/Click/ClickRouteService.swift Sources/BackgroundComputerUse/Actions/PressKey/PressKeyRouteService.swift Sources/BackgroundComputerUse/Actions/SecondaryAction/SecondaryActionRouteService.swift Sources/BackgroundComputerUse/Actions/Text/TextRouteService.swift Sources/BackgroundComputerUse/Actions/WaitFor/WaitForRouteService.swift Sources/BackgroundComputerUse/App/RuntimeBootstrap.swift Sources/BackgroundComputerUse/Runtime/RuntimeExecutionQueue.swift Sources/BackgroundComputerUse/Window/WindowTargetCache.swift Sources/BackgroundComputerUse/Actions/Click/RendererAccessibilityBootstrap.swift Sources/BackgroundComputerUse/Contracts/RouteRequestContracts.swift Sources/BackgroundComputerUse/API/RouteRegistry.swift Tests/BackgroundComputerUseTests/CaptureArtifactStoreTests.swift Tests/BackgroundComputerUseTests/CursorScreenshotCompositorTests.swift Tests/BackgroundComputerUseTests/RuntimeEnhancementTests.swift Tests/BackgroundComputerUseTests/RuntimeExecutionQueueTests.swift Tests/BackgroundComputerUseTests/WindowTargetCacheTests.swift Tests/BackgroundComputerUseTests/APIDocumentationTests.swift Tests/BackgroundComputerUseTests/RuntimeFacadePublicAPITests.swift openspec/changes/bound-runtime-resources plans/README.md`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P2
- **Effort**: M
- **Risk**: MED
- **Depends on**: none
- **Category**: bug
- **Planned at**: commit `0110ffb`, 2026-09-02

## Why this matters

Every state-changing screenshot token currently creates retained PNGs, including base64-only responses; a live session accumulated 44 files in one afternoon. Long-lived runtimes also retain one queue per supplied window ID, cached window metadata for dead processes, and AX observers/run-loop sources for terminated renderer processes. This plan gives disk and memory resources explicit lifecycle bounds while preserving recent client-visible paths and in-flight window serialization.

## Current state

- `Sources/BackgroundComputerUse/Screenshot/ScreenshotCaptureService.swift` always persists encoded images.
  - `ScreenshotCaptureService.swift:167-182`: model and optional raw images are encoded as PNG before output selection.
  - `ScreenshotCaptureService.swift:184-204`: model and raw PNGs are always written under `$TMPDIR/background-computer-use/captures`.
  - `ScreenshotCaptureService.swift:234-255`: base64 is conditional, but `imagePath` is still populated from the unconditional write.
  - `ScreenshotCaptureService.swift:361-383`: a missing path is always reported as a persistence error, so intentional base64-only output needs explicit handling.
- `Sources/BackgroundComputerUse/StatePipeline/WindowAnnotationService.swift` adds another retained artifact.
  - `WindowAnnotationService.swift:11-45`: annotation currently requires the base screenshot's file path.
  - `WindowAnnotationService.swift:269-317`: the renderer always writes the annotated PNG, then optionally also base64-encodes it.
- `OCRRecognitionService.swift:55-83` already provides the correct transient-file contrast: CGImage OCR writes a UUID input and deletes it in `defer`. Reuse that overload rather than making base64 screenshots permanent for OCR.
- `Sources/BackgroundComputerUse/Runtime/RuntimeExecutionQueue.swift` owns process-global dispatch queues.
  - `RuntimeExecutionQueue.swift:10-15`: `windowQueues` is an unbounded dictionary.
  - `RuntimeExecutionQueue.swift:43-49`: reads and barrier writes select a queue by caller-supplied window ID.
  - `RuntimeExecutionQueue.swift:83-98`: every unseen ID inserts a concurrent queue and no entry is removed.
  - `RuntimeExecutionQueue.swift:22-28`: every scoped unit intentionally runs on a dedicated 64 MiB-stack pthread; preserve this current fix.
- `RuntimeCoordinator.swift:8-24` selects the window queue before route work validates the window; invalid unique IDs can therefore allocate queues.
- `Sources/BackgroundComputerUse/Window/WindowTargetCache.swift:11-49` has a locked dictionary with remember, lookup, and explicit single-ID removal, but no dead-process pruning.
- `WindowTargetResolver.swift:28-31` consults that cache first; lines 153-167 remove an entry only when the same stale ID is resolved again.
- `Sources/BackgroundComputerUse/Actions/Click/RendererAccessibilityBootstrap.swift` retains renderer state for process lifetime.
  - `RendererAccessibilityBootstrap.swift:10-16`: prepared process keys and observers are static collections.
  - `RendererAccessibilityBootstrap.swift:49-73`: prepare inserts a process key, creates an `AXObserver`, adds its source to the main run loop, and retains it forever.
- Public-contract rules from `openspec/project.md:13-15`: `Contracts` remains a leaf, and every real request/response field must match `GET /v1/routes`.
- OpenSpec format and validation are defined at `openspec/project.md:25-29`.

## Commands you will need

| Purpose | Command | Expected on success |
|---|---|---|
| Prerequisite check | `git status --short -- Sources/BackgroundComputerUse/API/Router.swift Sources/BackgroundComputerUse/App/BackgroundComputerUseControlBridge.swift Sources/BackgroundComputerUseControlShared/CodeSignatureIdentity.swift Sources/BackgroundComputerUse/Runtime/RuntimeExecutionQueue.swift Sources/BackgroundComputerUse/Actions/TypeText/AdaptiveTextDispatcher.swift Sources/BackgroundComputerUse/StatePipeline/InteractionToken.swift Sources/BackgroundComputerUse/Runtime/Process/BoundedProcessRunner.swift skills/background-computer-use/scripts/bcu-request.py Tests/BackgroundComputerUseTests/InteractionTokenTests.swift Tests/BackgroundComputerUseTests/RuntimeExecutionQueueTests.swift && git diff --name-only 0110ffb..HEAD -- Sources/BackgroundComputerUse/API/Router.swift Sources/BackgroundComputerUse/App/BackgroundComputerUseControlBridge.swift Sources/BackgroundComputerUseControlShared/CodeSignatureIdentity.swift Sources/BackgroundComputerUse/Runtime/RuntimeExecutionQueue.swift Sources/BackgroundComputerUse/Actions/TypeText/AdaptiveTextDispatcher.swift Sources/BackgroundComputerUse/StatePipeline/InteractionToken.swift Sources/BackgroundComputerUse/Runtime/Process/BoundedProcessRunner.swift skills/background-computer-use/scripts/bcu-request.py Tests/BackgroundComputerUseTests/InteractionTokenTests.swift Tests/BackgroundComputerUseTests/RuntimeExecutionQueueTests.swift` | every listed prerequisite appears in at least one output; otherwise STOP |
| Artifact tests | `swift test --filter CaptureArtifactStoreTests` | all tests pass |
| Screenshot tests | `swift test --filter CursorScreenshotCompositorTests` | all tests pass |
| Queue tests | `swift test --filter RuntimeExecutionQueueTests` | all tests pass |
| Cache tests | `swift test --filter WindowTargetCacheTests` | all tests pass |
| Contract tests | `swift test --filter APIDocumentationTests && swift test --filter RuntimeFacadePublicAPITests` | all tests pass |
| Full verification | `swift test` | all tests pass; baseline is 391 tests before this plan |
| OpenSpec availability | `which openspec` | prints a path, or exits nonzero and validation is skipped/noted |

## Scope

**In scope** (the only files you should modify):
- `Sources/BackgroundComputerUse/Screenshot/CaptureArtifactStore.swift` (create)
- `Sources/BackgroundComputerUse/Screenshot/ScreenshotCaptureService.swift`
- `Sources/BackgroundComputerUse/StatePipeline/WindowStateService.swift`
- `Sources/BackgroundComputerUse/StatePipeline/WindowAnnotationService.swift`
- `Sources/BackgroundComputerUse/StatePipeline/AXPipelineV2/State/StatePipelineExperiment.swift`
- `Sources/BackgroundComputerUse/Actions/Shared/AXActionTargetResolver.swift`
- `Sources/BackgroundComputerUse/Actions/Click/ClickRouteService.swift`
- `Sources/BackgroundComputerUse/Actions/PressKey/PressKeyRouteService.swift`
- `Sources/BackgroundComputerUse/Actions/SecondaryAction/SecondaryActionRouteService.swift`
- `Sources/BackgroundComputerUse/Actions/Text/TextRouteService.swift`
- `Sources/BackgroundComputerUse/Actions/WaitFor/WaitForRouteService.swift`
- `Sources/BackgroundComputerUse/App/RuntimeBootstrap.swift`
- `Sources/BackgroundComputerUse/Runtime/RuntimeExecutionQueue.swift`
- `Sources/BackgroundComputerUse/Window/WindowTargetCache.swift`
- `Sources/BackgroundComputerUse/Actions/Click/RendererAccessibilityBootstrap.swift`
- `Sources/BackgroundComputerUse/Contracts/RouteRequestContracts.swift`
- `Sources/BackgroundComputerUse/API/RouteRegistry.swift`
- `Tests/BackgroundComputerUseTests/CaptureArtifactStoreTests.swift` (create)
- `Tests/BackgroundComputerUseTests/CursorScreenshotCompositorTests.swift`
- `Tests/BackgroundComputerUseTests/RuntimeEnhancementTests.swift`
- `Tests/BackgroundComputerUseTests/RuntimeExecutionQueueTests.swift`
- `Tests/BackgroundComputerUseTests/WindowTargetCacheTests.swift` (create)
- `Tests/BackgroundComputerUseTests/APIDocumentationTests.swift`
- `Tests/BackgroundComputerUseTests/RuntimeFacadePublicAPITests.swift`
- `openspec/changes/bound-runtime-resources/proposal.md` (create)
- `openspec/changes/bound-runtime-resources/tasks.md` (create)
- `openspec/changes/bound-runtime-resources/specs/runtime-security/spec.md` (create)
- `openspec/changes/bound-runtime-resources/specs/request-validation/spec.md` (create)
- `plans/README.md` (status row only)

**Out of scope** (do NOT touch, even though related):
- Lower-resolution capture, PNG compression changes, OCR worker persistence, or the 1 MiB subprocess output cap.
- Changing state-token generation or screenshot coordinate transforms.
- Rejecting invalid window IDs before `RuntimeCoordinator`; bounded queue retention is sufficient here.
- Renderer bootstrap readiness/polling performance; only observer/process lifecycle is in scope.
- Debug artifact and `run_script` audit retention; those are separate stores with separate security semantics.

## Git workflow

- Branch: `advisor/017-resource-bounds`
- Preserve all prerequisite working-tree changes, especially the 64 MiB worker-stack fix and new queue tests.
- Use observed commit style, for example `fix: bound screenshot artifact retention` and `fix: evict idle window resources`.
- Do NOT push or open a PR unless the operator instructed it.

## Steps

### Step 1: Specify artifact output and retention as a public contract

Create the listed OpenSpec change. Modify the existing `runtime-security` capability for artifact retention and the existing `request-validation` capability for image output fields. State these exact rules: `imageMode=path` writes a PNG and returns `imagePath`; `imageMode=base64` returns `imageBase64` and does not write or return `imagePath` by default; optional request field `persist=true` makes base64 mode also write and return a path; `imageMode=omit` writes neither; `imagePath` is present only after a successful write. Captures are pruned best-effort at runtime startup and every 15 minutes, by 2-hour age and a 512 MiB aggregate cap, but files younger than 10 minutes are never deleted.

Use the exact proposal/tasks/spec structure from `openspec/project.md:25-29`. Include scenarios for base64 default, base64+persist, path, age pruning, byte pruning, and grace protection. The final task must include focused tests, `swift test`, strict validation, and an operator-gated live smoke entry marked skipped unless the operator separately authorizes app launch.

**Verify**: `openspec validate bound-runtime-resources --strict` when available; otherwise record the CLI absence → exits 0 or absence is explicitly noted.

### Step 2: Implement a deterministic capture pruning policy

Create `CaptureArtifactStore.swift`. Separate pure selection from filesystem effects:

```swift
struct CaptureArtifactEntry: Equatable {
    let url: URL
    let modificationDate: Date
    let size: Int64
}

struct CaptureArtifactPruningPolicy {
    let maximumAge: TimeInterval       // 2 * 60 * 60
    let maximumTotalBytes: Int64       // 512 * 1024 * 1024
    let gracePeriod: TimeInterval      // 10 * 60

    func filesToDelete(from entries: [CaptureArtifactEntry], now: Date) -> Set<URL>
}
```

First select eligible files older than the grace period and older than maximum age. Recompute retained total bytes, then remove the oldest remaining eligible files until under the byte cap. Sort by modification date then path for deterministic ties. Never choose a file inside the grace period, even when total bytes remain above cap.

`CaptureArtifactStore` owns only `$TMPDIR/background-computer-use/captures`, enumerates regular `.png` files with resource keys for mtime/size, writes via `SecureFileWriter`, and deletes selected files best-effort. It must never follow/delete a directory or a non-PNG entry.

**Verify**: `swift test --filter CaptureArtifactStoreTests` → the new suite compiles; tests are completed in Step 3.

### Step 3: Test age, byte, and grace pruning without filesystem timing

Create `CaptureArtifactStoreTests.swift` using pure entries and a fixed `now`. Add four tests: an old file past 2 hours is selected; multiple old files are removed oldest-first until 512 MiB; a 9-minute file is protected even when it alone exceeds 512 MiB; age-selected files count as removed before byte-cap selection and equal timestamps use path order. Assert exact URL sets.

Add one small temporary-directory integration test that writes an old PNG and a non-PNG sentinel, injects the directory into a non-shared store, runs prune, and proves only the old PNG is removed. Restore/remove the unique temp directory in `defer`.

**Verify**: `swift test --filter CaptureArtifactStoreTests` → 5 tests pass without launching the app.

### Step 4: Start best-effort artifact maintenance once per runtime

Give `CaptureArtifactStore.shared` an idempotent `startMaintenance()` guarded by its serial state queue. It must enqueue (not synchronously perform) one startup prune and retain a `DispatchSourceTimer` scheduled every 15 minutes with reasonable leeway; the event handler runs prune on the store queue and ignores individual metadata/delete failures. Call it in `RuntimeBootstrap.init` after `ScriptAuditLogger().prepare()` and before creating `LoopbackServer` (`RuntimeBootstrap.swift:13-18`).

Allow the internal non-shared initializer to inject its directory and a `timerFactory: (DispatchQueue) -> DispatchSourceTimer` so the test can count timer creation. Calling `startMaintenance()` twice must invoke that factory once. Do not make runtime startup wait or fail because pruning failed. Keep the timer retained by the shared store and cancel it only in an internal test teardown/deinit path.

**Verify**: `swift test --filter CaptureArtifactStoreTests` → integration test passes and repeated `startMaintenance()` creates one timer.

### Step 5: Make base64 output memory-only unless explicitly persisted

Add `persist: Bool = false` to `ScreenshotCaptureService.capture`. Compute `shouldWrite = imageMode == .path || (imageMode == .base64 && persist)`. Encode once, but call `CaptureArtifactStore.shared.write` only when `shouldWrite`; raw output follows the same rule. Set `imagePath` only after successful writes. Change `captureError` to receive `pathExpected` so intentional nil paths are not reported as failures. Coordinate contracts must continue to build with nil paths.

Update `CursorScreenshotCompositorTests.swift:35-59`: use a unique state token and assert base64 is present, `imagePath == nil`, and no token-named file exists. Add a second test with `persist: true` that asserts both base64 and path, then removes the returned file. Preserve cursor pixel assertions.

In `WindowStateService`, pass `request.persist ?? false`. When `includeOCR=true` and no path exists but base64 does, decode it to `NSBitmapImageRep.cgImage` and use the existing `OCRRecognitionService.measure(cgImage:interactionToken:)` path (`OCRRecognitionService.swift:55-83`), whose temporary input is deleted. Do not silently disable OCR.

**Verify**: `swift test --filter CursorScreenshotCompositorTests` → base64-only and base64+persist tests pass with correct path presence.

### Step 6: Preserve annotation support without requiring a base path

Change `WindowAnnotationRenderer.render` to accept `baseImage: ScreenshotImageDTO` rather than a mandatory `baseImagePath`. Load bytes from `imagePath` when present, otherwise from `Data(base64Encoded: imageBase64)`. Return nil only when neither source decodes. Add `persist: Bool`; annotated PNG output obeys the same path/base64/both matrix as normal screenshots and uses `CaptureArtifactStore` for writes.

Thread `AnnotateWindowRequest.persist` into the internal `GetWindowStateRequest` and renderer. Extend `RuntimeEnhancementTests.swift:264-312` with a base64-only source/annotation case that returns annotated base64 with nil path; retain the existing path-backed test.

**Verify**: `swift test --filter RuntimeEnhancementTests` → existing annotation path test and new base64-only test pass.

### Step 7: Add and propagate the optional `persist` request field

Add `public let persist: Bool?` and defaulted `persist: Bool? = nil` initializer parameters to every request DTO that already exposes `imageMode`: `GetWindowStateRequest`, `ClickRequest` (both public initializers), `PerformSecondaryActionRequest`, `PressKeyRequest`, `WaitForRequest`, `AnnotateWindowRequest`, and `SelectTextRequest`. Keep source compatibility through defaults.

Add `persist` to every corresponding `RouteRegistry.requestSchema` branch, including `clickRequestSchema`, with description: “For imageMode=base64 only, also write the PNG and return imagePath; defaults to false. Path mode always writes; omit never writes.” Update global route notes to explain that base64 is memory-only by default and `imagePath` appears only when written.

Thread the value through `WindowStateService`, `WindowAnnotationService`, and the initial `AXActionTargetResolver.capture` calls in Click, PressKey, SecondaryAction, Text/select, and WaitFor. Add `persistScreenshot` to `AXActionStateCapture`; `reread(after:imageMode:)` must reuse it automatically. Add the corresponding defaulted parameter through `StatePipelineExperiment.captureResolvedWindow` to `ScreenshotCaptureService.capture`. Do not add persistence to routes without `imageMode`.

Update `RuntimeFacadePublicAPITests.swift:17-58` to construct at least one public request with `imageMode: .base64, persist: true` and assert the field. Update `APIDocumentationTests` expected request fields for all seven routes so the strict top-level registry remains a superset of DTO fields.

**Verify**: `swift test --filter APIDocumentationTests && swift test --filter RuntimeFacadePublicAPITests` → all schema/public-construction tests pass.

### Step 8: Replace the unbounded window queue map with leased LRU entries

In `RuntimeExecutionQueue.swift`, introduce internal `WindowQueueRegistry` with capacity 128, an injected monotonic clock for tests, and entries containing `DispatchQueue`, `inFlight`, and `lastUsed`. Acquire increments `inFlight` under the lock before exposing a queue; `defer` release decrements and updates recency. Evict only `inFlight == 0` entries, oldest first. If all entries are active, allow temporary capacity overflow and prune back to 128 on release; never evict an active queue because a second queue for the same window would violate barrier serialization.

Target usage:

```swift
let lease = state.registry.acquire(windowID: windowID)
defer { lease.release() }
return lease.queue.sync(flags: isWrite ? .barrier : []) { onLargeStack(work) }
```

Keep shared reads unchanged and preserve the 64 MiB pthread path. Remove the old `queue(for:)` dictionary logic completely.

Extend `RuntimeExecutionQueueTests` with an in-flight barrier regression: capacity 1; block a write for window A; create pressure with window B; start a second A write and prove it cannot enter until the first A barrier releases; after release/additional access, assert the registry returns to capacity and evicts the idle LRU, never active A.

**Verify**: `swift test --filter RuntimeExecutionQueueTests` → existing large-stack/error tests and new leased-LRU barrier test pass.

### Step 9: Prune dead window-cache entries through an injected liveness policy

Change `WindowTargetCache` to accept an internal `isProcessAlive: (pid_t) -> Bool` initializer while `shared` uses a live implementation. Live liveness returns true when `NSRunningApplication(processIdentifier:)` exists, or `kill(pid, 0)` succeeds, or it fails with `EPERM`; only `ESRCH` means dead. On `remember`, prune all dead-PID entries before insertion. On `entry(for:)`, remove and return nil for a dead PID. Snapshot entries under the lock, evaluate liveness outside it, then reacquire the lock and remove a candidate only if the current entry still has the snapshotted PID/launch identity; this prevents a concurrent replacement from being deleted.
Target initializer shape: `init(isProcessAlive: @escaping (pid_t) -> Bool = Self.liveProcessIsAlive)`. Put `liveProcessIsAlive` beside the cache, import AppKit and Darwin there, and treat errors other than `ESRCH` conservatively as alive.

Create `WindowTargetCacheTests.swift` with a fake mutable set of live PIDs. Prove: live entries survive; marking one PID dead prunes every entry for that PID; entries for another live PID remain; and lookup of a dead entry returns nil. No real process creation is needed.

**Verify**: `swift test --filter WindowTargetCacheTests` → all fake-liveness tests pass.

### Step 10: Release renderer observer sources on process termination

Import AppKit in `RendererAccessibilityBootstrap.swift`. Register exactly one `NSWorkspace.didTerminateApplicationNotification` observer lazily under the existing state lock. Store each AX observer with its numeric PID, not only the process key. On termination, atomically remove every matching prepared key/observer from state, then on the main run loop call `CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)` for each removed observer. Retain the workspace notification token for runtime lifetime.
Store `ObserverRecord(pid: pid_t, observer: AXObserver)` values by process key. The notification closure extracts the terminated `NSRunningApplication.processIdentifier` and calls one `remove(processID:) -> [AXObserver]`; only that returned array is used for main-run-loop source removal.

Do not remove an observer merely because an LRU queue/cache entry was evicted; process termination is the ownership boundary. Do not change the renderer readiness worker or its 5-second poll in this plan.

**Verify**: `swift test --filter RuntimeExecutionQueueTests && swift test --filter WindowTargetCacheTests` → resource suites pass and the target compiles with AppKit notification handling.

### Step 11: Run the final gate once

Run all focused commands, then `swift test` once. Inspect `git status --short`; only Scope files plus preserved prerequisite changes may appear. Update only plan 017's status row in `plans/README.md`.

**Verify**: `swift test` → exit 0 with all baseline and new tests passing.

## Test plan

- New `CaptureArtifactStoreTests`: pure age/byte/grace/tie policy plus safe temp-directory integration.
- Updated screenshot/compositor tests: base64-only has no path/write; `persist=true` returns both.
- Updated annotation tests: render from base64 without a base path and keep output memory-only.
- Updated `RuntimeExecutionQueueTests`: pressure cannot evict an in-flight barrier queue; idle LRU returns to capacity.
- New `WindowTargetCacheTests`: fake PID liveness prunes only dead-process entries.
- Updated route/public API tests: all seven image-mode requests advertise/construct `persist`.
- Verification: `swift test --filter CaptureArtifactStoreTests && swift test --filter CursorScreenshotCompositorTests && swift test --filter RuntimeExecutionQueueTests && swift test --filter WindowTargetCacheTests` → all focused tests pass.

## Done criteria

- [ ] Startup and 15-minute maintenance apply 2-hour/512 MiB pruning while protecting the newest 10 minutes.
- [ ] Pruning is deterministic, best-effort, limited to regular PNG files in the capture directory, and never blocks runtime startup.
- [ ] Base64 mode performs no capture/annotation disk write by default; `persist=true` returns both base64 and path; path mode remains path-backed.
- [ ] OCR and annotations still work for base64-only state without retaining capture PNGs.
- [ ] `GET /v1/routes` and all seven request DTOs agree on `persist`; `imagePath` is present only after a write.
- [ ] Window queue retention returns to 128 idle entries or fewer without evicting in-flight/barrier work.
- [ ] Dead-PID window cache entries and terminated-process renderer observer sources are removed.
- [ ] Focused suites and one final `swift test` exit 0.
- [ ] No files outside Scope are newly modified; prerequisite changes remain intact.
- [ ] `plans/README.md` status row is updated.

## STOP conditions

Stop and report back (do not improvise) if:

- Any prerequisite working-tree fix is absent from both `git status` and commits after `0110ffb`.
- Current code already has artifact pruning, queue leasing, PID-liveness pruning, or observer teardown that conflicts with these excerpts.
- A pruning implementation would delete files younger than 10 minutes, follow symlinks/directories, or touch outside the exact captures directory.
- Supporting base64 OCR/annotation appears to require retaining a permanent file; use the existing transient OCR CGImage path and in-memory annotation decode instead.
- Queue pressure can create two concurrent queues for one in-flight window ID; never trade serialization correctness for the 128-entry bound.
- `persist` cannot be added consistently to every existing image-mode DTO and RouteRegistry branch within Scope.
- Swift 6 concurrency would require broadly marking runtime state unchecked; keep unchecked boundaries narrow and lock-backed.
- A focused verification fails twice or a step requires launching/installing the app.

## Maintenance notes

- Review pruning order and grace handling with files larger than the total cap; exceeding 512 MiB is allowed temporarily when all excess files are younger than 10 minutes.
- Keep artifact policy values centralized in `CaptureArtifactPruningPolicy`, not repeated in screenshot and annotation services.
- Any future request that adds `imageMode` must also decide and document whether it exposes `persist`, and its DTO must match RouteRegistry strict fields.
- Queue capacity is a retention bound, not a concurrency limit. Active windows may temporarily exceed 128 entries; release must prune later.
- PID reuse is why renderer cleanup remains notification/process-lifecycle based and process keys include launch date; cache resolution still validates bundle, launch date, and window number.
- If plan 016 has already changed `WaitForRouteService`, thread `persist` through its new capture seam rather than restoring the old unbounded final-capture structure.
