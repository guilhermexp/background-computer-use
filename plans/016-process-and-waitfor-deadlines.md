# Plan 016: Make process and wait-for deadlines bound the complete operation

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**: `git diff --stat 0110ffb..HEAD -- Sources/BackgroundComputerUse/Runtime/Process/BoundedProcessRunner.swift Sources/BackgroundComputerUse/Actions/WaitFor/WaitForRouteService.swift Sources/BackgroundComputerUse/API/RouteRegistry.swift Tests/BackgroundComputerUseTests/BoundedProcessRunnerTests.swift Tests/BackgroundComputerUseTests/WaitForDeadlineTests.swift Tests/BackgroundComputerUseTests/AgentAPICorrectnessTests.swift openspec/changes/bound-complete-operation-deadlines plans/README.md`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P1
- **Effort**: M
- **Risk**: MED
- **Depends on**: none
- **Category**: bug
- **Planned at**: commit `0110ffb`, 2026-09-02

## Why this matters

`BoundedProcessRunner` stops applying its timeout as soon as the direct child exits, then waits forever if a detached descendant retains a pipe. Both OCR and `run_script` depend on this runner, so one escaped descriptor can wedge an execution lane permanently. Separately, `wait_for` lets full captures and sleeps overrun its advertised timeout and always performs another capture afterward. This plan makes each deadline cover all service-controlled work while preserving the last useful state instead of recapturing without a bound.

## Current state

- `Sources/BackgroundComputerUse/Runtime/Process/BoundedProcessRunner.swift` is already a low-level `posix_spawn` runner; preserve its current hardening.
  - `BoundedProcessRunner.swift:91-110`: file actions map only stdin/stdout/stderr and spawn flags include `POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_CLOEXEC_DEFAULT`.
  - `BoundedProcessRunner.swift:153-161`: stdout/stderr readers and stdin writer participate in one `DispatchGroup`.
  - `BoundedProcessRunner.swift:163-195`: monotonic timeout enforcement ends when `waitpid` reports the direct child exited.
  - `BoundedProcessRunner.swift:198`: the subsequent `ioGroup.wait()` has no deadline.
  - `BoundedProcessRunner.swift:222-257`: pipe I/O already uses dedicated `Thread.detachNewThread` workers, not the shared GCD pool; retain that design.
  - `BoundedProcessRunner.swift:260-289`: timeout already signals the process group plus observed descendants and verifies termination.
- `Tests/BackgroundComputerUseTests/BoundedProcessRunnerTests.swift:27-53` covers a `setsid` descendant only while the shell waits for that child; it does not cover the direct child exiting while the descendant keeps stdout open.
- `Sources/BackgroundComputerUse/Actions/WaitFor/WaitForRouteService.swift` has no injected clock or capture seam today; its only initializer takes `ActionExecutionOptions` (`WaitForRouteService.swift:19-24`).
  - `WaitForRouteService.swift:46-52`: timeout and interval are clamped, then a wall-clock `Date` deadline is computed.
  - `WaitForRouteService.swift:58-97`: each poll performs an unbudgeted full AX capture and sleeps the full interval when still before the deadline.
  - `WaitForRouteService.swift:99-122`: after polling, one more full capture runs unconditionally unless the window closed.
  - `WaitForRouteService.swift:123-151`: elapsed time uses `Date`, and notes promise the returned state came from the final capture.
- `Sources/BackgroundComputerUse/API/RouteRegistry.swift:244-263` describes `wait_for` as returning fresh state and says intermediate polls omit screenshots.
- `RouteRegistry.swift:561-577` says `imageMode` controls the returned final state, but gives no timeout/final-capture bound.
- Existing window-close policy is unit tested through `WaitForRouteService.closedWindowOutcome` in `AgentAPICorrectnessTests.swift:112-132`; preserve it.
- Project conventions from `openspec/project.md:7-15`: Swift 6.2 strict concurrency, macOS 14, Swift Testing, and `GET /v1/routes` is the contract source of truth.

## Commands you will need

| Purpose | Command | Expected on success |
|---|---|---|
| Prerequisite check | `git status --short -- Sources/BackgroundComputerUse/API/Router.swift Sources/BackgroundComputerUse/App/BackgroundComputerUseControlBridge.swift Sources/BackgroundComputerUseControlShared/CodeSignatureIdentity.swift Sources/BackgroundComputerUse/Runtime/RuntimeExecutionQueue.swift Sources/BackgroundComputerUse/Actions/TypeText/AdaptiveTextDispatcher.swift Sources/BackgroundComputerUse/StatePipeline/InteractionToken.swift Sources/BackgroundComputerUse/Runtime/Process/BoundedProcessRunner.swift skills/background-computer-use/scripts/bcu-request.py Tests/BackgroundComputerUseTests/InteractionTokenTests.swift Tests/BackgroundComputerUseTests/RuntimeExecutionQueueTests.swift && git diff --name-only 0110ffb..HEAD -- Sources/BackgroundComputerUse/API/Router.swift Sources/BackgroundComputerUse/App/BackgroundComputerUseControlBridge.swift Sources/BackgroundComputerUseControlShared/CodeSignatureIdentity.swift Sources/BackgroundComputerUse/Runtime/RuntimeExecutionQueue.swift Sources/BackgroundComputerUse/Actions/TypeText/AdaptiveTextDispatcher.swift Sources/BackgroundComputerUse/StatePipeline/InteractionToken.swift Sources/BackgroundComputerUse/Runtime/Process/BoundedProcessRunner.swift skills/background-computer-use/scripts/bcu-request.py Tests/BackgroundComputerUseTests/InteractionTokenTests.swift Tests/BackgroundComputerUseTests/RuntimeExecutionQueueTests.swift` | every listed prerequisite appears in at least one output; otherwise STOP |
| Runner tests | `swift test --filter BoundedProcessRunnerTests` | all tests pass |
| Wait tests | `swift test --filter WaitForDeadlineTests` | all tests pass |
| Existing wait policy | `swift test --filter AgentAPICorrectnessTests` | all tests pass |
| Full verification | `swift test` | all tests pass; baseline is 391 tests before this plan |
| OpenSpec availability | `which openspec` | prints a path, or exits nonzero and validation is skipped/noted |

## Scope

**In scope** (the only files you should modify):
- `Sources/BackgroundComputerUse/Runtime/Process/BoundedProcessRunner.swift`
- `Sources/BackgroundComputerUse/Actions/WaitFor/WaitForRouteService.swift`
- `Sources/BackgroundComputerUse/API/RouteRegistry.swift`
- `Tests/BackgroundComputerUseTests/BoundedProcessRunnerTests.swift`
- `Tests/BackgroundComputerUseTests/WaitForDeadlineTests.swift` (create)
- `Tests/BackgroundComputerUseTests/AgentAPICorrectnessTests.swift` only if an existing window-close assertion must be adjusted without weakening it
- `openspec/changes/bound-complete-operation-deadlines/proposal.md` (create)
- `openspec/changes/bound-complete-operation-deadlines/tasks.md` (create)
- `openspec/changes/bound-complete-operation-deadlines/specs/wait-for/spec.md` (create)
- `plans/README.md` (status row only)

**Out of scope** (do NOT touch, even though related):
- OCR worker protocol, `run_script` request/response fields, or process output byte limits.
- Replacing `posix_spawn`, removing process groups, removing `POSIX_SPAWN_CLOEXEC_DEFAULT`, or moving pipe I/O back to GCD.
- Changing `wait_for` match semantics, its 60-second public cap, or window-close/gone behavior.
- Adding cancellation to the entire AX state pipeline or changing action-route verification waits.
- Live app launch, signed installation, or smoke scripts.

## Git workflow

- Branch: `advisor/016-process-and-waitfor-deadlines`
- Preserve all prerequisite working-tree changes, especially the current dedicated-thread/CLOEXEC changes in `BoundedProcessRunner.swift`.
- Use observed conventional-style commits such as `fix: enforce process deadlines through pipe drain` and `fix: bound wait-for final capture`.
- Do NOT push or open a PR unless the operator instructed it.

## Steps

### Step 1: Specify complete-operation timeout semantics

Create the listed OpenSpec change. Define that `wait_for.timeoutSeconds` bounds polling, poll sleeps, and polling captures; a timeout returns the last completed poll rather than performing an unbounded recapture. Define a maximum 250 ms final-image allowance when `imageMode != omit`: exactly one capture attempt may use it, and failure/deadline returns the last poll with a note that the requested image could not be completed. Define that subprocess timeout applies until the root is reaped and all parent pipe workers finish, even if descendants inherit descriptors.

Use the exact OpenSpec structure in `openspec/project.md:25-29`. The final task must include focused tests, `swift test`, strict validation, and the repository-required live smoke entry. Mark the live smoke skipped unless the operator separately authorizes launching the signed app; this plan itself does not authorize it.

**Verify**: `openspec validate bound-complete-operation-deadlines --strict` if available; otherwise note the missing CLI → exits 0 or absence is explicitly recorded.

### Step 2: Give each pipe worker cancellation-safe descriptor ownership

Replace `FileHandle(fileDescriptor:closeOnDealloc: true)` with a dedicated `CancellablePipeWorker` for stdout, stderr, and stdin. Create a separate parent-only cancellation pipe for each worker after `posix_spawn`, so descendants cannot inherit it. The worker uses `Darwin.poll` on its data descriptor plus cancellation-read descriptor; timeout cancellation writes one byte to the cancellation-write descriptor. The worker—not the timeout thread—is the only code that calls `Darwin.close` on its data descriptor, in `defer` before `group.leave()`.

Target shape:

```swift
private final class CancellablePipeWorker: @unchecked Sendable {
    let dataDescriptor: Int32
    private let cancelRead: Int32
    private let cancelWrite: Int32
    private let lock = NSLock()
    private var cancelled = false
    private var finished = false

    func cancel() {
        lock.withLock {
            guard !cancelled, !finished else { return }
            cancelled = true
            var byte: UInt8 = 1
            _ = Darwin.write(cancelWrite, &byte, 1)
        }
    }
}
```

In the read loop, `poll` indefinitely, return immediately when `cancelRead` is readable, otherwise call `Darwin.read` only when the data FD reports `POLLIN|POLLHUP`. Because one worker exclusively owns and closes the data FD, no timeout thread can close it between a numeric-FD check and `read`; this avoids reuse of that number for an unrelated file. Apply the same poll/cancel ownership to a potentially blocked stdin write. Worker teardown must set `finished` and close both cancellation descriptors while holding `lock`, then close its data descriptor outside the lock; `cancel()` holds the same lock through its one-byte wake write, so it cannot write to a reused cancellation FD after normal completion. Mark the original `parentDescriptors` entries invalid as soon as ownership transfers. Preserve dedicated threads and the 1 MiB truncation behavior.

**Verify**: `swift test --filter BoundedProcessRunnerTests` → existing stdin/stdout/stderr and truncation tests pass.

### Step 3: Enforce the deadline until root reap and I/O completion

Track `rootReaped` separately from `ioFinished`. Continue the monotonic loop until both are true. Before root reap, keep collecting descendant PIDs and call nonblocking `waitpid`; after root reap, continue checking `ioGroup.wait(timeout: .now())` without calling `waitpid` again.

At the first deadline expiry: set `timedOut`; signal the process group and every previously observed descendant even when the root was already reaped; call `cancel()` on stdout, stderr, and stdin workers; reap the root if needed; and run the existing bounded process-tree verification. Cancellation wakes each `poll`, and each worker immediately closes its owned `output.read`, `errorOutput.read`, or `input.write` descriptor before leaving the group. Replace the final unbounded `ioGroup.wait()` with a bounded drain grace of 250 ms. If that grace expires, return status 124 with captured bytes and `timedOut == true`; never block indefinitely and never access unsynchronized buffer storage.

Target loop shape (the timeout branch is the only exit that does not require `ioFinished`):

```swift
while true {
    // collect descendants and waitpid(WNOHANG) only until rootReaped
    let ioFinished = ioGroup.wait(timeout: .now()) == .success
    if rootReaped && ioFinished { break }

    if DispatchTime.now().uptimeNanoseconds >= deadline {
        timedOut = true
        signalProcessTree(processID, descendants: observedDescendants)
        stdoutReader.cancel()
        stderrReader.cancel()
        stdinWriter.cancel()
        // reap root if needed; run the existing bounded tree verification
        _ = ioGroup.wait(timeout: .now() + .milliseconds(250))
        break
    }
    usleep(10_000)
}
```

Preserve result status 124 for a deadline, even if the direct child had already exited 0. Duration must include bounded drain/termination work.

**Verify**: `swift test --filter BoundedProcessRunnerTests` → all existing tests pass and no invocation hangs.

### Step 4: Reproduce the detached inherited-pipe regression

Extend `BoundedProcessRunnerTests` after `killsASetSidDescendantOnTimeout`. Build the shell string exactly as `"/usr/bin/perl -MPOSIX -e 'POSIX::setsid(); sleep 30' & child=$!; echo $child > '\(pidFile.path)'; exit 0"` after creating the same unique `pidFile` URL pattern used by the existing test. Run it via `/bin/sh -c`. The shell must exit immediately while the detached Perl process inherits stdout/stderr. Use `timeoutMs: 500`, measure monotonic elapsed time, and assert: result returns in less than 1.5 seconds; `timedOut == true`; status is 124; the PID file exists; and `kill(childPID, 0)` reports `ESRCH`. Clean the unique temp directory in `defer`.

This differs intentionally from the existing test, whose shell executes `wait $child` and therefore never exercises post-root pipe drain.

**Verify**: `swift test --filter BoundedProcessRunnerTests` → the new regression test fails on the old unbounded wait and passes on the fixed runner.

### Step 5: Add monotonic wait-for dependencies and a generic polling engine

In `WaitForRouteService.swift`, add internal dependencies for monotonic `now`, sleeping, and capture. Keep the public/default initializer unchanged. Put scheduling in a generic internal `WaitForPollingEngine<State>` so deadline tests can use tiny fake states instead of constructing `AXActionStateCapture`.

Use this shape:

```swift
struct WaitForClock {
    let nowNanoseconds: () -> UInt64
    let sleep: (TimeInterval) -> Void
}

enum WaitForCaptureResult<State> {
    case captured(State)
    case windowClosed(String)
    case deadlineExceeded
}

// capture receives image mode and remaining seconds.
typealias WaitForCapture<State> = (ImageMode, TimeInterval) throws -> WaitForCaptureResult<State>
```

Production `now` is `DispatchTime.now().uptimeNanoseconds`; production sleep is `sleepRunLoop`. The engine clamps each sleep to `min(pollInterval, remaining)`, never starts a poll with zero remaining, stores every completed state as `lastCapture`, and returns that state at timeout for `.omit`.

**Verify**: `swift test --filter WaitForDeadlineTests` → the new test target compiles with fake generic states; test bodies are completed in Step 7.

### Step 6: Bound each synchronous capture attempt

Add a private `WaitForCaptureOperation: @unchecked Sendable` that owns the non-Sendable capture closure, lock-protected `Result<AXActionStateCapture, Error>?`, and a semaphore. Start it on one dedicated thread and wait only for the passed remaining budget. Capturing the operation box—not the AX resolver directly—in the `@Sendable` thread closure keeps Swift 6 concurrency checking explicit. A timed-out operation may finish in its retained box, but the route must start no further poll captures after one deadline expiry.

For a condition met before the main deadline, use the remaining main budget for the requested final image. For a timeout: return `lastCapture` immediately when `imageMode == .omit`; otherwise make exactly one final capture with `min(0.25, configuredFinalImageAllowance)` and return it only if completed. If it misses the allowance, return `lastCapture` and append a stable note that the requested final image exceeded the bounded allowance. If the very first capture misses the whole timeout and there is no last state, throw a new `WaitForRouteError.captureDeadlineExceededBeforeInitialState` instead of fabricating a response.

Keep `DiscoveryError.windowNotFound` handling and `closedWindowOutcome` behavior unchanged. Compute response `elapsedMs` from the monotonic clock. Do not use `Date` for deadline decisions.

**Verify**: `swift test --filter AgentAPICorrectnessTests` → existing gone/window-close tests pass unchanged.

### Step 7: Prove wait-for scheduling with injected time and capture

Create `WaitForDeadlineTests.swift` using Swift Testing and a fake nanosecond clock. The fake sleep advances time by exactly its argument; the fake capture records its mode/budget and advances by a configured duration. Add these cases:

1. a 1.0-second timeout with 400 ms polls sleeps only the final remainder, returns the last fake state, and finishes at or before 1.0 seconds for `omit`;
2. an unmatched `base64` wait makes one final capture attempt capped at 250 ms and total fake elapsed is at most 1.25 seconds;
3. a final capture that reports `.deadlineExceeded` returns the last poll and the “final image exceeded allowance” note decision;
4. a condition matched before expiry uses the remaining main budget, performs no extra sleep, and returns the matched/final state;
5. a first capture deadline with no completed state produces the explicit error rather than a force unwrap or synthetic state.

Assert exact capture counts and every budget passed to the capture closure, not just elapsed time.

**Verify**: `swift test --filter WaitForDeadlineTests` → 5 tests pass without Accessibility or Screen Recording permissions.

### Step 8: Update route self-documentation and run the final gate

Change `RouteRegistry.swift:249-263` and the `imageMode` field description at lines 572-576 to state the last-poll/final-image rules and 250 ms allowance. Remove the unconditional promise of “one fresh final state.” Run the focused tests, then the full suite once. Update only plan 016's status row.

**Verify**: `swift test --filter BoundedProcessRunnerTests && swift test --filter WaitForDeadlineTests && swift test` → all tests pass and the process regression completes rather than hanging.

## Test plan

- Extend `BoundedProcessRunnerTests` with the direct-child-exits/detached-descendant-inherits-pipe case, modeled after `killsASetSidDescendantOnTimeout` at lines 27-53.
- Create `WaitForDeadlineTests` around the generic engine's fake clock/capture; no real AX objects, app launch, or wall-clock sleeps.
- Preserve `AgentAPICorrectnessTests` window-close assertions.
- Verification: `swift test --filter BoundedProcessRunnerTests && swift test --filter WaitForDeadlineTests && swift test --filter AgentAPICorrectnessTests` → all focused suites pass.

## Done criteria

- [ ] The runner does not return normally until root reap and I/O EOF, except for its explicit bounded timeout drain path.
- [ ] A detached descendant retaining stdout cannot keep `run` blocked beyond timeout plus bounded termination/drain grace.
- [ ] Pipe descriptors close exactly once; dedicated reader threads and CLOEXEC remain.
- [ ] `wait_for` uses monotonic remaining time for capture and sleep decisions.
- [ ] Timeout with `imageMode=omit` returns the last completed poll without recapture.
- [ ] Non-omit timeout permits exactly one at-most-250 ms final attempt and otherwise returns the last poll with an honest note.
- [ ] `GET /v1/routes` matches the new behavior.
- [ ] Focused suites and one final `swift test` exit 0.
- [ ] No files outside Scope are newly modified; prerequisite changes are preserved.
- [ ] `plans/README.md` status row is updated.

## STOP conditions

Stop and report back (do not improvise) if:

- Any prerequisite fix is absent from both the working tree and commits after `0110ffb`.
- `BoundedProcessRunner` no longer uses dedicated threads or `POSIX_SPAWN_CLOEXEC_DEFAULT`; do not overwrite newer hardening.
- The inherited-pipe regression cannot be reproduced with the exact direct-child-exits shape after two reasonable test fixes.
- Closing a read descriptor can double-close a reused FD; solve ownership before proceeding, never accept the race.
- Meeting the wait deadline appears to require silently dropping the last valid state or fabricating screenshot fields.
- A Swift 6 sendability fix would require marking the whole service/module unchecked; only the narrow operation box may be `@unchecked Sendable`.
- A focused verification fails twice, or implementation requires any out-of-scope file.

## Maintenance notes

- Deadline math must remain monotonic and overflow-safe. `Date` may still be used for response timestamps, never for elapsed timeout control.
- Process-tree discovery is inherently racy after reparenting; retain the process-group signal and the accumulated descendant set.
- The bounded capture operation cannot forcibly cancel a blocking Apple AX call. It bounds HTTP response latency and prevents subsequent polls, while the one retained worker may finish later; reviewers should ensure repeated timed-out polls cannot accumulate workers.
- If screenshot capture latency regularly exceeds 250 ms, revisit the documented allowance explicitly rather than quietly increasing an unbounded post-timeout capture.
- Future `wait_for` conditions must run against the completed poll state and must not add their own sleeps outside the engine.
