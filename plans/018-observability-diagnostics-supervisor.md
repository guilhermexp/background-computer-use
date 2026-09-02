# Plan 018: Make runtime failures observable and recover abnormal exits

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**: `git diff --stat 0110ffb..HEAD -- Sources/BackgroundComputerUse/API Sources/BackgroundComputerUse/App Sources/BackgroundComputerUse/Contracts Sources/BackgroundComputerUse/OCR Sources/BackgroundComputerUse/Runtime Sources/BackgroundComputerUseControl Sources/BackgroundComputerUseServer script/install_launch_agent.sh skills/background-computer-use/references/runtime.md Tests/BackgroundComputerUseTests openspec/changes/add-runtime-diagnostics`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.
>
> Also run `git status --short` and `git diff --name-only 0110ffb..HEAD`. The union must show the baseline fixes in `Sources/BackgroundComputerUse/API/Router.swift`, `Sources/BackgroundComputerUse/App/BackgroundComputerUseControlBridge.swift`, `Sources/BackgroundComputerUseControlShared/CodeSignatureIdentity.swift`, `Sources/BackgroundComputerUse/Runtime/RuntimeExecutionQueue.swift`, `Sources/BackgroundComputerUse/Actions/TypeText/AdaptiveTextDispatcher.swift`, `Sources/BackgroundComputerUse/StatePipeline/InteractionToken.swift`, `Sources/BackgroundComputerUse/Runtime/Process/BoundedProcessRunner.swift`, `skills/background-computer-use/scripts/bcu-request.py`, `Tests/BackgroundComputerUseTests/InteractionTokenTests.swift`, and `Tests/BackgroundComputerUseTests/RuntimeExecutionQueueTests.swift`. STOP if any is neither committed after `0110ffb` nor present as a working-tree change.

## Status

- **Priority**: P1
- **Effort**: M/L
- **Risk**: MED
- **Depends on**: plans/001-build-fingerprint.md
- **Category**: dx
- **Planned at**: commit `0110ffb`, 2026-09-02

## Why this matters

The runtime currently prints startup state to transient standard streams, silently ignores artifact-write failures, and records Control activity only after decoded actions execute. A crash can therefore leave no useful unified log, a valid-looking manifest, and a dead port. This plan adds privacy-bounded correlated telemetry, a token-protected recent-event API and one-shot doctor mode, then makes abnormal exits recoverable through an opt-in per-user LaunchAgent without relaunching after the user's explicit Quit.

## Current state

- `Sources/BackgroundComputerUse/App/BackgroundComputerUseServer.swift:29-36` uses `print` and `fputs`, then enters the AppKit event loop:
  ```swift
  let state = try resultBox.unwrapped()
  print("BackgroundComputerUse running at \(state.baseURL.absoluteString)")
  print("Runtime manifest: \(state.manifestPath)")
  AppKitRuntimeBootstrap.runEventLoop()
  ```
- `Sources/BackgroundComputerUse/API/Router.swift:377-438` returns `control_paused`, `control_policy_required`, `control_denied`, and `control_identity_unresolvable` before decoded work. `Router.swift:498-525` calls `publishControlActivity` only on the successful decode/work path, so those decisions never become correlated activity.
- `Router.swift:585-603` discards artifact failures with `_ = try? debugArtifactRecorder.record(...)`.
- `Sources/BackgroundComputerUse/Runtime/DebugArtifactRecorder.swift:15-22,77-80` confirms artifacts are opt-in through `BACKGROUND_COMPUTER_USE_DEBUG_ARTIFACTS`; they cannot be the default operational log.
- `Sources/BackgroundComputerUse/App/RuntimeBootstrap.swift:20-50` writes the manifest after listener startup but exposes no stop/cleanup operation. `Sources/BackgroundComputerUse/API/LoopbackServer.swift:39-65` clears in-memory URL state on failure/cancellation but does not remove the on-disk manifest.
- `Sources/BackgroundComputerUseControl/ControlViewModel.swift:176-179` orders explicit Quit as `stop()` then `onQuit()`. `Sources/BackgroundComputerUseControl/BCUControlRuntime.swift:80-82` supplies `NSApplication.shared.terminate(nil)`. Preserve that exit as a normal status-0 termination.
- `docs/plans/2026-08-28-bcu-direct-quit-menu-design.md:23-28` deliberately puts ordered quit ownership in `ControlViewModel` and native termination in `BCUControlRuntime`; do not replace that design with a second quit path.
- `Sources/BackgroundComputerUseServer/main.swift:5-9` already multiplexes `--ocr-worker` and `--ax-bootstrap-worker`; `--doctor` belongs in this argument dispatch and must return before Control/runtime startup.
- `Sources/BackgroundComputerUse/OCR/OCRWorkerMain.swift:5-20` emits only a generic `fputs` failure. `Sources/BackgroundComputerUse/Runtime/Process/BoundedProcessRunner.swift:163-180` measures process duration/deadline but emits no lifecycle diagnostics.
- `openspec/project.md:13-15` requires layer direction, verifier-honest action outcomes, and `/v1/routes` as the contract source of truth. Lines 17-23 name all five route wiring points; diagnostics must update each one. Lines 31-35 establish the `/v1` token as the local-user boundary and forbid treating loopback alone as authorization.
- Plan 001 adds `RuntimeBuildIdentity.current` and `RuntimeBuildIdentityDTO { identity, commit, dirty, sourcesSHA256 }`; health and the manifest also gain `build`, `pid`, and process `startedAt`. This plan must consume that API, not invent another fingerprint.
- Measured incident context: a live Electron run had 220–330 ms warm OCR and AX trees around 70 levels, while a crash left no useful `os_log` entry. Logging must stay O(1), bounded, and independent of AX tree or screenshot size.

## Commands you will need

| Purpose | Command | Expected on success |
|---|---|---|
| Event log | `swift test --filter RuntimeEventLogTests` | exit 0; ring, filters, crash metadata, and redaction pass |
| Diagnostics route | `swift test --filter RuntimeDiagnosticsRouteTests` | exit 0; auth/query/contract cases pass |
| Lifecycle | `swift test --filter RuntimeLifecycleTests` | exit 0; owned-manifest cleanup cases pass |
| Existing Control policy | `swift test --filter ActivityControlTests` | exit 0; early decision behavior remains fail-closed |
| LaunchAgent syntax | `bash -n script/install_launch_agent.sh && script/install_launch_agent.sh --dry-run | plutil -lint -` | exit 0; plist on stdout is valid |
| OpenSpec | `openspec validate add-runtime-diagnostics --strict` | exit 0 when CLI exists |
| Final suite | `swift test` | exit 0; complete suite passes |

## Scope

**In scope** (the only files you should modify):
- `Sources/BackgroundComputerUse/Runtime/RuntimeLogging.swift` (create)
- `Sources/BackgroundComputerUse/Runtime/RuntimeEventLog.swift` (create)
- `Sources/BackgroundComputerUse/Contracts/DiagnosticsContracts.swift` (create)
- `Sources/BackgroundComputerUse/API/RouteRegistry.swift`
- `Sources/BackgroundComputerUse/API/APIDocumentation.swift`
- `Sources/BackgroundComputerUse/API/Router.swift`
- `Sources/BackgroundComputerUse/API/LoopbackServer.swift`
- `Sources/BackgroundComputerUse/Runtime/RuntimeServices.swift`
- `Sources/BackgroundComputerUse/Runtime/Process/BoundedProcessRunner.swift`
- `Sources/BackgroundComputerUse/OCR/OCRWorkerMain.swift`
- `Sources/BackgroundComputerUse/OCR/OCRWorkerClient.swift`
- `Sources/BackgroundComputerUse/App/BackgroundComputerUseRuntime.swift`
- `Sources/BackgroundComputerUse/App/BackgroundComputerUseControlBridge.swift`
- `Sources/BackgroundComputerUse/App/RuntimeBootstrap.swift`
- `Sources/BackgroundComputerUse/App/AppKitRuntimeBootstrap.swift`
- `Sources/BackgroundComputerUse/App/BackgroundComputerUseServer.swift`
- `Sources/BackgroundComputerUseServer/main.swift`
- `script/install_launch_agent.sh` (create)
- `skills/background-computer-use/references/runtime.md`
- `Tests/BackgroundComputerUseTests/RuntimeEventLogTests.swift` (create)
- `Tests/BackgroundComputerUseTests/RuntimeDiagnosticsRouteTests.swift` (create)
- `Tests/BackgroundComputerUseTests/RuntimeLifecycleTests.swift` (create)
- `Tests/BackgroundComputerUseTests/ActivityControlTests.swift`
- `Tests/BackgroundComputerUseTests/RuntimeFacadePublicAPITests.swift`
- `openspec/changes/add-runtime-diagnostics/proposal.md` (create)
- `openspec/changes/add-runtime-diagnostics/tasks.md` (create)
- `openspec/changes/add-runtime-diagnostics/specs/runtime-diagnostics/spec.md` (create)
- `plans/README.md` (status row only)

**Out of scope** (do NOT touch, even though related):
- Raw request/response artifact redaction and script audit retention; plan 020 owns those.
- Private-symbol loading behavior; consume `PrivateSymbolCapabilities` only if plan 014 has landed, otherwise report `n/a`.
- Changing action success classifications or adding foreground retries.
- Installing or launching the app while implementing; live permission and crash-relaunch QA requires explicit operator authorization.
- A system LaunchDaemon or root helper. Supervision is opt-in and per-user only.

## Git workflow

- Branch: `advisor/018-observability-diagnostics-supervisor`
- Commit logical units with conventional messages such as `feat: add correlated runtime diagnostics` and `feat: add opt-in runtime supervisor`.
- Do NOT push or open a PR unless the operator instructed it.

## Steps

### Step 1: Specify the diagnostics contract before code

Create the OpenSpec change with a token-protected `GET /v1/diagnostics?requestID=&session=&since=` requirement, conjunctive optional filters, ISO-8601 `since`, bounded newest-first results, and HTTP 400 `invalid_request` for an invalid timestamp. Specify that diagnostics remain available while Control is paused/stopped but never without the runtime token. Add requirements for privacy-safe fields, graceful manifest invalidation, abnormal-only relaunch, and `--doctor` having no launch side effects.

The spec must explicitly forbid auth tokens, request/response bodies, typed/pasted/selected text, clipboard data, script source, AX values, window titles, screenshot paths/bytes, process stdin/stdout/stderr, and arbitrary error descriptions in both unified logs and `RuntimeEventLog`.

**Verify**: `if command -v openspec >/dev/null; then openspec validate add-runtime-diagnostics --strict; else echo 'openspec unavailable; validation skipped'; fi` → strict validation passes, or the exact skip message is printed.

### Step 2: Add privacy-typed unified logging and the bounded event ring

Create `RuntimeLogging.swift` with category-specific `os.Logger` values using subsystem `xyz.dubdub.backgroundcomputeruse`: `server`, `router`, `ocr`, `process`, and `control`. Callers may interpolate only allowlisted scalar fields with `privacy: .public`: request ID, route ID, HTTP status, classification, duration milliseconds, stable error/detail code, process exit status, timeout flag, and byte counts. Never pass an `Error`, body, URL query, payload, script arguments, path, or DTO description to Logger.

Create `RuntimeEventLog.swift` as a synchronous `final class RuntimeEventLog: @unchecked Sendable` with an `NSLock`, one lazy process-wide `static let shared`, default capacity 500, append eviction from the oldest edge, and newest-first snapshot filtering. Keep an injectable initializer so Router/OCR tests can use isolated rings. Use public DTOs from `DiagnosticsContracts.swift`:

```swift
public enum RuntimeEventKindDTO: String, Codable, Sendable {
    case authorization, routeStarted, routeFinished, failure, ocr, process, priorTermination
}
public struct RuntimeEventDTO: Codable, Sendable {
    public let id: String
    public let timestamp: String
    public let kind: RuntimeEventKindDTO
    public let requestID: String?
    public let session: String?
    public let route: String?
    public let statusCode: Int?
    public let classification: String?
    public let errorCode: String?
    public let durationMs: Double?
    public let priorTermination: PriorTerminationMetadataDTO?
}
```

Do not add a generic message or `[String: Any]` metadata field. Add a crash reader that selects the newest `~/Library/Logs/DiagnosticReports/BackgroundComputerUse-*.ips`, parses only timestamp/capture time, exception type, and the first triggered-thread frame symbol, and returns nil on absent/malformed reports. Store its basename, never its full path. Inject the reader and clock in tests.

**Verify**: `swift test --filter RuntimeEventLogTests` → tests prove capacity 500 evicts oldest, request/session/since filters are conjunctive and newest-first, malformed crash reports are ignored, and encoded events contain no sentinel payload.

### Step 3: Correlate every Router outcome and expose diagnostics

Use the process-wide `RuntimeEventLog.shared` in `RuntimeBootstrap`, then inject that same reference through `LoopbackServer`, `Router`, and `RuntimeServices`; Router tests may pass an isolated log. Refactor `Router.response` into a thin boundary that creates one request ID and monotonic start time, resolves a known `RouteID` from method/path, appends `routeStarted`, delegates to a private route switch, then appends/logs `routeFinished` or `failure`. Extract only `classification` and `error` from the response JSON; never store summaries or bodies. Pass the boundary request ID into `decodeAndExecute` so artifacts, response errors, activity, unified logs, and event entries correlate.

Record authorization events for read pause, mutation pause, arbitrary-script denial, window allow/ask/deny, and identity-unresolvable decisions. Extend `RouterControlPolicy.authorizeWindow` and `BackgroundComputerUseControlBridge.authorizeWindow` with `requestID`; update every test closure. Log stable decision/error codes, not resolver error descriptions. Replace artifact `try?` with `do/catch` that records/logs only `artifact_write_failed`.

Move Control activity publication out of the decoded-work success branch and into the same Router finish boundary for every recognized action route. Publish exactly once for success and early 403/423/429/409 outcomes, using fixed safe summaries for pre-dispatch failures. Extend the bridge activity sink with `requestID`; in `Sources/BackgroundComputerUseServer/main.swift`, use it as `ActivityEnvelope.id` instead of creating a second UUID. Keep diagnostics and read routes out of the activity timeline.

Add `RouteID.diagnostics`, a GET descriptor in category `system`, query/response schemas, APIDocumentation usage/errors, `RuntimeServices.diagnostics(_:)`, Router dispatch, `BackgroundComputerUseRuntime.diagnostics(_:)`, and public constructors. The response shape is:

```swift
public struct RuntimeDiagnosticsRequest: Sendable {
    public let requestID: String?
    public let session: String?
    public let since: String?
}
public struct RuntimeDiagnosticsResponse: Encodable, Sendable {
    public let contractVersion: String
    public let build: RuntimeBuildIdentityDTO
    public let pid: Int32
    public let startedAt: String?
    public let permissions: RuntimePermissionsDTO
    public let controlConnected: Bool
    public let priorTermination: PriorTerminationMetadataDTO?
    public let events: [RuntimeEventDTO]
}
```

Keep the existing host and token guards. Exempt only `/v1/diagnostics` from `controlPolicy.readAllowed()`, so a stopped Control cannot hide why it stopped; it remains token-protected. Do not add diagnostics to `isActionRoute`.

**Verify**: `swift test --filter RuntimeDiagnosticsRouteTests && swift test --filter ActivityControlTests && swift test --filter RuntimeFacadePublicAPITests` → authenticated filtering returns 200, missing/wrong token returns 401, invalid `since` returns 400, stopped Control still permits authenticated diagnostics, and early 403/423 outcomes reach both the event log and Control activity exactly once with the response request ID.

### Step 4: Instrument server, workers, process execution, and Control decisions

Replace server/OCR `print` and `fputs` operational reporting with the typed log categories (stderr may retain a one-line CLI failure, but unified logging is authoritative). Log listener ready/failed/cancelled, startup complete/failure, OCR start/end/failure, and process spawn/end/timeout/failure. Process logs include status, duration, timeout, truncation flags, and byte counts only—never executable path, arguments, environment, stdin, stdout, or stderr. OCR logs never include image path or recognized text.

Expose a lock-protected `BackgroundComputerUseControlBridge.connectivitySnapshot()` containing only configured/connected booleans. Log configure/disconnect and allow/deny/error decision codes; do not log identities, designated requirements, session IDs, or window IDs. `BoundedProcessRunner` appends process failures to `RuntimeEventLog.shared`. Give `OCRWorkerClient` an injectable event log (default `.shared`) and append `.ocr` failures with stable codes such as `encode_failed`, `launch_failed`, `timed_out`, `nonzero_exit`, `truncated`, and `invalid_response`; never put its human diagnostic or recognized text in the event.

**Verify**: `swift test --filter RuntimeEventLogTests && swift test --filter BoundedProcessRunnerTests && swift test --filter OCRWorkerTests` → existing worker/process behavior passes and failure events contain only allowlisted fields.

### Step 5: Add a side-effect-free `--doctor` mode

Dispatch `--doctor` in `Sources/BackgroundComputerUseServer/main.swift` before constructing `BCUControlRuntime`. Implement the doctor in the library so it reads plan 001's manifest/build identity, checks manifest PID/start identity and `/health` with a short deadline, reads live permissions and authenticated diagnostics when reachable, and prints stable key/value lines for: build identity, manifest existence/ownership, process liveness, health, Accessibility, Screen Recording, private symbols, Control connectivity, and prior termination metadata.

If plan 014's `PrivateSymbolCapabilities` exists, print one availability line per probed private symbol; otherwise print exactly `privateSymbols: n/a (plan 014 not landed)`. If the runtime is dead, print Control connectivity as `n/a`, not false. Never print base URL query data, token, crash-report path, or diagnostic event bodies. Exit 0 when checks execute even if health/permissions are degraded; reserve nonzero for malformed CLI usage or an internal doctor failure.

**Verify**: `swift run BackgroundComputerUse --doctor` → exits 0 without launching the app/runtime and prints every named key; output contains neither `authToken` nor `X-Background-Computer-Use-Token`.

### Step 6: Remove only this process's manifest on graceful termination

Add an AppKit termination hook registered after `RuntimeBootstrap.start()` writes the manifest. Its cleanup cancels the listener and unlinks `runtime-manifest.json` only after rereading it and confirming both plan 001's `pid == getpid()` and build identity match this process. This ownership guard prevents an older terminating process from deleting a newer process's manifest. `SecureFileWriter.write` already gives atomic start-time replacement; preserve it on every start.

Do not remove the manifest from crash/signal handlers. A crash is recovered by launchd and the next successful start atomically rewrites it. Preserve `ControlViewModel.quit()` → stop → native terminate so explicit Quit reaches AppKit termination and exits successfully.

**Verify**: `swift test --filter RuntimeLifecycleTests` → owned manifest is removed on simulated graceful termination, mismatched PID/build manifests remain, and each start rewrites stale content.

### Step 7: Add the opt-in per-user LaunchAgent and operator docs

Create `script/install_launch_agent.sh` with `--dry-run`, `--install`, and `--uninstall`. Dry-run prints only the plist. Install writes owner-only `~/Library/LaunchAgents/xyz.dubdub.backgroundcomputeruse.plist` atomically and bootstraps it in `gui/$UID`; uninstall bootouts and removes only that label. Resolve the executable under `~/Applications/BackgroundComputerUse.app` and fail before mutation if absent.

The plist must contain `RunAtLoad=true`, `ThrottleInterval=10`, and:

```xml
<key>KeepAlive</key>
<dict><key>SuccessfulExit</key><false/></dict>
```

Do not set unconditional KeepAlive. Explicit Quit follows the existing status-0 path and stays stopped; crashes/nonzero exits relaunch with launchd throttling. Document opt-in/install/uninstall, `--doctor`, diagnostics filters, and exactly:

```bash
log stream --predicate 'subsystem == "xyz.dubdub.backgroundcomputeruse"' --level info
```

in `skills/background-computer-use/references/runtime.md`. State the sensitive-field exclusions there.

**Verify**: `bash -n script/install_launch_agent.sh && script/install_launch_agent.sh --dry-run | plutil -lint -` → shell syntax and plist lint pass; no LaunchAgent is installed by dry-run.

### Step 8: Run the final non-live gate

Run focused suites first, then the project suite once. Do not run `script/start.sh`, install the LaunchAgent, crash the signed app, or execute live smoke on this host.

**Verify**: `swift test` → exit 0; complete suite passes.

## Test plan

- `RuntimeEventLogTests.swift`: exact ring capacity/eviction, thread-safe concurrent append, newest-first conjunctive filters, inclusive `since`, crash metadata allowlist, malformed report, and sentinel absence after encoding.
- `RuntimeDiagnosticsRouteTests.swift`: model Router construction and raw requests after `ActivityControlTests.swift:188-238`; cover valid token, invalid token, stopped Control exemption, invalid timestamp, all filters, registry request/response fields, and early 403/423 correlation.
- `RuntimeLifecycleTests.swift`: inject a temporary manifest URL and process identity; prove owned removal, mismatched owner preservation, and atomic rewrite.
- Update `ActivityControlTests.swift` for request-ID-aware authorization/activity closures; assert early denials append payload-free authorization events and publish exactly one activity with the response request ID.
- Update `RuntimeFacadePublicAPITests.swift` with non-`@testable` construction of `RuntimeDiagnosticsRequest` and the `runtime.diagnostics` function type.
- Existing `BoundedProcessRunnerTests` and `OCRWorkerTests` remain behavior regressions; add event-sink assertions without launching a live app.
- Verification: `swift test --filter RuntimeEventLogTests && swift test --filter RuntimeDiagnosticsRouteTests && swift test --filter RuntimeLifecycleTests && swift test --filter ActivityControlTests` → all pass.

## Done criteria

- [ ] Unified logs use subsystem `xyz.dubdub.backgroundcomputeruse` and only allowlisted scalar metadata.
- [ ] The event ring is thread-safe, capped at 500, filterable, and cannot encode a sentinel request/body value.
- [ ] Every recognized Router request has one correlated request ID across response errors, events, artifacts, and logs.
- [ ] Early action denials publish exactly one Control activity using the Router request ID.
- [ ] `GET /v1/diagnostics` is documented in `/v1/routes`, token-protected, and available while Control is stopped.
- [ ] `swift run BackgroundComputerUse --doctor` performs no runtime/app launch and never prints the token.
- [ ] Graceful explicit Quit removes only the owning manifest and exits successfully.
- [ ] LaunchAgent dry-run lints; `KeepAlive.SuccessfulExit=false` and throttling are present.
- [ ] `swift test` exits 0.
- [ ] `git status --short` shows only in-scope files and the pre-existing baseline changes.
- [ ] `plans/README.md` status row is updated.

## STOP conditions

Stop and report back (do not improvise) if:

- Plan 001 has not landed with `RuntimeBuildIdentity.current`, manifest `build`/`pid`, and health `build`/`pid`; diagnostics must not create a competing identity.
- Current Router early-control branches or direct-quit ordering differ from the excerpts.
- Making diagnostics available while Control is stopped would require bypassing the runtime token guard.
- A private-symbol status requires loading a symbol outside plan 014's `PrivateSymbolCapabilities`; print `n/a` instead.
- LaunchAgent validation requires installing, launching, signing, or crashing the app on the primary host.
- A logging call would need a payload, arbitrary error description, file path, or other non-allowlisted data.
- A focused verification fails twice after a reasonable fix attempt.

## Maintenance notes

- Any new route must flow through the Router boundary so start/end/failure correlation is automatic; reviewers should reject route-local body logging.
- When plan 014 lands, replace only the doctor's `n/a` adapter with `PrivateSymbolCapabilities`; do not duplicate symbol loading.
- If diagnostics fields change, update Contracts, RouteRegistry, APIDocumentation, facade tests, and OpenSpec together.
- Review launchd changes specifically for abnormal-only relaunch and manifest ownership races. Live crash recovery remains operator-authorized QA on a disposable/safe host.