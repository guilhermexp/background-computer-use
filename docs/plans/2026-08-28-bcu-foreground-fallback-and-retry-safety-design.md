# BCU Foreground Fallback and Retry Safety Design

**Date:** 2026-08-28

## Problem

Two failures were observed during a real Termio-to-Zeron workflow.

First, AX-opaque `type_text` posted PID-scoped Unicode successfully, then returned
`effect_not_verified` after foreground preservation was lost. The response kept
`dispatchSucceeded=true`, but `strategiesAttempted` was empty and the failure did not carry an
explicit retry prohibition. The caller interpreted the response as a no-op, repeated the request,
and duplicated the text.

Second, BCU treats every foreground change as an action failure even when the requested work can
still be completed. Target preparation, PID-scoped input, application launch, and the Control
activity panel can all participate in foreground transitions. The product should prefer true
background operation, but completion has priority when a target cannot accept safe background
input.

## Product decision

BCU is background-first, not background-only.

When an exact target-bound transport works without activation, BCU preserves the user's foreground
application. When the target cannot accept that transport, BCU may use one deliberate foreground
fallback to complete the action. Foreground use is telemetry and user-impact evidence; it is not by
itself a reason to discard an otherwise verified result.

Foreground fallback must never be accidental or hidden. The route must identify that it happened,
must dispatch text at most once, and must tell the caller whether repeating the request is safe.

## Selected architecture

### 1. Truthful dispatch and retry contract

`TypeTextResponse` gains explicit retry and foreground-fallback telemetry:

- `retrySafe`: `true` only when no text transport could have changed the target.
- `foregroundFallbackUsed`: whether BCU intentionally or effectively continued with the target in
  the foreground.
- `foregroundRestored`: whether BCU restored the application that was frontmost before the action.

Every attempted text transport is listed in `strategiesAttempted`. An AX-opaque PID Unicode post
therefore reports `pid_unicode`; a successful transport always reports
`dispatchSucceeded=true`, including when verification or foreground restoration later fails.

Once a transport may have changed text, `retrySafe` is false. A dispatched but unverifiable result
uses `verifier_ambiguous` and instructs the caller to reread before continuing. It never presents
itself as a safe no-op. Exact mismatch or partial mutation remains fail-closed, but is also not safe
for blind retry.

### 2. Background-first foreground coordinator

A small shared coordinator owns foreground snapshots, intentional target activation, and conditional
restoration. It is injected so route tests can control every transition without activating real apps.

The coordinator follows these rules:

1. Capture the original frontmost application.
2. Try the existing exact background transport.
3. If target preparation leaves the target frontmost, treat that as foreground fallback instead of
   aborting after a side effect.
4. If background input cannot proceed and no unrelated user foreground change occurred, activate the
   exact target PID once and continue.
5. Never dispatch text more than once.
6. After the action, restore the original application only when the target is still frontmost. If the
   user moved to a third application during the operation, preserve that newer choice.

An unrelated foreground transition before dispatch blocks that attempt without a text side effect;
the caller may reread and try again. A target transition caused by BCU is an allowed fallback.

### 3. Type-text behavior

Target-bound `AXValue` and `AXTextOperation` remain the preferred transports and keep exact value and
selection verification authoritative.

PID Unicode is used only after the existing unchanged-baseline and exact-target checks. If the
background preflight cannot keep the target usable in the background, the coordinator promotes the
same target PID to foreground and permits exactly one Unicode post. The route then verifies the exact
value when AX state is available. For AX-opaque surfaces, it returns `verifier_ambiguous`,
`dispatchSucceeded=true`, `strategiesAttempted=["pid_unicode"]`, and `retrySafe=false`; the caller
must visually reread before pressing Return or issuing another text mutation.

Foreground loss after a verified exact insertion does not downgrade the text result. Restoration
status remains separately visible.

### 4. Launch behavior

`launch_app` continues requesting `activates=false`. If macOS or the target activates anyway, BCU
conditionally restores the previous application. A resolved or launched signed app is still a
successful launch; `foregroundPreserved` and restoration fields describe the user impact instead of
turning a completed launch into a retryable failure.

An already-running app is never relaunched merely because foreground changed during authorization,
window discovery, activity publication, or user interaction.

### 5. Control activity card

The transient activity card remains visible without making the BCU Control process key, main, or
frontmost. Its window explicitly refuses key/main status and its presentation path never activates
`NSApplication`. The preference to disable the card remains unchanged.

## Error handling

- No text dispatch: `retrySafe=true`; the response may be retried after a fresh state read.
- Text transport attempted: `retrySafe=false`, regardless of later verification outcome.
- Exact text verified: `success`, even if controlled foreground fallback was required.
- Text dispatched but opaque or unverifiable: `verifier_ambiguous` with an explicit reread warning.
- Partial or mismatched mutation: fail closed with `retrySafe=false`; never dispatch another fallback.
- Unrelated user foreground change before dispatch: abort before text mutation and do not restore or
  override the user's newly selected app.

## Test strategy

Swift Testing regressions reproduce the real failures before implementation:

1. AX-opaque Unicode dispatch followed by foreground loss reports `pid_unicode`,
   `dispatchSucceeded=true`, and `retrySafe=false`.
2. A caller cannot interpret a dispatched opaque result as a retryable no-op.
3. Target foreground transition permits one bounded fallback and never a second text post.
4. Exact text verification remains success when foreground fallback was used.
5. Restoration occurs only while the target remains frontmost; a third-app user transition wins.
6. `launch_app` remains successful when launch completes with a foreground transition and reports
   restoration honestly.
7. The activity panel cannot become key or main and a signed runtime smoke proves it does not become
   the frontmost application.

Focused tests run during each RED/GREEN cycle. The final gate runs the complete Swift suite, Python
smoke-policy tests, strict OpenSpec validation, a signed universal build, and live macOS smoke with an
unrelated app held frontmost. The live test separately proves the preferred background lane and the
controlled foreground fallback lane.

## Scope

This correction is limited to `type_text`, `launch_app`, shared foreground coordination, Control
activity presentation, their public documentation, and their tests. Click, paste, scroll, Locked Use,
and unrelated UI are unchanged.
