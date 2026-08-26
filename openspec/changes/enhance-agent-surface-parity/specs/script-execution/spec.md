# script-execution Specification

## ADDED Requirements

### Requirement: Script lane executes arbitrary Apple Events source

`POST /v1/run_script` SHALL accept an arbitrary AppleScript or JavaScript-for-Automation source string, execute it, and return `status`, `stdout`, `stderr`, `durationMs` and `timedOut`. The route exists because Apple Events reach app capabilities no verified action route covers, such as closing a document without saving or quitting an app.

#### Scenario: AppleScript source runs and returns its output

- **WHEN** a client posts an AppleScript source that returns a value
- **THEN** the response carries the script's `stdout`, an exit `status`, and the measured `durationMs`

#### Scenario: Failing script reports its error instead of a transport failure

- **WHEN** a posted script fails to compile or raises at runtime
- **THEN** the response reports the failure in `stderr` with a non-zero `status`, rather than surfacing as a transport-level error

### Requirement: Script lane declares that it verifies nothing

The route SHALL be documented in `GET /v1/routes` as an ungated lane that promises no effect verification, and its response SHALL NOT carry a `classification` field. A script's observable effect is arbitrary and unknowable to the runtime, so claiming verification here would reintroduce exactly the dishonesty the click gate removed.

#### Scenario: Self-documentation names the absent gate

- **WHEN** an agent reads the route catalog
- **THEN** the `run_script` entry states that the lane dispatches without effect verification and that the caller must confirm any effect by reading state afterwards

#### Scenario: Response makes no success claim about the UI

- **WHEN** a script executes successfully
- **THEN** the response reports process-level success only, and contains no `classification` asserting an observed UI effect

### Requirement: Script execution is bounded by an enforced timeout

Every execution SHALL be bounded by a `timeoutMs` that the runtime enforces and caps, terminating a runaway script and returning `timedOut: true` instead of hanging the request or leaking a process.

#### Scenario: Runaway script is terminated

- **WHEN** a posted script exceeds its effective timeout
- **THEN** the runtime terminates it, returns `timedOut: true` with whatever output was captured, and leaves no surviving child process

#### Scenario: Excessive requested timeout is capped

- **WHEN** a client requests a timeout above the runtime's declared maximum
- **THEN** the runtime applies its maximum and reports the effective value it used

### Requirement: Script lane participates in action exclusion

Because a script mutates arbitrary application state, the route SHALL be classified as an action route, taking part in session exclusion and action-rate throttling exactly as the other mutating routes do.

#### Scenario: Concurrent session is excluded

- **WHEN** one session holds the action lane and another session posts `run_script`
- **THEN** the second request is refused with the same conflict status any other action route returns
