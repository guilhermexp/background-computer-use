# visual-annotations Specification

## ADDED Requirements

### Requirement: Window annotation route

`POST /v1/annotate_window` SHALL return a model-facing screenshot with numbered visual marks and a machine-readable mark table for visible UI targets.

#### Scenario: Annotated screenshot with reusable targets

- **WHEN** a client sends `annotate_window` for a live window
- **THEN** the response contains an annotated image, a bounded `marks` array, and each mark includes its `markID`, model-facing point, role/label metadata, and a reusable semantic target when one is available

#### Scenario: Annotations are opt-in

- **WHEN** a client calls `get_window_state`
- **THEN** the normal state response remains unannotated unless the client separately calls `annotate_window`

#### Scenario: Bounded marks

- **WHEN** the window has more annotatable targets than `maxMarks`
- **THEN** the route returns at most `maxMarks` marks and sets `truncated:true`

#### Scenario: Menu bar stays opt-in

- **WHEN** a client sends `annotate_window` without `includeMenuBar`
- **THEN** the route omits macOS menu bar nodes from annotation candidates by default

#### Scenario: Screenshot unavailable

- **WHEN** screenshot capture fails or is unavailable
- **THEN** the route returns the state and marks it could compute, reports `annotatedImage:null`, and includes a note explaining why no annotated artifact was generated
