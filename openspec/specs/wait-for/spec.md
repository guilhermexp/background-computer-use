# wait-for Specification

## Purpose
`POST /v1/wait_for` bloqueia até uma condição de UI ser satisfeita (role/label/valor/título/URL/texto presente ou ausente via `gone`), com polling e timeout, evitando busy-wait no lado do agente.
## Requirements
### Requirement: Conditional wait predicates

`POST /v1/wait_for` SHALL support waiting for window title substrings, window title changes, URL substrings exposed by projected nodes, rendered text substrings, and existing element role/label/value predicates.

#### Scenario: Wait for title change

- **WHEN** a client sends `wait_for` with `windowTitleChanged:true`
- **THEN** the runtime establishes the first observed window title as the baseline and resolves the wait only after a later poll observes a different title

#### Scenario: Wait for URL or rendered text

- **WHEN** a client sends `wait_for` with `urlContains` or `textContains`
- **THEN** the runtime evaluates those predicates against the projected state without requiring a specific element target

#### Scenario: Wait polling avoids screenshot churn

- **WHEN** `wait_for` polls repeatedly
- **THEN** intermediate polls omit screenshots and the response returns one fresh final state using the requested `imageMode`

#### Scenario: Reject nonsensical title-change disappearance waits

- **WHEN** a client sends `wait_for` with both `windowTitleChanged:true` and `gone:true`
- **THEN** the runtime rejects the request instead of immediately satisfying the inverted baseline condition

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

