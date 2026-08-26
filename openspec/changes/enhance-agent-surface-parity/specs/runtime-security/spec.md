# runtime-security Specification

## ADDED Requirements

### Requirement: Script executions are recorded in an owner-only audit log

Every `run_script` execution SHALL be appended to an audit log recording the timestamp, the language, the submitted source, the measured duration and the exit status. The log SHALL be created with owner-only permissions inside an owner-only directory, matching the manifest and screenshot rule, so the record of what was executed is neither readable by another local user nor lost.

#### Scenario: Execution leaves an audit record

- **WHEN** a client posts a script and it executes
- **THEN** an entry naming the timestamp, language, source, duration and exit status is appended to the audit log

#### Scenario: Rejected and timed-out executions are recorded too

- **WHEN** a script is refused before dispatch or is terminated by its timeout
- **THEN** the attempt is still recorded, with the outcome that applied

#### Scenario: Audit log is not world-readable

- **WHEN** the runtime creates the audit log
- **THEN** the file is `0600` inside a `0700` directory

### Requirement: The declared security posture states the script lane's authority

The project's declared posture SHALL state that enabling the script lane widens the auth token's authority from the set of verified UI actions to arbitrary control of any scriptable application, so the trade-off is recorded rather than implied.

#### Scenario: Posture documents the widened authority

- **WHEN** a reader consults the runtime's declared security posture
- **THEN** it states that the token now authorizes arbitrary Apple Events execution, that loopback is not a user boundary, and that the audit log is the compensating control
