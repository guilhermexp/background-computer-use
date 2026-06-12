# cursor-overlay Specification

## Purpose
TBD - created by archiving change harden-agent-api-reliability. Update Purpose after archive.
## Requirements
### Requirement: Visual cursor uses a stable default session

The HTTP runtime SHALL render a visual cursor overlay for action requests when visual cursors are enabled. When the action request omits `cursor`, the runtime SHALL reuse the stable default agent cursor profile (`id: "agent"`, `name: "Agent"`) instead of creating duplicate unnamed sessions.

#### Scenario: Action without cursor reuses the Agent cursor

- **WHEN** a client sends any action request (`click`, `scroll`, `type_text`, `press_key`, etc.) without a `cursor` field
- **THEN** the visual cursor session uses the default `agent` id and action choreography is animated on screen

#### Scenario: Explicit cursor uses the requested lane

- **WHEN** a client sends an action with `"cursor":{"id":"agent-1","name":"Agent","color":"#20C46B"}`
- **THEN** the named cursor is rendered, and reusing the same `cursor.id` in later actions moves the same on-screen cursor continuously
