# BackgroundComputerUse

Local macOS computer-use API for controlling native apps, browser windows, and multi-window desktop workflows without taking over the user's pointer.

The runtime exposes a loopback HTTP API, reads window screenshots and Accessibility state, and dispatches clicks, scrolling, text, key presses, secondary actions, and window motion against target windows. It uses macOS Accessibility, Screen Recording, and native/private window-event APIs.

At rough parity with OpenAI Codex Computer Use plugin 

[![BackgroundComputerUse demo](cover.png)](https://youtu.be/RmB5Ontqb3Y)

[Watch the demo](https://youtu.be/RmB5Ontqb3Y)

## Start

```bash
./script/start.sh
```

The script builds the Swift package, creates/signs a `.app` bundle, installs it to `~/Applications/BackgroundComputerUse.app`, launches it, waits for the runtime manifest, prints the active local URL, and calls `/v1/bootstrap`.

Runtime metadata is written to:

```text
$TMPDIR/background-computer-use/runtime-manifest.json
```

The manifest includes `baseURL`, `authToken`, permission status, bootstrap instructions, and route summaries. Agents should read this file instead of assuming a fixed port, then send `authToken` as the `X-Background-Computer-Use-Token` header for every `/v1` request. `/health` remains unauthenticated for local liveness checks.

## Signing And Permissions

Since the app requires accessibility + screenshot permissions, you need to sign (self-sign ok) the app after building 

macOS permissions attach to the signed app bundle, not to an arbitrary command-line binary. Launch development builds through:

```bash
./script/start.sh
```

or:

```bash
./script/build_and_run.sh run
```

If no signing identity is configured, `script/build_and_run.sh` calls `script/bootstrap_signing_identity.sh` to create a local development code-signing identity in:

```text
~/Library/Keychains/background-computer-use-dev.keychain-db
```

You can override signing with:

```bash
BACKGROUND_COMPUTER_USE_SIGNING_IDENTITY="Developer ID Application: ..."
./script/start.sh
```

If `/v1/bootstrap` reports missing permissions, grant them in System Settings and relaunch the app through the script.

## Swift Package Usage

The package also exposes a direct Swift API for callers that do not need the loopback server:

Depend on the `BackgroundComputerUseKit` library product, then import the `BackgroundComputerUse` module:

```swift
import BackgroundComputerUse

let runtime = BackgroundComputerUseRuntime()
let apps = runtime.listApps()
let windows = try runtime.listWindows(.init(pid: apps.runningApps[0].pid))
```

Direct package calls default to `visualCursor: .disabled`, so action methods do not start the virtual cursor overlay or wait for cursor animation before dispatching. Existing action verification and post-action rereads still run.

Target factories validate the same shape as the HTTP JSON decoder and throw for invalid display indexes or empty node identifiers.

Enable the visual cursor explicitly when you want the same cursor choreography used by the app runtime:

```swift
let runtime = BackgroundComputerUseRuntime(
    options: .init(visualCursor: .enabled)
)
```

macOS permissions attach to the signed host application. The bundled HTTP runtime keeps using the stable `xyz.dubdub.backgroundcomputeruse` app identity from `script/build_and_run.sh`; direct package consumers should use their own stable signed app identity if they need Accessibility or Screen Recording permissions.

## API Flow

1. `GET /v1/bootstrap`
2. Check `permissions` and `instructions.ready`.
3. `GET /v1/routes`
4. `POST /v1/list_apps`
5. `POST /v1/list_windows` with the exact `pid` picked from `list_apps`. Application names and bundle IDs are descriptive only and are never accepted as selectors, so duplicate instances of the same app stay distinguishable.
6. `POST /v1/get_window_state`
7. Optionally call `POST /v1/annotate_window` when you need a numbered screenshot-to-target map.
8. Optionally stream visible agent feedback with `/v1/cursor_feedback`.
9. Act with `/v1/click`, `/v1/scroll`, `/v1/type_text`, `/v1/press_key`, `/v1/set_value`, `/v1/perform_secondary_action`, `/v1/drag`, `/v1/resize`, or `/v1/set_window_frame`.
10. Read state again.

For visual work, request screenshots with `imageMode: "path"` or `imageMode: "base64"` and inspect them whenever possible. The AX tree is useful for semantic targeting, but screenshots are the visual ground truth; AX state and verifier summaries can lag, omit visual-only state, or be incomplete in some apps.

## Routes

`GET /v1/routes` is the self-documenting API catalog. It returns each route's method, path, summary, request schema, and response schema.

All `/v1` POST routes decode strictly against the documented top-level `request.fields` returned by `/v1/routes`. Unknown fields return HTTP 400 `invalid_request`; the error message names the unknown field(s), lists the accepted fields for that route, and includes `recovery` guidance.

Action responses omit verbose implementation `notes` by default. Add `"debug": true` to action requests when you want transport/planner notes for debugging.

Core routes:

- `GET /health`
- `GET /v1/bootstrap`
- `GET /v1/routes`
- `POST /v1/list_apps`
- `POST /v1/list_windows`
- `POST /v1/cursor_feedback`
- `POST /v1/get_window_state`
- `POST /v1/find_elements`
- `POST /v1/annotate_window`
- `POST /v1/click`
- `POST /v1/scroll`
- `POST /v1/perform_secondary_action`
- `POST /v1/drag`
- `POST /v1/resize`
- `POST /v1/set_window_frame`
- `POST /v1/type_text`
- `POST /v1/press_key`
- `POST /v1/set_value`
- `POST /v1/wait_for`
- `POST /v1/read_text`
- `POST /v1/select_text`
- `POST /v1/run_script`

## Minimal Curl

```bash
BASE="$(python3 - <<'PY'
import json, os
path = os.path.join(os.environ["TMPDIR"], "background-computer-use", "runtime-manifest.json")
print(json.load(open(path))["baseURL"])
PY
)"

TOKEN="$(python3 - <<'PY'
import json, os
path = os.path.join(os.environ["TMPDIR"], "background-computer-use", "runtime-manifest.json")
print(json.load(open(path))["authToken"])
PY
)"

curl -s -H "X-Background-Computer-Use-Token: $TOKEN" "$BASE/v1/bootstrap" | python3 -m json.tool
curl -s -H "X-Background-Computer-Use-Token: $TOKEN" "$BASE/v1/routes" | python3 -m json.tool
curl -s -X POST "$BASE/v1/list_apps" -H "X-Background-Computer-Use-Token: $TOKEN" -H 'content-type: application/json' -d '{}' | python3 -m json.tool
```

## State And Actions

Read a window:

```bash
curl -s -X POST "$BASE/v1/list_windows" \
  -H "X-Background-Computer-Use-Token: $TOKEN" \
  -H 'content-type: application/json' \
  -d '{"pid":1234}' | python3 -m json.tool

curl -s -X POST "$BASE/v1/get_window_state" \
  -H "X-Background-Computer-Use-Token: $TOKEN" \
  -H 'content-type: application/json' \
  -d '{"window":"WINDOW_ID","imageMode":"path","maxNodes":6500}' | python3 -m json.tool
```

Click by semantic target:

```bash
curl -s -X POST "$BASE/v1/click" \
  -H "X-Background-Computer-Use-Token: $TOKEN" \
  -H 'content-type: application/json' \
  -d '{"window":"WINDOW_ID","target":{"kind":"display_index","value":12},"clickCount":1,"imageMode":"path"}' | python3 -m json.tool
```

Click by screenshot coordinate:

```bash
curl -s -X POST "$BASE/v1/click" \
  -H "X-Background-Computer-Use-Token: $TOKEN" \
  -H 'content-type: application/json' \
  -d '{"window":"WINDOW_ID","x":240,"y":180,"clickCount":2,"imageMode":"path"}' | python3 -m json.tool
```

Type into a text target:

```bash
curl -s -X POST "$BASE/v1/type_text" \
  -H "X-Background-Computer-Use-Token: $TOKEN" \
  -H 'content-type: application/json' \
  -d '{"window":"WINDOW_ID","target":{"kind":"display_index","value":4},"text":"hello","imageMode":"path"}' | python3 -m json.tool
```

Action routes show the on-screen agent cursor by default when the HTTP runtime has visual cursors enabled. If the request omits `cursor`, the runtime reuses the stable default session:

```json
{"id":"agent","name":"Agent","color":"#0095A1"}
```

Use the optional `cursor` object when a client needs to customize or reuse a separate cursor lane:

```json
{"id":"agent-1","name":"Agent","color":"#20C46B"}
```

Cursors are session-based: the same `cursor.id` moves one continuous on-screen cursor, while different IDs create independent lanes. The default `agent` session prevents duplicate unnamed cursors while keeping activity visibly present during actions.

Use `POST /v1/cursor_feedback` to update the visible cursor bubble without dispatching input. The message is public, user-visible narration: use observations or response text, not route labels, hidden chain-of-thought, tool names, or product branding.

```bash
curl -s -X POST "$BASE/v1/cursor_feedback" \
  -H "X-Background-Computer-Use-Token: $TOKEN" \
  -H 'content-type: application/json' \
  -d '{"operation":"update","state":"streaming","window":"WINDOW_ID","message":"Vou verificar o resultado antes do proximo clique."}' | python3 -m json.tool
```

When no target window is available, cursor feedback is accepted but deferred instead of showing a global overlay above unrelated apps. Use `operation:"hide"` to clear the bubble immediately after a task.

Use `POST /v1/annotate_window` when the screenshot and AX tree are hard to align. It returns a numbered annotated screenshot plus `marks[]`; each mark includes a model-facing point and a reusable `target` when available.

Use `POST /v1/wait_for` after navigation or actions that trigger loading instead of manual sleep/read loops. It can wait for role/label/value matches, `windowTitleContains`, `windowTitleChanged`, `urlContains`, or `textContains`. Intermediate polls omit screenshots for speed; the returned final state honors the requested `imageMode`.

`POST /v1/press_key` returns transport-level `ok` plus a `verification` block. Read `verification.classification` for the observed effect signal: `success`, `dispatched_no_observed_effect`, or `failed`. The block includes post-action state evidence such as focused element changes, text/value diffs, selection changes, visual changes, and the post `stateToken` when available.

`press_key` accepts normal macOS chord names such as `command+a`, `escape`, and `backspace`. For select-all in Electron text fields, the runtime first tries verified AX selection semantics and falls back to native key delivery when AX selection cannot be verified.

`POST /v1/type_text` prepares background input by itself: there is no public focus mode, and a success requires that the user's foreground application was preserved. Read `backgroundSafety.foregroundPreserved` in the response.

`POST /v1/list_windows` takes the exact `pid` of one running process, returns only real AX windows, and keeps one entry per backing `windowID`; auxiliary AX containers such as Finder's desktop scroll area are excluded.

`POST /v1/run_script` runs arbitrary AppleScript/JXA source, so the runtime token also authorizes control of any scriptable app. The lane is unverified — re-read state afterwards — and every attempt is recorded in `$TMPDIR/background-computer-use/audit/script-executions.jsonl`.

## License

MIT

---

crafted by [cam](https://x.com/financialvice) and [anupam](https://x.com/anupambatra_) | [dubdubdub labs](https://www.dubdubdub.xyz/)
