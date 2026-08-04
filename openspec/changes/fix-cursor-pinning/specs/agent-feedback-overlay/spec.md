# agent-feedback-overlay Specification

## MODIFIED Requirements

### Requirement: Semantic pointing feedback

The runtime SHALL support an explicit pointing feedback operation that moves or orients the active cursor toward a target screen point and shows a short label.

#### Scenario: Pointing label appears at target

- **WHEN** a client sends pointing feedback with a valid screen coordinate and label `Deploy logs`
- **THEN** the active cursor schedules an animation toward the target, renders a short label, and returns to normal cursor lifecycle after the pointing dwell completes

#### Scenario: Pointing coordinate is clamped

- **WHEN** a client sends pointing feedback with a coordinate outside the selected screen bounds
- **THEN** the runtime clamps the target into the screen that contains the cursor session's attached window (or, when the session has no attachment, into the visible screen containing the point), reports that clamping occurred in the response, and does not throw solely because the point was out of bounds

#### Scenario: Pointing response is asynchronous

- **WHEN** a client sends pointing feedback with a valid target
- **THEN** the route returns after scheduling the pointing animation with planned duration metadata, without waiting for the full animation and dwell to complete

#### Scenario: Pointing is interrupted by newer action

- **WHEN** a cursor is running a pointing feedback animation and a new action starts for the same `cursor.id`
- **THEN** the runtime cancels or replaces the pointing feedback before rendering the new action state

#### Scenario: Disabled cursor skips visual pointing

- **WHEN** visual cursor behavior is disabled for the caller
- **THEN** pointing feedback returns a disabled or no-op cursor response and does not start overlay windows or wait for animation
