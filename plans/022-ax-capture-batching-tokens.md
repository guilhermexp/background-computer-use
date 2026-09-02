# Plan 022: Batch AX capture reads and stream stable token hashing

> **Executor instructions**: Follow this plan step by step. Run every verification command and confirm the expected result before moving to the next step. If anything in the "STOP conditions" section occurs, stop and report — do not improvise. When done, update the status row for this plan in `plans/README.md` — unless a reviewer dispatched you and told you they maintain the index.
>
> **Required working-tree baseline**: Before the drift check, run `git diff --name-only 0110ffb..HEAD -- Sources/BackgroundComputerUse/API/Router.swift Sources/BackgroundComputerUse/App/BackgroundComputerUseControlBridge.swift Sources/BackgroundComputerUseControlShared/CodeSignatureIdentity.swift Sources/BackgroundComputerUse/Runtime/RuntimeExecutionQueue.swift Sources/BackgroundComputerUse/Actions/TypeText/AdaptiveTextDispatcher.swift Sources/BackgroundComputerUse/StatePipeline/InteractionToken.swift Sources/BackgroundComputerUse/Runtime/Process/BoundedProcessRunner.swift skills/background-computer-use/scripts/bcu-request.py Tests/BackgroundComputerUseTests/InteractionTokenTests.swift Tests/BackgroundComputerUseTests/RuntimeExecutionQueueTests.swift` and `git status --short --` with the same paths. Each named file must appear in at least one output (committed after `0110ffb` or still modified/untracked). If any is absent, STOP: this plan assumes those fixes, especially window-chrome exclusion and rebased interaction-token indices.
>
> **Drift check (run first)**: `git diff --stat 0110ffb..HEAD -- Sources/BackgroundComputerUse/StatePipeline/AXPipelineV2/Capture/AXRawCaptureService.swift Sources/BackgroundComputerUse/StatePipeline/StateToken.swift Sources/BackgroundComputerUse/StatePipeline/InteractionToken.swift Tests/BackgroundComputerUseTests/InteractionTokenTests.swift Tests/BackgroundComputerUseTests/Fixtures/AX`
> If any in-scope file changed since this plan was written, compare the "Current state" excerpts against the live code before proceeding; on a mismatch, treat it as a STOP condition.

## Status

- **Priority**: P2
- **Effort**: M/L
- **Risk**: MED
- **Depends on**: `plans/004-real-app-ax-fixture-corpus.md`
- **Category**: perf
- **Planned at**: commit `0110ffb`, 2026-09-02

## Why this matters

Every read and every action reread traverses the AX tree, finalizes refetch paths, and hashes two overlapping full-tree representations. A common node currently pays separate AX batches for base, children, rows, and relationships, plus a standalone activation-point read; large trees also create joined strings and repeat parent-chain walks. This plan reduces AX IPC and transient allocation while requiring byte-identical raw fixture output and token values.

## Current state

- `Sources/BackgroundComputerUse/StatePipeline/AXPipelineV2/Capture/AXRawCaptureService.swift` owns live node traversal and AX reads.
  - `:86-100`: `var baseValues = session.multiple(... baseAttributesForCapture() ...)`; missing root/required role fields have a narrow individual-read fallback.
  - `:110-140`: child, native-row, and relationship attributes each call `session.multiple` independently, then `mergedValues(baseValues, childValues, rowValues, relationshipValues)`.
  - `:177-188`: action descriptors and settable state use separate APIs, while activation point is read separately through `AXHelpers.activationPoint(item.element)`.
  - `:239-257` proves parent-before-child order: the node is appended before its children are pushed with `parentIndex: index`; the LIFO stack later visits those children.
  - `:266-273`: `workingNodes.map` calls `node.dto(... workingNodes: workingNodes ...)` once per node.
  - `:943-950`: each DTO calls both `ancestorFingerprints(workingNodes:...)` and `rolePath(workingNodes:...)`.
  - `:1008-1035`: both helpers walk `parentIndex` to the root and call `reversed()`.
  - `:1070-1102`: `AXReadSession.multiple` already wraps `AXUIElementCopyMultipleAttributeValues`; partial values are retained, and only `fallbackOnFailure` triggers individual reads.
- `Sources/BackgroundComputerUse/StatePipeline/StateToken.swift` hashes the externally visible `st_` token.
  - `:16-31`: it builds a complete `[String]` payload including rendered text, line mappings, and projected nodes.
  - `:34-36`: `payloadComponents.joined(separator: "|")` is materialized before `SHA256.hash`.
  - `:83-108`: every projected node joins canonical indices, sorted metadata/flags/actions, frame, and children into another string.
- `Sources/BackgroundComputerUse/StatePipeline/InteractionToken.swift` contains the required current chrome exclusion/rebasing behavior.
  - `:31-38`: `contentNodes` filters chrome, then a dictionary rebases retained projected indices.
  - `:40-41`: all components are joined before hashing.
  - `:44-54`: a chrome node and all descendants are excluded; do not remove this behavior.
  - `:70-87`: each retained node sorts flags/actions and joins fourteen fields with `:`.
- `Tests/BackgroundComputerUseTests/InteractionTokenTests.swift:7-39` is the existing Swift Testing fixture proving chrome subtree churn does not move an interaction token.
- Plan 004 places sanitized real-app fixtures in `Tests/BackgroundComputerUseTests/Fixtures/AX/*.json`, copies `Fixtures` as a test resource, and provides `RecordedAXRouteRegressionTests`. If that corpus is absent, use `BCU_FIXTURE_EXPORT_DIR` and the existing `StatePipelineExperiment.saveFixture` (`StatePipelineExperiment.swift:592-599`); never hand-author a “real-app” fixture.
- Repository rules from `openspec/project.md:7-15`: Swift 6.2/Swift 6 strict concurrency, Apple runtime SDKs only, Swift Testing rather than XCTest, `Actions` may consume `StatePipeline` but not reverse, and action routes remain verifier-first read-act-read.

## Commands you will need

| Purpose | Command | Expected on success |
|---|---|---|
| Fixture corpus | `python3 -c 'from pathlib import Path; p=Path("Tests/BackgroundComputerUseTests/Fixtures/AX"); assert p.is_dir() and any(p.glob("*.json"))'` | exit 0 |
| Token tests | `swift test --filter InteractionTokenTests` | exit 0; all selected tests pass |
| Fixture parity | `swift test --filter RecordedAXRouteRegressionTests` | exit 0; all fixture cases pass |
| Focused performance | `BCU_PRINT_PERF=1 swift test --filter AXCapturePerformanceTests` | exit 0 and one `performance.tokenHashMs=` line |
| Final suite | `swift test` | exit 0; all tests pass |

## Scope

**In scope** (the only production/test files you should modify or create):
- `Sources/BackgroundComputerUse/StatePipeline/AXPipelineV2/Capture/AXRawCaptureService.swift`
- `Sources/BackgroundComputerUse/StatePipeline/StateToken.swift`
- `Sources/BackgroundComputerUse/StatePipeline/InteractionToken.swift`
- `Sources/BackgroundComputerUse/StatePipeline/CanonicalTokenHasher.swift` (create)
- `Tests/BackgroundComputerUseTests/InteractionTokenTests.swift`
- `Tests/BackgroundComputerUseTests/AXRawCaptureFixtureParityTests.swift` (create)
- `Tests/BackgroundComputerUseTests/AXCapturePerformanceTests.swift` (create)
- `Tests/BackgroundComputerUseTests/Fixtures/AX/*.json` only when the dependency corpus is absent and an operator authorizes fixture capture
- `plans/README.md` status row only

**Out of scope**:
- Action-name, parameterized-attribute, and settable-value APIs; they are not attributes accepted by `AXUIElementCopyMultipleAttributeValues`.
- Token field sets, ordering, separators, prefixes, truncation, chrome filtering, or rebasing semantics.
- Public DTO/schema changes, projection transforms, capture node limits, and route behavior.
- Launching/installing the app or running live capture without explicit operator authorization.

## Git workflow

- Branch: `advisor/022-ax-capture-batching-tokens`
- Commit logical units using the observed style, for example `perf: batch AX capture and stream stable tokens`.
- Do not push or open a PR unless the operator instructs it.

## Steps

### Step 1: Lock current token bytes and record the benchmark baseline
First run the fixture-corpus command from the table. If no plan-004 fixture exists, STOP for explicit live authorization, then run `BCU_FIXTURE_EXPORT_DIR="$PWD/Tests/BackgroundComputerUseTests/Fixtures/AX" ./script/verify.sh --live`; plan 004 wires that environment variable to sanitize a live `StatePipelineFixture` and call the existing `StatePipelineExperiment.saveFixture`. Re-run the corpus command and do not begin refactoring until at least one JSON fixture is present. If the export hook is absent, complete plan 004 rather than inventing JSON.

Extend `InteractionTokenTests.swift` before changing either token implementation. Keep the existing chrome fixture and add two literal golden checks:

```swift
#expect(token(chromeWithInnerGroup) == "it_49aee88e4a542306dead7369")
#expect(StateToken.make(
    windowID: "w", title: "T", frame: CGRect(x: 0, y: 0, width: 640, height: 480),
    projectedTree: goldenProjectedTree(), selectionSummary: nil,
    pixelWidth: 768, pixelHeight: 576
) == "st_3BQWK210TE0XX")
```

`goldenProjectedTree()` must contain two nodes: root `window/Demo` at `(0,0,640,480)` with metadata `['z','a']`, flag `enabled`, actions `['Press','Show Menu']`, child 1; and child `button/Run` at `(20,30,80,30)` with metadata `['title:Run']`, flags `['focused','enabled']`, action `Press`. Use rendered text `[1] button Run`, one line mapping `(display=1, projected=1, primary=1, canonical=[1], kind='node')`, focused indices 1, profile `default`, and no selection/transforms. The deliberately unsorted arrays lock sorting behavior.

Create `AXCapturePerformanceTests.swift`: build a deterministic 6,500-node shallow projected/surface tree, run both token makers 20 times under `ContinuousClock`, consume the outputs with `#expect(!token.isEmpty)`, and only print `performance.tokenHashMs=<milliseconds>` when `BCU_PRINT_PERF=1`. This is a micro-benchmark, not a timing assertion. Run it now and save the printed baseline in the commit/PR notes.

**Verify**: `swift test --filter InteractionTokenTests && BCU_PRINT_PERF=1 swift test --filter AXCapturePerformanceTests` → all selected tests pass and exactly one token timing line is printed.

### Step 2: Collapse each node to a base batch plus one conditional attribute batch

Keep the first base batch because role determines the second set. Add a helper with this shape:

```swift
private func conditionalAttributesForCapture(role: String?, isWebNode: Bool,
                                             isPassiveMenuBarItem: Bool) -> [CFString] {
    var attributes: [CFString] = []
    if shouldCaptureChildren(role: role, isPassiveMenuBarItem: isPassiveMenuBarItem) {
        attributes += childAttributesForCapture()
        if shouldReadNativeRows(role: role, isWebNode: isWebNode) { attributes += nativeRowAttributesForCapture() }
    }
    if !isPassiveMenuBarItem && !isWebNode { attributes += relationshipAttributesForCapture() }
    if shouldReadActivationPoint(role: role, isWebNode: isWebNode) { attributes.append("AXActivationPoint" as CFString) }
    return attributes
}
```

Call `session.multiple` exactly once with that list, then parse children/rows/relationships and activation point from the merged base + conditional dictionary. Add `AXReadSession.point(from:attribute:)` using `AXValueGetValue(.cgPoint, ...)`. Preserve only existing narrow individual fallbacks for required base/child fields; do not fall back every optional field when a wide call is partial. Keep action descriptors, parameterized names, text extraction, and `isValueSettable` as separate calls.

Add an internal call-plan helper testable without AX IPC and tests covering passive menu item, ordinary native container, native row collection, and web node. Each asserts one base group and one deduplicated conditional group with the expected membership.

**Verify**: `swift test --filter AXRawCaptureFixtureParityTests` → the attribute-plan tests pass and no test expects more than two `multiple` groups per node.

### Step 3: Derive ancestry in parent-before-child order

Replace the two full-parent-chain helpers with one parent-before-child cache pass. Use an internal value like:

```swift
struct AXRawCachedPaths: Equatable {
    let ancestorFingerprints: [String]
    let rolePath: [String]
}

static func next(parent: AXRawCachedPaths?, parentFingerprint: String?, role: String?) -> AXRawCachedPaths {
    AXRawCachedPaths(
        ancestorFingerprints: (parent?.ancestorFingerprints ?? []) + (parentFingerprint.map { [$0] } ?? []),
        rolePath: (parent?.rolePath ?? []) + [role ?? "unknown"]
    )
}
```

Reserve capacity for one cache entry per working node. Iterate nodes by index; require `parentIndex < index`, derive from the already cached parent, and pass the two arrays into `dto`. Delete `ancestorFingerprints(workingNodes:...)` and `rolePath(workingNodes:...)`; `dto` must no longer receive all `workingNodes`. The serialized output is inherently proportional to all emitted path arrays, but this removes repeated parent lookups and reversals.

In `AXRawCaptureFixtureParityTests`, load every plan-004 JSON via `Bundle.module`. Build an `ExpectedPathRecord(index, ancestorFingerprints, rolePath)` array directly from each fixture's finalized nodes and an `ActualPathRecord` array through `AXRawCachedPaths.next`. Encode both arrays with one sorted-key `JSONEncoder` and require byte equality; this compares the exact emitted path payload rather than merely counting nodes. Also run the existing fixture replay suite to cover the full projected response.

**Verify**: `swift test --filter AXRawCaptureFixtureParityTests && swift test --filter RecordedAXRouteRegressionTests` → every real-app path-record JSON payload is byte-identical and all full fixture replays pass.

### Step 4: Stream both token formats through one canonical writer

Create `CanonicalTokenHasher.swift` around mutable `CryptoKit.SHA256`. Every canonical value must call `hasher.update(data:)` as it is written; use reusable `Data` constants for `|`, `:`, `;`, and `,`. Expose explicit operations such as `beginComponent(named:)`, `writeField(_:separator:)`, `writeSortedStrings(_:separator:)`, and `finalize()`. It must not build a whole payload or per-node field array.
Refactor both token makers to use it. Preserve every byte of the old grammar: state top-level components use `|`, line/node records use `;`, fields use `:`, collections use `,`; interaction nodes remain separate `|` components. Keep each token's distinct field set and output encoding (`st_` base32 of the first 8 digest bytes versus `it_` hex of the first 12). Keep sorting metadata, flags, actions, selected indices, and selected node IDs until a separate proof establishes producer ordering. Stream retained interaction nodes in one pass while maintaining the exclusion set and rebasing map; do not reintroduce chrome descendants or raw canonical indices.

**Verify**: `swift test --filter InteractionTokenTests` → both literal goldens pass, including chrome-churn equality and geometry-change inequality.

### Step 5: Measure the combined change and run the final gate

Run the same 6,500-node benchmark and compare its printed number with Step 1. The code-derived expectation is **1.2–1.5× faster token hashing**, not a release gate; host load makes one run noisy. For AX capture, the code-derived expectation is **one base + one conditional attribute batch instead of 3–5 attribute reads**, roughly **1.5–2.5× faster for the attribute-read portion** and a smaller total-capture gain because action/text APIs remain separate. Record actual fixture/live `performance.captureMs` only if an operator authorizes the plan-004 capture workflow; never present these estimates as measurements.

Run the full suite once, then update only this plan's index row.

**Verify**: `BCU_PRINT_PERF=1 swift test --filter AXCapturePerformanceTests && swift test` → timing line printed; all tests pass.

## Test plan

- `InteractionTokenTests`: literal state and interaction token goldens; chrome subtree excluded/rebased; content geometry still changes interaction token; unsorted fields retain canonical sorting.
- `AXRawCaptureFixtureParityTests`: role-conditional attribute plans; parent-before-child invariant; every recorded ancestor fingerprint/role path exactly matches; raw fixture bytes remain stable.
- `AXCapturePerformanceTests`: deterministic large synthetic trees, elapsed output only under `BCU_PRINT_PERF`, no fragile time threshold.
- Existing `RecordedAXRouteRegressionTests`: every plan-004 real-app fixture still replays.

## Done criteria

- [ ] Common nodes execute one base and at most one conditional `AXReadSession.multiple` call.
- [ ] No action-name, parameterized, or settable API was incorrectly folded into attribute batching.
- [ ] The two parent-walking/reversing helpers are deleted.
- [ ] Golden values remain exactly `it_49aee88e4a542306dead7369` and `st_3BQWK210TE0XX`.
- [ ] No token maker calls `components.joined(separator: "|")` or materializes per-node field arrays.
- [ ] Fixture parity, benchmark, focused token tests, and final `swift test` pass.
- [ ] No files outside Scope are modified, except the assigned `plans/README.md` row.

## STOP conditions

Stop and report back (do not improvise) if:

- Any required baseline fix is absent, especially current `InteractionToken` chrome exclusion/rebasing.
- Plan 004's fixture corpus/loader is absent. Request operator authorization before using `BCU_FIXTURE_EXPORT_DIR`; do not fabricate fixtures.
- A real fixture violates `parentIndex < child index`; the proposed parent-before-child cache is then invalid.
- Wider conditional AX batches return missing required children in a live authorized fixture after the existing narrow fallback, or capture classification/click readiness regresses.
- Either literal token changes by one byte, even if the new value appears deterministic.
- The implementation would need a public contract or token-version change.
- A verification command fails twice after one focused correction.

## Maintenance notes

- Treat separators, sorting, number formatting, prefixes, chrome exclusion, and index rebasing as persisted token grammar; add a golden before changing any of them.
- Review partial-result behavior in `AXUIElementCopyMultipleAttributeValues`: optional unsupported attributes must not erase valid values from the same batch.
- The ancestry cache removes avoidable walks but cannot remove the contract's repeated ancestor arrays; changing that storage requires a separate versioned DTO proposal.
- Benchmark ratios are code-derived expectations until the same host/app fixture is measured before and after.