# cursor-overlay Specification

## Purpose
TBD - created by archiving change harden-agent-api-reliability. Update Purpose after archive.
## Requirements
### Requirement: Visual cursor is opt-in per request

The HTTP runtime SHALL render a visual cursor overlay only when the action request includes an explicit `cursor` object. There SHALL be no implicit default cursor profile.

#### Scenario: Action without cursor renders no overlay

- **WHEN** a client sends any action request (`click`, `scroll`, `type_text`, `press_key`, etc.) without a `cursor` field
- **THEN** no visual cursor session is created or animated on screen, and the action dispatches without cursor choreography delay

#### Scenario: Explicit cursor behaves as before

- **WHEN** a client sends an action with `"cursor":{"id":"agent-1","name":"Agent","color":"#20C46B"}`
- **THEN** the named cursor is rendered, and reusing the same `cursor.id` in later actions moves the same on-screen cursor continuously
