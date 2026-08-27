# BCU Runtime Excellence Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Eliminate resident-process OCR poisoning, ambiguous application selection, and foreground-stealing text entry from the live BCU runtime.

**Architecture:** Move Vision into a self-executed, disposable OCR worker supervised by a shared bounded-process runner. Replace fuzzy application discovery with an exact PID contract. Make `type_text` own one background-only transaction that prepares the target window, verifies exact text state, and refuses success if the foreground application changes.

**Tech Stack:** Swift 6.2, Swift Testing, AppKit Accessibility, CoreGraphics, Vision, Darwin `posix_spawn`, existing Python smoke runtime.

**Spec:** `docs/plans/2026-08-27-bcu-runtime-excellence-design.md`

## Global Constraints

- macOS 14 remains the deployment minimum.
- No new dependency, CDP bridge, browser plugin, or foreground activation fallback.
- Breaking `list_windows.app` and `type_text.focusAssistMode` is approved.
- Every production behavior starts with a focused failing Swift Testing test.
- Preserve strict request decoding and self-documentation parity.
- Preserve `run_script` source-on-stdin, audit, output limits, timeout, and descendant cleanup.
- Execute Tasks 1-3, review/debug, then Tasks 4-6, review/debug.
- Run focused gates continuously and the full suite once at the end.
- Maximum three fix attempts for one failing hypothesis.
- Do not commit, push, publish, or release without separate authorization.
- Preserve the unrelated untracked `multiplan-artifacts/` directory.

---

## Batch 1 — Process isolation and OCR

### Task 1: Extract one bounded process supervisor

**Files:**
- Create: `Sources/BackgroundComputerUse/Runtime/Process/BoundedProcessRunner.swift`
- Modify: `Sources/BackgroundComputerUse/Actions/Script/ScriptProcessExecutor.swift`
- Modify: `Tests/BackgroundComputerUseTests/ScriptExecutionParityTests.swift`
- Create: `Tests/BackgroundComputerUseTests/BoundedProcessRunnerTests.swift`
- Create: `openspec/changes/harden-bcu-runtime-excellence/proposal.md`
- Create: `openspec/changes/harden-bcu-runtime-excellence/tasks.md`
- Create: `openspec/changes/harden-bcu-runtime-excellence/specs/runtime-security/spec.md`

**Interfaces:**
- Produces: `BoundedProcessInvocation(executableURL:arguments:stdin:timeoutMs:environment:)`.
- Produces: `BoundedProcessResult(status:stdout:stderr:stdoutTruncated:stderrTruncated:durationMs:timedOut:)`.
- Produces: `BoundedProcessRunner.run(_:) throws -> BoundedProcessResult`.
- Preserves: `ScriptProcessExecutor.execute(language:source:timeoutMs:) throws -> ScriptProcessResult`.

- [x] **Step 1: Materialize the OpenSpec change**

Write the approved requirements as strict deltas: disposable OCR worker cleanup in `runtime-security`, exact PID selection in `window-discovery`, and foreground-preserved text success in `action-verification`. The task checklist ends with full tests, strict validation, and live smoke.

- [x] **Step 2: Write the failing generic-runner tests**

Add real-process tests:

```swift
@Test
func boundedRunnerPassesStdinAndCapturesBothStreams() throws {
    let result = try BoundedProcessRunner().run(
        BoundedProcessInvocation(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "read value; printf '%s' \"$value\"; printf 'warn' >&2"],
            stdin: Data("hello\n".utf8),
            timeoutMs: 2_000
        )
    )

    #expect(result.status == 0)
    #expect(String(decoding: result.stdout, as: UTF8.self) == "hello")
    #expect(String(decoding: result.stderr, as: UTF8.self) == "warn")
    #expect(result.timedOut == false)
}

@Test
func boundedRunnerKillsASetSidDescendantOnTimeout() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("bcu-runner-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let pidFile = root.appendingPathComponent("child.pid")
    let shell = "/usr/bin/perl -MPOSIX -e 'POSIX::setsid(); sleep 30' & child=$!; echo $child > '\(pidFile.path)'; wait $child"

    let result = try BoundedProcessRunner().run(
        .init(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", shell],
            stdin: Data(),
            timeoutMs: 500
        )
    )

    let childPID = pid_t(try #require(Int(String(contentsOf: pidFile).trimmingCharacters(in: .whitespacesAndNewlines))))
    #expect(result.timedOut)
    errno = 0
    #expect(Darwin.kill(childPID, 0) == -1)
    #expect(errno == ESRCH)
}
```

Move output-cap and invalid-executable coverage to this suite while leaving script audit tests in `ScriptExecutionParityTests`.

- [x] **Step 3: Verify RED**

Run:

```bash
swift test --filter BoundedProcessRunnerTests
```

Expected: compile failure because the generic invocation, result, and runner do not exist.

- [x] **Step 4: Implement the generic supervisor**

Move pipe creation, `posix_spawn`, safe environment, concurrent drains, `F_SETNOSIGPIPE`, deadline polling, recursive `proc_listchildpids`, process-group signaling, reap, and termination verification into `BoundedProcessRunner`. Use `Data` at the boundary; do not assume UTF-8 in the generic layer.

Use these primary shapes:

```swift
struct BoundedProcessInvocation: Sendable {
    let executableURL: URL
    let arguments: [String]
    let stdin: Data
    let timeoutMs: Int
    let environment: [String]
}

struct BoundedProcessResult: Sendable {
    let status: Int
    let stdout: Data
    let stderr: Data
    let stdoutTruncated: Bool
    let stderrTruncated: Bool
    let durationMs: Double
    let timedOut: Bool
}
```

Keep all Darwin helpers private to the new file.

- [x] **Step 5: Adapt `ScriptProcessExecutor` without behavior change**

`ScriptProcessExecutor` constructs:

```swift
let invocation = BoundedProcessInvocation(
    executableURL: URL(fileURLWithPath: "/usr/bin/osascript"),
    arguments: ["-l", language.osascriptName],
    stdin: Data((source + "\n").utf8),
    timeoutMs: timeoutMs,
    environment: BoundedProcessInvocation.safeEnvironment()
)
```

Map the generic data result back to the existing string response. Do not move audit policy into the generic runner.

- [x] **Step 6: Verify GREEN and no script regression**

Run:

```bash
swift test --filter 'BoundedProcessRunnerTests|ScriptExecutionParityTests'
```

Expected: all selected tests pass, including descendant cleanup and audit permissions.

- [x] **Step 7: Checkpoint without commit**

Run `git diff --check` and record the touched paths. Do not stage or commit.

### Task 2: Add the disposable OCR worker protocol

**Files:**
- Create: `Sources/BackgroundComputerUse/OCR/OCRWorkerProtocol.swift`
- Create: `Sources/BackgroundComputerUse/OCR/OCRVisionEngine.swift`
- Create: `Sources/BackgroundComputerUse/OCR/OCRWorkerMain.swift`
- Modify: `Sources/BackgroundComputerUseServer/main.swift`
- Create: `Tests/BackgroundComputerUseTests/OCRWorkerTests.swift`
- Modify: `Tests/BackgroundComputerUseTests/VerificationHonestyTests.swift`

**Interfaces:**
- Produces: `OCRWorkerRequest(imagePath:interactionToken:)`.
- Produces: `OCRWorkerResponse(summary:durationMs:)`.
- Produces: `OCRVisionEngine.measure(imagePath:interactionToken:) -> OCRRecognitionOutcome`.
- Produces: `OCRWorkerMain.run() -> Never` for the `--ocr-worker` entry mode.

- [x] **Step 1: Write failing protocol and Vision-engine tests**

Add Codable round-trip tests and a real-text image helper using CoreText and ImageIO. The image must contain `BCU OCR worker` rather than blank rectangles:

```swift
@Test
func visionEngineRecognizesARealTextFixture() throws {
    let imageURL = try OCRTextFixture.makePNG(text: "BCU OCR worker")
    defer { try? FileManager.default.removeItem(at: imageURL) }

    let outcome = OCRVisionEngine.measure(
        imagePath: imageURL.path,
        interactionToken: "it_worker"
    )

    #expect(outcome.summary.status == .success)
    #expect(outcome.summary.anchors.contains { $0.text.localizedCaseInsensitiveContains("BCU") })
}
```

Replace `ocrRecognitionReportsItsOwnDuration`, which feeds Vision a blank 64x64 bitmap, with this real-text assertion. Keep the deadline-mapping test for the parent client in Task 3 rather than inside Vision.

- [x] **Step 2: Verify RED**

Run:

```bash
swift test --filter 'OCRWorkerTests|visionEngineRecognizesARealTextFixture'
```

Expected: compile failure because worker protocol, engine, and fixture helper do not exist.

- [x] **Step 3: Implement one synchronous worker engine**

Move image decoding, `VNRecognizeTextRequest`, result-to-line conversion, and elapsed-time measurement from `OCRRecognitionService` into `OCRVisionEngine`. Run `VNImageRequestHandler.perform` synchronously because the process boundary owns the deadline.

On Vision error, return a sanitized diagnostic with domain and code:

```swift
let nsError = error as NSError
let diagnostic = "Apple Vision failed (domain=\(nsError.domain), code=\(nsError.code))."
```

Do not serialize `userInfo`, image paths, or recognized content in errors.

- [x] **Step 4: Implement the worker entry mode**

`OCRWorkerMain.run()` reads all stdin, decodes exactly one request, runs the engine, encodes exactly one response to stdout, and exits `0`. Decode/encode failures print a short diagnostic to stderr and exit `2`.

Route before AppKit bootstrap:

```swift
if CommandLine.arguments.dropFirst().first == "--ocr-worker" {
    OCRWorkerMain.run()
} else {
    BackgroundComputerUseServer.run()
}
```

- [x] **Step 5: Verify GREEN**

Run:

```bash
swift test --filter 'OCRWorkerTests|visionEngineRecognizesARealTextFixture'
swift build --product BackgroundComputerUse
```

Expected: protocol/engine tests pass and the executable builds with both modes.

- [x] **Step 6: Checkpoint without commit**

Run `git diff --check`. Do not stage or commit.

### Task 3: Switch every OCR caller to the worker and delete the legacy path

**Files:**
- Create: `Sources/BackgroundComputerUse/OCR/OCRWorkerClient.swift`
- Modify: `Sources/BackgroundComputerUse/OCR/OCRRecognitionService.swift`
- Modify: `Sources/BackgroundComputerUse/StatePipeline/WindowStateService.swift`
- Modify: `Sources/BackgroundComputerUse/Actions/Click/ClickRouteService.swift`
- Modify: `Sources/BackgroundComputerUse/App/RuntimeBootstrap.swift`
- Modify: `Sources/BackgroundComputerUse/API/RouteRegistry.swift`
- Modify: `Sources/BackgroundComputerUse/API/APIDocumentation.swift`
- Modify: `script/smoke_runtime.py`
- Modify: `Tests/BackgroundComputerUseTests/OCRWorkerTests.swift`
- Modify: `Tests/BackgroundComputerUseTests/APIDocumentationTests.swift`

**Interfaces:**
- Produces: `OCRWorkerClient.recognize(imagePath:interactionToken:deadline:) -> OCRRecognitionOutcome`.
- Produces: instance-based `OCRRecognitionService` injected into window-state and click services.
- Removes: `OCRRecognitionService.prewarm`, `RecognitionBox`, in-process dispatch/semaphore deadline, and `RuntimeBootstrap.prewarmOCR`.

- [x] **Step 1: Write failing client failure-mapping tests**

Inject a runner closure into `OCRWorkerClient` and require:

```swift
@Test func workerTimeoutReturnsRecognitionFailed() {
    let client = OCRWorkerClient(run: { _ in
        BoundedProcessResult(
            status: 124,
            stdout: Data(),
            stderr: Data(),
            stdoutTruncated: false,
            stderrTruncated: false,
            durationMs: 8_000,
            timedOut: true
        )
    }, executableURL: URL(fileURLWithPath: "/tmp/BackgroundComputerUse"))

    let outcome = client.recognize(imagePath: "/tmp/window.png", interactionToken: "it_1", deadline: 8)
    #expect(outcome.summary.status == .recognitionFailed)
    #expect(outcome.summary.diagnostic?.contains("timed out") == true)
}
```

Also cover non-zero exit, truncated stdout, invalid JSON, and a valid response.

- [x] **Step 2: Verify RED**

Run `swift test --filter OCRWorkerTests`.

Expected: compile failure because `OCRWorkerClient` does not exist.

- [x] **Step 3: Implement the client and inject it**

Resolve the production executable through `Bundle.main.executableURL`, falling back to the current absolute argument only when needed. Send `OCRWorkerRequest` on stdin through `BoundedProcessRunner` with `--ocr-worker`; require status `0`, untruncated stdout, and valid JSON.

Make `OCRRecognitionService` a small instance wrapper around the client and inject `.live` into `WindowStateService` and `ClickRouteService`. No caller imports Vision or owns a deadline thread.

- [x] **Step 4: Delete legacy OCR execution and prewarm**

Remove the synthetic warm-up bitmap, `prewarm()`, `RecognitionBox`, global queue, semaphore, and best-effort cancellation. Update route docs and smoke comments so cold/warm behavior refers to disposable worker startup, not prewarm.

- [x] **Step 5: Verify GREEN and review Batch 1**

Run:

```bash
swift test --filter 'OCRWorkerTests|VerificationHonestyTests|ScriptExecutionParityTests|APIDocumentationTests'
swift build -c release
git diff --check
```

Review the Batch 1 diff for duplicate process management, any remaining `VNRecognizeTextRequest` outside `OCRVisionEngine`, and any `prewarmOCR`/`RecognitionBox` references. Fix at most three focused attempts.

---

## Batch 2 — Exact discovery, background text, and closeout

### Task 4: Replace fuzzy application discovery with exact PID selection

**Files:**
- Modify: `Sources/BackgroundComputerUse/Contracts/RouteRequestContracts.swift`
- Modify: `Sources/BackgroundComputerUse/Contracts/RouteContracts.swift`
- Modify: `Sources/BackgroundComputerUse/Discovery/RunningAppService.swift`
- Modify: `Sources/BackgroundComputerUse/Discovery/WindowListService.swift`
- Modify: `Sources/BackgroundComputerUse/Runtime/RuntimeServices.swift`
- Modify: `Sources/BackgroundComputerUse/API/RouteRegistry.swift`
- Modify: `Sources/BackgroundComputerUse/API/APIDocumentation.swift`
- Modify: `Tests/BackgroundComputerUseTests/RuntimeFacadePublicAPITests.swift`
- Modify: `Tests/BackgroundComputerUseTests/APIDocumentationTests.swift`
- Create: `Tests/BackgroundComputerUseTests/PIDWindowDiscoveryTests.swift`
- Modify: `openspec/changes/harden-bcu-runtime-excellence/specs/window-discovery/spec.md`

**Interfaces:**
- Produces: `ListWindowsRequest(pid: Int32)` with strict positive validation.
- Produces: `RunningAppService.resolveApp(pid:) -> NSRunningApplication?`.
- Produces: `WindowListService.listWindows(pid:) throws -> ListWindowsResponse`.
- Produces: route target kind `appPID` with `pid`, not `appQuery`.
- Removes: `ListWindowsRequest.app`, `resolveApp(query:)`, `WindowListService.listWindows(appQuery:)`, and public fuzzy lookup documentation.

- [x] **Step 1: Write failing request and route tests**

```swift
@Test
func listWindowsRequiresAPositivePIDAndRejectsLegacyApp() throws {
    let request = try JSONDecoder().decode(
        ListWindowsRequest.self,
        from: Data(#"{"pid":25268}"#.utf8)
    )
    #expect(request.pid == 25268)

    #expect(throws: DecodingError.self) {
        _ = try JSONDecoder().decode(
            ListWindowsRequest.self,
            from: Data(#"{"app":"Google Chrome"}"#.utf8)
        )
    }
}
```

Assert `/v1/routes` documents `pid`, omits `app`, and missing input reports `Missing required field 'pid'`.

- [x] **Step 2: Verify RED**

Run:

```bash
swift test --filter 'PIDWindowDiscoveryTests|RuntimeFacadePublicAPITests|APIDocumentationTests'
```

Expected: tests fail because the old string contract remains.

- [x] **Step 3: Implement PID-only resolution**

Decode `Int32`, reject values `<= 0`, resolve only `targetableApps().first { $0.processIdentifier == pid }`, and throw `DiscoveryError.appNotFound("PID \(pid)")` if absent. Never retry by bundle or name.

Update runtime coordination metadata:

```swift
RouteTargetSummaryDTO(kind: .appPID, pid: request.pid, windowID: nil)
```

Delete `appQuery` from this DTO and update its constructors/call sites.

- [x] **Step 4: Verify GREEN**

Run the focused discovery/public/docs tests and `openspec validate harden-bcu-runtime-excellence --strict`.

- [x] **Step 5: Checkpoint without commit**

Run `rg -n 'resolveApp\(query:|ListWindowsRequest\(app:|appQuery' Sources Tests script` and remove only selector-related remnants proven obsolete by this change. Run `git diff --check`.

### Task 5: Make `type_text` an automatic background-only transaction

**Files:**
- Create: `Sources/BackgroundComputerUse/Actions/Shared/ForegroundApplicationSnapshot.swift`
- Create: `Sources/BackgroundComputerUse/Actions/TypeText/BackgroundTextPreparation.swift`
- Modify: `Sources/BackgroundComputerUse/Actions/TypeText/TypeTextRouteService.swift`
- Modify: `Sources/BackgroundComputerUse/Contracts/RouteRequestContracts.swift`
- Modify: `Sources/BackgroundComputerUse/Contracts/TextActionContracts.swift`
- Modify: `Sources/BackgroundComputerUse/API/RouteRegistry.swift`
- Modify: `Sources/BackgroundComputerUse/API/APIDocumentation.swift`
- Create: `Tests/BackgroundComputerUseTests/BackgroundTextSafetyTests.swift`
- Modify: `Tests/BackgroundComputerUseTests/RuntimeFacadePublicAPITests.swift`
- Modify: `Tests/BackgroundComputerUseTests/APIDocumentationTests.swift`
- Modify: `openspec/changes/harden-bcu-runtime-excellence/specs/action-verification/spec.md`

**Interfaces:**
- Produces: `ForegroundApplicationSnapshot(pid:bundleID:)` and `capture()`.
- Produces: `BackgroundTextPreparation.prepare(pid:windowNumber:) -> NativeWindowServerPreparationResult`.
- Produces: `TypeTextBackgroundSafetyDTO(frontmostBefore:frontmostBeforeDispatch:frontmostAfter:foregroundPreserved:)`.
- Adds: `ActionFailureDomainDTO.backgroundSafety`.
- Removes: `TypeTextFocusAssistModeDTO`, `TypeTextRequest.focusAssistMode`, and `TypeTextResponse.focusAssistMode`.

- [x] **Step 1: Write failing safety-gate tests**

```swift
@Test
func textSuccessRequiresTheSameForegroundProcessThroughout() {
    let userApp = ForegroundApplicationSnapshot(pid: 41, bundleID: "com.example.User")
    let targetApp = ForegroundApplicationSnapshot(pid: 52, bundleID: "com.example.Target")

    #expect(TypeTextBackgroundSafety.evaluate(
        before: userApp,
        beforeDispatch: userApp,
        after: userApp
    ).foregroundPreserved)

    #expect(TypeTextBackgroundSafety.evaluate(
        before: userApp,
        beforeDispatch: targetApp,
        after: targetApp
    ).foregroundPreserved == false)
}
```

Add strict-decode coverage proving `focusAssistMode` is rejected and response-schema coverage proving the field is gone.

- [x] **Step 2: Verify RED**

Run:

```bash
swift test --filter 'BackgroundTextSafetyTests|RuntimeFacadePublicAPITests|APIDocumentationTests'
```

Expected: compile/schema failures because automatic background evidence does not exist and the legacy field remains.

- [x] **Step 3: Implement shared preparation and evidence**

Centralize the call to `NativeWindowServerPreparation.targetOnlyFocusAndKeyWindow`. Capture foreground identity before preparation and immediately after it. If preparation fails or the foreground identity changes, return `effect_not_verified` with `failureDomain: background_safety` before text dispatch.

For a semantic writable target, compute the exact expected value/selection, prepare the window, apply the AX value and selected range, reread, and capture foreground again. Do not set `kAXFocusedAttribute` as a public-mode side effect and do not activate an application.

Use the same preparation helper for the explicitly confirmed opaque PID path; keep its existing confirmation gate.

- [x] **Step 4: Require background safety in classification**

Change classification ordering:

```swift
guard backgroundSafety.foregroundPreserved else {
    return response(
        classification: .effectNotVerified,
        failureDomain: .backgroundSafety,
        summary: "Text dispatch did not preserve the user's foreground application.",
        backgroundSafety: backgroundSafety,
        verification: verification
    )
}
```

Only then evaluate exact value and selection matches.

- [x] **Step 5: Verify GREEN**

Run focused text/public/docs tests, then existing text-related tests selected by `swift test --filter 'TypeText|TextAction|BackgroundText'`.

- [x] **Step 6: Checkpoint without commit**

Run `rg -n 'focusAssistMode|TypeTextFocusAssistModeDTO' Sources Tests script skills` and remove only obsolete contract/docs/smoke references. Run `git diff --check`.

### Task 6: Update smoke, documentation, strict specs, and run final gates

**Files:**
- Modify: `script/smoke_runtime.py`
- Modify: `skills/background-computer-use/SKILL.md`
- Modify: `skills/background-computer-use/references/runtime.md`
- Modify: `openspec/changes/harden-bcu-runtime-excellence/tasks.md`
- Modify: `docs/plans/2026-08-27-bcu-runtime-excellence-design.md` only if implementation evidence requires a factual correction.
- Modify: `docs/superpowers/plans/2026-08-27-bcu-runtime-excellence.md` only to check completed steps.

**Interfaces:**
- Smoke discovery consumes `list_apps.runningApps[].pid` and sends `{"pid": pid}` to `list_windows`.
- Chrome fixture creation returns the exact fixture process PID, not a name.
- Safari text smoke records frontmost PID before/after and requires `classification == "success"` plus `backgroundSafety.foregroundPreserved == true`.

- [x] **Step 1: Write failing Python smoke unit checks where pure seams exist**

Extract and test request-building helpers:

```python
def list_windows_request(pid: int) -> dict:
    if pid <= 0:
        raise ValueError("pid must be positive")
    return {"pid": pid}

def text_result_is_background_safe(payload: dict) -> bool:
    return (
        payload.get("classification") == "success"
        and payload.get("backgroundSafety", {}).get("foregroundPreserved") is True
    )
```

Run the repository's existing Python test mechanism if present; otherwise exercise these helpers through the live smoke and record that no standalone Python suite exists.

- [x] **Step 2: Update the live fixture flow**

Capture the PID of the launched isolated Chrome process, wait until `list_apps` exposes that exact PID, and call PID-only `list_windows`. Add a duplicate-instance check that proves the fixture PID never receives a sibling window.

Add Safari typing with another application frontmost. Require exact target value, background safety, and unchanged external frontmost PID.

- [x] **Step 3: Update skill and route examples**

All examples must follow `list_apps -> select pid -> list_windows`. Remove prewarm guidance and public focus-assist guidance. Describe OCR worker timeout honestly without exposing internal process details that agents do not need.

- [x] **Step 4: Run focused final validation**

Run:

```bash
swift build -c release
openspec validate harden-bcu-runtime-excellence --strict
git diff --check
```

- [x] **Step 5: Run the full suite once**

Run:

```bash
swift test
```

Expected: zero failures. The former `ocrRecognitionReportsItsOwnDuration` baseline no longer exists; real-text worker coverage replaces it.

- [x] **Step 6: Run the signed-app live smoke**

Launch through the repository signing script so permissions stay attached to the app bundle, then run the complete smoke against the loopback runtime. Required evidence:

- two same-bundle processes resolve by their exact PID;
- two OCR reads succeed inside budget and later OCR still succeeds;
- Chrome OCR-anchor click returns verified success;
- Safari background text returns verified success and foreground PID is unchanged;
- no worker remains after success or forced timeout.

- [x] **Step 7: Final review and debug**

Review the complete diff read-only against the design, OpenSpec, and public route schemas. Search for duplicated process supervision, fuzzy app resolution, in-process Vision execution, and public focus-assist remnants. For any failure, apply the systematic-debugging loop with at most three fixes, rerun only the affected focused gate, then rerun the full gate once if code changed.

- [x] **Step 8: Final status without commit**

Report literal gate outcomes, live-smoke evidence, remaining platform limitations, changed paths, and `git status --short`. Do not stage, commit, push, package, or publish.

---

## Plan Self-Review

- Every approved design requirement maps to Tasks 1-6.
- Process supervision has one production owner and one adapter per caller.
- Vision exists only in the disposable worker engine.
- Application selection has one exact PID path and no fuzzy fallback.
- Text success requires both exact effect and foreground preservation.
- No step authorizes unrelated cleanup, commit, push, release, or publication.
