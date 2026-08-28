# action-verification Specification

## ADDED Requirements

### Requirement: type_text makes retry safety explicit after every possible mutation

Every `POST /v1/type_text` response SHALL include `retrySafe`, `foregroundFallbackUsed`, and
`foregroundRestored`. Every attempted text transport SHALL be named in `strategiesAttempted`. Once a
transport may have changed the target, `retrySafe` SHALL be false regardless of later verification,
foreground restoration, or classification. `retrySafe` SHALL be true only when no transport was
attempted and no text side effect could have occurred. A caller receiving `retrySafe=false` SHALL
reread the exact target state and SHALL NOT repeat the text request blindly.

#### Scenario: Opaque Unicode dispatch cannot be retried blindly

- **WHEN** PID-scoped Unicode dispatch succeeds but AX cannot expose an exact post-dispatch value
- **THEN** the response is `verifier_ambiguous`, reports `dispatchSucceeded: true`, includes
  `pid_unicode` in `strategiesAttempted`, sets `retrySafe: false`, and instructs the caller to reread
  before continuing

#### Scenario: Blocked before transport remains retryable only after a reread

- **WHEN** an unrelated foreground transition blocks the request before any text transport is
  attempted
- **THEN** `strategiesAttempted` is empty, `dispatchSucceeded` is not true, and `retrySafe` is true,
  so a caller may issue a new request only after reading fresh target state

#### Scenario: Partial mutation does not trigger another fallback

- **WHEN** a target reread differs from both the prepared baseline and the exact expected text
- **THEN** the route fails closed with `retrySafe: false` and does not dispatch another text
  transport

### Requirement: type_text is background-first with one controlled foreground fallback

`type_text` SHALL try exact target-bound AX transports without activation first. When those
transports cannot proceed, the route MAY activate the exact target PID once only if the foreground
still matches the original app or the target itself. The request SHALL dispatch text at most once.
An exact target transition SHALL be reported as `foregroundFallbackUsed: true`; an unrelated user
transition SHALL block the request before text mutation.

#### Scenario: Exact AX transport stays entirely in background

- **WHEN** exact AX value or target-bound text operation produces the expected value and selection
  without activation
- **THEN** the response is `success`, `foregroundFallbackUsed` is false, and the foreground identity
  remains unchanged

#### Scenario: Exact target is activated once for Unicode fallback

- **WHEN** the unchanged-baseline checks make PID Unicode eligible, background preparation cannot
  keep the target usable, and no unrelated app became frontmost
- **THEN** BCU activates the exact target PID once, posts the requested text once, and reports
  `foregroundFallbackUsed: true`

#### Scenario: Verified fallback remains successful

- **WHEN** a controlled foreground fallback dispatches once and the exact expected value and
  selection are verified
- **THEN** `type_text` returns `success` even if foreground preservation was not continuous, while
  reporting fallback and restoration telemetry separately

#### Scenario: Third-app user transition blocks dispatch

- **WHEN** a third application becomes frontmost before fallback dispatch
- **THEN** BCU does not activate the target, does not dispatch text, and does not override the user's
  newer foreground choice

### Requirement: Foreground restoration is conditional and separately observable

After a controlled type or launch fallback, BCU SHALL restore the application that was frontmost
before the request only while the exact target is still frontmost. It SHALL NOT restore over a third
application selected during the operation. `foregroundRestored` SHALL report whether restoration
actually succeeded rather than whether it was merely attempted.

#### Scenario: Target still frontmost is restored

- **WHEN** the action completes after controlled fallback and the target remains frontmost
- **THEN** BCU activates the original PID and reports `foregroundRestored: true` only if the original
  application is observed frontmost afterwards

#### Scenario: Third-app choice wins over restoration

- **WHEN** the user selects a third application before restoration
- **THEN** BCU leaves that application frontmost and reports `foregroundRestored: false`

#### Scenario: Completed launch is not downgraded by foreground impact

- **WHEN** an authorized signed application resolves or launches successfully but becomes frontmost
- **THEN** `launch_app` remains `success`, reports `foregroundFallbackUsed` and
  `foregroundRestored` truthfully, and does not relaunch an already-running PID

### Requirement: The transient activity card cannot activate BCU Control

The BCU Control activity card SHALL be presented by a panel that cannot become key or main, ignores
mouse events, and is ordered without activating `NSApplication`. Showing, updating, dismissing, or
repositioning the card SHALL NOT make BCU Control frontmost. The persisted preference that disables
the card SHALL remain effective without disabling activity history.

#### Scenario: Presenting activity preserves the user's foreground app

- **WHEN** BCU Control presents or updates the transient activity card while another application is
  frontmost
- **THEN** the panel is visible without becoming key or main and BCU Control does not become
  frontmost

#### Scenario: Disabled card still records activity

- **WHEN** the user disables the activity-card preference and an action is published
- **THEN** no card is shown while the activity history continues to record the action
