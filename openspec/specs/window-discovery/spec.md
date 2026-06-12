# window-discovery Specification

## Purpose
TBD - created by archiving change harden-agent-api-reliability. Update Purpose after archive.
## Requirements
### Requirement: list_windows returns unique real windows

`POST /v1/list_windows` SHALL return only real windows (AX role `AXWindow`), SHALL exclude auxiliary AX containers such as the desktop scroll area, and SHALL guarantee that each returned entry has a unique `windowID`.

#### Scenario: Desktop scroll area is not listed as a window

- **WHEN** a client lists windows for Finder while the desktop `AXScrollArea` is exposed by the app's AX tree
- **THEN** the response contains only the real Finder windows, with no `AXScrollArea` entry

#### Scenario: windowID uniqueness

- **WHEN** two AX elements resolve to the same backing window
- **THEN** the response contains a single entry for that window, and no two entries in any response share a `windowID`
