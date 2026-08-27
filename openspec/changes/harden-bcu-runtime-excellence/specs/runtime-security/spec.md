# runtime-security Specification

## ADDED Requirements

### Requirement: OCR execution is isolated from the resident runtime

The runtime SHALL execute Apple Vision OCR in a disposable child process supervised by a bounded
process runner. A stalled recognition SHALL be terminated with its observed descendants before the
HTTP request returns, and SHALL NOT prevent a later OCR request from starting in a fresh process.

#### Scenario: A stalled recognition cannot poison the next request

- **WHEN** an OCR worker exceeds its configured deadline
- **THEN** the runtime terminates and reaps that worker tree, returns `recognition_failed`, and the next OCR request launches a new worker

#### Scenario: Invalid worker output fails closed

- **WHEN** an OCR worker exits non-zero, truncates its response, or emits invalid JSON
- **THEN** the runtime returns `recognition_failed` with a bounded diagnostic and no anchors

### Requirement: Process supervision has one implementation

`run_script` and OCR SHALL use the same bounded process runner for pipe handling, output limits,
timeouts, recursive descendant observation, process-group termination, and reap verification.

#### Scenario: A detached descendant is still terminated

- **WHEN** a supervised child creates a new session and the root process times out
- **THEN** the shared runner terminates the observed descendant as well as the root process group
