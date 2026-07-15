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
