## 1. Cursor State Model

- [x] 1.1 Add cursor feedback/action state types to `CursorModels.swift`, including idle, moving, acting, waiting, streaming, pointing, error, message text, append buffer, dwell timing, and target metadata.
- [x] 1.2 Extend `CursorSessionState` and `CursorSnapshot` in `CursorCoordinator.swift`/`CursorModels.swift` to carry feedback state without changing existing cursor response DTO compatibility.
- [x] 1.3 Add session helpers to begin, update, append, finish, hide, and expire feedback while refreshing cursor visibility timestamps.
- [x] 1.4 Extract a single active-session predicate used by both visibility fade and session purging, including feedback streaming/dwell/pointing states.
- [x] 1.5 Add an overlay attachment model that keeps cursor presentation window-anchored and defers no-window feedback instead of rendering globally.

## 2. Rendering

- [x] 2.1 Extend `CursorRenderer.draw` to render a bounded cursor-attached feedback bubble after glyph/trail drawing.
- [x] 2.2 Implement bubble layout, wrapping/truncation, screen-edge clamping, opacity, and scale transitions using CoreGraphics/AppKit drawing.
- [x] 2.3 Add visual indicators for waiting/streaming/error states without replacing existing action glyph choreography.
- [x] 2.4 Separate screen-overlay rendering from model-facing screenshot compositing so feedback bubbles are excluded from screenshots/OCR by default.

## 3. Feedback API

- [x] 3.1 Add request/response DTOs and strict validation for `POST /v1/cursor_feedback`.
- [x] 3.2 Implement `/v1/cursor_feedback` operations for update, append, finish, hide, and point using `CursorRuntime`/`CursorCoordinator`.
- [x] 3.3 Document `/v1/cursor_feedback` in `GET /v1/routes` with examples and invalid-field errors.
- [x] 3.4 Support optional feedback attachment fields, including `window` for immediate window-anchored presentation and deferred no-window feedback for pre-action updates.

## 4. Action Integration

- [x] 4.1 Keep action state visible through cursor choreography instead of route-label bubble copy.
- [x] 4.2 Ensure new actions interrupt stale pointing feedback without overwriting active public narration on the same cursor id.
- [x] 4.3 Keep direct package execution with `visualCursor: .disabled` headless, with no feedback rendering, overlay startup, or feedback dwell.

## 5. Semantic Pointing

- [x] 5.1 Implement explicit pointing feedback that accepts screen coordinates, clamps out-of-bounds targets, and reports clamping in the response.
- [x] 5.2 Reuse existing cursor motion planning for pointing animation and hold a short label at the target before returning to normal lifecycle.
- [x] 5.3 Make pointing feedback asynchronous: return after scheduling with planned duration metadata instead of waiting for animation and dwell.
- [x] 5.4 Cancel or replace in-flight pointing feedback when a newer action starts for the same cursor id.

## 6. Validation

- [x] 6.1 Add unit tests for feedback lifecycle, append/finish/hide behavior, cursor id isolation, stale feedback replacement, and disabled-cursor no-op behavior.
- [x] 6.2 Add renderer tests proving the bubble draws pixels near the mapped cursor position and remains bounded near screen edges.
- [x] 6.3 Add screenshot compositor/OCR tests proving feedback bubbles are excluded from model-facing screenshots by default while cursor glyph/trail behavior remains stable.
- [x] 6.4 Add tests for deferred pre-action feedback and window-anchored feedback.
- [x] 6.5 Add tests proving streaming feedback prevents premature fade and finalized feedback still expires.
- [x] 6.6 Add API documentation tests for `/v1/cursor_feedback` and strict unknown-field rejection.
- [x] 6.7 Run `swift test` and `openspec validate enhance-agent-cursor-feedback --strict`.
- [x] 6.8 Run a real runtime smoke test with a safe app action plus streamed feedback and verify screenshots show one cursor, one bubble, no stuck overlay after idle, and no feedback text in model-facing screenshot/OCR output.
- [x] 6.9 Dogfood Clicky-style visible response streaming: public agent narration, no route-label copy, and newest stream text preserved when bounded.
