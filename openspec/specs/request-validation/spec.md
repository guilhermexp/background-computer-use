# request-validation Specification

## Purpose
Decodificação estrita dos requests: campos desconhecidos são rejeitados com `invalid_request` nomeando o campo, e formas mutuamente exclusivas (ex.: target vs x/y) são validadas antes da execução.
## Requirements
### Requirement: Strict request field validation

All `/v1` POST routes SHALL reject requests containing top-level fields that are not part of the route's documented request schema, returning an `invalid_request` error instead of silently ignoring the unknown fields.

#### Scenario: Unknown field is rejected with actionable error

- **WHEN** a client sends `POST /v1/press_key` with body `{"window":"w_X","key":"w","modifiers":["command"]}`
- **THEN** the response is an `invalid_request` error whose message names `modifiers` as an unknown field and lists the accepted fields for the route, and no key press is dispatched

#### Scenario: Fully documented request still succeeds

- **WHEN** a client sends a request using only fields documented by `GET /v1/routes` for that route, including all optional fields
- **THEN** the request is decoded and executed normally

### Requirement: Self-documentation matches runtime behavior

`GET /v1/routes` SHALL document every request field's default and coordinate space to match the value the runtime actually applies, so an agent that trusts the self-documentation observes the documented behavior.

#### Scenario: Documented defaults equal effective defaults

- **WHEN** a client reads the `includeMenuBar` default for `get_window_state` or `annotate_window` from `/v1/routes`
- **THEN** the documented default equals the value the corresponding service applies when the field is omitted (`get_window_state` includes the menu bar by default; `annotate_window` does not)

#### Scenario: Coordinate fields name their space

- **WHEN** a client reads the `toX`/`toY` fields of `drag`/`resize` or the `x`/`y` fields of any action route
- **THEN** the documentation names the coordinate space the runtime consumes (e.g. AppKit-global bottom-left logical points for window motion) rather than a mismatched or absent space

#### Scenario: press_key key syntax is documented

- **WHEN** a client reads the `key` field of `press_key`
- **THEN** the documentation describes the chord separator `+` and the accepted modifier aliases (command/cmd/meta/super, control/ctrl, option/alt, shift) with examples

### Requirement: No silently-ignored request fields

Every request field accepted by strict decoding SHALL have an observable effect, so a client cannot believe it changed behavior when it did not.

#### Scenario: Dead fields are removed, not ignored

- **WHEN** a request field has no effect on any service (e.g. a verification-mode selector never read by the scroll service)
- **THEN** the field is removed from the request contract and its schema documentation rather than being accepted and ignored

#### Scenario: Documented image capture is retrievable

- **WHEN** a client sends an action with `imageMode` other than `omit`
- **THEN** either the captured screenshot is returned in the response, or the action route does not advertise `imageMode` at all — the runtime never captures and discards a screenshot the client cannot retrieve

### Requirement: Errors carry their underlying cause

Error responses for unexpected failures SHALL include the underlying error description and a stable request identifier, so an agent can act on a specific cause instead of a generic message.

#### Scenario: Capture failure reports the cause

- **WHEN** a route fails because AX capture or screenshot capture threw
- **THEN** the error response carries the underlying error description and a route-specific error code (e.g. `capture_failed`, `screenshot_failed`) rather than a fixed "Route X failed." message

#### Scenario: Error requestID is the request's own

- **WHEN** an error response is produced
- **THEN** its `requestID` is the identifier of the failing request, not a freshly generated one

