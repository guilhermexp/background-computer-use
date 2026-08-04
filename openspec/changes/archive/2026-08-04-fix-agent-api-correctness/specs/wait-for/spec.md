# wait-for Specification

## ADDED Requirements

### Requirement: Disappearance waits tolerate window closure

`POST /v1/wait_for` with `gone:true` SHALL treat the target window closing during the wait as the condition being satisfied, not as a routing error, so an agent waiting for a dialog or window to disappear receives success at the moment the wait succeeds.

#### Scenario: Target window closes during polling

- **WHEN** a `wait_for` with `gone:true` is polling and the target window closes (resolution would raise window-not-found)
- **THEN** the runtime returns `conditionMet:true` with a note that the target window closed, instead of a 404 window-not-found error

#### Scenario: Window closes before the final capture

- **WHEN** the condition already became satisfied inside the poll loop and the target window closes before the mandatory final capture
- **THEN** the runtime still returns `conditionMet:true` rather than letting the final capture raise a 404

#### Scenario: Non-gone wait reports closure as unmet

- **WHEN** a `wait_for` with `gone:false` is polling and the target window closes
- **THEN** the runtime returns `conditionMet:false` with a note that the target window closed, instead of a 404 error
