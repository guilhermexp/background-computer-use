# App policy specification

## ADDED Requirements

### Requirement: App authorization is bound to signed identity

An app identity SHALL contain bundle ID, Team ID, and designated requirement. A persisted decision
for one identity SHALL NOT apply to a different signer or requirement, even when bundle IDs match.

#### Scenario: Same bundle is signed by another team

- **WHEN** an app has the same bundle ID as an allowed app but a different Team ID or designated requirement
- **THEN** Control evaluates it as a new identity and requires a new explicit decision

### Requirement: Decisions are explicit and session scoped

Unknown apps SHALL evaluate to `ask`. Allow-once SHALL be scoped to one runtime session. Persistent
allow SHALL survive restart. Deny SHALL override every allow.

#### Scenario: Allow-once session ends

- **WHEN** the task session associated with an allow-once decision ends
- **THEN** the identity evaluates to `ask` in every later session

#### Scenario: User denies an allowed identity

- **WHEN** a deny decision is stored for an identity with an existing session or persistent allow
- **THEN** deny takes precedence immediately

### Requirement: Protected apps fail closed

Protected identities SHALL default to deny and SHALL NOT accept persistent or session allow.

#### Scenario: Protected app is requested

- **WHEN** a request targets a configured protected identity
- **THEN** Control returns deny without presenting an allow choice

### Requirement: Missing authority denies new access

Unavailable policy authority, corrupt persistence, timeout, dismissal, or invalid peer identity SHALL
deny new app access.

#### Scenario: Control is unavailable

- **WHEN** Core cannot obtain a valid Control decision because of timeout, interruption, dismissal, persistence failure, or peer validation failure
- **THEN** the app is not launched or mutated
