## Context

BCU already has a native cursor runtime built around `CursorCoordinator`, `CursorSessionState`, `CursorSnapshot`, `CursorOverlayController`, and `CursorRenderer`. The cursor is session-based, defaults to the stable `agent` session, animates action choreography, and fades out shortly after activity.

The Clicky reference is useful as a product behavior pattern, not as an implementation template. It streams the model's visible response text into a cursor-adjacent bubble and uses semantic pointing labels from the same response. BCU should keep its existing AppKit/CoreGraphics renderer and action pipeline, then add feedback state and bubble rendering to the current cursor presentation.

## Goals / Non-Goals

**Goals:**

- Make the default `agent` cursor communicate public agent narration, visible response text, pointing labels, and errors.
- Let external clients stream public agent-facing text into the cursor through a documented loopback API.
- Keep feedback attached to the same cursor session so the user sees one continuous agent, not multiple cursors or panels.
- Keep overlays click-through and non-focus-stealing.
- Preserve direct package behavior where visual cursor is disabled by default.

**Non-Goals:**

- Do not port Clicky's SwiftUI overlay/window architecture into BCU.
- Do not bind the feedback cursor to the user's physical mouse position.
- Do not add model-specific prompt parsing such as `[POINT:x,y:label]` in the first implementation pass.
- Do not make action dispatch wait on optional text streaming beyond existing cursor motion and action timing.

## Decisions

### Extend the existing cursor presentation instead of creating a second overlay

Add feedback fields to the session and snapshot model, then draw the bubble/indicator inside `CursorRenderer`. This keeps lifecycle, window ordering, screenshot compositing, and cursor session reuse in one system.

Alternative considered: add a separate `NSPanel` like Clicky's legacy response overlay. That is simpler to prototype, but it risks the duplicate-overlay behavior the user already observed and creates another lifecycle path that can get stuck.

### Introduce `/v1/cursor_feedback` for visible response streaming

Action routes should express their work through cursor motion, glyphs, ripples, and keycaps. Useful user-facing streaming needs a small explicit API for the agent's public narration. The route should accept a cursor selector, state, optional message, optional append mode, optional target point, and finish/hide operations. `GET /v1/routes` must document that `message` is visible agent-facing text, not hidden reasoning, route labels, tool names, or product branding.

Alternative considered: overload every action route with feedback fields. That makes simple actions noisy and does not help long-running visible response streaming periods that occur between actions.

### Keep feedback window-anchored or deferred

The existing overlay path orders cursor windows above an attached app window. `/v1/cursor_feedback` needs an explicit attachment decision: use a provided `window` or the session's current attachment when available; otherwise accept the feedback state but defer visual presentation. The overlay must not create a screen-level or globally ordered window because that can leak the cursor and streaming bubble above unrelated frontmost apps while the user is working elsewhere.

Alternative considered: screen-anchor pre-action feedback. That shows liveness before the first click, but it creates the exact global overlay failure mode we need to avoid. Clients that need immediate visible feedback before an action should resolve a target window and pass `window`.

### Use bounded text rendering

Feedback text should be compact, wrap to a bounded width, clamp on screen, and be trimmed to a documented maximum. When text exceeds the maximum, the renderer should preserve the newest visible text instead of freezing on the beginning of the stream. The cursor should never cover large portions of the target app or cause layout churn while text streams.

Alternative considered: render the full agent response. Full transcripts are useful in a chat UI, but near-cursor text must be compact and glanceable.

### Exclude feedback bubbles from model-facing screenshots by default

BCU screenshots can be used as visual ground truth and OCR input. The cursor glyph/trail may remain useful as an action trace, but feedback text should not be injected into the model-facing image by default because it can occlude targets and pollute OCR anchors. Renderer/compositor paths should distinguish screen overlay presentation from screenshot compositing.

Alternative considered: composite the bubble everywhere. That is easier to test visually, but it makes the agent read its own visible narration as part of the app.

### Make semantic pointing asynchronous

`POST /v1/cursor_feedback` pointing is feedback, not a verified input action. The route should return after scheduling the pointing animation, reporting the planned duration and any clamping, while the cursor animation/dwell runs through the normal coordinator lifecycle.

Alternative considered: block the HTTP response until animation and dwell finish. The existing action choreography has synchronous waits, but applying that to feedback would make streaming/control APIs feel slow and can hold the main actor unnecessarily.

### Keep cursor state independent from transport success

The feedback state should represent what the agent is publicly saying or pointing at, while action responses continue to expose transport and verification status separately. Failed actions can set an error/retry feedback state, but verification remains the source of truth for success classification.

Alternative considered: derive all feedback solely from verifier output. That misses pre-action movement, waiting, and streaming phases.

## Risks / Trade-offs

- Text bubbles can obscure target UI -> clamp placement to the visible screen and keep a small max width and line count.
- Pre-action feedback may have no attached window -> defer visual presentation and require `window` for immediate visible bubbles.
- More session state can make stale overlays easier to create -> centralize the "session is active" predicate so visibility fade and session purging agree.
- Feedback text can contaminate screenshots/OCR -> exclude feedback bubbles from model-facing compositing by default.
- Streaming updates could over-render -> coalesce redraws on the existing display link and avoid starting extra timers for text.
- New route can be misused with unknown fields -> reuse strict request validation and route documentation patterns.
- Pointing animation can slow down real actions -> semantic pointing is explicit, optional, asynchronous, and interruptible by later actions on the same cursor id.

## Migration Plan

1. Add models and renderer support behind existing cursor-enabled paths.
2. Add `/v1/cursor_feedback` and document it in `/v1/routes`.
3. Preserve cursor choreography for action state while keeping text bubbles reserved for explicit public narration.
4. Validate with unit tests, compositor tests, route documentation tests, and a real runtime smoke test.
5. If visual regressions appear, keep the explicit feedback route and cursor choreography independently testable.
