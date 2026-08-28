# Locked-use specification

## ADDED Requirements

### Requirement: Locked use is opt-in and screensaver scoped

Locked use SHALL be disabled by default. Installation SHALL modify only
`system.login.screensaver` and SHALL preserve all existing mechanisms and unknown rule fields.

#### Scenario: Installer receives another authorization right

- **WHEN** installation targets `system.login.console` or any right other than `system.login.screensaver`
- **THEN** installation fails before filesystem or authorization database mutation

### Requirement: Authorization consumes one bound lease

Authorization SHALL require an unexpired one-use lease bound to UID, boot session, task session,
nonce, and exact Control/Core designated requirements. Replay and mismatch SHALL deny.

#### Scenario: Lease is consumed twice

- **WHEN** the authorization mechanism presents a nonce that has already been consumed
- **THEN** the broker denies it as a replay

#### Scenario: Lease binding differs

- **WHEN** UID, boot session, task session, signer requirement, or expiry differs from the armed lease
- **THEN** the broker denies and revokes that lease

### Requirement: Safety loss relocks immediately

Local keyboard or pointer input, expiry, heartbeat loss, dependency death, shield loss, stop, or
display coverage loss SHALL revoke the lease and relock. Local input SHALL require a manual unlock
before automatic unlock can be armed again.

#### Scenario: Physical local input is observed

- **WHEN** a trusted HID event has no process-directed synthetic source while locked activity is active
- **THEN** the broker revokes the lease, relocks, and requires manual unlock before rearming

#### Scenario: Display coverage changes

- **WHEN** the active display set differs from the shielded display set
- **THEN** Control requests relock and refuses continued locked activity

### Requirement: Recovery restores the exact prior rule

The installer SHALL be dry-run first and maintain a protected exact rule snapshot. An independent
recovery tool SHALL restore the prior rule without Control or Core.

#### Scenario: Backup digest is valid

- **WHEN** the independent recovery tool receives the versioned protected backup
- **THEN** it verifies the digest and materializes the exact prior `system.login.screensaver` rule

#### Scenario: Backup digest is invalid

- **WHEN** any backup byte differs from its recorded digest
- **THEN** recovery refuses to write an authorization rule
