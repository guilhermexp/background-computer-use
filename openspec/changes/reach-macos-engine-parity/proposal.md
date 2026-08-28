# Change: Reach macOS Engine Parity

## Why

A controlled Safari comparison showed that native Computer Use completes a background
`click + type_text` flow where BCU's direct AX value write reports success but produces no value. BCU
correctly returns `effect_not_verified`, but it needs an adaptive, verified fallback and lower
condition-based latency to match native completion without weakening its evidence model.

## What Changes

- Add a pure decision seam for exact, unchanged, and partially changed AX text outcomes.
- Add an ordered exact-target fallback: target-bound `AXTextOperation` when advertised, then one
  PID-scoped Unicode attempt only if the complete baseline remains unchanged and exact focus is proven.
- Add clipboard-safe text/Markdown/HTML paste with complete pasteboard restoration.
- Replace unconditional action settle sleeps with bounded evidence polling.
- Add action-stage performance telemetry and a repeated signed-app parity benchmark.

## Impact

- Extends `type_text` response evidence without removing existing fields.
- Adds a new mutating `paste` route.
- Changes timing implementation while preserving verifier and foreground gates.
- Adds live Safari/Chromium fixtures that reproduce the native comparison.
