# Plan 005: Make live smoke and transport-boundary tests prove observable effects

> **Executor instructions**: Follow this plan step by step. Run every verification command and confirm the expected result before moving to the next step. If anything in the "STOP conditions" section occurs, stop and report — do not improvise. When done, update the status row for this plan in `plans/README.md` unless a reviewer told you they maintain the index. Deterministic Swift/Python tests run normally; commands marked LIVE may launch apps, drive the signed Control UI, and require Accessibility/Screen Recording, so run them only with explicit operator authorization.
>
> **Drift check (run first)**: `git diff --stat 0110ffb..HEAD -- script Sources/BackgroundComputerUse/API/LoopbackServer.swift Sources/BackgroundComputerUseControl/ApprovalWindow.swift Tests/BackgroundComputerUseTests Tests/Fixtures/Apps/BCUElectronFixture`
> If any in-scope file changed since this plan was written, compare the "Current state" excerpts against the live code before proceeding; on a mismatch, treat it as a STOP condition. Also run `git status --short` and `git log --oneline 0110ffb..HEAD -- Sources/BackgroundComputerUse/API/Router.swift Sources/BackgroundComputerUse/App/BackgroundComputerUseControlBridge.swift Sources/BackgroundComputerUseControlShared/CodeSignatureIdentity.swift Sources/BackgroundComputerUse/Runtime/RuntimeExecutionQueue.swift Sources/BackgroundComputerUse/Actions/TypeText/AdaptiveTextDispatcher.swift Sources/BackgroundComputerUse/StatePipeline/InteractionToken.swift Sources/BackgroundComputerUse/Runtime/Process/BoundedProcessRunner.swift skills/background-computer-use/scripts/bcu-request.py Tests/BackgroundComputerUseTests/InteractionTokenTests.swift Tests/BackgroundComputerUseTests/RuntimeExecutionQueueTests.swift`. Every named baseline fix must be either modified in the working tree or present in a post-`0110ffb` commit; otherwise STOP.

## Status

- **Priority**: P1
- **Effort**: M/L
- **Risk**: MED
- **Depends on**: `plans/004-real-app-ax-fixture-corpus.md`
- **Category**: tests
- **Planned at**: commit `0110ffb`, 2026-09-02

## Why this matters

Several live smoke lanes currently accept HTTP transport success or ambiguous verification without checking the target application. The suite also bypasses two production boundaries: streamed HTTP chunks and the executable OCR worker protocol. This plan adds a deterministic Electron oracle, honest lane statuses, real loopback/subprocess integration tests, and a live Control identity test so a green result means the claimed effect was observed.

## Current state

- `script/smoke_runtime.py:264-300` uses `/v1/set_value` for Chrome text and passes `chrome-click` on HTTP 200 plus `ok`; it does not require `classification == "success"` plus the page marker.
- `script/smoke_runtime.py:314-330` accepts `verifier_ambiguous` for scroll. `reload_fixture` at lines 359-370 checks only HTTP status for `command+r` and sleeps two seconds.
- `script/smoke_runtime.py:392-545` has a strong OCR DOM oracle, but line 522 passes when the page changes regardless of response classification. `safari_text_fixture` starts at line 745, so strict `type_text`/paste coverage is WebKit-only.
- `script/smoke_runtime.py:660-710` generates a Chrome fixture with input/button text markers but no scroll-position or reload-generation marker.
- `script/smoke_control.py:89-129` sends `/v1/launch_app` in a worker thread and finds a localized Portuguese button title. It does not mutate an ad-hoc target window or exercise real `CodeSignatureIdentity.resolve(pid:)`.
- `ApprovalWindow.swift:23-30` adds three localized NSAlert buttons and only sets a window accessibility label; there are no stable AX identifiers.
- `ActivityControlTests.swift:242-277` injects `.deny` and `.identityUnresolvable` directly into `RouterControlPolicy.authorizeWindow`, bypassing the bridge and signature lookup.
- `LoopbackServer.swift:16-29` takes `RuntimeAuth`, binds IPv4 loopback on `.any`, and returns the ephemeral base URL. Lines 81-139 recursively receive arbitrary chunks and close after one response, but there is no stop method for tests.
- `APIDocumentationTests.swift:185-215` builds one complete `Data` buffer and calls `HTTPRequest.parse`/Router directly; it cannot catch streaming regressions.
- `OCRWorkerMain.swift:3-20` reads one JSON request from stdin, writes one JSON response to stdout, exits 0, and exits 2 on malformed input. `OCRWorkerClient.swift:6-42` locates `Bundle.main.executableURL`/`CommandLine.arguments[0]` and passes `--ocr-worker`; existing `OCRWorkerTests.swift:180-184` injects a process result instead.
- Project rules (`openspec/project.md:7-15`) are Swift 6.2/macOS 14, Swift Testing rather than XCTest, Actions consuming StatePipeline, and verifier-first action responses. A dispatched transport is not proof of effect; background errors must never be hidden by stealing focus.
- Measured live context to preserve in diagnostics: warm OCR was about 220–330 ms; Electron trees reached roughly 70 levels; Chromium applies AXValue asynchronously, discards pid-directed background key/mouse events, and previously returned `effect_not_verified` with `opaque_renderer_focus_unconfirmed`; foreground fallback has also failed to restore the prior app.

## Commands you will need

| Purpose | Command | Expected on success |
|---|---|---|
| Python policy tests | `python3 -m unittest script.test_smoke_runtime` | exit 0; strict classification/oracle policies pass |
| Loopback integration | `swift test --filter LoopbackServerIntegrationTests` | exit 0; split/EOF/auth/oversize cases pass |
| OCR executable protocol | `swift build --product BackgroundComputerUse && swift test --filter OCRWorkerProtocolTests` | exit 0; valid and malformed worker cases pass |
| Install pinned fixture dependency | `npm ci --prefix Tests/Fixtures/Apps/BCUElectronFixture` | exit 0; pinned Electron is installed locally |
| LIVE Electron regression | `python3 script/live_regression.py --output .build/live-regression.json` | JSON written; exit 0 only when no strict lane fails/skips |
| LIVE aggregate | `BCU_LIVE_AUTHORIZED=1 ./script/verify.sh --live` | deterministic gates pass; JSON artifacts written; declared limitations are not mislabeled as passes |
| Final deterministic gate | `swift test && python3 -m unittest script.test_smoke_runtime` | exit 0 |

## Scope

**In scope** (the only files you should modify):
- `Tests/Fixtures/Apps/BCUElectronFixture/package.json`, `package-lock.json`, `main.js`, `index.html` (create)
- `script/live_regression.py` (create)
- `script/smoke_runtime.py`
- `script/test_smoke_runtime.py`
- `script/smoke_control.py`
- `script/verify.sh` (created by dependency plan 002; extend it)
- `Sources/BackgroundComputerUseControl/ApprovalWindow.swift`
- `Sources/BackgroundComputerUse/API/LoopbackServer.swift`
- `Tests/BackgroundComputerUseTests/LoopbackServerIntegrationTests.swift` (create)
- `Tests/BackgroundComputerUseTests/OCRWorkerProtocolTests.swift` (create)

**Out of scope** (do NOT touch):
- Runtime action algorithms/classification policy; this plan exposes failures rather than weakening or special-casing them.
- A fixture-export HTTP route or public API contract.
- CI installation of Accessibility/Screen Recording permissions.
- Committing `node_modules`, temporary Electron app copies, runtime manifests/tokens, screenshots, or live JSON artifacts.
- XCTest, Playwright, WebDriver, or another test dependency.

## Git workflow

- Branch: `advisor/005-live-smoke-honesty`
- Commit logical units using repository style, for example `test: add strict Electron live regression` and `test: cover loopback and OCR process boundaries`.
- Do not push or open a PR unless instructed.

## Steps

### Step 1: Add the pinned Electron oracle application

Create `package.json` with this complete content, then run `npm install --package-lock-only --prefix Tests/Fixtures/Apps/BCUElectronFixture` and commit the generated lockfile:

```json
{
  "name": "bcu-electron-fixture",
  "version": "1.0.0",
  "private": true,
  "main": "main.js",
  "scripts": { "start": "electron ." },
  "devDependencies": { "electron": "37.4.0" }
}
```

Create `main.js` with this complete content:

```javascript
const { app, BrowserWindow } = require("electron");
app.commandLine.appendSwitch("force-renderer-accessibility");
app.setName("BCU Electron Fixture");
function createWindow() {
  const window = new BrowserWindow({
    width: 900, height: 720, show: false, title: "BCU Electron Fixture",
    webPreferences: { contextIsolation: true, nodeIntegration: false, sandbox: true }
  });
  window.loadFile("index.html");
  window.once("ready-to-show", () => { window.show(); console.log(`BCU_FIXTURE_READY pid=${process.pid}`); });
}
app.whenReady().then(createWindow);
app.on("window-all-closed", () => app.quit());
```

Create `index.html` with this complete content:

```html
<!doctype html>
<html lang="en"><head><meta charset="utf-8"><title>BCU Electron Fixture</title>
<style>body{font:16px -apple-system;padding:20px}textarea,button{font:inherit;padding:8px}.scroll{height:180px;overflow:auto;border:1px solid #777}.row{height:42px;padding:8px}</style></head>
<body><h1>BCU Electron Fixture</h1><div id="deep-root"></div>
<section id="controls" role="group" aria-label="fixture controls">
<label for="composer">Composer</label><textarea id="composer" aria-label="Composer" rows="4"></textarea>
<output id="value-marker" role="status" aria-live="polite">value:""</output>
<output id="selection-marker" role="status" aria-live="polite">selection:0:0</output>
<output id="input-count" role="status" aria-live="polite">input-events:0</output>
<output id="event-log" role="log" aria-live="polite">events:[]</output>
<button id="action-button" aria-label="BCU Fixture Button">BCU Fixture Button</button>
<output id="click-marker" role="status" aria-live="polite">clicked:false</output>
<div id="scroll-region" class="scroll" role="region" aria-label="BCU Scroll Region"><div id="rows"></div></div>
<output id="scroll-marker" role="status" aria-live="polite">scroll-top:0</output>
<output id="generation-marker" role="status" aria-live="polite">generation:1</output>
</section><script>
const composer=document.getElementById("composer"), events=[]; let inputCount=0;
function renderText(){document.getElementById("value-marker").textContent=`value:${JSON.stringify(composer.value)}`;document.getElementById("selection-marker").textContent=`selection:${composer.selectionStart}:${composer.selectionEnd}`;document.getElementById("input-count").textContent=`input-events:${inputCount}`;document.getElementById("event-log").textContent=`events:${JSON.stringify(events)}`;}
composer.addEventListener("input",e=>{const entry={type:"input",inputType:e.inputType||"unknown",value:composer.value};setTimeout(()=>{inputCount+=1;events.push(entry);renderText();},50);});
composer.addEventListener("keydown",e=>{events.push({type:"keydown",key:e.key,meta:e.metaKey});setTimeout(renderText,50);});
document.addEventListener("selectionchange",()=>setTimeout(renderText,50));
document.getElementById("action-button").addEventListener("click",()=>{const marker=document.getElementById("click-marker");marker.textContent=marker.textContent==="clicked:false"?"clicked:true":"clicked:false";});
const rows=document.getElementById("rows");for(let i=1;i<=80;i++){const row=document.createElement("div");row.className="row";row.textContent=`Row ${i}`;rows.appendChild(row);}
const scroll=document.getElementById("scroll-region");scroll.addEventListener("scroll",()=>document.getElementById("scroll-marker").textContent=`scroll-top:${Math.round(scroll.scrollTop)}`);
const generation=Number(sessionStorage.getItem("generation")||"0")+1;sessionStorage.setItem("generation",String(generation));document.getElementById("generation-marker").textContent=`generation:${generation}`;
let parent=document.getElementById("deep-root");for(let i=1;i<=72;i++){const group=document.createElement("div");group.setAttribute("role","group");group.setAttribute("aria-label",`depth-${i}`);parent.appendChild(group);parent=group;}parent.appendChild(document.getElementById("controls"));renderText();
</script></body></html>
```

**Verify**: `npm ci --prefix Tests/Fixtures/Apps/BCUElectronFixture && Tests/Fixtures/Apps/BCUElectronFixture/node_modules/electron/dist/Electron.app/Contents/MacOS/Electron --version` → exit 0 and prints the pinned Electron version.

### Step 2: Build a strict live Electron regression harness

Create `script/live_regression.py`, following `BCUClient`, `Smoke.call`, bounded polling, cleanup, and JSON style in `smoke_runtime.py:100-216`. Add `--output PATH`; atomically write the same JSON object printed to stdout. Require the installed Electron binary, copy `Electron.app` to a temporary `BCUElectronFixture.app`, add a unique inert resource, ad-hoc sign the copy with `/usr/bin/codesign --force --deep --sign -`, launch its `Contents/MacOS/Electron` with the fixture directory, and discover the exact `Popen.pid` through `/v1/list_apps` then `/v1/list_windows`. Never run npm from the harness.

Emit schema `{schemaVersion:1, startedAt, finishedAt, host:{osVersion}, fixture:{electronVersion,pid,windowID}, passed, fullyQualified, lanes:[...]}`; each lane contains `name`, `status` (`pass|fail|known_limitation|skip`), `durationMs`, `classification`, foreground PIDs, `oracle`, and `detail`. `passed` means no fail/skip; `fullyQualified` additionally requires no known limitation.

Implement strict bounded-poll lanes: three pristine reads have identical `interactionToken`; `type_text` to Composer yields exact `value:"bcu-once"`, exactly `input-events:1`, `classification == success`, and one dispatch strategy; `command+a`, `delete`, and `return` each either produce its exact selection/value/event oracle or return `effect_not_verified` and receive status `known_limitation` (never `pass`); any success without its oracle is `fail`; OCR-anchor click requires `classification == success` and `clicked:true`; scroll requires a numeric `scroll-top` increase and successful/boundary classification. Immediately before and after every action call `/v1/list_apps` and require the same unrelated foreground PID. Cleanup terminates the process group and deletes the temporary signed app.

**Verify**: `python3 -m py_compile script/live_regression.py` → exit 0; `python3 script/live_regression.py --help` documents `--output` without launching anything.

### Step 3: Tighten the existing Chrome smoke predicates and fixture oracles

In `smoke_runtime.py`, add `known_limitation(name, detail)` and include its count separately in `summary`; it never increments passes. A `verifier_ambiguous` result is invalid unless the lane name ends in `-known-limitation`, in which case record that status, not pass. Update `write_fixture` with `generation-marker` backed by `sessionStorage` and a fixed-height `scroll-region`/`scroll-marker`.

Require semantic Chrome click and OCR click to have both `classification == "success"` and the exact `Button clicked N` post-read marker. Require scroll to change the numeric marker; do not accept ambiguous dispatch. Make `reload_fixture` poll for generation increment and require a verified key result; if Chromium returns the documented opaque failure, name the lane `chrome-reload-known-limitation` and record it separately. Add pure tests in `script/test_smoke_runtime.py` for success+oracle, false success, ambiguous ordinary lane, named known limitation, unchanged scroll, and generation change.

**Verify**: `python3 -m unittest script.test_smoke_runtime` → exit 0; no ordinary lane policy accepts `verifier_ambiguous` or HTTP-only success.

### Step 4: Exercise real ad-hoc Control identity and approval decisions

In `ApprovalWindow.swift`, retain localized labels but capture each returned `NSButton` and set identifiers `bcu.approval.allow-once`, `bcu.approval.always-allow`, and `bcu.approval.deny`; set the alert window identifier to `bcu.approval.window`.

Extend `smoke_control.py` with a helper that locates buttons by the `AXIdentifier` attribute through System Events, never by title. Create three separately copied/ad-hoc-signed Electron fixture apps (a unique resource before signing gives each a distinct cdhash/policy identity). For each, find the button target through `/v1/find_elements`, issue real `/v1/click` concurrently, assert the approval window identifier appeared, then: allow-once must return action `classification == success` and flip `clicked:true`; deny must return HTTP 403 with `error == control_denied`; for the third app, launch it validly, remove/tamper its on-disk signature after the window exists, then `/v1/click` must return HTTP 403 with `error == control_identity_unresolvable`. This post-launch invalidation is required because arm64 macOS may refuse to start a never-signed Mach-O. Use fresh session IDs and terminate every copy.

**Verify**: `python3 -m py_compile script/smoke_control.py` → exit 0; source contains the four stable identifiers and no lookup for `Permitir uma vez`.

### Step 5: Test real loopback streaming and OCR executable protocols

Add `LoopbackServer.stop()` that cancels/nils the listener and clears URL/timestamp. Create serialized async `LoopbackServerIntegrationTests`: start with `RuntimeAuth(token: "integration-token")`; URLSession `/health` returns 200; `/v1/routes` without/with token returns 401/200; an `NWConnection` sends a POST header and JSON body in separate writes and receives one closed response; premature EOF returns 400; malformed header returns 400; `Content-Length: 10485761` returns 413. Parse status from the raw response and assert `Connection: close`. Do not call Router directly.

Create serialized `OCRWorkerProtocolTests`. Resolve `$PWD/.build/debug/BackgroundComputerUse` after `swift build --product BackgroundComputerUse`; fail clearly if absent. Reuse the real PNG construction pattern from `OCRWorkerTests.swift:188-232`. Launch through `BoundedProcessRunner` with `--ocr-worker`: valid encoded `OCRWorkerRequest` exits 0, decodes `OCRWorkerResponse`, reports OCR success, and preserves the interaction token in anchors; malformed stdin `not-json` exits 2, stdout is empty, and stderr is nonempty.

**Verify**: `swift test --filter 'LoopbackServerIntegrationTests|OCRWorkerProtocolTests'` → exit 0 after the product build; tests use real socket/process boundaries and no live app.

### Step 6: Extend the verification gate without hiding live evidence

In dependency-created `script/verify.sh`, preserve its deterministic default. Add `--live` that requires `BCU_LIVE_AUTHORIZED=1` and an already healthy signed runtime (never auto-install/start it), creates `${BCU_VERIFY_ARTIFACT_DIR:-.build/verification}`, and runs `live_regression.py --output ...`, `smoke_runtime.py --json`, and `smoke_control.py`, preserving each JSON output and command status. Write an aggregate JSON containing commit, timestamp, OS, each artifact path/status, `passed`, and `fullyQualified`; fail on command failure/skip, but retain `fullyQualified:false` when declared known limitations remain. Never include auth tokens.

**Verify**: `./script/verify.sh --help` → exit 0 and documents `--live`, authorization, prerequisites, artifact directory, and known-limitation semantics.

### Step 7: Run deterministic gates, then authorized live qualification once

Run the deterministic commands first. If authorized, start the signed runtime separately, install fixture dependencies, and run the aggregate LIVE command. Inspect JSON rather than accepting console prose; preserve observed known limitations.

**Verify**: `swift test && python3 -m unittest script.test_smoke_runtime` → exit 0; when authorized, `python3 -c 'import json; d=json.load(open(".build/live-regression.json")); assert d["schemaVersion"]==1 and "fullyQualified" in d and all(x["status"] in {"pass","fail","known_limitation","skip"} for x in d["lanes"])'` → exit 0.

## Test plan

- Python unit policy cases prove HTTP 200, `ok`, ambiguous classification, and DOM change are not interchangeable.
- Loopback integration covers happy/auth, split header/body, premature EOF, malformed input, oversize declaration, one response, and close.
- OCR protocol integration covers real executable valid JSON/stdin/stdout and malformed/nonzero exit.
- LIVE Electron covers deep-tree token stability, exactly-once text, key limitations, OCR click, scroll, and foreground PID preservation.
- LIVE Control covers real ad-hoc identity resolution, identifier-based dialog discovery, deny, allow-once, and unresolvable identity.
- Verification: `swift test --filter 'LoopbackServerIntegrationTests|OCRWorkerProtocolTests' && python3 -m unittest script.test_smoke_runtime` → all deterministic tests pass.

## Done criteria

- [ ] Electron package and lock pin one exact version; all three fixture source files match Step 1.
- [ ] No ordinary smoke lane passes on HTTP status/`ok` alone or accepts `verifier_ambiguous`.
- [ ] Electron type_text proves exact once-only input and every live action records before/after foreground PID.
- [ ] Known key limitations have status `known_limitation`, never `pass`; success without an oracle fails.
- [ ] Control smoke reaches Router → bridge → real code-signature resolution and asserts all three decisions by stable AX identifiers.
- [ ] Loopback and OCR integration suites pass over real socket/process boundaries.
- [ ] Default `script/verify.sh` remains non-live; `--live` writes token-free JSON evidence and distinguishes `passed` from `fullyQualified`.
- [ ] `swift test && python3 -m unittest script.test_smoke_runtime` exits 0.
- [ ] No files outside Scope are modified, apart from pre-existing baseline changes; `plans/README.md` marks plan 005 DONE.

## STOP conditions

Stop and report back (do not improvise) if:
- Plan 004’s recorded fixture/seam work or plan 002’s `script/verify.sh` is absent after dependencies are declared complete.
- The pinned Electron version cannot be installed for macOS arm64, or the launched main PID cannot be matched exactly by `list_apps`/`list_windows`.
- A proposed assertion requires DevTools, renderer IPC, foreground activation, or an unverified transport instead of BCU readback.
- Stable NSAlert identifiers are not exposed through Accessibility; do not fall back to localized button titles.
- Post-launch signature invalidation terminates the app before Router can resolve its window; report the OS/code-signing behavior rather than mocking identity.
- The operator has not explicitly authorized LIVE execution or permissions/runtime prerequisites are missing.
- A verification command fails twice after a reasonable fix attempt.

## Maintenance notes

- Update Electron deliberately with its lockfile and record the version in every live artifact; version drift invalidates comparisons.
- Treat new `verifier_ambiguous` allowances as review blockers unless their lane is explicitly named and reported as a limitation.
- Keep the fixture’s visible/ARIA markers as the oracle contract. Styling is irrelevant; exact marker text and event counts are load-bearing.
- Loopback tests own framing, while parser unit tests own syntax details; do not duplicate all parser cases through sockets.
- Live JSON may contain window metadata. Keep it in ignored `.build/verification`, redact tokens, and never commit artifacts.
