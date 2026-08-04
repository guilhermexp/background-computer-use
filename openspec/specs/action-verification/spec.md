# action-verification Specification

## Purpose
Ações mutantes (click, scroll, press_key, set_value, type_text) retornam um bloco `verification` que classifica o efeito observado (success / effect_not_verified / verifier_ambiguous), permitindo ao agente distinguir sucesso de transporte de efeito real na UI.
## Requirements
### Requirement: press_key effect verification

`POST /v1/press_key` responses SHALL include a post-action `verification` block, using the same post-state read and classification machinery as click and scroll, so callers can distinguish transport success from observed effect.

#### Scenario: Key press with observable effect

- **WHEN** a client sends `press_key` with `"key":"command+w"` against a window whose close triggers a save sheet
- **THEN** the response contains a `verification` block with classification `success` and evidence of the observed change (e.g. focused element or window content change) plus a post-action `stateToken`

#### Scenario: Key press with no observable effect

- **WHEN** a client sends a `press_key` whose dispatch succeeds but produces no detectable state change
- **THEN** the response still has `ok:true` at the transport level and the `verification` block classifies the action as `dispatched_no_observed_effect`

### Requirement: Consistent window resolution across action routes

All action routes SHALL resolve a given `windowID` to the same window element using shared resolution logic, so `press_key` never acts on a different window than `click`/`scroll`/`type_text` for the same request.

#### Scenario: press_key and click resolve the same window

- **WHEN** two windows of the same app exist without a usable AXWindowNumber (one focused) and a client targets one `windowID`
- **THEN** `press_key` resolves the same window element that `click`/`scroll`/`type_text` resolve, because they share one `scoreWindow`/`resolveWindowElement` implementation

#### Scenario: No duplicated resolution heuristic

- **WHEN** the window-resolution heuristic (frame tolerance, focus bonus, fallback) is invoked by any action route
- **THEN** it is defined in exactly one place (the shared target resolver), not copied per route with divergent weights

### Requirement: Action settle timing elapses before verification

The configured settle delay before a verification reread, and the poll interval of `wait_for`, SHALL actually elapse on the threads where routes execute, so verification observes post-action state and polling does not busy-loop.

#### Scenario: Settle delay elapses on a background queue

- **WHEN** an action's settle delay runs on a dispatch queue thread (not the main thread, no run-loop source attached)
- **THEN** the delay actually pauses for its configured duration before the verification reread, instead of returning immediately

#### Scenario: Run-loop-dependent call sites are preserved

- **WHEN** a call site depends on pumping the run loop (AX observer callbacks, or an explicitly main-thread branch)
- **THEN** it continues to use `run(until:)` rather than a plain sleep

