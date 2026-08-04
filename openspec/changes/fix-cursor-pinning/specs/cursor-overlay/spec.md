# cursor-overlay Specification

## ADDED Requirements

### Requirement: Visual cursor tip matches the dispatched action point

The visual cursor tip SHALL be placed at the same point the action dispatches. The runtime SHALL NOT apply any decorative, randomized, or "visual interest" offset between the resolved action point and the rendered cursor position, and SHALL NOT use random number generation to choose a cursor position.

#### Scenario: Reported visual point equals the action point

- **WHEN** an action route resolves a target point and prepares the visual cursor for that action
- **THEN** `cursor.targetPointAppKit` equals the point the action dispatches (`coordinate.targetPointAppKit` or the resolved AX point), not an offset derived from the target frame

#### Scenario: Large targets get no decorative offset

- **WHEN** the action target frame is large enough that a decorative offset used to be applied (any dimension of 72 pt or more)
- **THEN** the visual cursor still lands on the resolved action point and `cursor.targetPointSource` reports only the action point source, without a `visual_interest_offset` component

#### Scenario: Cursor position is not randomized

- **WHEN** the same action is prepared twice against the same target and window from the same previous cursor position
- **THEN** both preparations produce the same visual cursor point

### Requirement: Visual cursor is pinned to the attached window

The runtime SHALL clamp the visual cursor position first to the frame of the attached window and then to the screen that contains that window. When the cursor session has a window attachment, the runtime SHALL NOT fall back to `NSScreen.main` or to a screen chosen by the stray point.

#### Scenario: Point outside the window is clamped into the window

- **WHEN** a cursor point resolves outside the attached window frame
- **THEN** the point is clamped inside that window frame and the response reports the clamp in `cursor.warnings`

#### Scenario: Multi-display clamp uses the window screen

- **WHEN** two displays are present, the attached window lives on one of them, and the cursor point falls outside visible screen geometry
- **THEN** the point is clamped into the screen that contains the attached window, never into `NSScreen.main` or the other display

#### Scenario: Cursor follows the attached window frame

- **WHEN** the attached window changes frame between two actions
- **THEN** the cursor keeps its relative position inside the window instead of staying at the stale absolute screen point

### Requirement: Attached cursor stays visible

While a cursor session has a live window attachment and that window is on screen, the overlay SHALL keep the cursor visible (`visibilityAlpha = 1`) and SHALL NOT fade it out because `CursorPresenceTiming.idleHideDelay` elapsed. The idle fade SHALL resume when the attachment is lost, and `CursorPresenceTiming.idleExpireDelay` SHALL keep expiring inactive sessions unchanged.

#### Scenario: Attached cursor survives the idle hide delay

- **WHEN** a cursor session is attached to an on-screen window and stays idle for longer than `CursorPresenceTiming.idleHideDelay`
- **THEN** the cursor remains visible with full visibility alpha

#### Scenario: Lost attachment resumes the idle fade

- **WHEN** the attached window is closed, minimized, or moved off every screen
- **THEN** the cursor fades out following `CursorPresenceTiming.idleHideDelay` and `CursorPresenceTiming.fadeOutDuration`

#### Scenario: Session expiry is unchanged

- **WHEN** an attached cursor session stays inactive for `CursorPresenceTiming.idleExpireDelay`
- **THEN** the session is expired and all its overlay presentation is removed, exactly as for unattached sessions

### Requirement: Idle visual cursor does not drift

When no action is in progress and no motion plan is running, the visual cursor position SHALL remain constant. The runtime SHALL NOT apply idle breathing, wobble, or any other continuous positional animation to a resting cursor.

#### Scenario: Resting cursor keeps its position

- **WHEN** a cursor session is at rest and the overlay advances several animation frames
- **THEN** the cursor position is unchanged across those frames

#### Scenario: Action choreography still animates

- **WHEN** an action starts for that cursor session (approach, click, scroll streak)
- **THEN** the cursor animates through the action choreography as before

### Requirement: Visual cursor is only drawn over the window it drives

The overlay SHALL be presented only while the attached window is the window visible under the cursor. The runtime SHALL NOT order the overlay relative to another application's window number, and SHALL NOT present the overlay when another application's window covers the cursor point. The window's own model-facing screenshot SHALL keep compositing the cursor even while the window is covered on screen.

#### Scenario: Covered window hides the on-screen cursor

- **WHEN** another application's window covers the point where the visual cursor sits for its attached window
- **THEN** no cursor overlay is drawn on screen for that session

#### Scenario: Exposed window shows the cursor at the action point

- **WHEN** the attached window is the frontmost window under the cursor point
- **THEN** the cursor overlay is drawn at the dispatched action point, above the driven window

#### Scenario: Overlay windows of the runtime never count as occluders

- **WHEN** exposure is resolved for an attached window
- **THEN** windows owned by the runtime process itself are ignored, so the cursor overlay does not hide itself

#### Scenario: Covered window still shows the cursor in its own screenshot

- **WHEN** the attached window is covered on screen and a model-facing screenshot of that window is captured with the cursor overlay enabled
- **THEN** the cursor is composited into that screenshot, because the screenshot is the agent's view of that window

## MODIFIED Requirements

### Requirement: Feedback lifecycle does not leave stuck overlays

The cursor overlay SHALL clear stale feedback and remove inactive overlay windows within bounded timing after the final activity for a cursor session.

#### Scenario: Finished feedback fades out

- **WHEN** a cursor feedback stream is finished and no action is in progress
- **THEN** the feedback bubble fades out within the configured feedback dwell and the cursor itself follows its presence rules: it stays visible while its window attachment is live, and follows `CursorPresenceTiming.idleHideDelay` once the attachment is lost

#### Scenario: Interrupted action clears transient feedback

- **WHEN** a new action starts for a cursor while previous feedback is still visible
- **THEN** stale transient feedback from the previous action is cleared or replaced before the new action state is rendered

#### Scenario: Expired cursor removes all overlay presentation

- **WHEN** a cursor session exceeds `CursorPresenceTiming.idleExpireDelay`
- **THEN** all cursor glyph, trail, effects, action state, feedback bubble, and overlay controller presentation for that cursor are removed

#### Scenario: Streaming feedback prevents premature fade

- **WHEN** a cursor session has active streaming feedback and no input action is currently in progress
- **THEN** cursor visibility remains active and does not fade out solely because `CursorPresenceTiming.idleHideDelay` elapsed

#### Scenario: Visibility and purge use same activity predicate

- **WHEN** cursor activity is evaluated for fade-out and session expiration
- **THEN** both paths use the same definition of active cursor state, including motion, action, press/release, visual effects, feedback dwell, streaming feedback, and pointing feedback

### Requirement: The window screenshot composites the cursor only around real activity

The pinned on-screen overlay SHALL NOT keep the cursor composited into the window's model-facing screenshot indefinitely. Compositing SHALL follow real cursor activity, because the screenshot is the evidence action verification reads and a parked cursor would occlude the very anchor a click uses as proof.

#### Scenario: Idle cursor leaves the screenshot but stays on screen

- **WHEN** a cursor session stays attached and idle beyond the idle hide delay
- **THEN** the window screenshot no longer composites it, while the on-screen overlay remains drawn

#### Scenario: Cursor around an action is composited

- **WHEN** a cursor session has just acted in its attached window
- **THEN** the window screenshot composites it, including while another app covers that window on screen
