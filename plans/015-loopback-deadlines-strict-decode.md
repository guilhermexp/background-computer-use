# Plan 015: Bound loopback reads and reject malformed requests before admission

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**: `git diff --stat 0110ffb..HEAD -- Sources/BackgroundComputerUse/API/LoopbackServer.swift Sources/BackgroundComputerUse/API/HTTPTypes.swift Sources/BackgroundComputerUse/API/Router.swift Sources/BackgroundComputerUse/API/RouteRegistry.swift Sources/BackgroundComputerUse/Contracts/CommonContracts.swift Sources/BackgroundComputerUse/Contracts/RouteRequestContracts.swift Sources/BackgroundComputerUse/Contracts/StrictKeyedDecoding.swift Tests/BackgroundComputerUseTests/LoopbackServerTimeoutTests.swift Tests/BackgroundComputerUseTests/HardenedAgentAPITests.swift openspec/changes/bound-loopback-and-strict-decoding plans/README.md`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P1
- **Effort**: M
- **Risk**: MED
- **Depends on**: none
- **Category**: security
- **Planned at**: commit `0110ffb`, 2026-09-02

## Why this matters

The listener accepts unlimited unauthenticated connections and retains every partial request forever, so any local process can exhaust queues, connections, and memory before token authentication runs. Typed decoding also occurs after action admission, allowing a missing or wrong-typed field to consume the caller's rate-limit slot. Finally, only root JSON keys are strict; misspelled keys inside `target` and `cursor` are silently ignored. This plan bounds pre-auth resources and makes malformed input fail consistently without charging action admission.

## Current state

- `Sources/BackgroundComputerUse/API/LoopbackServer.swift` owns one `NWListener` and recursively buffers one HTTP request per accepted connection.
  - `LoopbackServer.swift:35-37`: `listener.newConnectionHandler = { [weak self] connection in self?.handle(connection: connection) }` has no admission check.
  - `LoopbackServer.swift:72-79`: every accepted connection creates a unique serial queue, starts, and immediately calls `receiveRequest`.
  - `LoopbackServer.swift:85-123`: `receive` has no timer; `.incomplete` recursively receives with the accumulated `Data`.
- `Sources/BackgroundComputerUse/API/HTTPTypes.swift` parses and byte-bounds requests.
  - `HTTPTypes.swift:21-22`: headers are limited to 64 KiB and bodies to 10 MiB.
  - `HTTPTypes.swift:42-49`: a header without `\r\n\r\n` remains `.incomplete` indefinitely while under the byte cap.
  - `HTTPTypes.swift:104-115`: `Content-Length` is validated and body completeness is known, but that progress is not exposed to the server.
- `Sources/BackgroundComputerUse/API/Router.swift` owns strict root-field checks and action gates.
  - `Router.swift:351-375`: `decodeAndExecute` rejects unknown root fields before admission.
  - `Router.swift:441-461`: `sessionLimiter.beforeAction()` runs before typed decoding.
  - `Router.swift:464-499`: session acquisition also precedes `JSONSupport.decoder.decode`.
  - `Router.swift:736-745`: `unknownTopLevelFields` compares only the root dictionary with `RouteRegistry.requestFieldNames`.
  - `Router.swift:792-819`: decoding errors already render their `codingPath`, so a nested strict-decoder error can report `target.extra` or `cursor.extra` without a new response type.
- `Sources/BackgroundComputerUse/Contracts/RouteRequestContracts.swift` and `CommonContracts.swift` contain the nested request objects.
  - `RouteRequestContracts.swift:110-143`: `ActionTargetRequestDTO.CodingKeys` contains `kind` and `value`, but its decoder never rejects other keys.
  - `CommonContracts.swift:56-66`: `CursorRequestDTO` uses synthesized decoding for `id`, `name`, and `color`, which also ignores unknown keys.
- `Tests/BackgroundComputerUseTests/HardenedAgentAPITests.swift:28-47` says invalid requests do not consume admission, but sends only an unknown root field that returns before the limiter.
- Project constraints from `openspec/project.md:7-15`: Swift 6.2/macOS 14, Swift Testing rather than XCTest, `Contracts` is a leaf layer, and `GET /v1/routes` must match the real request DTOs.
- Security posture from `openspec/project.md:31-35`: the server is single-user loopback, but loopback is not a user boundary; the token protects `/v1`, so pre-auth listener limits are still required.

## Commands you will need

| Purpose | Command | Expected on success |
|---|---|---|
| Prerequisite check | `git status --short -- Sources/BackgroundComputerUse/API/Router.swift Sources/BackgroundComputerUse/App/BackgroundComputerUseControlBridge.swift Sources/BackgroundComputerUseControlShared/CodeSignatureIdentity.swift Sources/BackgroundComputerUse/Runtime/RuntimeExecutionQueue.swift Sources/BackgroundComputerUse/Actions/TypeText/AdaptiveTextDispatcher.swift Sources/BackgroundComputerUse/StatePipeline/InteractionToken.swift Sources/BackgroundComputerUse/Runtime/Process/BoundedProcessRunner.swift skills/background-computer-use/scripts/bcu-request.py Tests/BackgroundComputerUseTests/InteractionTokenTests.swift Tests/BackgroundComputerUseTests/RuntimeExecutionQueueTests.swift && git diff --name-only 0110ffb..HEAD -- Sources/BackgroundComputerUse/API/Router.swift Sources/BackgroundComputerUse/App/BackgroundComputerUseControlBridge.swift Sources/BackgroundComputerUseControlShared/CodeSignatureIdentity.swift Sources/BackgroundComputerUse/Runtime/RuntimeExecutionQueue.swift Sources/BackgroundComputerUse/Actions/TypeText/AdaptiveTextDispatcher.swift Sources/BackgroundComputerUse/StatePipeline/InteractionToken.swift Sources/BackgroundComputerUse/Runtime/Process/BoundedProcessRunner.swift skills/background-computer-use/scripts/bcu-request.py Tests/BackgroundComputerUseTests/InteractionTokenTests.swift Tests/BackgroundComputerUseTests/RuntimeExecutionQueueTests.swift` | every listed prerequisite appears in at least one of the two outputs; otherwise STOP |
| Listener tests | `swift test --filter LoopbackServerTimeoutTests` | all tests pass |
| Decode tests | `swift test --filter StrictRequestDecodingTests` | all tests pass |
| Full verification | `swift test` | all tests pass; baseline is 391 tests before this plan |
| OpenSpec availability | `which openspec` | prints a path, or exits nonzero and validation is explicitly skipped/noted |

## Scope

**In scope** (the only files you should modify):
- `Sources/BackgroundComputerUse/API/LoopbackServer.swift`
- `Sources/BackgroundComputerUse/API/HTTPTypes.swift`
- `Sources/BackgroundComputerUse/API/Router.swift`
- `Sources/BackgroundComputerUse/API/RouteRegistry.swift`
- `Sources/BackgroundComputerUse/Contracts/CommonContracts.swift`
- `Sources/BackgroundComputerUse/Contracts/RouteRequestContracts.swift`
- `Sources/BackgroundComputerUse/Contracts/StrictKeyedDecoding.swift` (create)
- `Tests/BackgroundComputerUseTests/LoopbackServerTimeoutTests.swift` (create)
- `Tests/BackgroundComputerUseTests/HardenedAgentAPITests.swift`
- `openspec/changes/bound-loopback-and-strict-decoding/proposal.md` (create)
- `openspec/changes/bound-loopback-and-strict-decoding/tasks.md` (create)
- `openspec/changes/bound-loopback-and-strict-decoding/specs/runtime-security/spec.md` (create)
- `openspec/changes/bound-loopback-and-strict-decoding/specs/request-validation/spec.md` (create)
- `plans/README.md` (status row only)

**Out of scope** (do NOT touch, even though related):
- Authentication/token format, CORS, nonce/replay, or non-loopback binding.
- HTTP keep-alive, chunked transfer, pipelining, TLS, or replacing `Network.framework`.
- Request/response field renames; this plan only tightens unknown-field behavior.
- Action semantics, session-limit values, or control-policy decisions.

## Git workflow

- Branch: `advisor/015-loopback-deadlines-strict-decode`
- Preserve the prerequisite working-tree fixes listed above; STOP rather than resetting or overwriting them.
- Commit logical units with the observed style, for example `fix: bound loopback request admission` and `fix: decode actions before admission`.
- Do NOT push or open a PR unless the operator instructed it.

## Steps

### Step 1: Record the strictness and deadline contract in OpenSpec

Create the four listed OpenSpec files. Modify the existing `runtime-security` capability with connection admission/header/body deadline requirements, and modify `request-validation` from root-only strictness to root plus nested `target`/`cursor` strictness and decode-before-admission. State these exact behaviors: at most 64 live accepted connections; excess connections receive HTTP 503 and close; headers have a 5-second absolute read deadline; after valid headers arrive, the body deadline is `30 seconds + 1 second per started MiB of declared Content-Length`; timeout returns HTTP 408 and closes; malformed typed bodies are rejected before control, session, and rate admission; unknown keys are rejected at root and nested paths. Use the required `## Why`, `## What Changes`, `## Impact`, checklist, `SHALL`, and `WHEN/THEN` structure from `openspec/project.md:25-29`. The final task must include focused tests, `swift test`, strict OpenSpec validation, and an operator-gated live smoke entry marked skipped because this plan does not authorize launching the signed app.

**Verify**: `openspec validate bound-loopback-and-strict-decoding --strict` when `which openspec` succeeds; otherwise record “OpenSpec CLI unavailable; validation skipped” in the plan execution notes → validation exits 0 or the absence is explicitly noted.

### Step 2: Expose request read phase without duplicating header parsing

In `HTTPTypes.swift`, add an internal `HTTPRequestReadStage` with `.headers` and `.body(contentLength: Int)`. Refactor the existing header separator/header/`Content-Length` parsing into one private helper used by both `HTTPRequest.parse` and `HTTPRequest.readStage(for:)`; do not create a second permissive parser. `readStage(for:)` must return `.body` only after the same valid, within-limit headers accepted by `parse`; malformed/oversized inputs continue through `.invalid`/`.tooLarge`.

Target shape:

```swift
enum HTTPRequestReadStage: Equatable {
    case headers
    case body(contentLength: Int)
}

static func readStage(for data: Data) -> HTTPRequestReadStage {
    guard case let .valid(head) = parseHead(data) else { return .headers }
    return .body(contentLength: head.contentLength)
}
```

Keep `HTTPRequestParseResult` cases unchanged so existing exhaustive test switches do not need a repo-wide migration.

**Verify**: `swift test --filter APIDocumentationTests` → all tests pass and existing request parsing still compiles.

### Step 3: Add connection admission and stage deadlines

Add internal, test-injectable `LoopbackServer.Configuration` defaults: `maximumLiveConnections = 64`, `headerTimeout = 5`, `bodyBaseTimeout = 30`, `bodySecondsPerMiB = 1`. Add an initializer parameter with this default. Manage live slots behind one `NSLock`; reserve before normal handling, and release exactly once on every send completion, receive error, timeout, cancellation, and explicit `stop()`.

Represent each admitted connection with a queue-confined session object containing its `NWConnection`, buffer, current stage, one `DispatchSourceTimer`, and a single `finish` gate. Arm the header timer when accepted. When parsing first reports incomplete body, replace it with an absolute body timer computed from declared length. Do not reset either absolute deadline for one-byte progress.

Target shape:

```swift
let mib = max(1, (contentLength + (1 << 20) - 1) / (1 << 20))
let timeout = configuration.bodyBaseTimeout
    + Double(mib) * configuration.bodySecondsPerMiB
session.arm(stage: .body, after: timeout)
```

On expiry, `finish` sends JSON error `request_timeout` with HTTP 408/`Request Timeout`, then cancels. When no slot is available, start the connection on a short queue, send JSON error `server_busy` with HTTP 503/`Service Unavailable`, and cancel without adding it to the live set. Add internal `stop()` that cancels the listener and all admitted sessions so real-port tests leave no live resources.

**Verify**: `swift test --filter LoopbackServerTimeoutTests` → the new file compiles; tests may still be pending until Step 4, with no failures outside missing test bodies.

### Step 4: Exercise the real listener on an ephemeral port

Create `LoopbackServerTimeoutTests.swift` with `@Suite(.serialized)`. Start `LoopbackServer(auth: .disabled, configuration: shortTestConfiguration)` via `await server.start()`, connect to its returned port using `NWConnection`, send raw bytes, receive until the server closes, and `defer { server.stop() }`. Add these deterministic cases:

1. send `GET /health HTTP/1.1\r\nHost: 127.0.0.1` without the header terminator; expect status 408 and closure within 1 second;
2. send valid headers declaring 10 body bytes plus one body byte; expect 408 within 1 second and later than the configured header timeout, proving transition to the body timer;
3. with capacity 1, hold one partial header and open a second connection; expect immediate 503, then let the first time out and prove a third complete `/health` request receives 200;
4. pure configuration check for 1 byte, exactly 1 MiB, and 1 MiB + 1 byte so body scaling uses started MiB and cannot overflow.

Use continuations only with a lock-backed resume gate, matching `LoopbackServer.swift:182-193`; never sleep for the production 5/30-second values.

**Verify**: `swift test --filter LoopbackServerTimeoutTests` → 4 tests pass in a few seconds and no test leaves a listener running.

### Step 5: Decode before control, session, and rate admission

Refactor `Router.decodeAndExecute` into this exact order: root unknown-field check; typed decode into one local `payload`; action control/window authorization; session acquire with `defer` release; action `beforeAction`; invoke `work(payload)`. Preserve `rejectedScriptAuditFailureResponse`, activity publication, artifact recording, and current error response bodies at every return.

Do not decode twice and do not move authentication/Host checks from `response(for:context:)`. Extract a small private `decodingFailureResponse` helper if needed to avoid duplicating the current lines 507-520 behavior.

Extend `invalidRequestsDoNotConsumeActionRateLimit` into table-driven fresh-limiter cases for press-key bodies missing `key`, using numeric `key`, and using an invalid enum on a typed action field. After each HTTP 400, call `limiter.beforeAction()` directly and expect `allowed == true`; this proves the malformed request did not consume the one-per-second slot without requiring Accessibility permissions or dispatching a valid action.

**Verify**: `swift test --filter StrictRequestDecodingTests` → all strict-decoding tests pass, including all three typed-malformation variants.

### Step 6: Reject unknown keys in every nested request object

Create `Contracts/StrictKeyedDecoding.swift` as a leaf-layer helper. Use a dynamic `CodingKey` to inspect `allKeys`, compare against `CodingKeys.allCases`, sort unknown names, and throw `DecodingError.dataCorrupted` whose `codingPath` appends the first unknown key and whose debug description lists all unknown keys.

```swift
enum StrictKeyedDecoding {
    static func container<Key>(from decoder: Decoder, keyedBy: Key.Type) throws -> KeyedDecodingContainer<Key>
    where Key: CodingKey & CaseIterable {
        let raw = try decoder.container(keyedBy: AnyStringCodingKey.self)
        let allowed = Set(Key.allCases.map(\.stringValue))
        let unknown = raw.allKeys.filter { !allowed.contains($0.stringValue) }.sorted { $0.stringValue < $1.stringValue }
        if let first = unknown.first {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath + [first],
                debugDescription: "Unknown field(s): \(unknown.map(\.stringValue).joined(separator: ", "))."
            ))
        }
        return try decoder.container(keyedBy: Key.self)
    }
}
```

Make `ActionTargetRequestDTO.CodingKeys` and a new `CursorRequestDTO.CodingKeys` conform to `CaseIterable`. Use this helper in `ActionTargetRequestDTO.init(from:)`; give `CursorRequestDTO` an explicit decoder using the helper while preserving its public initializer and synthesized encoder. Do not apply it to response DTOs. Update the `/v1/routes` global note at `RouteRegistry.swift:92-95` from “unknown top-level” to “unknown field at any documented object boundary.”

Add one Router-level test for `target.extra` and one for `cursor.extra`; assert HTTP 400, `invalid_request`, and the complete nested path in `message`. Use fresh routers so no AX work executes after decoding fails.

**Verify**: `swift test --filter StrictRequestDecodingTests` → nested target and cursor tests pass and messages contain `target.extra` and `cursor.extra` respectively.

### Step 7: Run the complete gate once

Run the full suite only after all focused tests pass. Inspect `git status --short` and confirm only in-scope files plus preserved prerequisite changes are present. Update only plan 015's status row in `plans/README.md`.

**Verify**: `swift test` → exit 0 with all baseline and new tests passing.

## Test plan

- New `LoopbackServerTimeoutTests.swift`: real ephemeral listener, partial header 408, partial body 408, capacity 503/recovery, body-time scaling.
- Extended `StrictRequestDecodingTests`: missing required field, wrong type, invalid enum do not charge; unknown `target` and `cursor` keys report nested paths.
- Keep tests on Swift Testing (`import Testing`, `@Suite`, `@Test`, `#expect`, `#require`), as established in `HardenedAgentAPITests.swift:1-8`.
- Do not launch the app or run `script/start.sh`; these are pure/in-process tests.
- Verification: `swift test --filter LoopbackServerTimeoutTests && swift test --filter StrictRequestDecodingTests` → all focused tests pass.

## Done criteria

- [ ] The listener admits at most 64 live connections and excess clients receive 503 then close.
- [ ] Partial headers expire after 5 seconds in production; partial bodies expire after `30s + 1s/started MiB`.
- [ ] Slot release is exactly once on all terminal paths, and a rejected/timed-out connection does not reduce later capacity.
- [ ] Typed payload decoding precedes control, session, and rate admission; malformed bodies leave the limiter unused.
- [ ] Unknown `target` and `cursor` fields return 400 and name their nested coding path.
- [ ] `GET /v1/routes` describes nested strictness.
- [ ] Focused tests and one final `swift test` exit 0.
- [ ] No files outside Scope are newly modified; preserved prerequisite changes remain intact.
- [ ] `plans/README.md` status row is updated.

## STOP conditions

Stop and report back (do not improvise) if:

- Any prerequisite working-tree fix listed in Commands is absent from both `git status` and commits after `0110ffb`.
- The current-state code no longer matches the excerpts, especially if LoopbackServer already owns connection lifecycle/timers or Router already decodes before admission.
- A safe body deadline requires accepting chunked transfer or changing the 10 MiB request cap.
- Strict nested decoding would require `Contracts` to import `API` (the helper must remain in the leaf `Contracts` layer).
- A timeout/capacity test cannot observe connection closure with a real ephemeral `NWListener` after two reasonable fixes.
- Any step requires launching/installing the signed app or changing authentication semantics.
- A focused verification fails twice after a reasonable fix attempt.

## Maintenance notes

- Review exact-once slot release carefully; send callbacks, receive errors, timeout handlers, `stop()`, and listener cancellation can race.
- Deadline math must use monotonic `DispatchTime`, not `Date`, and body multiplication/addition must be overflow-safe even though parsing currently caps bodies at 10 MiB.
- If the body-size cap changes, update the scaled-deadline tests and reassess the 64-connection memory ceiling together.
- Any new nested request DTO must opt into `StrictKeyedDecoding`; response DTOs should remain unaffected.
- A dispatched transport remains distinct from effect proof; this plan changes admission only, not action classification.
