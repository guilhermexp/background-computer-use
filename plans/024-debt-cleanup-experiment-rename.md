# Plan 024: Retire provisional pipeline naming and redundant contract/AX debt

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**: `git diff --stat 0110ffb..HEAD -- Sources/BackgroundComputerUse/StatePipeline Sources/BackgroundComputerUse/Actions Sources/BackgroundComputerUse/AXFoundation Sources/BackgroundComputerUse/API Sources/BackgroundComputerUse/Contracts Tests/BackgroundComputerUseTests openspec/changes`
> This plan depends on plan 004, so its fixture-export changes are expected drift. Compare every "Current state" excerpt against live code and apply the explicit plan-004 migration below. Any other mismatch is a STOP condition.
>
> **Required baseline check**: Run `git status --short`. The fixes known at planning time must be either committed in `HEAD` or still present as local modifications: `API/Router.swift`, `App/BackgroundComputerUseControlBridge.swift`, `BackgroundComputerUseControlShared/CodeSignatureIdentity.swift`, `Runtime/RuntimeExecutionQueue.swift`, `Actions/TypeText/AdaptiveTextDispatcher.swift`, `StatePipeline/InteractionToken.swift`, `Runtime/Process/BoundedProcessRunner.swift`, `skills/background-computer-use/scripts/bcu-request.py`, `InteractionTokenTests.swift`, and `RuntimeExecutionQueueTests.swift`. STOP if any was reverted or lost; do not reset or overwrite the operator's work.

## Status

- **Priority**: P3
- **Effort**: S/M
- **Risk**: LOW
- **Depends on**: `plans/004-real-app-ax-fixture-corpus.md`
- **Category**: tech-debt
- **Planned at**: commit `0110ffb`, 2026-09-02

## Why this matters

The production state-capture root is still called an “Experiment,” mixes live capture with fixture persistence/replay, and exposes dead entry points. The route catalog also publishes a one-value `implementationStatus`, while Actions maintains a second copy of low-level AX conversion helpers with subtly stricter range validation. This plan makes the production names and ownership truthful, removes a weightless public field, and leaves one canonical implementation of raw AX primitives without changing capture or action behavior.

## Current state

- `Sources/BackgroundComputerUse/StatePipeline/AXPipelineV2/State/StatePipelineExperiment.swift` is the production composition root, not an experiment:

```swift
// StatePipelineExperiment.swift:69-83
enum StatePipelineExperimentError: Error, CustomStringConvertible {
    case invalidFixture(String)
    case invalidScenario(String)
// lines 72-82 omitted
struct StatePipelineExperiment {
```

- The file has two live-capture entry points. `captureLive` resolves a PID/title itself, while production callers already resolve a window and use `captureResolvedWindow`:

```swift
// StatePipelineExperiment.swift:94-99,279-289
func captureLive(_ options: StatePipelineLiveCaptureOptions) throws -> StatePipelineCaptureResult {
    let frontmostBefore = NSWorkspace.shared.frontmostApplication
    let resolved = try targetResolver.resolve(
        pid: options.targetPID,
        windowTitleContains: options.windowTitleContains
    )
// lines 100-278 omitted
func captureResolvedWindow(
    resolved: ResolvedWindowTarget,
    includeMenuBar: Bool,
    menuMode: StatePipelineMenuMode? = nil,
    menuPathComponents: [String] = [],
    webTraversal: AXWebTraversalMode = .visible,
```

- Production call sites instantiate the provisional type directly:

```swift
// Actions/Shared/AXActionTargetResolver.swift:120-147
struct AXActionTargetResolver {
    private let executionOptions: ActionExecutionOptions
    private let windowResolver = WindowTargetResolver()
    private let statePipeline = StatePipelineExperiment()
```

```swift
// StatePipeline/WindowStateService.swift:8-12,37-39
struct WindowStateService {
    // lines 9-11 omitted
    private let statePipeline = StatePipelineExperiment()
```

- Replay and persistence currently live on the same type:

```swift
// StatePipelineExperiment.swift:477-480,583-607
func replayFixture(_ fixture: StatePipelineFixture, imageMode _: ImageMode = .path) -> StatePipelineEnvelope {
    let replayPreparation = prepareReplayFixture(fixture)
// lines 479-582 omitted
func loadFixture(at path: String) throws -> StatePipelineFixture {
// lines 584-591 omitted
func saveFixture(_ fixture: StatePipelineFixture, to path: String) throws {
// lines 593-600 omitted
func loadScenario(at path: String) throws -> StatePipelineScenario {
```

  At commit `0110ffb`, only `WindowStatePayloadParityTests.swift:404` calls replay. Plan 004 intentionally changes that: `RecordedAXRouteRegressionTests.swift` will call load/replay, and `captureResolvedWindow` will export a sanitized fixture through `saveFixture` when `BCU_FIXTURE_EXPORT_DIR` is set. Therefore **retain load, save, and replay**, but move them to dedicated types. Delete only `captureLive` and `loadScenario` after plan 004 is present.

- Router maps an error that today can only come from fixture/scenario I/O, not the HTTP live-capture path:

```swift
// API/Router.swift:839-850
case let captureError as StatePipelineExperimentError:
    .json(
        ErrorResponse(
            error: "capture_failed",
            message: "State capture failed for \(routeID.rawValue): \(String(describing: captureError))",
```

- The public route status has one possible value:

```swift
// Contracts/RouteContracts.swift:29-31,43-51
public enum RouteImplementationStatusDTO: String, Encodable, Sendable {
    case implemented
}
public struct RouteDescriptorDTO: Encodable, Sendable {
    public let id: String
    // lines 45-49 omitted
    public let implementationStatus: RouteImplementationStatusDTO
}
// Contracts/BootstrapContracts.swift:60-68
public struct APIRouteDTO: Encodable, Sendable {
    public let id: String
    // lines 62-67 omitted
    public let implementationStatus: RouteImplementationStatusDTO
```

  Every descriptor supplies `.implemented`; `RouteRegistry.swift:471-484` copies it into `/v1/routes`. `APIDocumentationTests.swift:9-19` only asserts the constant value.

- `AXHelpers` already owns the raw wrappers:

```swift
// AXFoundation/AXHelpers.swift:32-73,224-235
static func copyAttributeValue(_ element: AXUIElement, attribute: CFString) -> CFTypeRef? {
// lines 33-45 omitted
static func stringAttribute(_ element: AXUIElement, attribute: CFString) -> String? {
// lines 47-49 omitted
static func boolAttribute(_ element: AXUIElement, attribute: CFString) -> Bool? {
// lines 51-61 omitted
static func elementAttribute(_ element: AXUIElement, attribute: CFString) -> AXUIElement? {
// lines 63-70 omitted
static func elementArrayAttribute(_ element: AXUIElement, attribute: CFString) -> [AXUIElement] {
// lines 72-223 omitted
static func rangeValue(from value: CFTypeRef?) -> CFRange? {
```

- Actions duplicates those wrappers. Its string conversion additionally accepts `URL`/`NSURL`, and its visible range additionally rejects negative/implausibly large values:

```swift
// Actions/Shared/AXActionRuntimeSupport.swift:150-181,389-408
static func copyAttributeValue(_ element: AXUIElement, attribute: CFString) -> CFTypeRef? {
// lines 151-157 omitted
static func stringAttribute(_ element: AXUIElement, attribute: CFString) -> String? {
// lines 159-173 omitted
static func boolAttribute(_ element: AXUIElement, attribute: CFString) -> Bool? {
// lines 175-388 omitted
static func visibleCharacterRange(_ element: AXUIElement) -> CFRange? {
    guard range.location >= 0, range.length >= 0,
          range.location < Int.max / 4, range.length < Int.max / 4 else { return nil }
    return range
}
```

- Architectural constraints from `openspec/project.md:13-15`: Actions consumes StatePipeline/Cursor, never the reverse; Contracts is the public Codable leaf; route services follow capture → validate → resolve → safety → dispatch → reread/verify; `GET /v1/routes` is the contract source of truth.

## Commands you will need

| Purpose | Command | Expected on success |
|---|---|---|
| Baseline | `git status --short` | operator changes are preserved; no destructive cleanup |
| Symbol inventory | `git grep -n 'StatePipelineExperiment\|captureLive(\|loadScenario(\|implementationStatus\|RouteImplementationStatusDTO' -- Sources Tests` | only the expected pre-migration references |
| Focused pipeline tests | `swift test --filter WindowStatePayloadParityTests` | selected tests pass |
| Focused API tests | `swift test --filter APIDocumentationTests` | selected tests pass |
| Focused helper tests | `swift test --filter AXHelpersTests` | selected tests pass |
| OpenSpec | `which openspec && openspec validate remove-route-implementation-status --strict` | strict validation passes; if `which` finds nothing, skip and record that fact |
| Final suite | `swift test` | all tests pass (391 baseline plus new tests) |

## Scope

**In scope** (the only files you should modify):
- Rename `Sources/BackgroundComputerUse/StatePipeline/AXPipelineV2/State/StatePipelineExperiment.swift` to `StatePipeline.swift`.
- Create `Sources/BackgroundComputerUse/StatePipeline/AXPipelineV2/State/StatePipelineFixtureSupport.swift`.
- `Sources/BackgroundComputerUse/Actions/Shared/AXActionTargetResolver.swift`, `StatePipeline/WindowStateService.swift`, `API/{Router,RouteRegistry}.swift`
- `Sources/BackgroundComputerUse/Contracts/{RouteContracts,BootstrapContracts}.swift`, `AXFoundation/AXHelpers.swift`, and `Actions/Shared/AXActionRuntimeSupport.swift`
- Action files returned by `git grep -l 'AXActionRuntimeSupport\.\(copyAttributeValue\|stringAttribute\|boolAttribute\|elementAttribute\|elementArrayAttribute\)' -- Sources/BackgroundComputerUse/Actions` (currently Click, RendererAccessibilityBootstrap/Worker, Paste, PressKey, Scroll, SecondaryAction, AXActionTargetResolver, Text, and TypeText).
- Tests: `WindowStatePayloadParityTests.swift`, plan-004 `RecordedAXRouteRegressionTests.swift`, and new `StatePipelineFixtureStoreTests.swift`/`AXHelpersTests.swift`.
- Create `openspec/changes/remove-route-implementation-status/{proposal.md,tasks.md,specs/route-catalog/spec.md}`.

**Out of scope** (do NOT touch):
- AXPipelineV2 contract/type names and fixture JSON shape; V2 is a real compatibility identifier, not provisional naming.
- Any route request/response field except `implementationStatus`; plan-004 sanitizer/corpus/package/export semantics; or action dispatch, verification, timing, cursor, and foreground behavior.
- README/SKILL: repository search shows no `implementationStatus` mention there.

## Git workflow

- Branch: `advisor/024-debt-cleanup-experiment-rename`.
- Commit logical units with the observed style, e.g. `refactor: retire experimental state pipeline shell` and `refactor: consolidate AX attribute helpers`.
- Never discard pre-existing working-tree changes. Do not push or open a PR unless the operator instructs it.

## Steps

### Step 1: Record the public contract removal in OpenSpec

Create the three `remove-route-implementation-status` files. The spec SHALL say `/v1/routes` omits `implementationStatus`, only callable routes are catalogued, and all other route metadata is unchanged. Include scenarios for encoded omission and descriptor/catalog parity. The proposal must call this a breaking clean cutover, not a deprecated alias; tasks must name DTO/registry/test edits and final validation.

**Verify**: `if which openspec >/dev/null 2>&1; then openspec validate remove-route-implementation-status --strict; else echo 'SKIP: openspec CLI absent'; fi` → strict validation passes, or the explicit skip line is recorded.

### Step 2: Rename the production pipeline and separate fixture tooling

Rename the file and type to `StatePipeline`. Remove `captureLive`, `StatePipelineLiveCaptureOptions`, `StatePipelineScenario`, and `loadScenario`. Change `buildNotes` to accept `menuPathComponents: [String]` directly because that is the only options member it reads (`StatePipelineExperiment.swift:633-634`).

Move replay-only code, without rewriting its logic, into:

```swift
struct StatePipelineFixtureReplayer {
    private let semanticEnricher = AXSemanticEnricher()
    private let projectedTreeBuilder = AXProjectedTreeBuilder()
    func replay(_ fixture: StatePipelineFixture, imageMode: ImageMode = .path) -> StatePipelineEnvelope {
        // move the current replayFixture body unchanged
    }
}
enum StatePipelineFixtureStoreError: Error, CustomStringConvertible { case invalidFixture(String) }
enum StatePipelineFixtureStore {
    static func load(at path: String) throws -> StatePipelineFixture
    static func save(_ fixture: StatePipelineFixture, to path: String) throws
}
```

Move the existing projection/surface/replay preparation helpers intact into internal file-scope support usable by live capture and replay; do not duplicate them. Migrate plan 004 exactly: its exporter calls `StatePipelineFixtureStore.save`, and `RecordedAXRouteRegressionTests` calls `StatePipelineFixtureStore.load` plus `StatePipelineFixtureReplayer().replay`. Update `WindowStatePayloadParityTests.swift:404` the same way. Remove Router’s `StatePipelineExperimentError` case because fixture errors are not HTTP live-capture errors.

**Verify**: `git grep -n 'StatePipelineExperiment\|captureLive(\|loadScenario(' -- Sources Tests` → no matches; then `swift test --filter WindowStatePayloadParityTests` → pass.

### Step 3: Remove the one-value route implementation status

Delete `RouteImplementationStatusDTO` and both DTO properties, remove every `implementationStatus: .implemented` argument, and stop copying it in `RouteRegistry.publicRoute`. Update `APIDocumentationTests` to encode `RouteListResponse` and assert every route object lacks the `implementationStatus` key while retaining `id`, `method`, `path`, `request`, and `response`.

**Verify**: `git grep -n 'implementationStatus\|RouteImplementationStatusDTO' -- Sources Tests README.md skills || true` → no matches; then `swift test --filter APIDocumentationTests` → pass.

### Step 4: Make AXHelpers the single raw AX conversion owner

Move/merge raw `intAttribute`, `numberAttribute`, `rectAttribute`, and a validated `rangeAttribute` into `AXHelpers`. Upgrade the canonical string/range behavior so no semantics are lost:

```swift
static func stringAttribute(_ element: AXUIElement, attribute: CFString) -> String? {
    guard let value = copyAttributeValue(element, attribute: attribute) else { return nil }
    if let string = value as? String { return string }
    if let url = value as? URL { return url.absoluteString }
    if let url = value as? NSURL { return url.absoluteString }
    return nil
}
static func rangeValue(from value: CFTypeRef?) -> CFRange? {
    guard let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
    let axValue = unsafeDowncast(value, to: AXValue.self)
    var range = CFRange()
    guard AXValueGetType(axValue) == .cfRange, AXValueGetValue(axValue, .cfRange, &range),
          range.location >= 0, range.length >= 0,
          range.location < Int.max / 4, range.length < Int.max / 4 else { return nil }
    return range
}
static func rangeAttribute(_ element: AXUIElement, attribute: CFString) -> CFRange? {
    rangeValue(from: copyAttributeValue(element, attribute: attribute))
}
```

Replace raw wrapper calls with `AXHelpers`. Keep action-domain methods such as coercion, `performAction`, setters, traversal policy, labels, text snapshots, and `selectedTextRange` in `AXActionRuntimeSupport`; make its range DTO methods delegate to `AXHelpers.rangeAttribute`. Delete the duplicate raw methods from Actions.

**Verify**: `git grep -n 'static func \(copyAttributeValue\|stringAttribute\|boolAttribute\|elementAttribute\|elementArrayAttribute\)' -- Sources/BackgroundComputerUse/Actions/Shared/AXActionRuntimeSupport.swift || true` → no matches.

### Step 5: Add focused regression tests and finish

In `StatePipelineFixtureStoreTests`, round-trip a minimal fixture through a temporary path, assert sorted/decodable output, and assert invalid JSON throws `invalidFixture`. In `AXHelpersTests`, construct `.cfRange` AXValues and assert valid ranges decode while negative and `Int.max / 4` values are rejected. Keep Swift Testing style (`import Testing`, `@Test`, `#expect`, `#require`) and clean temporary files with `defer`.

**Verify**: `swift test --filter StatePipelineFixtureStoreTests && swift test --filter AXHelpersTests` → both suites pass; then `swift test` → all tests pass.

## Test plan

- Preserve the existing fixture replay parity assertions in `WindowStatePayloadParityTests` and plan 004’s recorded corpus tests.
- Add store round-trip, invalid fixture, valid range, negative location/length, and implausibly large range cases.
- Update `APIDocumentationTests` to verify JSON key omission, not merely Swift property absence.
- Run the full suite once after all three debt cuts; no live app, permissions, or `script/start.sh` is needed.

## Done criteria

- [ ] `StatePipeline.swift` is the sole production live-capture root; fixture load/save/replay use dedicated types and plan 004 callers migrated.
- [ ] `git grep 'StatePipelineExperiment\|captureLive(\|loadScenario(' -- Sources Tests` returns no matches.
- [ ] Encoded `/v1/routes` omits `implementationStatus`; its enum/assignments are gone; AXHelpers solely owns tested raw AX conversion.
- [ ] No action behavior or AXPipelineV2 fixture/contract shape changed.
- [ ] OpenSpec validation passes when available and `swift test` exits 0.
- [ ] Only in-scope files plus `plans/README.md` status are modified.

## STOP conditions

Stop and report back (do not improvise) if:
- Plan 004 is not complete, or its exporter/corpus does not use the APIs described above.
- Repository-wide search finds a live caller of `captureLive` or `loadScenario` after plan 004.
- Moving replay requires changing serialized fixture fields or AXPipelineV2 public names.
- Removing `implementationStatus` requires a compatibility shim; this plan requires a clean cutover.
- Canonicalizing AX helpers changes nil/error behavior beyond URL support and strict range validation.
- A focused verification fails twice or an out-of-scope file is required.

## Maintenance notes

- Future fixture tooling must keep live capture in `StatePipeline`, replay in `StatePipelineFixtureReplayer`, filesystem encoding in `StatePipelineFixtureStore`, and raw AX type checks in `AXHelpers`.
- Reviewer focus: plan-004 caller migration, exact replay parity, URL string conversion, and preservation of the stricter CFRange bounds.
