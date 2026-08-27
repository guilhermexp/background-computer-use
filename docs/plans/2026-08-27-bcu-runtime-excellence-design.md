# BCU Runtime Excellence Design

**Date:** 2026-08-27
**Status:** Approved

## Goal

Make the live BackgroundComputerUse runtime reliable across OCR, duplicate application instances,
and background text entry while removing the ambiguous and in-process legacy paths that caused the
observed failures.

## Scope

This design fixes the three failures reproduced in the live smoke:

1. Apple Vision work can stall or poison the resident runtime process.
2. `list_windows` cannot unambiguously select one of multiple processes with the same bundle ID.
3. `type_text` either loses its effect or activates the target app on Safari when the target is in the background.

Adjacent action routes, unrelated cleanup, new third-party dependencies, CDP, and browser-specific bridges are out of scope.

## Constraints

- Preserve the product rule that background actions do not steal the user's foreground app.
- A dispatched transport is never proof of effect.
- Breaking the current discovery and text-focus request contracts is explicitly approved.
- Use Swift 6.2, Swift Testing, and Apple frameworks already present in the repository.
- Every production behavior starts with a failing focused test.
- Execute in batches of three tasks, then review and debug before continuing.
- Do not push, publish, or commit without separate explicit authorization.

## Chosen Architecture

### Out-of-process OCR

The installed executable gains an internal `--ocr-worker` mode. The HTTP runtime sends a small JSON
request over stdin and receives an OCR result over stdout. Vision runs only in the disposable worker;
the server process never imports Vision execution state into its request lifecycle.

The existing audited script executor already contains the hard process-supervision requirements:
bounded stdout/stderr drains, timeout enforcement, process-group and descendant termination, tolerant
UTF-8 handling, and deterministic reap. Those mechanics move into one shared bounded-process runner.
`run_script` keeps its audit and osascript policy, while OCR supplies a self-executable invocation.

The old synthetic prewarm, in-process semaphore worker, and best-effort `VNRequest.cancel()` deadline
are deleted. A hung worker is killed at the process boundary and cannot poison later OCR requests.

### PID-only discovery

`POST /v1/list_windows` accepts only `{"pid": 123}`. `list_apps` remains the discovery entry point and
already returns each targetable process PID. Fuzzy application resolution by name or bundle ID is
removed from this public path, as are `appQuery` request-summary fields that imply ambiguity.

Resolution validates that the exact PID is still running, regular, non-terminated, and targetable.
It never falls back to a sibling process. Window IDs continue to bind bundle ID, PID, launch date, and
window number, so downstream window actions remain stable.

### Background-safe text transaction

`focusAssistMode` is removed from the public request contract. `type_text` owns the correct behavior:
resolve the exact live element, snapshot the foreground process, prepare the target window through the
existing WindowServer primitive, dispatch against the element, reread the exact value and selection,
and verify that the foreground process never changed.

The preparation used by semantic and explicitly confirmed opaque text paths is centralized. A target
that cannot be prepared without foreground activation fails closed; the route does not silently fall
back to global activation or claim success from a successful AX return code alone.

Responses add explicit background-safety evidence and a dedicated failure domain. Success requires
both exact text verification and foreground preservation.

## Public Contract Changes

### `list_windows`

Old request, removed:

```json
{"app":"Google Chrome"}
```

New request:

```json
{"pid":25268}
```

Non-positive, missing, terminated, or non-targetable PIDs return an explicit request or discovery
error. No name or bundle fallback remains.

### `type_text`

`focusAssistMode` is removed from request and response schemas. The existing exact text, target,
secure-field confirmation, cursor, and state-token fields remain. Response verification adds the
foreground PID/bundle before dispatch, immediately before transport, and after reread, plus a single
`foregroundPreserved` verdict.

### OCR responses

Existing OCR status and anchors remain stable. Diagnostics gain bounded worker failure details such as
timeout, non-zero exit, invalid response, and sanitized Vision error domain/code. Diagnostics never
expose screenshot contents or arbitrary paths.

## Data Flow

### OCR

1. Capture the requested window to a path-backed model-facing PNG.
2. Encode an internal worker request to stdin.
3. Spawn the current executable with `--ocr-worker` through the shared bounded-process runner.
4. The worker decodes the PNG, performs one Vision request, and writes one JSON result.
5. The parent decodes anchors or maps timeout/process/protocol failure to `recognition_failed`.
6. The complete worker tree is reaped before the HTTP response returns.

### Discovery

1. The agent calls `list_apps` and selects one returned PID.
2. `list_windows` resolves that exact running application.
3. AX discovery enumerates only that process's windows.
4. The target cache records PID-bound window identities as before.

### Text

1. Capture state and resolve the exact semantic element.
2. Record the current foreground application identity.
3. Prepare the target PID/window through WindowServer without activation.
4. Verify the foreground identity is unchanged before dispatch.
5. Apply the expected element value and selection, or use the confirmed opaque PID route.
6. Reread the same and relocated live element.
7. Return success only when value/selection match and the foreground identity is unchanged.

## Failure Handling

- OCR timeout kills the worker process group and observed descendants, then returns `recognition_failed`.
- Invalid worker JSON, truncated output, or non-zero exit never becomes `no_text` or success.
- PID resolution never selects another process after the requested PID exits.
- WindowServer preparation failure blocks text dispatch.
- Foreground changes before transport block dispatch; changes after transport prevent success and are
  reported as background-safety failures.
- Exact value mismatch remains an effect-verification failure even when AX reports success.
- Secure fields still require explicit confirmation.

## Testing

### Automated

- Shared process runner: success, timeout, descendant cleanup, bounded drains, and invalid executable.
- OCR worker protocol: real text image, no-text result, invalid image, Vision error serialization,
  timeout mapping, invalid JSON, and no leaked process.
- Discovery: duplicate name/bundle fixtures resolve only the requested PID; missing and terminated PID
  fail without fallback.
- Text: WindowServer preparation occurs before dispatch, foreground changes block success, exact
  verification is mandatory, and the public schema rejects removed focus fields.
- Public facade, route documentation, strict request decoding, and smoke fixture updates.
- Full `swift test` must be completely green, including replacement of the obsolete in-process OCR test.

### Live smoke

- Launch two instances sharing one bundle ID and prove each PID returns only its own window.
- Run two OCR reads and keep both below the declared warm budget without poisoning later reads.
- Exercise the Chrome OCR-anchor click and require verified AX escalation or direct intent evidence.
- Type into the Safari fixture while another app remains frontmost; require exact value and unchanged
  foreground identity.

## Rejected Approaches

- **Remove only the prewarm:** leaves unkillable Vision work inside the server and does not fix blank or
  pathological images.
- **Add optional PID beside `app`:** preserves ambiguous legacy behavior and two resolution paths.
- **Restore the foreground after typing:** still visibly steals focus and violates the product contract.
- **XPC service:** provides isolation but adds unnecessary bundle, entitlement, signing, and packaging
  complexity compared with a single-purpose self-executed worker.
