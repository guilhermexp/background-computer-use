# action-verification Specification

## Purpose
TBD - created by archiving change harden-agent-api-reliability. Update Purpose after archive.
## Requirements
### Requirement: press_key effect verification

`POST /v1/press_key` responses SHALL include a post-action `verification` block, using the same post-state read and classification machinery as click and scroll, so callers can distinguish transport success from observed effect.

#### Scenario: Key press with observable effect

- **WHEN** a client sends `press_key` with `"key":"command+w"` against a window whose close triggers a save sheet
- **THEN** the response contains a `verification` block with classification `success` and evidence of the observed change (e.g. focused element or window content change) plus a post-action `stateToken`

#### Scenario: Key press with no observable effect

- **WHEN** a client sends a `press_key` whose dispatch succeeds but produces no detectable state change
- **THEN** the response still has `ok:true` at the transport level and the `verification` block classifies the action as `dispatched_no_observed_effect`
