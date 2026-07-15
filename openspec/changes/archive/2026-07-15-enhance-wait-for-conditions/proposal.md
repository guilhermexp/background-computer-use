## Why

Real BCU sessions currently need clients to hand-roll repeated `get_window_state` calls when waiting for navigation, title changes, URL-bearing web nodes, or plain rendered text to settle. That makes agent flows slower and noisier because every poll may request a screenshot even when the wait condition only needs AX state.

Ghost OS shows a useful pattern here: keep waits as cheap condition polling, then return one fresh state after the condition is met.

## What Changes

- Extend `POST /v1/wait_for` with window title, URL, rendered text, and title-change predicates.
- Keep `gone=true` support for appearance/disappearance predicates, while rejecting nonsensical `gone + windowTitleChanged` requests.
- Poll with screenshots omitted, then capture the final state using the requested `imageMode`.
- Document that clients should use `wait_for` instead of manual sleep/read loops for UI transitions.

## Impact

- API surface: additive request fields for `wait_for`; no response shape change.
- Runtime: `WaitForRouteService` condition evaluation and polling image-mode policy.
- Docs/tests: route schema, guide text, README route list, and matcher unit coverage.
