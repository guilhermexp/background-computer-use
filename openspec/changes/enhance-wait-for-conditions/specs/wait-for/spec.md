# wait-for Specification

## ADDED Requirements

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
