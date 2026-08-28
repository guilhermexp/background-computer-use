---
name: background-computer-use
description: "Launch and use the local BackgroundComputerUse macOS runtime through its self-documenting loopback API. Use when an agent needs to control local macOS apps or windows, inspect screenshots and Accessibility state, click/type/scroll/press keys, use the visible cursor, or help install/start the BackgroundComputerUse API from a skill."
version: 1.0.0
platforms: [macos]
metadata:
  hermes:
    tags: [macos, computer-use, automation]
---

# Background Computer Use

Use this skill to start or connect to the local macOS `BackgroundComputerUse` runtime, then rely on the runtime's own documentation endpoints instead of memorizing route schemas.

## Workflow

1. Start or discover the runtime:
   ```bash
   bash "$SKILL_DIR/scripts/ensure-runtime.sh"
   ```
   If `$SKILL_DIR` is not already set by the host, derive it from this skill folder path before running scripts.

2. Read the runtime manifest from:
   ```text
   $TMPDIR/background-computer-use/runtime-manifest.json
   ```
   Never assume a fixed port. Send `authToken` from the manifest as the
   `X-Background-Computer-Use-Token` header for every `/v1` request.

3. Call `GET /v1/bootstrap`.
   - If `instructions.ready` is false, report the returned permission steps to the user.
   - Do not continue with actions until Accessibility and Screen Recording are ready.

4. Call `GET /v1/routes`.
   - Treat this as the source of truth for available routes, request fields, response fields, examples, and error codes.
   - Do not assume browser routes exist; use them only when `/v1/routes` advertises them.

5. Call `POST /v1/list_apps`, select the exact `pid` of the target process, then call
   `POST /v1/list_windows` with `{"pid": PID}`. Names and bundle IDs are descriptive only and are
   never accepted as window selectors.

   To open an app that is not running, use `POST /v1/launch_app` with exactly one signed target form
   (`bundleID` or canonical `appPath`) and a task `sessionID`. BCU Control may show an explicit
   allow-once / always-allow / deny dialog. Do not retry while that user decision is pending.

6. For visual tasks, request screenshots with `imageMode: "path"` and inspect the returned image files when useful.

7. For action routes, reuse `stateToken` from the state you inspected. Reuse the same `cursor.id` when the user wants one continuous visible cursor. `type_text` prepares background input automatically and reports `strategiesAttempted`; `paste` supports text, Markdown, and HTML while preserving the complete clipboard. Read `backgroundSafety.foregroundPreserved` and never send the removed `focusAssistMode` field.

   BCU Control binds policy to bundle ID + signer + designated requirement. HTTP 423
   `control_paused` means mutations are paused but read routes remain available. HTTP 423
   `control_stopped` means the task session was revoked; only `/health` remains available until the
   app is restarted.

8. When the visible cursor should explain work in real time, call `POST /v1/cursor_feedback` with public agent-facing text. Stream useful observations or visible response text; do not show route labels like "reading screen", tool names, product branding, or hidden chain-of-thought.

   BCU Control shows at most one transient activity card. The user can disable it in
   `Ajustes > Mostrar cartão de atividades`; activity history continues to be recorded.

## Find targeted elements before reading the full tree

Use `POST /v1/find_elements` when an exact role and/or accessible-text substring can identify the
target. The response returns only matching nodes plus `stateToken` and `interactionToken` from the
same capture. Reuse a match's `displayIndex`, `nodeID`, or `refetchFingerprint` directly in the next
action. A successful query with no match returns an empty `matches` list; do not treat that as a
transport error.

For web content, read optional `domIdentifier` as the page author's HTML `id`. Prefer it for
recognition and disambiguation, while still dispatching actions with one of the supported target
kinds advertised by `/v1/routes`.

## Clicking what the AX tree cannot see (OCR anchors)

Some surfaces — Chromium/Electron web content above all — expose little or nothing useful in the
Accessibility tree. `get_window_state` can return local OCR anchors that double as click targets.

Loop:

1. `POST /v1/get_window_state` with `{"includeOCR": true, "imageMode": "path"}`.
   Read `ocr.anchors[]`: each anchor carries `text`, model-facing `x`/`y`, `box`, and a ready-made
   `target` of `{"kind":"ocr_anchor","value":"ocr_..."}`. Also keep `interactionToken` from the *same*
   response.
2. `POST /v1/click` with that `target` **and** the `interactionToken` you just read.
3. Read state again (`get_window_state`) and confirm the change you expected actually happened.

`interactionToken` is fail-closed on purpose. It hashes window identity, geometry, and projected
topology while ignoring volatile text, so it survives a live-updating page but dies when the layout
moves. A missing or stale token returns HTTP 200 with `classification: "verifier_ambiguous"`,
`fallbackReason: "stale_coordinate_guard"`, an explanatory `summary`, `failureDomain: "targeting"`,
and a rejected entry in `routeSteps`. The recovery is always the same: re-read state, take the fresh
anchor and fresh token, and click again. Never reuse an anchor id across reads.

Right after a page load, a navigation, or a scroll, the very first read can already be superseded by
the time your click reaches the runtime, so a token that looks fresh still comes back stale. When that
happens, read state twice and only click once two consecutive reads report the same
`interactionToken`. That is re-establishing identity, not retrying a failed action.

### Reading the click verdict

`classification: "success"` requires dispatch **plus** at least one entry in
`verification.intentSignals`: `target_region_changed` (target-local pixels moved past
`verification.targetRegionChangeThreshold`), a clean pre-gate `ocr_anchor_disappeared`, `focused_element_changed`,
`modal_dialog_opened`, `window_title_changed` on native surfaces, `target_state_changed`, or
`web_area_text_changed`. Credit `web_area_text_changed` only on a web renderer after two identical
pre-dispatch web-area text samples and a differing post-settle sample. An unstable or unavailable
baseline never proves intent and carries a diagnostic. Whole-window rendered-text and
selection-summary changes remain ambient noise; they appear in
`verification.ambientOnlySignals` and never prove anything by themselves. When
`targetRegionChangeRatio` or `ocrAnchorDisappeared` is `null`, `targetRegionDiagnostic` /
`ocrAnchorDiagnostic` says why — a null field is never counted as evidence.

The runtime measures `ocrAnchorDisappeared` from a separate window capture that never composites the
agent cursor. The screenshot returned to you still includes that cursor. It compares focused elements
by stable AX identity against a baseline sampled after the click transport's own focus-without-raise
step. If either clean measurement is unavailable, it fails closed with a diagnostic. Anchor evidence
computed after the coordinate escalation decision remains diagnostic only and cannot upgrade the
classification that gate already evaluated.

### Cost of the first OCR read

Apple Vision pays a one-off system cold start that can take tens of seconds after boot. OCR runs in a
disposable child process, so a stalled recognition is terminated at the deadline and cannot poison
the loopback server or the next read. Later reads are normally under one second.
`performance.ocrMs` reports the complete OCR-worker time — use it instead of guessing. A deadline
failure returns `ocr.status: "recognition_failed"` with a diagnostic and no leaked worker.

### Chromium web content: the click escalates to accessibility

Measured 2026-08-04: Chromium **discards the pid-directed synthetic mouse events** this runtime posts.
Nine event variants were tried (NSEvent- and CGEventSource-backed, subtype 3/0/untouched, with and
without the primer pair, full/minimal/no field stamps, HID and private sources), in background and with
Chrome frontmost — none activated a plain HTML button. The identical event posted to the global HID tap
does click it, and an AX target on the same button always worked, so the coordinate and the event are
fine: only the per-process delivery is refused. The same is true of Chrome's own UI — an injected click
on an inactive tab does not switch tabs.

So the click route no longer stops there: when a coordinate or `ocr_anchor` click dispatches and the
intent gate proves nothing, the runtime hit-tests the accessibility element **at that same screen
point** and presses it, then re-verifies. On success you get `finalRoute: "coordinate_then_ax_hit_test"`
(or the OCR route with `fallbackReason: "coordinate_unverified_using_ax_hit_test"`), plus a
`transports[]` entry with `route: "ax_perform_action"` and `liveElementResolution:
"ax_hit_test_at_click_point"`. This is what makes the OCR-anchor lane work on Chromium, in background.

The escalation presses only an element that exposes a press action and whose frame really covers the
point: a renderer reports a control scrolled out of the viewport with a collapsed frame (a 177x1 button
was observed), and pressing that would act on something you never pointed at.

Residual limit: a surface with no accessibility node under the point — canvas, WebGL, custom renderers
— still has no background pointer path. You get `effect_not_verified`, `failureDomain:
"app_specific_semantics"` and the warning `renderer_ignores_coordinate_injection`. Do not retry the same
coordinate hoping for a different result, and never treat a dispatched-but-unverified click as done.

## Run arbitrary Apple Events source

Use `POST /v1/run_script` only when no verified UI route covers the required Apple Events
capability. Send `language: "applescript"` or `"javascript"`, arbitrary `source`, and an optional
`timeoutMs`. The runtime caps and enforces the timeout, terminates the process group on expiry, and
returns process-level `status`, `stdout`, `stderr`, `durationMs`, `timedOut`, and
`effectiveTimeoutMs`.

When BCU Control is connected, this route is blocked by default with `control_policy_required`
because arbitrary source cannot be bound to one approved app identity. Use the verified per-window
routes instead; do not weaken the Control policy to make a script convenient.

Treat this lane as **unverified**: the response intentionally has no `classification` and never
claims an observed UI effect. Always call `get_window_state` or `find_elements` afterwards to confirm
what changed. The auth token now authorizes arbitrary control of scriptable apps through this lane.
Every attempt is recorded at
`$TMPDIR/background-computer-use/audit/script-executions.jsonl`, mode `0600`, inside a `0700`
directory. Never copy the submitted source into ordinary debug artifacts or chat logs.

## Helpers

- `scripts/ensure-runtime.sh`: find, install, launch, and bootstrap the runtime.
- `scripts/install-runtime.sh`: install `BackgroundComputerUse.app` from an app zip or release URL.
- `scripts/bcu-request.py`: call runtime endpoints from the manifest base URL.

Locked use is opt-in and disabled by default. Never run a primary-host installation merely because
the bundle builds. `script/qualify_locked_use.sh` is non-mutating by default, and actual install is
eligible only after the VM/secondary-Mac matrix in `docs/locked-use-recovery.md` passes.

Examples:

```bash
python3 "$SKILL_DIR/scripts/bcu-request.py" GET /v1/bootstrap
python3 "$SKILL_DIR/scripts/bcu-request.py" GET /v1/routes
python3 "$SKILL_DIR/scripts/bcu-request.py" POST /v1/list_apps '{}'
python3 "$SKILL_DIR/scripts/bcu-request.py" POST /v1/list_windows '{"pid":12345}'
```

## Local Development

When working from a source checkout instead of an installed release:

```bash
BCU_SOURCE_DIR=/path/to/background-computer-use bash "$SKILL_DIR/scripts/ensure-runtime.sh"
```

That runs the repo's `script/start.sh`, which builds, signs, installs, launches, and bootstraps the app.

## More Detail

Read `references/runtime.md` only when you need install modes, release packaging notes, or the permission/debugging checklist.
