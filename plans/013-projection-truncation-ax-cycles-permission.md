# Plan 013: Make AX projection truncation, graph cycles, and permission loss explicit

> **Executor instructions**: Follow this plan step by step. Run every verification command and confirm the expected result before moving to the next step. If anything in the "STOP conditions" section occurs, stop and report — do not improvise. When done, update the status row for this plan in `plans/README.md` unless a reviewer maintains the index.
>
> **Drift check (run first)**: `git diff --stat 0110ffb..HEAD -- Sources/BackgroundComputerUse/AXFoundation Sources/BackgroundComputerUse/Actions/Shared/AXActionRuntimeSupport.swift Sources/BackgroundComputerUse/Actions/Shared/AXActionTargetResolver.swift Sources/BackgroundComputerUse/StatePipeline/AXPipelineV2 Tests/BackgroundComputerUseTests/AXPipelineSafetyTests.swift`
> Compare every Current state excerpt with live code if these paths changed. Run `git status --short` and STOP if the planned-at working-tree fixes named in plans 012/README are neither modified nor committed.

## Status

- **Priority**: P1
- **Effort**: M
- **Risk**: MED
- **Depends on**: `plans/004-real-app-ax-fixture-corpus.md`
- **Category**: bug
- **Planned at**: commit `0110ffb`, 2026-09-02

## Why this matters

The state pipeline can silently omit projected nodes while claiming `truncated=false`, loop on cyclic live AX relationships, and turn mid-capture TCC revocation into a plausible empty tree. Those are truth and safety failures: agents may target incomplete state, hang a request, or retry a permission failure as if no UI matched. This plan makes all three conditions bounded and observable without treating transient AX failures as permission denial.

## Current state

- `AXProjectedTreeBuilder.swift:34-47` sets `compactNative.maxProjectedNodes` to 2,800, independently of the raw capture limit. At `:165-171`, projection simply returns at the cap. A measured live Electron tree reached about 70 recursion levels, so both breadth truncation and bounded traversal are practical runtime concerns:

```swift
if projectedNodes.count >= policy.maxProjectedNodes {
    return
}
```

- `StatePipelineExperiment.swift:641-662` builds the public tree with `truncated: rawCapture.truncated`; projected omission is ignored. `InteractionToken.swift:24-30` hashes `tree.truncated`, so the false flag is also part of interaction identity.
- `AXRawCaptureService.swift:9,65-75` aliases identity to `ObjectIdentifier` and uses it in the main visited set. The same file falls back to `AXHelpers.elementsEqual` only for focus matching at `:705-719`, proving equality-correct comparison already exists but is not the canonical map key.
- `AXRawCaptureService.swift:695-703` follows `AXParent` without a visited set or bound. `AXMenuPathActivator.swift:133-145` appends `AXChildren` without visited/depth/examined-node limits.
- Other live AX identity sites must join the same implementation rather than preserve parallel policies: `AXMenuPresentationProvider.swift:148-161` uses bare `CFHash`; `AXAttachedSurfaceDiscovery.swift:16-25,72-89` uses hash-only sets; `AXActionTargetResolver.swift:571-585` hash-deduplicates menu roots and its recursive `resolveByLooseMatch` at `:923-963` has no cycle/node bound; `AXWindowDiscovery.swift:24-45` compares focused/main windows by hash alone. `AXActionRuntimeSupport.swift:340-351` has a depth bound of 8 but no cycle identity.
- `WindowTargetResolver.swift:20-29` calls `AXHelpers.requireAccessibility()` only before resolving. `AXRawCaptureService.swift:1070-1101` discards the `AXError` when `AXUIElementCopyMultipleAttributeValues` fails. `StatePipelineExperiment.swift:311-331` does not revalidate after raw reads.
- The existing denial is `DiscoveryError.accessibilityDenied` (`AXHelpers.swift:16-19`) and Router already maps it to `accessibility_denied`; reuse it.
- `openspec/project.md:7-15` requires Swift 6.2/macOS 14, Swift Testing (not XCTest), `Actions → StatePipeline/Cursor` layering, and honest verifier-first responses. Do not add a reverse dependency.

## Commands you will need

| Purpose | Command | Expected on success |
|---|---|---|
| Identity audit | `grep -R "typealias AXElementIdentity = ObjectIdentifier\|Set<CFHashCode>\|Set<UInt>()" Sources/BackgroundComputerUse` | matches before; no AX-element identity matches after |
| Focused tests | `swift test --filter AXPipelineSafetyTests` | exit 0; truncation, cycle, cap, and permission tests pass |
| Build | `swift build` | exit 0 |
| Full gate | `swift test` | exit 0; 391 baseline plus new tests pass |

## Scope

**In scope** (only these source/test files):
- `Sources/BackgroundComputerUse/AXFoundation/AXElementIdentity.swift` (create)
- `Sources/BackgroundComputerUse/AXFoundation/AXAttachedSurfaceDiscovery.swift`
- `Sources/BackgroundComputerUse/AXFoundation/AXWindowDiscovery.swift`
- `Sources/BackgroundComputerUse/Actions/Shared/AXActionRuntimeSupport.swift`
- `Sources/BackgroundComputerUse/Actions/Shared/AXActionTargetResolver.swift`
- `Sources/BackgroundComputerUse/StatePipeline/AXPipelineV2/Capture/AXRawCaptureService.swift`
- `Sources/BackgroundComputerUse/StatePipeline/AXPipelineV2/Menu/AXMenuPathActivator.swift`
- `Sources/BackgroundComputerUse/StatePipeline/AXPipelineV2/Menu/AXMenuPresentationProvider.swift`
- `Sources/BackgroundComputerUse/StatePipeline/AXPipelineV2/Projection/AXProjectedTreeBuilder.swift`
- `Sources/BackgroundComputerUse/StatePipeline/AXPipelineV2/State/StatePipelineExperiment.swift`
- `Tests/BackgroundComputerUseTests/AXPipelineSafetyTests.swift` (create)
- `plans/README.md` (status only)

**Out of scope**: changing public DTO field names; raising the 2,800/6,500 caps; retrying AX reads; prompting for TCC; changing projection passes; changing action classification; XCTest; live permission revocation automation.

## Git workflow

- Branch: `advisor/013-projection-truncation-ax-cycles-permission`
- Commits: `fix: report projected tree truncation`, then `fix: bound accessibility graph walks`, then `fix: surface capture permission loss`.
- Do not push or open a PR.

## Steps

### Step 1: Add failing projection truth tests

Create `AXPipelineSafetyTests.swift` with Swift Testing imports and a 2,900-node star (not a 2,900-deep chain). Reuse the complete `AXRawNodeDTO` initializer shape from `WindowStatePayloadParityTests.swift:458-493`; the helper below shows the required topology and assertions:

```swift
import ApplicationServices
import Foundation
import Testing
@testable import BackgroundComputerUse

@Suite
struct AXPipelineSafetyTests {
    @Test
    func compactProjectionReportsItsOwnTruncation() {
        let raw = largeRawCapture(count: 2_900)
        let semantic = AXSemanticEnricher().enrich(raw)
        let result = AXProjectedTreeBuilder().build(rawCapture: raw, semanticTree: semantic, policy: .compactNative(includeMenuBar: false))
        #expect(raw.truncated == false)
        #expect(result.tree.nodes.count == 2_800)
        #expect(result.didTruncate)
    }
    @Test
    func replayPublishesProjectionTruncationAndNote() {
        let raw = largeRawCapture(count: 2_900)
        let fixture = AXPipelineV2Fixture(generatedAt: "2026-09-02T00:00:00Z", scenarioID: nil, targetPID: 1,
            includeMenuBar: false, menuMode: .none, maxNodes: 6_500,
            window: ResolvedWindowDTO(windowID: "w_large", title: "Large", bundleID: "example.large", pid: 1, launchDate: nil, windowNumber: 1, frameAppKit: RectDTO(x: 0, y: 0, width: 800, height: 600), resolutionStrategy: "fixture"),
            rawCapture: raw, platformProfile: AXPlatformProfileDTO(bundleID: "example.large", bundlePath: nil, frameworkHints: [], helperAppHints: [], isChromiumLike: false, isElectronLike: false, manualAccessibility: nil, enablementAttempts: nil, notes: []), menuPresentation: nil, notes: [])
        let envelope = StatePipelineExperiment().replayFixture(fixture, imageMode: .omit)
        #expect(envelope.response.tree.truncated)
        #expect(envelope.response.notes.contains { $0.contains("Projection reached the maxProjectedNodes limit") })
        #expect(envelope.diagnostics.notes == envelope.response.notes)
    }
    private func largeRawCapture(count: Int) -> AXRawCaptureResult {
        let nodes = (0..<count).map { index in
            AXRawNodeDTO(index: index, parentIndex: index == 0 ? nil : 0, depth: index == 0 ? 0 : 1,
                childIndices: index == 0 ? Array(1..<count) : [], role: index == 0 ? "AXWindow" : "AXButton",
                subrole: nil, roleDescription: nil, title: "Node \(index)", placeholder: nil, description: nil,
                help: nil, identifier: "node-\(index)", domIdentifier: nil, url: nil, valueDescription: nil,
                valueType: nil, enabled: true, selected: false, expanded: nil, isFocused: false,
                value: ValueSummaryDTO(kind: "none", preview: nil, length: nil, truncated: false),
                isValueSettable: false, secondaryActions: [], availableActions: nil, parameterizedAttributes: nil,
                frameAppKit: nil, activationPointAppKit: nil, childCount: index == 0 ? count - 1 : 0,
                childSource: "AXChildren", collectionInfo: nil, identity: nil, relationships: nil,
                textExtraction: nil, interactionTraits: nil)
        }
        return AXRawCaptureResult(rootIndices: [0], nodes: nodes, focusedCanonicalIndex: nil, focusSelection: nil, truncated: false)
    }
}
```
Do not persist this 2,900-node synthetic fixture as JSON; construct it in the test so the cap boundary stays obvious.
**Verify**: `swift test --filter AXPipelineSafetyTests` → fails because builder has no `didTruncate` result and replay still reports false.
### Step 2: Carry projected truncation through live and replay responses
Change builder output to an internal wrapper and set the bit only when a node is actually rejected by the cap:
```swift
struct AXProjectedTreeBuildResult {
    let tree: AXProjectedTreeDTO
    let didTruncate: Bool
}

struct AXProjectedTreeBuilder {
    func build(rawCapture: AXRawCaptureResult, semanticTree: AXSemanticTreeDTO, policy: AXProjectionPolicy) -> AXProjectedTreeBuildResult {
        ProjectionContext(rawCapture: rawCapture, semanticTree: semanticTree, policy: policy).build()
    }
}
```

In `ProjectionContext`, add `private var didTruncate = false`; set it before returning at `projectCanonicalNode`'s cap. Wrap the existing DTO return as `AXProjectedTreeBuildResult(tree: AXProjectedTreeDTO(...), didTruncate: didTruncate)`. Do not mark exact-2,800 trees truncated unless traversal attempts a 2,801st retained node.

In both `captureLive` and `captureResolvedWindow`, name the wrapper `projection`, pass `projection.tree` to tokens/envelopes, and pass `projection.didTruncate` to `makeSurfaceTreeDTO` and `buildNotes`. Use exactly:

```swift
truncated: rawCapture.truncated || projectedTruncated
```

Append this one note when projected truncation occurs: `Projection reached the maxProjectedNodes limit; the public tree omits canonical nodes.` Apply the same union flag and note in `replayFixture`. This automatically corrects `InteractionToken` because it already hashes the public flag.

**Verify**: `swift test --filter AXPipelineSafetyTests` → the 2,900-node builder and replay tests pass.

### Step 3: Introduce one equality-correct identity and bounded generic walker

Create `AXElementIdentity.swift` with the exact identity rule and generic test seam:

```swift
struct AXElementIdentity: Hashable {
    private let element: AXUIElement
    init(_ element: AXUIElement) { self.element = element }
    static func == (lhs: Self, rhs: Self) -> Bool { CFEqual(lhs.element, rhs.element) }
    func hash(into hasher: inout Hasher) { hasher.combine(CFHash(element)) }
}

struct AXGraphWalkResult<Element> {
    let match: Element?
    let visited: [Element]
    let examinedCount: Int
    let stoppedByCycle: Bool
    let stoppedByDepth: Bool
    let stoppedByExaminedLimit: Bool
}

enum AXBoundedGraphWalker {
    static func ancestors<Element, Identity: Hashable>(from start: Element, maxDepth: Int = 256,
        maxExamined: Int = 256, identity: (Element) -> Identity, parent: (Element) -> Element?) -> AXGraphWalkResult<Element>
    static func firstDepthFirst<Element, Identity: Hashable>(roots: [Element], maxDepth: Int = 256,
        maxExamined: Int = 4096, identity: (Element) -> Identity, children: (Element) -> [Element],
        matches: (Element) -> Bool) -> AXGraphWalkResult<Element>
}
```
Implement both iteratively. Insert identity before expanding; a duplicate sets `stoppedByCycle`; depth `> maxDepth` sets `stoppedByDepth`; reaching `maxExamined` with pending work sets `stoppedByExaminedLimit`. Preserve deterministic root/child order by pushing reversed arrays.
**Verify**: `swift build` → exit 0.
### Step 4: Test cycles, logical wrapper equality, and caps
Add to `AXPipelineSafetyTests`:
```swift
private final class FakeElement {
    let id: Int
    var parent: FakeElement?
    var children: [FakeElement] = []
    init(_ id: Int) { self.id = id }
}
@Test func graphWalksStopAtCyclesAndLimits() {
    let a = FakeElement(1), b = FakeElement(2)
    a.parent = b; b.parent = a; a.children = [b]; b.children = [a]
    let ancestors = AXBoundedGraphWalker.ancestors(from: a, identity: { $0.id }, parent: { $0.parent })
    #expect(ancestors.visited.map(\.id) == [1, 2]); #expect(ancestors.stoppedByCycle)
    let menu = AXBoundedGraphWalker.firstDepthFirst(roots: [a], maxDepth: 256, maxExamined: 2,
        identity: { $0.id }, children: { $0.children }, matches: { _ in false })
    #expect(menu.match == nil); #expect(menu.examinedCount == 2); #expect(menu.stoppedByCycle || menu.stoppedByExaminedLimit)
}

@Test func distinctAXWrappersForOneApplicationShareIdentity() {
    let first = AXElementIdentity(AXUIElementCreateApplication(getpid()))
    let second = AXElementIdentity(AXUIElementCreateApplication(getpid()))
    #expect(first == second)
    #expect(Set([first, second]).count == 1)
}
```

**Verify**: `swift test --filter AXPipelineSafetyTests` → cycle tests terminate and pass.

### Step 5: Migrate every live AX walk/lookup in scope

Replace ObjectIdentifier/hash-only identity with `AXElementIdentity`: main capture visited/map, projected visible-child ordinal lookup, relationship mapping, focused lookup, attached-surface sets, window focused/main comparison, menu-root dedupe, and menu-presentation ancestors. Use `AXBoundedGraphWalker.ancestors` for raw focus, menu presentation, and the existing 8-deep action ancestor walk. Use `firstDepthFirst` in `findMenuItem`; convert stop flags into sanitized warnings on `AXMenuActivationResult`. Replace recursive `resolveByLooseMatch` with a bounded walker call and score only its returned `visited` elements, preserving the current best-score threshold. Main capture remains bounded by `maxNodes` and must still set raw `truncated` on that cap.

**Verify**: `grep -R "typealias AXElementIdentity = ObjectIdentifier\|Set<CFHashCode>\|Set<UInt>()" Sources/BackgroundComputerUse` → no AX identity matches; `swift test --filter AXPipelineSafetyTests` → pass.

### Step 6: Preserve root AX errors and classify permission revocation

Make `AXRawCaptureService.capture` throwing and update its two pipeline callers with `try`. Add an injectable backend:

```swift
struct AXMultipleRead { let error: AXError; let values: CFArray? }
struct AXSingleRead { let error: AXError; let value: CFTypeRef? }
struct AXReadBackend {
    let copyMultiple: (AXUIElement, [CFString]) -> AXMultipleRead
    let copySingle: (AXUIElement, CFString) -> AXSingleRead
    let isTrusted: () -> Bool

    static let live = AXReadBackend(
        copyMultiple: { element, attributes in
            var values: CFArray?
            let error = AXUIElementCopyMultipleAttributeValues(
                element, attributes as CFArray, [], &values
            )
            return AXMultipleRead(error: error, values: values)
        },
        copySingle: { element, attribute in
            var value: CFTypeRef?
            let error = AXUIElementCopyAttributeValue(element, attribute, &value)
            return AXSingleRead(error: error, value: value)
        },
        isTrusted: { AccessibilityAuthorization.isTrusted(prompt: false) }
    )
}
```

Give `AXRawCaptureService` `init(readBackend: AXReadBackend = .live)`. `AXReadSession` must count root batch attempts, mark a root read successful only when the multiple read or its individual fallback yields at least one normalized value, and retain non-success/embedded AX error codes. Add `diagnostics: [String]` to `AXRawLiveCaptureResult`. After traversal: if root attempts exist and none succeeded, throw `DiscoveryError.accessibilityDenied` only when `isTrusted()` is now false; otherwise return a note whose stable prefix is `AX root reads failed while Accessibility remained trusted; capture may be partial` followed by the sorted numeric error codes in parentheses. Never include titles/values.

**Verify**: `swift build` → exit 0; the only new thrown permission error is `DiscoveryError.accessibilityDenied`.

### Step 7: Test revoked and transient root-read failures

Add these deterministic tests and thread returned diagnostics into live `buildNotes`; replay has no read-session diagnostics:

```swift
private func failingBackend(trusted: Bool) -> AXReadBackend {
    AXReadBackend(copyMultiple: { _, _ in AXMultipleRead(error: .apiDisabled, values: nil) },
        copySingle: { _, _ in AXSingleRead(error: .apiDisabled, value: nil) }, isTrusted: { trusted })
}
@Test func revokedTrustThrowsAccessibilityDenied() {
    let service = AXRawCaptureService(readBackend: failingBackend(trusted: false))
    do { _ = try service.capture(roots: [AXUIElementCreateSystemWide()], focusedElement: nil, maxNodes: 10); Issue.record("Expected accessibilityDenied") }
    catch DiscoveryError.accessibilityDenied {} catch { Issue.record("Unexpected error: \(error)") }
}
@Test func trustedRootReadFailureReturnsPartialDiagnostic() throws {
    let service = AXRawCaptureService(readBackend: failingBackend(trusted: true))
    let result = try service.capture(roots: [AXUIElementCreateSystemWide()], focusedElement: nil, maxNodes: 10)
    #expect(result.diagnostics.contains { $0.contains("capture may be partial") })
}
```

**Verify**: `swift test --filter AXPipelineSafetyTests` → permission-denied and trusted-partial tests pass deterministically without changing TCC.

### Step 8: Run final gates

**Verify**: `swift test --filter AXPipelineSafetyTests && swift build && swift test` → all exit 0; full suite is 391 baseline plus new tests.

## Test plan

- One new Swift Testing suite covers 2,900-node projected truncation, public union flag/note, cycles, 256-depth and 4,096-examined caps, equality of distinct wrappers for one logical AX element, revoked trust, and transient trusted root failures.
- Use a star-shaped large fixture to test the cap rather than recursion depth. Use fake graph nodes for cycles and injected AX read results for permission status.
- Existing `InteractionTokenTests.swift:24-30,47-54` already proves the public truncation bit is in the token input; no duplicate hash implementation.

## Done criteria

- [ ] Public `tree.truncated` is raw OR projected, with the exact projection note in live and replay diagnostics.
- [ ] One `AXElementIdentity` uses `CFHash` plus `CFEqual`; no AX set/map relies on bare hash or wrapper ObjectIdentifier in scoped walks.
- [ ] Ancestor and menu walks are cycle-safe and depth/examined bounded.
- [ ] All failed root reads plus revoked trust throw existing `accessibility_denied`; trusted AX failures return a redacted partial-capture note.
- [ ] Focused tests, build, and full suite exit 0; only in-scope files plus README status changed.

## STOP conditions

Stop if excerpts drift; CFEqual/CFHash do not satisfy Hashable equality on supported macOS; the 2,900-node fixture is pruned below 2,800 (change roles/topology, not the cap); TCC classification requires guessing from AXError without a false trust check; public DTO shape must change; or an out-of-scope file is required.

## Maintenance notes

Keep raw and projected caps independent but union their truth signal. Any new AX parent/child traversal must use the shared identity/walker. Reviewers should reject retries/prompts: this plan classifies loss, it does not change permission policy. Plan 004 fixtures should later add real cyclic/large-tree captures when available, but deterministic synthetic coverage remains required.
