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

5. For visual tasks, request screenshots with `imageMode: "path"` and inspect the returned image files when useful.

6. For action routes, reuse `stateToken` from the state you inspected. Reuse the same `cursor.id` when the user wants one continuous visible cursor.

7. When the visible cursor should explain work in real time, call `POST /v1/cursor_feedback` with public agent-facing text. Stream useful observations or visible response text; do not show route labels like "reading screen", tool names, product branding, or hidden chain-of-thought.

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
`verification.targetRegionChangeThreshold`), `ocr_anchor_disappeared`, `focused_element_changed`,
`modal_dialog_opened`, `window_title_changed`, or `target_state_changed`. Rendered-text and
selection-summary changes are ambient noise on a live window; they appear in
`verification.ambientOnlySignals` and never prove anything by themselves. When
`targetRegionChangeRatio` or `ocrAnchorDisappeared` is `null`, `targetRegionDiagnostic` /
`ocrAnchorDiagnostic` says why — a null field is never counted as evidence.

### Cost of the first OCR read

Apple Vision pays a one-off cold start. The runtime prewarms it in the background at boot, but if you
call `includeOCR` within the first seconds after launch you may still wait several seconds. Warm reads
are around one second. `performance.ocrMs` reports the recognition time on every read that ran OCR —
use it instead of guessing. Recognition is bounded by a deadline; if it is exceeded you get
`ocr.status: "recognition_failed"` with a diagnostic rather than a hung request.

### Known limitation: Chromium web content

Measured 2026-08-04: coordinate and `ocr_anchor` clicks **do not activate controls inside Chromium web
content**. The events dispatch, the verifier honestly reports `effect_not_verified`, and the page does
not change — in background and in foreground, with offsets of ±10/20/30 px. Use an AX target
(`display_index` or `node_id`) from the projected tree for those controls; that path works. Do **not**
retry the same coordinate hoping for a different result, and do not treat a dispatched-but-unverified
click as done. OCR anchors remain the right tool for reading the screen and for surfaces where
coordinate dispatch does land.

## Helpers

- `scripts/ensure-runtime.sh`: find, install, launch, and bootstrap the runtime.
- `scripts/install-runtime.sh`: install `BackgroundComputerUse.app` from an app zip or release URL.
- `scripts/bcu-request.py`: call runtime endpoints from the manifest base URL.

Examples:

```bash
python3 "$SKILL_DIR/scripts/bcu-request.py" GET /v1/bootstrap
python3 "$SKILL_DIR/scripts/bcu-request.py" GET /v1/routes
python3 "$SKILL_DIR/scripts/bcu-request.py" POST /v1/list_apps '{}'
```

## Local Development

When working from a source checkout instead of an installed release:

```bash
BCU_SOURCE_DIR=/path/to/background-computer-use bash "$SKILL_DIR/scripts/ensure-runtime.sh"
```

That runs the repo's `script/start.sh`, which builds, signs, installs, launches, and bootstraps the app.

## More Detail

Read `references/runtime.md` only when you need install modes, release packaging notes, or the permission/debugging checklist.
