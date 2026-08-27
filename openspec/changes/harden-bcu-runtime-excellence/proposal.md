# Change: Harden BCU Runtime Excellence

## Why

Live runtime validation exposed three correctness gaps: Apple Vision can block the resident process,
application-name discovery cannot distinguish duplicate bundle instances, and background text entry
can either lose its effect or activate the target application. These gaps make successful local unit
gates insufficient evidence that the installed runtime is background-safe.

## What Changes

- Run Apple Vision OCR in a disposable self-executed worker supervised by the same bounded process
  primitive used by audited script execution.
- Replace fuzzy `list_windows` application lookup with an exact positive PID request.
- Make `type_text` automatically prepare its target window without a public focus-assist mode and
  require foreground preservation in the success verdict.
- Remove the synthetic OCR prewarm, in-process Vision deadline worker, fuzzy application lookup, and
  public `focusAssistMode` contract.
- Supersede the active `fix-verification-honesty` prewarm requirement with disposable worker
  isolation while preserving `performance.ocrMs` and bounded failure semantics.
- Expand the signed-app smoke to cover duplicate application instances, repeated OCR, Chrome OCR
  click verification, and Safari background text entry.

## Impact

- Breaking request changes for `list_windows` and `type_text`.
- New internal OCR worker mode on the existing executable; no new product or dependency.
- Shared process supervision becomes a runtime primitive consumed by `run_script` and OCR.
- Route documentation, skill examples, tests, and smoke fixtures change with the contracts.
