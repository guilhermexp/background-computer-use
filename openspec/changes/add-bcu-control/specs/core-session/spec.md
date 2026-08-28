# core-session Specification

## ADDED Requirements

### Requirement: Session authority runs in a signed embedded XPC service

The Control host SHALL validate the embedded Core XPC bundle identifier and signer before connecting.
The Core service SHALL validate the Control process bundle identifier and signer before accepting a
connection. Missing, invalid, interrupted, or unavailable Core authority SHALL deny access.

#### Scenario: Embedded Core has another signer

- **WHEN** the XPC bundle has the expected bundle identifier but a signer different from Control
- **THEN** Control refuses the connection and all `/v1` access fails closed

#### Scenario: Core starts without a configured session

- **WHEN** a caller requests read or mutation authorization before Control configures a session
- **THEN** Core returns `unavailable` and the Router denies the request

### Requirement: Pause and stop survive Core restart

Control SHALL retain its desired session state, reconfigure a relaunched Core service before asking
for authorization, and SHALL NOT permit a stopped session to become active again.

#### Scenario: Core crashes while paused

- **WHEN** the Core XPC process terminates while Control's desired state is paused
- **THEN** the next read relaunches and rehydrates Core as paused while mutations remain denied

#### Scenario: Core crashes after stop

- **WHEN** the Core XPC process terminates after the session is stopped
- **THEN** every subsequent read and mutation remains denied for that session
