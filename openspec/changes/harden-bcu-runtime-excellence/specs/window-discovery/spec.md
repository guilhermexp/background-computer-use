# window-discovery Specification

## MODIFIED Requirements

### Requirement: list_windows targets one exact running process

`POST /v1/list_windows` SHALL require a positive process identifier returned by `list_apps`. It SHALL
enumerate windows only for that exact targetable process and SHALL NOT fall back to another process
with the same name or bundle identifier.

#### Scenario: Duplicate bundle instances remain distinct

- **WHEN** two running applications share the same name and bundle identifier and the client requests one PID
- **THEN** every returned window belongs to the requested PID and no sibling-process window is returned

#### Scenario: A terminated PID does not fall back

- **WHEN** the requested PID is no longer a targetable running application
- **THEN** `list_windows` returns an application-not-found error for that PID

#### Scenario: Legacy name requests are rejected

- **WHEN** a client sends the removed `app` string instead of `pid`
- **THEN** strict request decoding returns `invalid_request`
