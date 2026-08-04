# action-verification Specification

## ADDED Requirements

### Requirement: Click success requires a target-local or structural intent signal

A click SHALL be classified `success` only when the dispatch succeeded AND at least one target-local or structural intent signal is observed. The declared intent signals are: `targetRegionChangeRatio` greater than or equal to the declared threshold `targetRegionChangeThreshold`, `ocrAnchorDisappeared`, `focusedElementChanged`, `modalDialogOpened`, `windowTitleChanged`, and `targetStateChanged` (selected/focused/value change on the target itself). `renderedTextChanged` and `selectionSummaryChanged` are ambient signals and SHALL NOT sustain a success verdict on their own. This gate SHALL be identical for every click route — `coordinate_xy`, `ocr_anchor_xy`, `semantic_ax`, and `ax_element_pointer_xy` — so no route is more permissive than another.

#### Scenario: Ambient-only evidence is not success

- **WHEN** a click dispatches and the post-state shows only `renderedTextChanged: true` and `selectionSummaryChanged: true`, with `targetRegionChangeRatio: 0` and no anchor, focus, modal, title, or target-state change
- **THEN** the response classifies the click as `effect_not_verified`, `verification.intentSignals` is empty, `verification.ambientOnlySignals` names `rendered_text_changed` and `selection_summary_changed`, and `verification.verificationNotes` states that ambient page changes are ambiguous and do not prove the requested effect

#### Scenario: Target-local pixel change is success

- **WHEN** a click dispatches and `targetRegionChangeRatio` is at or above `targetRegionChangeThreshold`
- **THEN** the response classifies the click as `success` and `verification.intentSignals` contains `target_region_changed`

#### Scenario: OCR route is not more permissive than the coordinate route

- **WHEN** the same physical click is issued through `target.kind=ocr_anchor` and through direct `x`/`y`, and both produce identical post-state evidence
- **THEN** both responses carry the same classification, because both are evaluated by the same intent-signal gate

#### Scenario: Selection AX plans use the same gate

- **WHEN** a `set_row_selected_true` or `set_container_selected_rows` AX plan dispatches and the only post-state evidence is `selectionSummaryChanged: true` or an unchanged `afterTargetSelected: true`
- **THEN** the response classifies the click as `effect_not_verified`, because neither is a target-local state change produced by this click

### Requirement: Click verification always computes target-local evidence or explains its absence

Every click route SHALL resolve a target region — the OCR anchor box, the AX target frame, or a declared fixed-size probe box centred on the dispatched coordinate — and SHALL compute `targetRegionChangeRatio` from window images captured before dispatch and after the settle delay. When the ratio genuinely cannot be computed, the response SHALL return the field as `null` together with a `targetRegionDiagnostic` naming the reason, and that case SHALL NOT count as an intent signal. On the OCR route, `ocrAnchorDisappeared` SHALL be computed the same way, with `ocrAnchorDiagnostic` when it cannot be.

#### Scenario: Coordinate click reports a computed ratio

- **WHEN** a coordinate or AX click dispatches against a capturable window
- **THEN** `verification.targetRegionChangeRatio` is a number, not `null`, and `verification.targetRegionDiagnostic` is absent

#### Scenario: Missing pixel evidence is diagnosed, never silent

- **WHEN** the window image cannot be captured before or after the dispatch
- **THEN** `verification.targetRegionChangeRatio` is `null`, `verification.targetRegionDiagnostic` explains which capture failed, and the click is not classified `success` on the strength of that field

#### Scenario: Verification declares its own threshold

- **WHEN** any click response includes a `verification` block
- **THEN** `verification.targetRegionChangeThreshold` reports the ratio threshold the runtime applied, so the caller can audit the verdict

### Requirement: OCR recognition is warm, timed, and bounded

The runtime SHALL prewarm Apple Vision text recognition during bootstrap without delaying `/health`, SHALL report the OCR time as `performance.ocrMs` on reads that run OCR, and SHALL bound each recognition with an explicit deadline that returns `status: recognition_failed` with a short diagnostic instead of hanging the request.

#### Scenario: First OCR read is not a cold start

- **WHEN** the runtime finishes bootstrapping and a client issues its first `get_window_state` with `includeOCR: true`
- **THEN** Apple Vision has already been warmed by a background prewarm, so the call does not pay the multi-second first-recognition cost

#### Scenario: OCR time is attributed

- **WHEN** `get_window_state` runs with `includeOCR: true`
- **THEN** `performance.ocrMs` reports the recognition time and `performance.totalMs` no longer hides it as unattributed time

#### Scenario: Recognition deadline fails closed

- **WHEN** Apple Vision text recognition exceeds the runtime's recognition deadline
- **THEN** the OCR summary returns `status: recognition_failed` with a diagnostic naming the deadline, the anchor list is empty, and the request returns instead of hanging
