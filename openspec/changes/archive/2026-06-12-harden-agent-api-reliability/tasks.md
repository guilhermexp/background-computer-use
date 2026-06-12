# Tasks

## 1. Strict request decoding (request-validation)

- [x] 1.1 Add a strict-decoding layer for `/v1` POST request DTOs: collect unknown top-level keys against the route's documented field set (reuse `RouteRegistry` schemas as the source of truth) and fail decoding when any are present.
- [x] 1.2 Return `invalid_request` with a message that names each unknown field and lists the route's accepted fields; keep the existing `recovery[]` array.
- [x] 1.3 Unit tests: unknown field rejected on `press_key` (regression: `modifiers`), `click`, and `scroll`; valid requests with all documented optional fields still pass.

## 2. press_key effect verification (action-verification)

- [x] 2.1 Wire the existing post-action verification machinery (post-state read + diff/classification, as used by click) into `PressKeyRouteService`.
- [x] 2.2 Response gains a `verification` block: classification (`success` / `dispatched_no_observed_effect` / `failed`), evidence (focused element change, value diff, window set change), and post `stateToken`. `ok` semantics stay transport-level; verification carries the effect signal.
- [x] 2.3 Unit tests for the verification block shape; integration-style test where a key press changes a text field value and verification reports the diff.
- [x] 2.4 Update `/v1/routes` documentation for `press_key` response schema.

## 3. Default visible cursor reuse (cursor-overlay)

- [x] 3.1 Replace the `defaultProfile = CursorProfile.codex` fallback path for HTTP actions with a stable Agent default cursor; when the request has no `cursor`, animate the reused `agent` session.
- [x] 3.2 Keep explicit `cursor` behavior unchanged (session reuse by `cursor.id`, color, label).
- [x] 3.3 Delete or repurpose `CursorProfile.codex`; ensure no route or test references the old Codex identity as an implicit default.
- [x] 3.4 Tests: action without `cursor` uses the default Agent session; action with `cursor` still renders/reuses.

## 4. Window listing dedup (window-discovery)

- [x] 4.1 In the window discovery service, filter listed entries to real windows (`role == AXWindow`); exclude auxiliary containers (e.g. desktop `AXScrollArea`) from `list_windows` output.
- [x] 4.2 Guarantee `windowID` uniqueness per response entry; if two AX elements resolve to the same backing window, return one entry.
- [x] 4.3 Test with a simulated/AX-stubbed duplicate (regression for the Finder desktop case).

## 5. Validation gate

- [x] 5.1 `swift build` and full `swift test` pass.
- [x] 5.2 Update README/route docs where behavior changed (strict decoding note, default visible Agent cursor, press_key verification).
- [x] 5.3 Run the repo smoke script (`Tests`/`script` smoke) against a relaunched runtime; manual API pass: unknown-field request → `invalid_request`; `press_key` `"command+w"` on a scratch TextEdit doc → verification block present; action without cursor → default `agent` overlay on screen; Finder `list_windows` → single entry per real window.
