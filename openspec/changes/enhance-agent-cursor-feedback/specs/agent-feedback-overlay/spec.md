## ADDED Requirements

### Requirement: Cursor feedback route

The runtime SHALL expose a documented `POST /v1/cursor_feedback` route that lets clients update the visible feedback state for a cursor session without dispatching an input action.

#### Scenario: Route is documented

- **WHEN** a client calls `GET /v1/routes`
- **THEN** the response documents `POST /v1/cursor_feedback`, accepted request fields, response fields, examples, and `invalid_request` errors for unsupported fields

#### Scenario: Feedback update uses stable default cursor

- **WHEN** a client sends `POST /v1/cursor_feedback` without a `cursor` field and visual cursors are enabled
- **THEN** the runtime updates the stable default `agent` cursor session and returns a cursor response whose id is `agent`

#### Scenario: Feedback update can target explicit cursor lane

- **WHEN** a client sends `POST /v1/cursor_feedback` with `"cursor":{"id":"agent-2","name":"Agent","color":"#20C46B"}`
- **THEN** the runtime updates that cursor session without modifying the default `agent` cursor session

#### Scenario: Feedback without a window does not render globally

- **WHEN** a client sends `POST /v1/cursor_feedback` before the selected cursor session has an attached window
- **THEN** the runtime accepts the feedback state but reports a deferred attachment and does not render an overlay above unrelated apps

#### Scenario: Feedback can attach above a window

- **WHEN** a client sends `POST /v1/cursor_feedback` with a valid `window` field
- **THEN** the runtime attaches the feedback cursor presentation above that window and reuses that attachment for later feedback updates on the same cursor session until another attachment is provided

### Requirement: Cursor-attached feedback bubble

The runtime SHALL render compact public agent-facing feedback text as a click-through bubble anchored near the active cursor, using the same cursor session and overlay window as the cursor glyph.

#### Scenario: Message appears next to active cursor

- **WHEN** a client updates cursor feedback with state `streaming` and a public message such as `Vou comparar o que mudou na tela antes do proximo clique.`
- **THEN** the overlay renders that message next to the active cursor glyph and keeps all mouse events passing through to the underlying app

#### Scenario: Message updates in place

- **WHEN** a client sends multiple feedback updates for the same cursor id
- **THEN** the existing feedback bubble updates in place and no additional cursor session, overlay window, or detached panel is created

#### Scenario: Action choreography does not overwrite public narration

- **WHEN** a client is streaming public feedback text for a cursor id and then dispatches a click, scroll, keyboard, text, value, secondary-action, drag, resize, or window-frame route with the same cursor id
- **THEN** the action route keeps using cursor motion and glyph choreography but does not replace the feedback bubble with route labels such as `Clicking`, `Scrolling`, or `Pressing Esc`

#### Scenario: Message is bounded on screen

- **WHEN** a feedback message is longer than the supported display length or the cursor is near a screen edge
- **THEN** the renderer wraps or truncates the message within the documented bubble bounds, preserves the newest visible text from the stream, and clamps the bubble inside the visible screen area

#### Scenario: Feedback bubble is excluded from model-facing screenshots by default

- **WHEN** a screenshot is generated for model-facing state or OCR while a feedback bubble is visible on screen
- **THEN** the screenshot compositor excludes the feedback bubble text by default so the model does not read the agent's own visible narration as app content

### Requirement: Streaming feedback lifecycle

The runtime SHALL support incremental text updates for an active feedback bubble and clear that bubble through explicit finish or hide operations.

#### Scenario: Streaming append accumulates text

- **WHEN** a client begins feedback with message `Opening` and then appends ` Chrome`
- **THEN** the feedback bubble displays `Opening Chrome` for the same cursor session

#### Scenario: Finish leaves short readable dwell

- **WHEN** a client finishes a streaming feedback update with a final message
- **THEN** the runtime keeps the final bubble visible for a bounded dwell period and then fades it without removing the cursor session prematurely

#### Scenario: Hide clears feedback immediately

- **WHEN** a client sends a hide operation for a cursor feedback session
- **THEN** the feedback bubble is removed from the next presentation while normal cursor lifecycle rules continue to apply

### Requirement: Semantic pointing feedback

The runtime SHALL support an explicit pointing feedback operation that moves or orients the active cursor toward a target screen point and shows a short label.

#### Scenario: Pointing label appears at target

- **WHEN** a client sends pointing feedback with a valid screen coordinate and label `Deploy logs`
- **THEN** the active cursor schedules an animation toward the target, renders a short label, and returns to normal cursor lifecycle after the pointing dwell completes

#### Scenario: Pointing coordinate is clamped

- **WHEN** a client sends pointing feedback with a coordinate outside the selected screen bounds
- **THEN** the runtime clamps the target to the visible screen, reports that clamping occurred in the response, and does not throw solely because the point was out of bounds

#### Scenario: Pointing response is asynchronous

- **WHEN** a client sends pointing feedback with a valid target
- **THEN** the route returns after scheduling the pointing animation with planned duration metadata, without waiting for the full animation and dwell to complete

#### Scenario: Pointing is interrupted by newer action

- **WHEN** a cursor is running a pointing feedback animation and a new action starts for the same `cursor.id`
- **THEN** the runtime cancels or replaces the pointing feedback before rendering the new action state

#### Scenario: Disabled cursor skips visual pointing

- **WHEN** visual cursor behavior is disabled for the caller
- **THEN** pointing feedback returns a disabled or no-op cursor response and does not start overlay windows or wait for animation
