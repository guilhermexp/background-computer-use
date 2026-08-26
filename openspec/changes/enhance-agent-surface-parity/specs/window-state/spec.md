# window-state Specification

## ADDED Requirements

### Requirement: State responses carry one canonical node locator

A state response SHALL serialize each node's locator exactly once. `nodeID`, `refetchFingerprint` and `displayIndex` SHALL be preserved because they are accepted as `target` input, and the duplicated locator objects carrying `ancestorFingerprints`, `rolePath` and a repeated signature SHALL NOT appear in the response, because fingerprint resolution happens in the runtime and never in the client. All four target kinds — `display_index`, `node_id`, `refetch_fingerprint` and `ocr_anchor` — SHALL keep working unchanged.

#### Scenario: The same hash is not repeated per node

- **WHEN** a client reads window state for a window whose tree contains nodes
- **THEN** each node exposes its fingerprint once, and no node contains a nested locator object repeating that fingerprint together with `ancestorFingerprints` and `rolePath`

#### Scenario: Targeting still works after the trim

- **WHEN** a client reads state and then dispatches an action using `display_index`, `node_id`, `refetch_fingerprint` or `ocr_anchor` taken from that read
- **THEN** the target resolves exactly as it did before the trim

### Requirement: State responses are encoded without cosmetic whitespace

The runtime SHALL encode API responses without pretty-printing and without key sorting, so bytes on the wire carry data rather than formatting.

#### Scenario: Response is compact

- **WHEN** any `/v1` response is serialized
- **THEN** it contains no indentation runs or newlines inserted for readability

### Requirement: State payload stays inside a declared budget

The runtime SHALL keep the per-node serialized cost inside a declared ceiling, asserted by a test against a representative window, so payload regressions fail the build instead of being discovered by an agent's context budget.

#### Scenario: Regression trips the budget test

- **WHEN** a change raises the serialized size of a node above the declared per-node ceiling
- **THEN** the budget test fails and names the measured size against the ceiling

### Requirement: Nodes expose the DOM identifier when the app publishes one

The runtime SHALL read `AXDOMIdentifier` and expose it on the node as `domIdentifier`, omitted when the app publishes no value, so an agent can target web content by the identity the page's own author assigned.

#### Scenario: Web button reports its HTML id

- **WHEN** a client reads state for a window rendering an HTML element that carries an `id` attribute
- **THEN** the corresponding node exposes `domIdentifier` with that value

#### Scenario: Native element omits the field

- **WHEN** a node's app publishes no `AXDOMIdentifier`
- **THEN** the node omits `domIdentifier` entirely rather than reporting an empty value

### Requirement: Targeted element query returns only matching nodes

`POST /v1/find_elements` SHALL accept a window plus a query by role and/or a text substring, and SHALL return only the matching nodes, each carrying the same target shapes a state read produces, together with the `stateToken` and `interactionToken` of the very read that produced them, so a match is directly actionable without a second full-window read. The route SHALL be read-only.

#### Scenario: Query returns the matched button, not the window

- **WHEN** a client queries a window for role `button` and text `Click me`
- **THEN** the response contains only nodes matching that query, and does not contain the full projected tree of the window

#### Scenario: Match is directly actionable

- **WHEN** a client dispatches a click using a target taken from a `find_elements` response together with the `interactionToken` from the same response
- **THEN** the target resolves and the stale-target guard accepts the token exactly as it would for a `get_window_state` read

#### Scenario: No match is an empty result, not an error

- **WHEN** a query matches no node in the window
- **THEN** the response succeeds with an empty match list and states that the query matched nothing
