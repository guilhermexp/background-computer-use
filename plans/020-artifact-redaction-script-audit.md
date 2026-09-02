# Plan 020: Redact every debug artifact and bound the script audit trail

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**: `git diff --stat 0110ffb..HEAD -- Sources/BackgroundComputerUse/Runtime/DebugArtifactRecorder.swift Sources/BackgroundComputerUse/Actions/Script/ScriptAuditLogger.swift Sources/BackgroundComputerUse/API/RouteRegistry.swift Sources/BackgroundComputerUse/API/Router.swift Tests/BackgroundComputerUseTests/AgentAPICorrectnessTests.swift Tests/BackgroundComputerUseTests/ScriptExecutionParityTests.swift Tests/BackgroundComputerUseTests/ArtifactRedactionTests.swift Tests/BackgroundComputerUseTests/ScriptAuditLoggerTests.swift README.md skills/background-computer-use/SKILL.md openspec/project.md openspec/changes/redact-runtime-artifacts`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.
>
> Also run `git status --short` and `git diff --name-only 0110ffb..HEAD`. The union must show the baseline fixes in `Sources/BackgroundComputerUse/API/Router.swift`, `Sources/BackgroundComputerUse/App/BackgroundComputerUseControlBridge.swift`, `Sources/BackgroundComputerUseControlShared/CodeSignatureIdentity.swift`, `Sources/BackgroundComputerUse/Runtime/RuntimeExecutionQueue.swift`, `Sources/BackgroundComputerUse/Actions/TypeText/AdaptiveTextDispatcher.swift`, `Sources/BackgroundComputerUse/StatePipeline/InteractionToken.swift`, `Sources/BackgroundComputerUse/Runtime/Process/BoundedProcessRunner.swift`, `skills/background-computer-use/scripts/bcu-request.py`, `Tests/BackgroundComputerUseTests/InteractionTokenTests.swift`, and `Tests/BackgroundComputerUseTests/RuntimeExecutionQueueTests.swift`. STOP if any is neither committed after `0110ffb` nor present as a working-tree change.

## Status

- **Priority**: P2
- **Effort**: M
- **Risk**: MED
- **Depends on**: none
- **Category**: security
- **Planned at**: commit `0110ffb`, 2026-09-02

## Why this matters

Ordinary debug mode currently persists most response JSON verbatim, including AX values, selected text, verification before/after values, and optional screenshot bytes. The separate `run_script` audit stores complete source forever in one unbounded path and coordinates only threads in one process. This plan makes redaction recursive and default-deny for every route, then preserves script traceability with a digest, content-free bounded preview, interprocess-safe appends, and bounded rotation while keeping an explicit raw-source override.

## Current state

- `Sources/BackgroundComputerUse/Runtime/DebugArtifactRecorder.swift:92-127` redacts request fields only for `type_text`, `select_text`, `paste`, `set_value`, and `press_key`; other request bodies are normalized unchanged.
- `DebugArtifactRecorder.swift:129-151` recursively redacts only key `text`, and only when `routeID == read_text`; every other response takes the verbatim normalization branch.
- `DebugArtifactRecorder.swift:15-22` already has the explicit raw override `DEBUG_ARTIFACTS_RAW=1`. Preserve that exact compatibility switch as the only way ordinary artifacts retain sensitive strings.
- `Sources/BackgroundComputerUse/StatePipeline/AXPipelineV2/Contracts/AXPipelineV2Contracts.swift:76-84` exposes `text`, `attributedText`, `selectedText`, and `selectedAttributedText`; lines 181-190 show nested affordance labels/values/source titles/URLs.
- `Sources/BackgroundComputerUse/Contracts/PasteContracts.swift:49-56` returns full `beforeValue`, `expectedValue`, and `afterValue`. `Sources/BackgroundComputerUse/Contracts/UtilityActionContracts.swift:3-10` embeds a full AX state in `wait_for` responses. `FindElementsContracts.swift:38-47` returns matched surface nodes and echoes the query.
- `Sources/BackgroundComputerUse/Contracts/WindowStateContracts.swift:51-65` permits `imageBase64` in normal response JSON. Default debug artifacts must not become a second screenshot store.
- `Sources/BackgroundComputerUse/Actions/Script/ScriptAuditLogger.swift:4-13` stores `source: String` in every entry. Lines 15-16 use a process-local `NSLock`; lines 37-51 and 75-103 append/fsync one `script-executions.jsonl` with no size or retention limit.
- `Sources/BackgroundComputerUse/API/HTTPTypes.swift:20-23` accepts bodies up to 10 MiB, so one source/record can be large enough to require multi-write appends.
- `Tests/BackgroundComputerUseTests/AgentAPICorrectnessTests.swift:231-301` covers a few route-specific redactions and the raw override. It does not use a representative response matrix.
- `Tests/BackgroundComputerUseTests/ScriptExecutionParityTests.swift:199-229` currently requires the complete source to appear in the audit log.
- `README.md:237-238`, `skills/background-computer-use/SKILL.md:180-182`, `Sources/BackgroundComputerUse/API/RouteRegistry.swift:222-242`, and `openspec/project.md:33-35` describe one fixed owner-only audit file and imply source retention. The new bounded/default-redacted contract must update all four.
- `openspec/project.md:13-15` requires `/v1/routes` to match runtime behavior. Lines 25-29 require an OpenSpec delta for the changed security contract.

## Commands you will need

| Purpose | Command | Expected on success |
|---|---|---|
| Artifact matrix | `swift test --filter ArtifactRedactionTests` | exit 0; every representative route redacts the sentinel |
| Existing security tests | `swift test --filter RuntimeSecurityCorrectnessTests` | exit 0; owner-only modes/raw override pass |
| Audit concurrency/rotation | `swift test --filter ScriptAuditLoggerTests` | exit 0; complete JSONL records and rotation bounds pass |
| Script route regression | `swift test --filter ScriptExecutionParityTests` | exit 0; outcomes remain audited without default source leakage |
| OpenSpec | `openspec validate redact-runtime-artifacts --strict` | exit 0 when CLI exists |
| Final suite | `swift test` | exit 0; complete suite passes |

## Scope

**In scope** (the only files you should modify):
- `Sources/BackgroundComputerUse/Runtime/DebugArtifactRecorder.swift`
- `Sources/BackgroundComputerUse/Actions/Script/ScriptAuditLogger.swift`
- `Sources/BackgroundComputerUse/API/RouteRegistry.swift`
- `Sources/BackgroundComputerUse/API/Router.swift` (audit recovery path/copy only)
- `Tests/BackgroundComputerUseTests/AgentAPICorrectnessTests.swift`
- `Tests/BackgroundComputerUseTests/ScriptExecutionParityTests.swift`
- `Tests/BackgroundComputerUseTests/ArtifactRedactionTests.swift` (create)
- `Tests/BackgroundComputerUseTests/ScriptAuditLoggerTests.swift` (create)
- `README.md`
- `skills/background-computer-use/SKILL.md`
- `openspec/project.md`
- `openspec/changes/redact-runtime-artifacts/proposal.md` (create)
- `openspec/changes/redact-runtime-artifacts/tasks.md` (create)
- `openspec/changes/redact-runtime-artifacts/specs/runtime-security/spec.md` (create)
- `plans/README.md` (status row only)

**Out of scope** (do NOT touch, even though related):
- HTTP body size, subprocess output limits, script timeout, or script execution semantics.
- A support-bundle/export feature or deletion of all debug artifacts.
- Logging/diagnostics events from plan 018; this plan secures files persisted by existing recorder/audit paths.
- Encryption or Keychain storage. The audit remains an owner-only local JSONL trail.
- Any implicit raw mode. Only the two explicitly named environment variables may retain raw data.

## Git workflow

- Branch: `advisor/020-artifact-redaction-script-audit`
- Commit logical units with messages such as `fix: redact sensitive debug artifacts` and `fix: bound script audit retention`.
- Do NOT push or open a PR unless the operator instructed it.

## Steps

### Step 1: Record the new security contract in OpenSpec

Create `redact-runtime-artifacts` with MODIFIED requirements replacing the archived promise that every script source is stored verbatim. The new requirement SHALL record SHA-256, source UTF-8 byte length, a content-free preview of at most the first 200 source characters, timing/status/outcome, and optional full source only under `BCU_SCRIPT_AUDIT_FULL_SOURCE=1`. Specify 0600 files in a 0700 directory, a 32 MiB active-file ceiling, four retained rotations, serialized complete JSONL records, and fail-closed refusal when mandatory audit persistence fails.

Add a requirement that non-raw debug artifacts recursively redact sensitive JSON strings on every route, redact malformed/non-JSON bodies wholesale, and expose raw data only when `DEBUG_ARTIFACTS_RAW=1`.

**Verify**: `if command -v openspec >/dev/null; then openspec validate redact-runtime-artifacts --strict; else echo 'openspec unavailable; validation skipped'; fi` → strict validation passes, or the exact skip message is printed.

### Step 2: Replace route switches with one recursive redactor

In `DebugArtifactRecorder`, remove `sensitiveRequestKeys`, the `read_text` route gate, and the route-specific response branch. Both request and response call the same `redactedJSONBody(_:)` unless `rawArtifactsEnabled` is true.

Parse with `JSONSerialization`; recursively traverse dictionaries and arrays. Compare key names case-insensitively. Replace a String with `<redacted len=N>` when its key is in this exact set:

```swift
[
    "value", "valuePreview", "text", "selectedText", "selectedAttributedText",
    "attributedText", "renderedText", "content", "source", "key",
    "textContains", "valueContains", "windowTitleContains", "urlContains",
    "imageBase64"
]
```

Also redact any String whose key begins with `expected`, `before`, or `after` (case-insensitive), covering fields such as `expectedValue`, `beforeValue`, and `afterValue`. Preserve dictionary/array structure, booleans, numbers, nulls, counts, status, classification, roles, geometry, and stable IDs. If a sensitive key contains an object/array, recurse into it rather than replacing the container.

If JSON parsing fails, store only `{"body":"<redacted malformed body len=N>"}` for every route. If the top-level JSON is a String, redact it. Normalize sorted/pretty JSON after redaction. Length is Swift character count, matching the current helper; do not include a prefix or hash in ordinary artifacts.

**Verify**: `swift test --filter ArtifactRedactionTests && swift test --filter RuntimeSecurityCorrectnessTests` → matrix and existing mode/permission tests pass.

### Step 3: Build a representative artifact redaction matrix

Create `ArtifactRedactionTests.swift` using a fresh temporary root and `DebugArtifactRecorder(enabled:true, rawArtifactsEnabled:false)`. Use one unique sentinel in nested request/response JSON for: `get_window_state` (`valuePreview`, text extraction, `imageBase64`), `find_elements` (query text and nested match value), `wait_for` (contains query plus nested final state), `paste` (content/before/expected/after), `set_value`, `select_text`, `read_text`, and `run_script`.

For each recorded request and response, read raw file bytes and assert the sentinel is absent, then decode and assert the sensitive leaf is `<redacted len=N>` while sibling structure/status/counts remain. Add malformed JSON and top-level string cases. Add one raw recorder case proving `DEBUG_ARTIFACTS_RAW` behavior through injected `rawArtifactsEnabled:true` still preserves a sentinel.

Keep the existing owner-only permission assertions in `AgentAPICorrectnessTests`; remove only assertions made redundant by the new matrix.

**Verify**: `swift test --filter ArtifactRedactionTests` → all representative routes, nested arrays, malformed JSON, and raw override pass.

### Step 4: Replace raw script source with a safe source summary

Import `CryptoKit` in `ScriptAuditLogger.swift`. Change `ScriptAuditEntry` to include `sourceSHA256`, `sourceUTF8Length`, `sourcePreview`, and optional `source`. Compute lowercase hex SHA-256 over exact UTF-8 bytes.

The default preview must not reveal any source character: take at most the first 200 Swift characters, preserve only whitespace/newline/tab positions, and replace every other character one-for-one with `•`. This retains a bounded rough line/layout diagnostic without leaking identifiers, comments, string literals, or tokens. Include full `source` only when an injected `fullSourceEnabled` is true; default it from exact environment check `BCU_SCRIPT_AUDIT_FULL_SOURCE == "1"`. Never infer full mode from debug-artifact settings.

Target shape:

```swift
ScriptAuditEntry(
    timestamp: ...,
    language: request.language,
    sourceSHA256: SHA256.hash(data: Data(request.source.utf8)).hex,
    sourceUTF8Length: request.source.utf8.count,
    sourcePreview: ScriptSourcePreview.make(request.source, characterLimit: 200),
    source: fullSourceEnabled ? request.source : nil,
    durationMs: durationMs,
    status: status,
    outcome: outcome,
    timedOut: timedOut,
    effectiveTimeoutMs: effectiveTimeoutMs
)
```

**Verify**: `swift test --filter ScriptExecutionParityTests` → audit outcomes/digest/length exist, default JSON does not contain submitted source, and explicit full-source injection does.

### Step 5: Serialize across processes and rotate under one stable lock

Keep the process-local `NSLock` and add a stable `script-executions.lock` file opened 0600. Under the NSLock, take `flock(lockFD, LOCK_EX)` before inspecting size, rotating, opening, or appending the active file; release with `LOCK_UN` in `defer`. This protects independent runtime processes as well as threads. Add `O_CLOEXEC` to audit and lock descriptors.

Keep the active path `script-executions.jsonl` for compatibility. Default `maximumFileBytes = 32 * 1024 * 1024` and `retainedRotationCount = 4`, injectable internally for tests. Before appending a nonempty active file, if `currentSize + entry.count > maximumFileBytes`, remove `.4`, rename `.3→.4`, `.2→.3`, `.1→.2`, and active→`.1`, all while holding the stable lock. Then create/fchmod the new active file 0600, append the complete entry with the existing EINTR-safe loop, and fsync before unlock.

An empty active file may accept one oversized record so an executed script never loses its mandatory audit; normal HTTP input is below the 32 MiB threshold. Rotation failures remain audit failures and therefore preserve current fail-closed route behavior.

**Verify**: `swift test --filter ScriptAuditLoggerTests` → two concurrent logger instances produce only decodable complete lines; a tiny injected threshold rotates before overflow, retains exactly four archives, and all active/rotated/lock files are 0600.

### Step 6: Update audit tests and operational descriptions

Change `ScriptExecutionParityTests.swift:199-229` to assert outcomes plus valid 64-hex digest and byte length, and assert the source sentinel is absent by default. Add an explicit injected-full-source case. In `RouteRegistry`, README, SKILL, and `openspec/project.md`, keep the fixed active path but state digest + redacted 200-character layout preview by default, 32 MiB/four-file rotation, and `BCU_SCRIPT_AUDIT_FULL_SOURCE=1` as the sensitive opt-in.

Update Router's audit failure recovery text only if it claims a different path/retention behavior; do not change HTTP response shapes. Warn that raw/full-source modes persist sensitive content and should be used temporarily.

**Verify**: `swift test --filter ScriptExecutionParityTests && swift test --filter APIDocumentationTests` → script security behavior and route documentation pass.

### Step 7: Run the final gate

Run the focused suites and full suite once. No live app, script smoke, or artifact collection is required.

**Verify**: `swift test` → exit 0; complete suite passes.

## Test plan

- `ArtifactRedactionTests.swift`: route matrix, nested dictionary/array, exact and prefix key matching, case-insensitive keys, screenshot base64, malformed JSON, scalar string, preserved non-sensitive structure, and raw override.
- `ScriptAuditLoggerTests.swift`: SHA-256/length, whitespace-only preview disclosure, 200-character bound, optional full source, two-thread/two-instance complete JSONL append, EINTR-safe write regression, rotation just below/at/above threshold, retention count, and 0600/0700 modes.
- `ScriptExecutionParityTests.swift`: successful/rejected/timed-out outcomes still recorded; replace the existing raw-source expectation with digest/no-leak expectations.
- `RuntimeSecurityCorrectnessTests`: preserve current owner-only artifact permissions and explicit raw artifact behavior.
- Verification: `swift test --filter ArtifactRedactionTests && swift test --filter ScriptAuditLoggerTests && swift test --filter ScriptExecutionParityTests && swift test --filter RuntimeSecurityCorrectnessTests` → all pass.

## Done criteria

- [ ] Default request and response artifacts for every route use the same recursive policy.
- [ ] Every exact/prefix sensitive key above is covered; malformed/non-JSON data is wholly redacted.
- [ ] Representative artifact files contain no sentinel and preserve non-sensitive structure.
- [ ] Default script audit contains digest, byte length, bounded content-free preview, and no source sentinel.
- [ ] `BCU_SCRIPT_AUDIT_FULL_SOURCE=1` is the only full-source audit override; `DEBUG_ARTIFACTS_RAW=1` remains the only raw artifact override.
- [ ] Appends are protected by NSLock plus stable-file `flock`; rotation is 32 MiB with four archives.
- [ ] Active, rotated, lock files are 0600 and the audit directory is 0700.
- [ ] OpenSpec and human/agent documentation match implementation.
- [ ] `swift test` exits 0.
- [ ] `git status --short` shows only in-scope files and pre-existing baseline changes.
- [ ] `plans/README.md` status row is updated.

## STOP conditions

Stop and report back (do not improvise) if:

- Any route requires retaining a sensitive string in default artifacts; the explicit raw override is the only exception.
- The existing raw override name differs from `DEBUG_ARTIFACTS_RAW`; preserve the live code's name rather than adding an alias.
- Rotation can occur without holding a stable interprocess lock across inspect/rename/open/append.
- A mandatory audit record could be dropped after script dispatch; audit persistence must remain fail-closed.
- Existing OpenSpec security requirements cannot be modified with a valid delta; do not leave contradictory specs.
- A focused verification fails twice after a reasonable fix attempt.

## Maintenance notes

- New DTO text fields are protected only when their key matches the centralized rules. Review every new request/response field for whether it belongs in the exact set or sensitive prefixes.
- Reviewers should search generated test artifacts and JSONL for the sentinel, not just inspect decoded fields.
- Raw/full-source overrides are intentionally independent and sensitive. Do not enable them in launch scripts, CI, or release defaults.
- Rotation is part of the forensic contract: preserve record ordering, complete JSON lines, fsync-before-unlock, and owner-only permissions.