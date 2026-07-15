## Why

Real-world BCU sessions need a clearer on-screen signal that the agent is alive and what it is publicly saying or observing while it works. The current cursor choreography shows activity, but it does not expose visible agent narration, streaming response text, or explicit target-pointing feedback in the overlay, making slow or stuck flows harder to diagnose.

## What Changes

- Add a stateful agent feedback layer to the existing visual cursor presentation.
- Render compact public response/observation bubbles anchored to the active agent cursor without stealing focus or intercepting clicks.
- Add explicit cursor states for idle, moving, acting, waiting, streaming, pointing, and error/retry feedback.
- Support semantic pointing feedback so callers can ask the cursor to briefly point at a screen coordinate with a short label.
- Preserve existing action route behavior and cursor request compatibility.
- Keep direct package calls with visual cursor disabled free of overlay startup, animation, and feedback costs.

## Capabilities

### New Capabilities

- `agent-feedback-overlay`: Cursor-attached feedback bubbles, streaming text, state indicators, and semantic pointing.

### Modified Capabilities

- `cursor-overlay`: Existing cursor sessions and presentation gain explicit action state and bounded lifecycle requirements while preserving stable default cursor behavior.

## Impact

- Cursor runtime: `Sources/BackgroundComputerUse/Cursor/CursorCoordinator.swift`, `CursorModels.swift`, `CursorOverlayController.swift`, and `CursorRenderer.swift`.
- Action targeting: `Sources/BackgroundComputerUse/Cursor/AXCursorTargeting.swift` and action services that call cursor prepare/finish hooks.
- API surface: route documentation may advertise optional feedback fields only where supported; existing request fields remain valid.
- Tests: extend cursor unit tests and add renderer/compositor checks for feedback visibility, lifecycle, disabled-cursor behavior, and semantic pointing.
