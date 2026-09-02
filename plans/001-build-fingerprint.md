# Plan 001: Make source builds prove the running runtime fingerprint

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**: `git diff --stat 0110ffb..HEAD -- Sources/BackgroundComputerUse/API/RouteRegistry.swift Sources/BackgroundComputerUse/API/Router.swift Sources/BackgroundComputerUse/App/RuntimeBootstrap.swift Sources/BackgroundComputerUse/Contracts/BootstrapContracts.swift Sources/BackgroundComputerUse/Runtime script/build_and_run.sh script/build_fingerprint.py script/test_ensure_runtime.py skills/background-computer-use/scripts/ensure-runtime.sh skills/background-computer-use/scripts/bcu-request.py openspec/changes/expose-runtime-build-fingerprint plans/README.md`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P1
- **Effort**: S
- **Risk**: LOW
- **Depends on**: none
- **Category**: dx
- **Planned at**: commit `0110ffb`, 2026-09-02

## Why this matters

A healthy loopback endpoint proves only that *some* BCU runtime is alive. Today the source helper accepts that process before looking at `BCU_SOURCE_DIR`, so an agent can change Swift source and unknowingly exercise an old installed binary. A deterministic source fingerprint carried from checkout to app bundle, health response, and manifest makes freshness machine-checkable; PID validation also turns a dead manifest into an actionable error instead of a misleading connection failure.

## Current state

- `skills/background-computer-use/scripts/ensure-runtime.sh` discovers or starts the runtime. Its healthy-process fast path precedes the source-build branch:

  ```text
  skills/background-computer-use/scripts/ensure-runtime.sh:126-131
  if current_runtime_ok; then
    BASE_URL="$(read_base_url)"
  else
    if [ -n "${BCU_SOURCE_DIR:-}" ]; then
      start_from_source "$BCU_SOURCE_DIR"
  ```

- `Sources/BackgroundComputerUse/App/RuntimeBootstrap.swift` writes the manifest, but no build identity or PID:

  ```swift
  // Sources/BackgroundComputerUse/App/RuntimeBootstrap.swift:38-47
  let manifest = RuntimeManifestDTO(
      contractVersion: ContractVersion.current,
      baseURL: baseURL.absoluteString,
      startedAt: Time.iso8601String(from: startedAt),
      auth: auth.dto,
      authToken: auth.token,
      permissions: permissions,
      instructions: instructions,
      guide: APIDocumentation.guide,
      routes: RouteRegistry.bootstrapRouteDescriptors(baseURL: baseURL)
  )
  ```

- `/health` is intentionally unauthenticated and currently returns only liveness, contract version, and request time:

  ```swift
  // Sources/BackgroundComputerUse/API/Router.swift:90-97
  case (.get, "/health"):
      return .json(
          HealthResponse(
              ok: true,
              contractVersion: ContractVersion.current,
              timestamp: Time.iso8601String(from: Date())
          )
      )
  ```

- The request helper reads `baseURL` and the credential from the manifest independently and never checks process identity:

  ```python
  # skills/background-computer-use/scripts/bcu-request.py:74-82
  def base_url() -> str:
      if os.environ.get("BCU_BASE_URL"):
          return os.environ["BCU_BASE_URL"].rstrip("/")
      path = manifest_path()
      try:
          data = json.loads(path.read_text())
          return str(data["baseURL"]).rstrip("/")
  ```

- `script/build_and_run.sh:105-125` writes the app `Info.plist` immediately before signing it. This is the least invasive injection point: add four plist keys there; do not generate or mutate Swift source during builds.
- The contract rule is explicit: “`GET /v1/routes` (RouteRegistry + APIDocumentation) é a fonte de verdade do contrato para o agente. Todo campo de request/response deve estar documentado lá e bater com o DTO real.” (`openspec/project.md:15`). Update the health response schema with its DTO.
- Swift is 6.2 in strict Swift 6 mode on macOS 14+, and tests use Swift Testing rather than XCTest (`openspec/project.md:7-9`).
- This plan assumes the post-`0110ffb` working fixes are present. For each listed path, either `git status --short` or `git diff --name-only 0110ffb..HEAD` must report it: `Router.swift`, `BackgroundComputerUseControlBridge.swift`, `CodeSignatureIdentity.swift`, `RuntimeExecutionQueue.swift`, `AdaptiveTextDispatcher.swift`, `InteractionToken.swift`, `BoundedProcessRunner.swift`, `bcu-request.py`, `InteractionTokenTests.swift`, and `RuntimeExecutionQueueTests.swift`.

## Commands you will need

| Purpose | Command | Expected on success |
|---|---|---|
| Check prerequisites | `for f in Sources/BackgroundComputerUse/API/Router.swift Sources/BackgroundComputerUse/App/BackgroundComputerUseControlBridge.swift Sources/BackgroundComputerUseControlShared/CodeSignatureIdentity.swift Sources/BackgroundComputerUse/Runtime/RuntimeExecutionQueue.swift Sources/BackgroundComputerUse/Actions/TypeText/AdaptiveTextDispatcher.swift Sources/BackgroundComputerUse/StatePipeline/InteractionToken.swift Sources/BackgroundComputerUse/Runtime/Process/BoundedProcessRunner.swift skills/background-computer-use/scripts/bcu-request.py Tests/BackgroundComputerUseTests/InteractionTokenTests.swift Tests/BackgroundComputerUseTests/RuntimeExecutionQueueTests.swift; do { git status --short -- "$f"; git diff --name-only 0110ffb..HEAD -- "$f"; } | grep -q . || echo "MISSING $f"; done` | no `MISSING` lines |
| Fingerprint tests | `python3 -m unittest script.test_ensure_runtime -v` | all tests pass; no real BCU process is launched or killed |
| Focused Swift tests | `swift test --filter RuntimeBuildIdentityTests` | all tests in the suite pass |
| Contract tests | `swift test --filter APIDocumentationTests` | all tests pass |
| OpenSpec | `openspec validate expose-runtime-build-fingerprint --strict` | exit 0 when `openspec` is installed |
| Final suite | `swift test` | exit 0; the complete suite passes |

## Scope

**In scope** (the only files you should modify):
- `script/build_fingerprint.py` (create)
- `script/build_and_run.sh`
- `Sources/BackgroundComputerUse/Contracts/BootstrapContracts.swift`
- `Sources/BackgroundComputerUse/Runtime/RuntimeBuildIdentity.swift` (create)
- `Sources/BackgroundComputerUse/API/Router.swift`
- `Sources/BackgroundComputerUse/API/RouteRegistry.swift`
- `Sources/BackgroundComputerUse/App/RuntimeBootstrap.swift`
- `skills/background-computer-use/scripts/ensure-runtime.sh`
- `skills/background-computer-use/scripts/bcu-request.py`
- `script/test_ensure_runtime.py` (create)
- `Tests/BackgroundComputerUseTests/RuntimeBuildIdentityTests.swift` (create)
- `openspec/changes/expose-runtime-build-fingerprint/proposal.md` (create)
- `openspec/changes/expose-runtime-build-fingerprint/tasks.md` (create)
- `openspec/changes/expose-runtime-build-fingerprint/specs/runtime-bootstrap/spec.md` (create)
- `plans/README.md`

**Out of scope**:
- Supervising or automatically relaunching a crashed runtime; plan 018 owns supervision.
- Release notarization, semantic app versions, or installer trust.
- Authenticating `/health`; it must remain open as documented at `Router.swift:74-78`.
- Running `script/start.sh` or installing/launching the app during implementation. Live validation requires separate operator approval.

## Git workflow

- Branch: `advisor/001-build-fingerprint`
- Commit logical units with the repository’s conventional style, for example `fix: reject stale BCU source runtimes`.
- Do not push or open a PR unless the operator instructs it.
- Preserve the prerequisite working-tree fixes; never discard or rewrite them.

## Steps

### Step 1: Record the additive runtime-bootstrap contract

Create OpenSpec change `expose-runtime-build-fingerprint`. `proposal.md` must state that health and the owner-only manifest gain build identity, PID, and process start time. `spec.md` must add these scenarios: a packaged runtime reports the exact build fingerprint in both surfaces; a source helper reuses only an exact match; a mismatch stops/rebuilds; a dead manifest PID fails before HTTP. In `tasks.md`, list the implementation and focused tests from this plan; its final checklist item must run `swift test`, strict validation, and say that signed live smoke is skipped unless the operator explicitly authorizes it.

**Verify**: `test -f openspec/changes/expose-runtime-build-fingerprint/proposal.md && test -f openspec/changes/expose-runtime-build-fingerprint/tasks.md && test -f openspec/changes/expose-runtime-build-fingerprint/specs/runtime-bootstrap/spec.md` → exit 0.

### Step 2: Add one deterministic fingerprint calculator

Create `script/build_fingerprint.py` using only Python’s standard library. It must accept `--repo PATH` and `--format json|tsv`. Resolve the 12-character commit with `git -C PATH rev-parse --short=12 HEAD`; set `dirty` from nonempty `git status --porcelain --untracked-files=all`; enumerate `git ls-files --cached --others --exclude-standard -- Sources`, sorted by repository-relative POSIX path. Hash each path, a NUL byte, its bytes, and another NUL with SHA-256. Fail if Git fails or no `Sources/` files exist.

The JSON shape is exact:

```json
{"identity":"a1b2c3d4e5f6-dirty:0000000000000000000000000000000000000000000000000000000000000000","commit":"a1b2c3d4e5f6","dirty":true,"sourcesSHA256":"0000000000000000000000000000000000000000000000000000000000000000"}
```

For a clean tree use `-clean:`. TSV prints those four values in that order, with dirty as lowercase `true`/`false`. Keep this as the only fingerprint algorithm; both shell scripts call it rather than duplicating hashing logic.

**Verify**: `python3 script/build_fingerprint.py --repo . --format json | python3 -c 'import json,sys; x=json.load(sys.stdin); assert len(x["commit"]) == 12 and len(x["sourcesSHA256"]) == 64 and x["identity"].endswith(x["sourcesSHA256"])'` → exit 0.

### Step 3: Inject the fingerprint into the signed app bundle

In `script/build_and_run.sh`, immediately after `cd "$ROOT_DIR"` and before any `swift build`, read TSV once:

```bash
IFS=$'\t' read -r BCU_BUILD_IDENTITY BCU_BUILD_COMMIT BCU_BUILD_DIRTY BCU_SOURCES_SHA256 \
  < <(python3 "$ROOT_DIR/script/build_fingerprint.py" --repo "$ROOT_DIR" --format tsv)
```

In the main app plist heredoc, add `BCUBuildIdentity`, `BCUBuildCommit`, `BCUBuildDirty`, and `BCUSourcesSHA256`. The boolean must be an XML boolean (`<$BCU_BUILD_DIRTY/>`), not a string. Do not add these keys to the Core XPC plist and do not mutate generated Swift source.

**Verify**: `BACKGROUND_COMPUTER_USE_SIGNING_IDENTITY=- ./script/build_and_run.sh build && /usr/libexec/PlistBuddy -c 'Print :BCUBuildIdentity' dist/BackgroundComputerUse.app/Contents/Info.plist && /usr/libexec/PlistBuddy -c 'Print :BCUSourcesSHA256' dist/BackgroundComputerUse.app/Contents/Info.plist` → build exits 0 and prints an identity ending in a 64-hex digest plus that digest; no app launches.

### Step 4: Model and load build identity once

Add public `RuntimeBuildIdentityDTO` to `BootstrapContracts.swift` with `identity`, `commit`, `dirty`, and `sourcesSHA256`, plus a public initializer. Create `Runtime/RuntimeBuildIdentity.swift`:

```swift
enum RuntimeBuildIdentity {
    static let current = load(from: Bundle.main.infoDictionary ?? [:])

    static func load(from info: [String: Any]) -> RuntimeBuildIdentityDTO {
        guard let identity = info["BCUBuildIdentity"] as? String,
              let commit = info["BCUBuildCommit"] as? String,
              let dirty = info["BCUBuildDirty"] as? Bool,
              let digest = info["BCUSourcesSHA256"] as? String else {
            return RuntimeBuildIdentityDTO(
                identity: "development-unknown", commit: "unknown",
                dirty: true, sourcesSHA256: "unknown"
            )
        }
        return RuntimeBuildIdentityDTO(
            identity: identity, commit: commit, dirty: dirty, sourcesSHA256: digest
        )
    }
}
```

Write `RuntimeBuildIdentityTests` with injected dictionaries for clean/dirty parsing and the missing-key fallback. Do not read the live test process bundle.

**Verify**: `swift test --filter RuntimeBuildIdentityTests` → all three cases pass.

### Step 5: Expose the same process metadata through health and manifest

Extend `HealthResponse` with `build: RuntimeBuildIdentityDTO`, `pid: Int32`, and `startedAt: String?`. Extend `RuntimeManifestDTO` with `build` and `pid`; keep its existing nonoptional `startedAt` as the process start time. In `Router.swift`, populate health from `RuntimeBuildIdentity.current`, `ProcessInfo.processInfo.processIdentifier`, and `context.startedAt.map(Time.iso8601String)`. In `RuntimeBootstrap.writeManifest`, populate the same build value and PID. Do not expose the manifest credential through health.

Update the health branch of `RouteRegistry.responseSchema` to document required `build`, `pid`, and nullable `startedAt` fields alongside the existing keys. Extend `APIDocumentationTests.healthStaysOpenWhenRuntimeAuthIsEnabled` to decode the body and assert those keys exist while `authToken` does not.

**Verify**: `swift test --filter 'RuntimeBuildIdentityTests|APIDocumentationTests'` → all selected tests pass, including unauthenticated health metadata coverage.

### Step 6: Make source discovery fail closed on a fingerprint mismatch

In `ensure-runtime.sh`, allow `APP_NAME="${BCU_APP_NAME:-BackgroundComputerUse}"` and `START_SCRIPT="${BCU_START_SCRIPT:-}"` solely so the regression test cannot touch a real process. Add `read_build_identity` for `.build.identity` in the manifest and `expected_build_identity` that runs `$BCU_SOURCE_DIR/script/build_fingerprint.py --repo "$BCU_SOURCE_DIR" --format json` and prints `.identity` via Python.

When `BCU_SOURCE_DIR` is set, `current_runtime_ok` must require both healthy `/health` and exact manifest/expected identity equality. On missing identity or mismatch, print both non-secret identities, call `stop_stale_runtime`, remove the stale manifest, and invoke `${BCU_START_SCRIPT:-$BCU_SOURCE_DIR/script/start.sh}`. Make `wait_for_runtime` use the same match predicate, so a start script cannot return an unrelated healthy process. With no `BCU_SOURCE_DIR`, retain today’s healthy installed-runtime behavior.

**Verify**: `bash -n skills/background-computer-use/scripts/ensure-runtime.sh` → exit 0.

### Step 7: Reject a dead manifest before issuing requests

Refactor `bcu-request.py` to load the manifest once when `BCU_BASE_URL` is absent. Before constructing `urllib.request.Request`, validate that `pid` is a positive non-boolean integer and call `os.kill(pid, 0)`. Treat `ProcessLookupError` as dead, `PermissionError` as alive, and malformed/missing PID as invalid manifest metadata. The failure must name the manifest path and end with: `Run skills/background-computer-use/scripts/ensure-runtime.sh to start or refresh the runtime.` Explicit `BCU_BASE_URL` remains an intentional manifest-free override.

Use signatures `load_manifest() -> tuple[Path, dict]`, `require_live_manifest_process(path: Path, data: dict) -> None`, `base_url(data: Optional[dict]) -> str`, and `auth_token(data: Optional[dict]) -> Optional[str]`. Never print the credential.

**Verify**: `python3 -m py_compile skills/background-computer-use/scripts/bcu-request.py` → exit 0.

### Step 8: Cover match, mismatch, and dead PID without touching the app

Create `script/test_ensure_runtime.py` with `unittest`. Start `ThreadingHTTPServer(("127.0.0.1", 0), Handler)` in a daemon thread; return JSON from `/health` and `/v1/bootstrap`. Use a temporary manifest containing the test process PID, fake credential, base URL, and selected `.build.identity`. Point `BCU_MANIFEST_PATH` at it, `BCU_SOURCE_DIR` at the real checkout, and `BCU_APP_NAME` at a unique impossible process name.

For the matching case, set `BCU_START_SCRIPT` to a temporary executable that creates a marker; assert ensure exits 0 and the marker does not exist. For mismatch, the fake start script must rewrite `.build.identity` to the expected value and create the marker; assert ensure exits 0 and the marker exists. A third subprocess test writes PID `999999999`, runs `bcu-request.py GET /health`, and asserts nonzero exit plus the exact ensure-runtime guidance. Always shut down and close the fake server in cleanup.

**Verify**: `python3 -m unittest script.test_ensure_runtime -v` → three tests pass; `pgrep -x BackgroundComputerUse` state is not changed by the tests.

### Step 9: Run contract gates and record completion

Run the focused tests first, then the complete Swift suite once. If `which openspec` succeeds, run strict validation; if it is absent, skip only that command and record “OpenSpec CLI unavailable” in the commit notes. Update this plan’s row in `plans/README.md` to `DONE` only after all available gates pass.

**Verify**: `swift test && python3 -m unittest script.test_ensure_runtime -v && if which openspec >/dev/null 2>&1; then openspec validate expose-runtime-build-fingerprint --strict; else echo 'OpenSpec CLI unavailable; validation skipped'; fi` → Swift and Python gates pass; OpenSpec validates when installed or prints the single documented skip.

## Test plan

- `RuntimeBuildIdentityTests.swift`: clean plist parsing, dirty plist parsing, and safe unknown fallback.
- `APIDocumentationTests.swift`: unauthenticated `/health` includes build, PID, and process start time; it never contains the manifest credential.
- `script/test_ensure_runtime.py`: matching healthy runtime is reused; mismatching healthy runtime invokes the source start path and waits for a matching manifest; dead PID fails before HTTP with exact recovery guidance.
- The fake process name and injectable start-script path are mandatory safety boundaries; no test may invoke `pkill BackgroundComputerUse`, `open`, signing, installation, or `script/start.sh`.
- Final verification: `swift test && python3 -m unittest script.test_ensure_runtime -v` → all pass.

## Done criteria

- [ ] Fingerprint is deterministic and computed by one Python implementation.
- [ ] The signed app plist, `/health`, and runtime manifest report the same four build fields.
- [ ] Health and manifest report PID; both report the server start time, with manifest retaining `startedAt`.
- [ ] `RouteRegistry` documents every added health field.
- [ ] `BCU_SOURCE_DIR` never accepts a healthy runtime with missing or mismatched build identity.
- [ ] `bcu-request.py` rejects malformed or dead manifest PIDs before network I/O and names the recovery command.
- [ ] Focused and complete tests pass without launching or killing the real app.
- [ ] No credentials appear in health, logs, errors, or committed fixtures.
- [ ] `plans/README.md` marks plan 001 `DONE`.

## STOP conditions

Stop and report back (do not improvise) if:

- Any prerequisite path listed under “Current state” is neither changed relative to `0110ffb` nor present as a working-tree change.
- The current manifest no longer uses `RuntimeManifestDTO` or health no longer routes through `HealthResponse`; another metadata design has landed.
- The packaged main app no longer gets its plist from `script/build_and_run.sh`.
- Deterministic source enumeration would require hashing ignored build output or credential-bearing files outside `Sources/`.
- A test would call the real `script/start.sh`, install an app, or signal a real `BackgroundComputerUse` process.
- A verification fails twice after a reasonable fix attempt.

## Maintenance notes

- Any new source root that contributes executable Swift outside `Sources/` must be added deliberately to the fingerprint algorithm and its tests; never hash `.build/` or `dist/`.
- Reviewers should verify the plist boolean is a real boolean, the digest includes relative paths as well as bytes, and shell/Python compute exactly the same identity by calling one helper.
- PID plus start time identifies this runtime instance; crash supervision and manifest removal remain plan 018’s responsibility.
- The build fingerprint is provenance, not authentication. It must not weaken code-signing or Control peer-identity checks.
