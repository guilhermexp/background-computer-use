# action-verification Specification

## ADDED Requirements

### Requirement: Unverified coordinate clicks escalate to the accessibility element under the point

When a coordinate or OCR-anchor click dispatches and the honest intent gate proves no effect, the runtime SHALL hit-test the accessibility element at the same screen point and, when that element is eligible, perform its press action and re-verify with the same gate. The escalation SHALL be adopted only when re-verification proves an effect, and SHALL be reported as its own route rather than as success of the coordinate transport.

#### Scenario: Renderer discards coordinate injection and the accessibility press succeeds

- **WHEN** a coordinate or OCR-anchor click dispatches without proving an effect and an eligible pressable element sits under the click point
- **THEN** the accessibility press is performed, the click is re-verified, and on proven effect the response reports `finalRoute: coordinate_then_ax_hit_test`, `fallbackReason: coordinate_unverified_using_ax_hit_test`, and a transport attempt with `route: ax_perform_action` and `liveElementResolution: ax_hit_test_at_click_point`

#### Scenario: Escalation that proves nothing does not become success

- **WHEN** the accessibility press at the click point is performed and re-verification still proves no effect
- **THEN** the response keeps `classification: effect_not_verified`, keeps the coordinate route as the final route, and records the escalation attempt in `transports[]` and `routeSteps[]`

#### Scenario: Escalation is not attempted for a verified coordinate click

- **WHEN** a coordinate click already proved an effect through the intent gate
- **THEN** no accessibility hit-test or press is performed

### Requirement: Only an element a human could have hit is pressable by escalation

The escalation SHALL press an element only when it exposes the press action and its frame covers the click point with real dimensions. Nodes the accessibility tree keeps for content outside the viewport SHALL NOT be pressed.

#### Scenario: Element without a press action is skipped

- **WHEN** the element under the point exposes no press action
- **THEN** it is not pressed and the escalation continues to the nearest eligible ancestor, if any

#### Scenario: Scrolled-out control with a collapsed frame is skipped

- **WHEN** the element under the point reports a frame whose width or height is below the minimum eligible dimension, as a renderer does for a control scrolled out of the viewport
- **THEN** it is not pressed

#### Scenario: Element whose frame does not cover the point is skipped

- **WHEN** the hit-tested element or ancestor reports a frame that does not contain the click point within the declared tolerance
- **THEN** it is not pressed

### Requirement: Web renderer surfaces name the coordinate injection limit

When a coordinate click dispatches on a web renderer surface and neither the injection nor the accessibility escalation proves an effect, the response SHALL classify the failure as application-specific semantics and SHALL name the measured limitation together with the accessibility alternative.

#### Scenario: Unverified coordinate click on a web renderer surface

- **WHEN** the target window projects a web renderer profile and the coordinate click plus escalation prove no effect
- **THEN** `failureDomain` is `app_specific_semantics` and the warnings carry `renderer_ignores_coordinate_injection` plus the instruction to target `display_index` or `node_id`

#### Scenario: Unverified coordinate click on a native surface

- **WHEN** the target window is not a web renderer surface and the coordinate click proves no effect
- **THEN** the warnings carry `coordinate_dispatch_effect_unconfirmed` without claiming a renderer limitation

### Requirement: The escalation obeys the same limits as the semantic route

The accessibility escalation performs the same primitive as a semantic click, so it SHALL be held to the same rules: it SHALL act only inside the process the caller named, it SHALL NOT press destructive wording without explicit confirmation, and it SHALL NOT run while the window still shows signs of an effect in flight.

#### Scenario: Element resolved outside the target process is refused

- **WHEN** the hit-test resolves an element whose process is not the process of the window the caller named
- **THEN** nothing is pressed

#### Scenario: Destructive wording still requires confirmation

- **WHEN** the eligible element under the point carries destructive wording and the request did not set `confirm=true`
- **THEN** nothing is pressed and the response warns that the element requires explicit confirmation

#### Scenario: A window that is still settling is not pressed again

- **WHEN** the coordinate click proved no intent signal but the window reports ambient change or any full-window visual change
- **THEN** the escalation does not run, so a slow but real effect is never actuated twice

#### Scenario: Post-state follows the press that was performed

- **WHEN** the escalation pressed an element and re-verification still proved no effect
- **THEN** the response reports the state read after that press, never a snapshot that predates it

#### Scenario: The coordinate step keeps its own verdict

- **WHEN** the escalation is what produced the verified effect
- **THEN** the coordinate route step still reports its own unverified verdict and is not relabelled as the escalation route
