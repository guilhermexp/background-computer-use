# action-verification Specification

## MODIFIED Requirements

### Requirement: OCR recognition is warm, timed, and bounded

The runtime SHALL execute Apple Vision recognition only in a disposable child process, SHALL report
the complete worker time as `performance.ocrMs`, and SHALL terminate and reap the worker tree when the
deadline expires. The resident loopback process SHALL NOT prewarm or execute Vision. A failed worker
SHALL return `status: recognition_failed` with a bounded diagnostic and SHALL NOT prevent a later
request from starting a fresh worker.

#### Scenario: First OCR read pays an isolated cold start

- **WHEN** the first OCR request after system boot pays Apple Vision's cold-start cost
- **THEN** the latency is confined to the disposable worker and the resident runtime remains responsive

#### Scenario: OCR time is attributed

- **WHEN** `get_window_state` runs with `includeOCR: true`
- **THEN** `performance.ocrMs` reports the complete OCR-worker time

#### Scenario: Recognition deadline fails closed without poisoning later reads

- **WHEN** an OCR worker exceeds the recognition deadline
- **THEN** the worker tree is terminated and reaped, the response is `recognition_failed`, and a later OCR request launches a fresh worker

## ADDED Requirements

### Requirement: type_text success requires foreground preservation

`POST /v1/type_text` SHALL own background preparation internally and SHALL NOT expose a focus-assist
mode. A successful response SHALL require exact value and selection verification plus evidence that
the user's foreground application identity remained unchanged before preparation, before dispatch,
and after reread.

#### Scenario: Background text succeeds without activation

- **WHEN** the runtime prepares a background window, writes the requested text, rereads the exact expected value, and the foreground process remains unchanged
- **THEN** `type_text` returns `success` with `foregroundPreserved: true`

#### Scenario: Foreground change fails closed

- **WHEN** target preparation or text dispatch changes the foreground process
- **THEN** `type_text` does not return success and reports the background-safety failure domain

#### Scenario: AX success without exact effect is insufficient

- **WHEN** AX reports that a value write succeeded but reread does not match the exact expected value and selection
- **THEN** `type_text` returns `effect_not_verified`

#### Scenario: Legacy focus assist is rejected

- **WHEN** a client sends the removed `focusAssistMode` field
- **THEN** strict request decoding returns `invalid_request`
