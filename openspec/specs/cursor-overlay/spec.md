# cursor-overlay Specification

## Purpose
Cursor visível opt-in do agente (id/nome/cor reutilizáveis por sessão via o mesmo id), desabilitado por default para operação stealth.
## Requirements
### Requirement: Visual cursor uses a stable default session

The HTTP runtime SHALL render a visual cursor overlay for action requests when visual cursors are enabled. When the action request omits `cursor`, the runtime SHALL reuse the stable default agent cursor profile (`id: "agent"`, `name: "Agent"`) instead of creating duplicate unnamed sessions.

#### Scenario: Action without cursor reuses the Agent cursor

- **WHEN** a client sends any action request (`click`, `scroll`, `type_text`, `press_key`, etc.) without a `cursor` field
- **THEN** the visual cursor session uses the default `agent` id and action choreography is animated on screen

#### Scenario: Explicit cursor uses the requested lane

- **WHEN** a client sends an action with `"cursor":{"id":"agent-1","name":"Agent","color":"#20C46B"}`
- **THEN** the named cursor is rendered, and reusing the same `cursor.id` in later actions moves the same on-screen cursor continuously

### Requirement: Visual cursor exposes action state

The HTTP runtime SHALL associate a visible action state with each cursor session so the overlay can distinguish idle, moving, acting, waiting, streaming, pointing, and error states without creating duplicate cursor sessions.

#### Scenario: Action route sets acting state

- **WHEN** a client sends an action request such as `click`, `scroll`, `type_text`, `press_key`, or `set_value`
- **THEN** the cursor session used for the action enters an action-specific state during cursor choreography and dispatch

#### Scenario: State returns to idle after action completion

- **WHEN** action choreography, dispatch, verification, and any scheduled cursor dwell finish
- **THEN** the cursor session clears the action-specific state and follows the existing idle fade lifecycle

#### Scenario: Explicit cursor state remains isolated

- **WHEN** two cursor ids are active and one cursor enters a feedback or action state
- **THEN** the other cursor id keeps its own state, message, glyph, and lifecycle

### Requirement: Feedback lifecycle does not leave stuck overlays

The cursor overlay SHALL clear stale feedback and remove inactive overlay windows within bounded timing after the final activity for a cursor session.

#### Scenario: Finished feedback fades out

- **WHEN** a cursor feedback stream is finished and no action is in progress
- **THEN** the feedback bubble fades out within the configured feedback dwell and the cursor itself follows `CursorPresenceTiming.idleHideDelay`

#### Scenario: Interrupted action clears transient feedback

- **WHEN** a new action starts for a cursor while previous feedback is still visible
- **THEN** stale transient feedback from the previous action is cleared or replaced before the new action state is rendered

#### Scenario: Expired cursor removes all overlay presentation

- **WHEN** a cursor session exceeds `CursorPresenceTiming.idleExpireDelay`
- **THEN** all cursor glyph, trail, effects, action state, feedback bubble, and overlay controller presentation for that cursor are removed

#### Scenario: Streaming feedback prevents premature fade

- **WHEN** a cursor session has active streaming feedback and no input action is currently in progress
- **THEN** cursor visibility remains active and does not fade out solely because `CursorPresenceTiming.idleHideDelay` elapsed

#### Scenario: Visibility and purge use same activity predicate

- **WHEN** cursor activity is evaluated for fade-out and session expiration
- **THEN** both paths use the same definition of active cursor state, including motion, action, press/release, visual effects, feedback dwell, streaming feedback, and pointing feedback

### Requirement: Disabled visual cursor avoids feedback overhead

When action execution options disable the visual cursor, the runtime SHALL NOT start overlay windows, wait for feedback animation, or render feedback bubbles for that execution path.

#### Scenario: Direct package default remains headless

- **WHEN** a direct package action runs with default visual cursor settings
- **THEN** no cursor feedback state is rendered and no overlay startup or feedback dwell is added to the action duration

#### Scenario: HTTP visual cursor remains enabled by default

- **WHEN** an HTTP action route runs with visual cursors enabled and no explicit cursor is provided
- **THEN** the default `agent` cursor may render action state and feedback according to the cursor-overlay and agent-feedback-overlay requirements

