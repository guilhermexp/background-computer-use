# Harden agent-facing API reliability

## Why

E2E testing by an AI agent (2026-06-11, TextEdit full workflow) surfaced four real defects that make the API unsafe or confusing for agent consumers:

1. **Unknown request fields are silently ignored.** `POST /v1/press_key` with `{"key":"w","modifiers":["command"]}` typed a literal "w" into the focused document and returned `ok:true`. The correct syntax is `"key":"command+w"`, but nothing told the caller their `modifiers` field was dropped. For agents this is the worst failure mode: wrong action, success response.
2. **`press_key` returns `ok:true` with no effect verification.** Click and scroll responses carry verification evidence (scrollbar delta, image change ratio, label diffs); `press_key` reports transport success only, so a shortcut that did nothing (or typed text instead) still looks successful.
3. **Actions without an explicit `cursor` render a hardcoded "Codex" overlay.** `CursorCoordinator.swift:99` falls back to `CursorProfile.codex` (`CursorModels.swift:9-13`). On a multi-agent machine this looks like a second, unknown agent is acting. The default cursor should instead be an explicit Agent identity that is reused whenever the request omits `cursor`.
4. **`list_windows` can return the desktop AXScrollArea as a duplicate window with the same `windowID` as the real window.** Observed with Finder: two entries, both `windowID w_ZRNF83TF`, one `role: AXWindow`, one `role: AXScrollArea`. Stable IDs must be unique per listed entry, and non-window AX containers should not be listed as windows.

## What Changes

- **request-validation**: all `/v1` POST routes decode strictly; an unknown top-level field returns `invalid_request` naming the offending field(s) plus the route's accepted fields, with the existing `recovery[]` guidance.
- **action-verification**: `press_key` responses include a post-action verification block (same machinery as click/scroll: post-state read, focused-element/value diff, classification) so callers can distinguish "dispatched" from "had an effect".
- **cursor-overlay**: replace the `CursorProfile.codex` fallback for HTTP actions with a stable default Agent cursor (`id: "agent"`, `name: "Agent"`); when a request has no `cursor` object, the runtime animates that same default session. Behavior with an explicit `cursor` is unchanged.
- **window-discovery**: `list_windows` lists only real windows (`AXWindow` role); auxiliary containers like the desktop scroll area are excluded, and every returned entry has a unique `windowID`.

## Impact

- Affected specs: `request-validation`, `action-verification`, `cursor-overlay`, `window-discovery` (all new).
- Affected code: `Sources/BackgroundComputerUse/API/Router.swift`, `Contracts/RouteRequestContracts.swift` (strict decoding), `Actions/PressKey/*` (verification), `Cursor/CursorCoordinator.swift` + `Cursor/CursorModels.swift` (default profile removal), `Discovery/*` window listing service, plus `Tests/`.
- **BREAKING (minor):** clients that send extra/unknown fields will start receiving `invalid_request` instead of silent acceptance; clients relying on the implicit "Codex" cursor identity now see the stable "Agent" cursor identity. Both breaks are intentional and safer for agent use. `/v1/routes` docs must reflect the new behavior.
