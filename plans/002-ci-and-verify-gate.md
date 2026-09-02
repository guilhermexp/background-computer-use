# Plan 002: Establish one reproducible unsigned CI and local verification gate

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**: `git diff --stat 0110ffb..HEAD -- .github/workflows/ci.yml .gitignore script/verify.sh Tests/BackgroundComputerUseTests/AXPointPressEligibilityTests.swift Tests/BackgroundComputerUseTests/ActivityControlTests.swift Sources/BackgroundComputerUse/Actions/Click/RendererAccessibilityBootstrap.swift docs/parity-completion-audit.md plans/README.md`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status
- **Priority**: P1
- **Effort**: S/M
- **Risk**: LOW
- **Depends on**: none
- **Category**: dx
- **Planned at**: commit `0110ffb`, 2026-09-02

## Why this matters
The package has a substantial green test suite but no hosted gate, so compile failures, Swift 6 concurrency regressions, and Python policy-test failures can merge unnoticed. Local verification is also described as historical prose rather than emitted as one correlated artifact. A single unsigned gate used both locally and by CI removes command drift, while deterministic concurrency assertions keep scheduler speed from deciding whether authoritative tests pass.

## Current state
- The package requires Swift 6.2, macOS 14, and a test-only `swift-testing` revision:

  ```swift
  // Package.swift:1-6,19-23
  // swift-tools-version: 6.2
  let package = Package(
      name: "BackgroundComputerUse",
      platforms: [.macOS(.v14)],
      dependencies: [
          .package(
              url: "https://github.com/swiftlang/swift-testing.git",
              revision: "swift-6.2.3-RELEASE"
  ```

- There is currently no `.github/workflows/` directory. The ordinary SwiftPM test target is declared at `Package.swift:85-98`; signing and app installation are not part of `swift test`.
- These three pure-Python unittest modules exist and are safe for CI: `script/test_smoke_runtime.py`, `script/test_smoke_control.py`, and `script/test_benchmark_mac_parity.py`.
- One test treats a 50 ms wall-clock threshold as proof that dispatch is asynchronous:

  ```swift
  // Tests/BackgroundComputerUseTests/AXPointPressEligibilityTests.swift:50-61
  @Test
  func rendererBootstrapWorkerDispatchDoesNotBlockTheCaller() {
      let finished = DispatchSemaphore(value: 0)
      let startedAt = Date()
      RendererAccessibilityBootstrap.dispatchWorker {
          Thread.sleep(forTimeInterval: 0.15)
          finished.signal()
      }
      #expect(Date().timeIntervalSince(startedAt) < 0.05)
      #expect(finished.wait(timeout: .now() + 1) == .success)
  }
  ```

- The dispatch seam is only a hard-coded global queue today:

  ```swift
  // Sources/BackgroundComputerUse/Actions/Click/RendererAccessibilityBootstrap.swift:38-40
  static func dispatchWorker(_ work: @escaping @Sendable () -> Void) {
      DispatchQueue.global(qos: .userInitiated).async(execute: work)
  }
  ```

- Another unit test measures a lock-protected in-memory insert against a 150 ms budget:

  ```swift
  // Tests/BackgroundComputerUseTests/ActivityControlTests.swift:168-171
  @Test
  func synchronousActivityPublicationFitsUpdateBudget() {
      let history = ActivityHistoryStore(capacity: 10)
      let started = ContinuousClock.now
  // Tests/BackgroundComputerUseTests/ActivityControlTests.swift:183-184
  let elapsed = started.duration(to: .now)
  #expect(elapsed < .milliseconds(150))
  ```

- The store is synchronous and lock-bounded (`ActivityHistoryStore.swift:13-22`): it inserts, enforces capacity, updates a screenshot index, and unlocks. Its observable contract is ordering/visibility, not a machine-dependent microbenchmark.
- `docs/parity-completion-audit.md:23-37` records one historical run, including “382 tests”; the known current baseline is 391 tests. The count will grow as other plans add tests, so the gate artifact—not prose—must become authoritative.
- Project tests use Swift Testing (`import Testing`, `@Suite`, `@Test`, `#expect`), never XCTest (`openspec/project.md:7-9`). Signed/live smoke requires a running installed app, Chrome, and macOS permissions (`openspec/project.md:37-42`) and must remain opt-in.
- This plan assumes all post-`0110ffb` working fixes named in plan 001 are present; use the prerequisite command below and stop on any `MISSING` line.

## Commands you will need

| Purpose | Command | Expected on success |
|---|---|---|
| Check prerequisites | `for f in Sources/BackgroundComputerUse/API/Router.swift Sources/BackgroundComputerUse/App/BackgroundComputerUseControlBridge.swift Sources/BackgroundComputerUseControlShared/CodeSignatureIdentity.swift Sources/BackgroundComputerUse/Runtime/RuntimeExecutionQueue.swift Sources/BackgroundComputerUse/Actions/TypeText/AdaptiveTextDispatcher.swift Sources/BackgroundComputerUse/StatePipeline/InteractionToken.swift Sources/BackgroundComputerUse/Runtime/Process/BoundedProcessRunner.swift skills/background-computer-use/scripts/bcu-request.py Tests/BackgroundComputerUseTests/InteractionTokenTests.swift Tests/BackgroundComputerUseTests/RuntimeExecutionQueueTests.swift; do { git status --short -- "$f"; git diff --name-only 0110ffb..HEAD -- "$f"; } | grep -q . || echo "MISSING $f"; done` | no `MISSING` lines |
| Focused worker test | `swift test --filter AXPointPressEligibilityTests` | all tests pass without timing comparisons |
| Focused activity test | `swift test --filter ActivityControlTests` | all tests pass without timing comparisons |
| Python lane | `python3 -m unittest script.test_smoke_runtime script.test_smoke_control script.test_benchmark_mac_parity` | all tests pass |
| Local gate | `./script/verify.sh` | exit 0 and writes `verify-result.json` with overall `pass` |
| JSON validation | `python3 -m json.tool verify-result.json >/dev/null` | exit 0 |

## Scope

**In scope** (the only files you should modify):
- `.github/workflows/ci.yml` (create)
- `script/verify.sh` (create)
- `.gitignore`
- `Sources/BackgroundComputerUse/Actions/Click/RendererAccessibilityBootstrap.swift`
- `Tests/BackgroundComputerUseTests/AXPointPressEligibilityTests.swift`
- `Tests/BackgroundComputerUseTests/ActivityControlTests.swift`
- `docs/parity-completion-audit.md` (only the “Current gates” evidence)
- `plans/README.md`

**Out of scope**:
- Code signing, installation, notarization, locked-use qualification, and permission-dependent UI tests in CI.
- Running `script/start.sh`, `script/smoke_runtime.py`, or `script/smoke_control.py` unless a human explicitly invokes `./script/verify.sh --live` on a prepared Mac.
- Linux CI; runtime production code imports macOS frameworks.
- Adding a formatter, linter, coverage service, or third-party shell/JSON dependency.
- Changing production performance budgets; live benchmark plans own those measurements.

## Git workflow

- Branch: `advisor/002-ci-and-verify-gate`
- Use conventional messages matching history, for example `ci: add unsigned macOS verification gate` and `test: remove wall-clock concurrency assertions`.
- Do not push or open a PR unless instructed.
- Preserve all prerequisite working-tree changes.

## Steps

### Step 1: Pin a hosted Swift 6.2 toolchain deliberately

Before writing YAML, inspect the `macos-15` software manifest in the official `actions/runner-images` repository and confirm `/Applications/Xcode_26.3.app` is listed and includes Apple Swift 6.2.3. Pin both `runs-on: macos-15` and that exact Xcode path. Do not select “latest” inside the job. If the manifest has advanced and removed 26.3, stop under the toolchain STOP condition rather than silently choosing another compiler.

The workflow’s toolchain step must run:

```bash
sudo xcode-select -s /Applications/Xcode_26.3.app/Contents/Developer
swift --version
echo "$(swift --version)" | grep -F "Apple Swift version 6.2.3"
```

**Verify**: `curl -fsSL https://raw.githubusercontent.com/actions/runner-images/main/images/macos/macos-15-Readme.md | grep -F 'Xcode_26.3.app'` → prints the pinned Xcode entry from the official runner manifest.

### Step 2: Replace the asynchronous-dispatch stopwatch with an injectable scheduler

Change `RendererAccessibilityBootstrap.dispatchWorker` to preserve its production call while accepting a deterministic scheduler seam:

```swift
typealias WorkerEnqueue = @Sendable (@escaping @Sendable () -> Void) -> Void

static func dispatchWorker(
    _ work: @escaping @Sendable () -> Void,
    enqueue: WorkerEnqueue = { work in
        DispatchQueue.global(qos: .userInitiated).async(execute: work)
    }
) {
    enqueue(work)
}
```

Replace `rendererBootstrapWorkerDispatchDoesNotBlockTheCaller` with a `WorkerDispatchProbe: @unchecked Sendable` test helper protected by `NSLock`. The injected `enqueue` captures (but does not run) the closure. Assert in order: `dispatchWorker` returns; the work has been captured; `ran == false`; manually run the captured work; `ran == true`. This proves enqueue-not-inline behavior with no `Date`, `Thread.sleep`, or elapsed threshold. The production call at `RendererAccessibilityBootstrap.swift:118` remains unchanged.

**Verify**: `swift test --filter AXPointPressEligibilityTests && ! grep -n 'startedAt\|forTimeInterval\|timeIntervalSince' Tests/BackgroundComputerUseTests/AXPointPressEligibilityTests.swift` → tests pass and the removed stopwatch/sleep names produce no matches.

### Step 3: Replace the activity microbenchmark with observable ordering

Delete `synchronousActivityPublicationFitsUpdateBudget`. Add this deterministic contract test using the suite’s existing `makeActivity(id:windowID:)` helper:

```swift
@Test
func appendPublishesSynchronouslyBeforeReturning() {
    let history = ActivityHistoryStore(capacity: 2)

    history.append(makeActivity(id: "one", windowID: "window-a"))
    #expect(history.activities().map(\.id) == ["one"])

    history.append(makeActivity(id: "two", windowID: "window-a"))
    #expect(history.activities().map(\.id) == ["two", "one"])
}
```

The first expectation establishes visibility before the next mutation; the second establishes newest-first ordering. Do not add a clock to production code merely to retain a unit-level speed budget.

**Verify**: `swift test --filter ActivityControlTests && ! grep -n 'ContinuousClock\|milliseconds(150)' Tests/BackgroundComputerUseTests/ActivityControlTests.swift` → tests pass and the removed timing assertion produces no matches.

### Step 4: Create the single local gate and machine-readable result

Create executable `script/verify.sh` with `set -uo pipefail` (intentionally not `-e`, because every lane must run and be recorded). Accept only no argument or `--live`; unknown arguments print `usage: ./script/verify.sh [--live]` and exit 2. Resolve repo root from the script directory, `cd` there, and record:

- `commit`: `git rev-parse --short=12 HEAD`
- `dirty`: whether `git status --porcelain --untracked-files=all` is nonempty
- `swiftVersion`: the complete `swift --version` output joined to one line
- `macOSVersion`: `sw_vers -productVersion`
- `live`: boolean
- `lanes`: objects `{name,status,exitCode}`
- `overall`: `pass` only when every lane passed

Use one `run_lane NAME COMMAND_AND_ARGUMENTS` shell function that executes the command, appends tab-separated name/status/exit code to a `mktemp` file, and sets `overall_exit=1` on failure. Run exactly these default lanes:

```bash
run_lane swift-build swift build
run_lane swift-test swift test
run_lane python-unit python3 -m unittest \
  script.test_smoke_runtime script.test_smoke_control script.test_benchmark_mac_parity
```

When `--live` is explicitly present, print a warning that the operator is authorizing signing, installation, app launch, Chrome interaction, and permission-dependent checks, then append `live-start` (`./script/start.sh`), `live-runtime-smoke` (`python3 script/smoke_runtime.py`), and `live-control-smoke` (`python3 script/smoke_control.py`). Default mode must never invoke them.

At the end, use an inline standard-library Python program to convert the TSV and metadata arguments to JSON, write a temporary JSON file, then atomically `mv` it to repository-root `verify-result.json`. Exit with `overall_exit`. Add `/verify-result.json` to `.gitignore`.

**Verify**: `bash -n script/verify.sh && chmod +x script/verify.sh && test -x script/verify.sh` → exit 0.

### Step 5: Add CI that calls the same gate

Create `.github/workflows/ci.yml` with this shape:

```yaml
name: CI
on:
  pull_request:
  push:
    branches: [main]
permissions:
  contents: read
jobs:
  verify:
    runs-on: macos-15
    timeout-minutes: 30
    steps:
      - uses: actions/checkout@v4
      - name: Select Swift 6.2.3 toolchain
        run: |
          sudo xcode-select -s /Applications/Xcode_26.3.app/Contents/Developer
          swift --version
          echo "$(swift --version)" | grep -F "Apple Swift version 6.2.3"
      - id: toolchain
        name: Fingerprint toolchain
        run: echo "hash=$(swift --version | shasum -a 256 | cut -d ' ' -f 1)" >> "$GITHUB_OUTPUT"
      - uses: actions/cache@v4
        with:
          path: .build
          key: ${{ runner.os }}-${{ runner.arch }}-swift-${{ steps.toolchain.outputs.hash }}-${{ hashFiles('Package.resolved') }}
      - name: Build and test
        run: ./script/verify.sh
      - name: Upload verification result
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: verify-result
          path: verify-result.json
          if-no-files-found: error
```

Do not put `--live` in YAML. Calling the local gate is what guarantees CI runs `swift build`, `swift test`, and all three Python modules without duplicating the command list.

**Verify**: `grep -F './script/verify.sh' .github/workflows/ci.yml && ! grep -F -- '--live' .github/workflows/ci.yml` → prints the gate line and exits 0.

### Step 6: Replace historical gate prose with the reproducible gate

In `docs/parity-completion-audit.md` under `## Current gates`, replace the stale “382 tests” bullet and formatter/retry prose that pretends to be a current gate with a short statement: the baseline before this plan was 391 passing Swift tests; `./script/verify.sh` is now authoritative for unsigned build, full Swift tests, and the three Python policy modules; `verify-result.json` binds results to commit/dirty/toolchain/macOS. Keep the existing signed-smoke and live-evidence bullets, explicitly labeling them manual point-in-time evidence outside CI. Do not alter the R1–R13 claims or qualifications.

**Verify**: `grep -F './script/verify.sh' docs/parity-completion-audit.md && ! grep -F '382 tests' docs/parity-completion-audit.md` → prints the gate reference and exits 0.

### Step 7: Exercise the local gate and finish

Run `./script/verify.sh` once; do not use `--live`. Inspect the JSON with `python3 -m json.tool`, assert all default lane statuses and overall are `pass`, and update plan 002’s row in `plans/README.md` to `DONE`.

**Verify**: `./script/verify.sh && python3 -c 'import json; x=json.load(open("verify-result.json")); assert x["overall"] == "pass" and x["live"] is False; assert {v["name"]: v["status"] for v in x["lanes"]} == {"swift-build":"pass","swift-test":"pass","python-unit":"pass"}'` → exit 0.

## Test plan

- `AXPointPressEligibilityTests`: injected enqueue captures work and proves it was not executed inline; no sleep or elapsed-time threshold.
- `ActivityControlTests`: append visibility and newest-first ordering are asserted at deterministic sequence points; performance measurement moves out of unit tests.
- `script/verify.sh`: default runs all three unsigned lanes and emits valid JSON even when a lane fails; unknown flags exit 2; `--live` is the only path to signed smoke.
- `.github/workflows/ci.yml`: same gate, pinned Swift 6.2.3 toolchain, `.build` cache keyed by lockfile plus toolchain, result artifact uploaded even on failure.
- Final verification: `./script/verify.sh` → all default lanes pass and JSON matches the exact schema above.

## Done criteria

- [ ] macOS CI is pinned to an available Xcode with Apple Swift 6.2.3.
- [ ] CI calls the same `script/verify.sh` developers run locally.
- [ ] `.build` cache key changes with `Package.resolved` or Swift toolchain.
- [ ] `verify-result.json` records commit, dirty state, Swift/macOS versions, each lane, and overall status.
- [ ] Default verification never signs, installs, launches, or drives GUI apps.
- [ ] Live smoke is available only via explicit `--live` and absent from CI.
- [ ] Both authoritative timing assertions are replaced by deterministic ordering/scheduling assertions.
- [ ] Parity audit names the gate and no longer reports 382 as current.
- [ ] `plans/README.md` marks plan 002 `DONE`.

## STOP conditions

Stop and report back (do not improvise) if:
- Any required post-`0110ffb` working fix is missing.
- The official `macos-15` runner manifest does not contain `Xcode_26.3.app` with Apple Swift 6.2.3. Report the available 6.2.x paths; do not silently change the planned compiler.
- Any of the three named Python test modules is missing or starts requiring a live app.
- `swift test` begins invoking signing, installation, or permission-dependent UI automation.
- Deterministic testing appears to require adding sleeps, widening timeouts, or adding a production clock used only by tests.
- A verification fails twice after a reasonable fix attempt.

## Maintenance notes

- When updating Xcode, change the pinned path and expected Swift version together; the cache key will isolate the new toolchain automatically. Add future pure policy-test modules to `script/verify.sh`, not directly to CI.
- Never add `--live` to PR CI; a prepared, authorized Mac is separate. Test-count prose is informational only; `verify-result.json` is authoritative.
