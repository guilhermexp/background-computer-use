# action-verification Specification

## ADDED Requirements

### Requirement: Verification never consumes evidence the runtime itself produced

No signal SHALL count as intent when the runtime's own drawing or its own input transport can produce it without any application effect. Specifically, anchor disappearance SHALL be measured on an image the runtime did not draw its cursor into, and a focus change SHALL be measured against a baseline taken after the transport's own focus manipulation. Evidence that cannot be measured cleanly SHALL be reported as `null` with a diagnostic and SHALL NOT count, matching the existing fail-closed rule.

#### Scenario: Cursor parked on the anchor is not proof

- **WHEN** the runtime animates its virtual cursor onto the OCR anchor before dispatch and the page does not change
- **THEN** `ocrAnchorDisappeared` is not reported as `true`, no `ocr_anchor_disappeared` intent signal is awarded, and the click is classified `effect_not_verified`

#### Scenario: Clean image unavailable fails closed

- **WHEN** the post-dispatch capture without the cursor overlay cannot be produced
- **THEN** `ocrAnchorDisappeared` is `null`, `ocrAnchorDiagnostic` names the reason, and the absence never counts as evidence

#### Scenario: Transport-set focus is not proof

- **WHEN** the click transport performs its focus-without-raise before posting the mouse event and nothing else changes
- **THEN** `focusedElementChanged` is false, because the focus baseline was sampled after that transport step

#### Scenario: Transport-caused ambient churn does not block recovery

- **WHEN** the transport's focus-without-raise changes rendered text or the selection summary before the mouse event, but the application does not change afterwards
- **THEN** that pre-mouse churn is absorbed into the post-focus baseline, does not populate `ambientOnlySignals`, and does not make `windowStillSettling` true

#### Scenario: Genuine ambient churn still blocks recovery

- **WHEN** rendered text or the selection summary continues changing after the post-focus baseline and through the post-dispatch read
- **THEN** the change remains ambient and the runtime does not escalate, preserving the guard against actuating a slow real effect twice

#### Scenario: Tree reordering is not a focus change

- **WHEN** nodes are inserted or removed ahead of the focused element so its positional accessibility path shifts while focus never moved
- **THEN** `focusedElementChanged` is false, because the comparison uses a stable element identity rather than the positional path

#### Scenario: A real focus move still counts

- **WHEN** a click moves focus to a different element than the one focused after the transport's focus step
- **THEN** `focusedElementChanged` is true and the click earns the `focused_element_changed` intent signal

### Requirement: The reported verdict is the verdict the escalation gate evaluated

A signal computed after the escalation decision SHALL NOT raise the reported classification above what the escalation gate saw. Either a signal participates in the verdict that gates escalation, or it cannot certify success. This prevents a post-hoc signal from certifying a click while simultaneously being invisible to the recovery path that would have made the click work.

#### Scenario: Post-hoc anchor evidence cannot outrank the gate

- **WHEN** the base verdict that gates escalation has no intent signal, and anchor disappearance is computed only afterwards
- **THEN** the response does not report `success` on the strength of that later signal alone

#### Scenario: Unverified coordinate click still reaches escalation

- **WHEN** an OCR-anchor click dispatches on a web renderer surface, produces no sound intent signal, and the window is quiet
- **THEN** the runtime escalates to pressing the accessibility element under the same point, and on a proven effect reports `finalRoute: coordinate_then_ax_hit_test` with `fallbackReason: coordinate_unverified_using_ax_hit_test`

#### Scenario: The in-flight-effect guard is preserved

- **WHEN** the base verdict has ambient signals or the window image is still changing after the settle delay
- **THEN** the runtime does not escalate, so a slow but real effect is never actuated a second time
