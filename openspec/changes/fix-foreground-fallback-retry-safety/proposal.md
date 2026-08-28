## Why

`type_text` could report `dispatchSucceeded=true` after a PID-scoped Unicode post while leaving
`strategiesAttempted` empty and exposing no explicit retry prohibition. A caller could therefore
misread an unverifiable side effect as a no-op and repeat the request, duplicating text. Separately,
the runtime treated every foreground transition as action failure even when the exact requested app
had already launched or accepted the text.

BCU is background-first, not background-only. It needs one bounded foreground fallback when the
exact target cannot accept safe background input, while making every possible text side effect and
the caller's retry obligation explicit.

## What Changes

- Add required `retrySafe`, `foregroundFallbackUsed`, and `foregroundRestored` telemetry to
  `type_text`; every attempted transport is named, and any possible text mutation forbids blind
  repetition.
- Return dispatched but unverifiable text as `verifier_ambiguous` with a reread requirement instead
  of presenting it as a retryable no-op.
- Keep exact AX transports background-first, but allow one deliberate activation of the exact target
  PID when background preparation cannot proceed and no unrelated user foreground change occurred.
  One request posts text at most once.
- Restore the original foreground application only while the target remains frontmost. A user's
  transition to a third application always wins.
- Treat a resolved or launched signed app as a completed `launch_app` result even if the target
  foregrounded; report fallback and restoration separately and never relaunch an already-running
  app merely because foreground changed.
- Make the transient BCU Control activity panel structurally unable to become key or main and keep
  its presentation path nonactivating.
- Qualify the retry policy separately from Safari's strict target-bound background proof.

## Impact

- **API:** additive required response fields for `type_text` and `launch_app`; `type_text` callers
  must reread state whenever `retrySafe=false` and must never repeat the request blindly.
- **Runtime:** shared foreground coordination, type-text outcome policy, launch completion policy,
  and nonactivating activity presentation.
- **Compatibility:** request schemas are unchanged. Exact background transports remain preferred.
- **Evidence:** Swift tests cover dispatch count and foreground transitions; Python smoke policy
  checks retry telemetry without treating controlled fallback as Safari background evidence. Live UI
  smoke remains a separate external qualification layer.
