## Why

Ghost OS has a useful "set-of-marks" orientation step: it draws numbered labels over visible UI targets and returns the matching element metadata. That makes agents faster and less brittle because they can visually inspect a screenshot with stable numbered anchors before choosing an action target.

BCU already returns screenshots and projected AX nodes, but callers still need to mentally align tree rows with the raw image. A dedicated annotation route can make that alignment explicit while keeping normal `get_window_state` responses compact.

## What Changes

- Add `POST /v1/annotate_window` as a window-read route.
- Capture normal window state with a model-facing screenshot, select visible/actionable projected nodes, map their AppKit frames into model-facing screenshot coordinates, and draw numbered marks.
- Return the annotated image plus a compact marks table containing mark ID, target identifiers, role/label/value preview, model-facing point/rect, and the action target callers can reuse.
- Keep annotations out of normal `get_window_state`; callers opt in only when visual grounding needs numbered anchors.

## Impact

- API surface: one additive read-only route.
- Runtime: annotation DTOs, route service, screenshot drawing helper, route registry/router wiring.
- Docs/tests: route schema, public usage docs, unit coverage for mark selection/mapping and strict request docs.
