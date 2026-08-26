# cursor-overlay Specification

## ADDED Requirements

### Requirement: The agent cursor is never composited into images used as verification evidence

The visible agent cursor exists to explain the agent's work to the user, so it belongs in model-facing and user-facing screenshots. It SHALL NOT appear in any image the runtime then reads back as evidence that an action had an effect, because the runtime would be measuring its own drawing. Images used for verification SHALL come from a capture path that composites no overlay.

#### Scenario: Verification capture excludes the overlay

- **WHEN** the runtime captures an image in order to compute anchor disappearance or a region change ratio
- **THEN** that image contains no agent cursor, independently of whether the cursor is currently visible to the user

#### Scenario: The user-facing screenshot still shows the cursor

- **WHEN** the same action returns a screenshot for the caller to inspect
- **THEN** the agent cursor remains composited into that returned image, so the visible explanation of the agent's work is unchanged
