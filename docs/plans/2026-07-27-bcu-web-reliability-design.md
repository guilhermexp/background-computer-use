# BCU Web Reliability Design

**Date:** 2026-07-27
**Status:** Approved

## Goal

Make BackgroundComputerUse reliable on AX-opaque web applications without CDP, browser-specific bridges, foreground stealing, or new dependencies.

## Constraints

- Preserve background-only interaction semantics.
- Keep existing API fields and request forms working.
- Never treat transport dispatch as proof of user-visible intent.
- Keep destructive-action confirmation behavior.
- Use Apple Vision, Accessibility, CoreGraphics, and existing project primitives only.

## Chosen Approach

Extend the native BCU model instead of adding route-specific patches:

1. OCR anchors become reusable click targets.
2. Click verification combines AX evidence, anchor disappearance, and target-local pixel differences.
3. A structural interaction token coexists with the full snapshot state token.
4. Focus surfaces receive explicit classifications for press-key diagnostics.
5. Attached sheets become first-class surfaces and duplicate sheet projections collapse into one live surface.
6. Window screenshots compose only same-process attached surfaces intersecting the root window.

## API Design

### OCR

`OCRAnchorDTO` retains its current fields and adds optional `id`, `box`, and `target`. `OCRAnchorSummaryDTO` adds a status and optional diagnostic. When OCR is requested, the response always distinguishes `success`, `no_text`, `image_unavailable`, and `recognition_failed`.

`ActionTargetKindDTO` adds `ocr_anchor`. Its value is a stable identifier generated from normalized text, occurrence, quantized geometry, and the interaction token. Non-click routes reject this target kind explicitly.

### Tokens

`stateToken` remains the digest of the complete projected snapshot. A new `interactionToken` hashes window identity, geometry, projected topology, roles, node identities, and target frames while excluding volatile rendered text and values. Action requests accept an optional interaction token. Legacy requests using only `stateToken` continue to work.

### Attached surfaces

Window responses add `attachedSurfaces`, containing role, title, frame, node identity, and live-action status for sheets and dialogs attached to the root window. The projected tree marks the canonical attached sheet and folds duplicate dialog subtrees only when normalized title and actionable-child signatures match the live sheet.

### Action verification and diagnostics

Click verification adds target-local and full-window visual change ratios plus OCR-anchor disappearance. A successful coordinate or OCR click requires dispatch success and at least one intent signal: AX state change, modal/sheet transition, anchor disappearance, or target-local visual change.

Press-key responses classify the current focus surface as `native_text`, `web_content`, `browser_chrome`, `attached_sheet`, `opaque_renderer`, or `unknown`. An unchanged opaque renderer returns `app_specific_semantics` with a precise recovery reason rather than the generic safe-click warning.

## Data Flow

1. `get_window_state` resolves and captures the AX window.
2. It captures the root window plus eligible same-PID attached surfaces.
3. It computes both state and interaction tokens.
4. When OCR is requested, Apple Vision produces anchors in model-facing coordinates and reusable targets.
5. An OCR click recaptures state and OCR, verifies the interaction token, and resolves the anchor by stable ID with text/occurrence/geometry checks.
6. The existing native background coordinate transport dispatches the click.
7. Post-action AX, OCR, and localized image evidence determine the result.

## Failure Handling

- Missing or ambiguous OCR anchors fail closed before dispatch.
- OCR errors return an explicit status and diagnostic.
- A stale interaction token blocks an OCR click; a stale full state token remains a warning when the interaction token still matches.
- Missing pixel evidence never becomes success.
- Attached surfaces from other processes are never captured or targeted.
- Existing confirmation gates remain authoritative.

## Testing

- Contract encoding/decoding and backward compatibility.
- OCR anchor identity, occurrence, geometry tolerance, and failure statuses.
- Localized visual-difference verification and anchor disappearance.
- Interaction-token stability under dynamic text and invalidation under structural changes.
- Sheet canonicalization and attached-surface discovery fixtures.
- Focus-surface classification and press-key failure-domain selection.
- Existing Swift suite.
- Real Chrome smoke fixture with an AX-opaque modal, driven exclusively through the BCU loopback API.

## Rejected Approaches

- **Per-route patches:** smaller initial changes but duplicate matching, visual verification, and diagnostics.
- **Chrome/CDP bridge:** violates BCU independence and the requirement to test the native product itself.
