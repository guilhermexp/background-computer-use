# Plan 014: Probe private macOS symbols once and degrade unsupported lanes without crashing

> **Executor instructions**: Follow this plan step by step. Run every verification command and confirm the expected result before moving to the next step. If a STOP condition occurs, stop and report; do not improvise. Update this plan's row in `plans/README.md` when done unless a reviewer owns the index.
>
> **Drift check (run first)**: `git diff --stat 0110ffb..HEAD -- Sources/BackgroundComputerUse/Runtime Sources/BackgroundComputerUse/Contracts/BootstrapContracts.swift Sources/BackgroundComputerUse/App/RuntimeBootstrap.swift Sources/BackgroundComputerUse/API Sources/BackgroundComputerUse/Actions/Click Sources/BackgroundComputerUse/Actions/Shared/NativeWindowServerPreparation.swift Sources/BackgroundComputerUse/AXFoundation Sources/BackgroundComputerUse/Screenshot/CGWindowCaptureService.swift Tests/BackgroundComputerUseTests openspec/changes/private-symbol-capabilities`
> Compare Current state excerpts with live code if an in-scope path changed. Run `git status --short` and STOP if the planned-at working-tree fixes named in plans 012/README are neither modified nor committed.

## Status

- **Priority**: P1
- **Effort**: M
- **Risk**: MED
- **Depends on**: none
- **Category**: migration
- **Planned at**: commit `0110ffb`, 2026-09-02

## Why this matters

A macOS update can rename or remove a private WindowServer symbol. Today the first coordinate click then calls `fatalError`, taking down the whole loopback runtime and every unrelated route. A startup capability matrix lets semantic AX clicks continue, rejects only unavailable native lanes as `unsupported`, and tells agents what the current OS/runtime can actually do before they act.

## Current state

- `NativeBackgroundClickTransport.swift:390-410` loads SkyLight and six required symbols with process-fatal branches:

```swift
static let loadedSkyLight: Bool = {
    guard dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY) != nil else {
        fatalError("Required SkyLight private framework could not be loaded for native background click transport.")
    }
    return true
}()
```

- The same loader's symbols at `:398-403` are `CGSMainConnectionID`, `CGSGetWindowOwner`, `CGSGetConnectionPSN`, `SLEventPostToPid`, `SLEventSetIntegerValueField`, and `CGEventSetWindowLocation`.
- `NativeWindowServerPreparation.swift:32-41,56-72` independently treats SkyLight, `GetProcessForPID`, and `SLPSPostEventRecordTo` as optional and falls back to pid event posting. This is a conflicting policy for the same dependency class.
- `AXHelpers.swift:6-14,158-168` optionally resolves `_AXUIElementGetWindow`; `AXAttachedSurfaceDiscovery.swift:93-97` consumes it for attached-surface window IDs.
- `CGWindowCaptureService.swift:17-32,81-88,212-229` optionally resolves `CGWindowListCreateImage` from CoreGraphics and already returns `.symbolUnavailable` rather than trapping.
- Repository-wide `dlopen(`/`dlsym(` inventory found only those four files. Repository-wide search found no `@_silgen_name`. Do not invent additional symbols.
- `RouteRegistry.swift:289-301` always advertises `/v1/click` as implemented and says it uses the SLPS/SLEvent fallback, regardless of availability. Live Chromium/Electron testing also showed pid-directed CGEvent mouse delivery is discarded, so semantic AX must remain independent and preferred when native capability degrades.
- `ClickRouteService.swift:1460-1523` catches every coordinate transport error as `.effectNotVerified` with `failureDomain: .transport`; it cannot report a missing capability. `ClickActionContracts.swift:143-170` has no `missingCapability` field.
- `BootstrapContracts.swift:99-108` publishes contract version, URL, auth, permissions, instructions, guide, and routes, but no capability matrix. Router constructs it at `Router.swift:100-115`; `RuntimeBootstrap.swift:31-49` writes the manifest independently.
- Startup wiring is `RuntimeBootstrap.swift:13-18` → `LoopbackServer.swift:16-18` → `Router.swift:53-67` → `RuntimeServices.swift:26-47` → `ClickRouteService.swift:207-221`.
- `openspec/project.md:13-15` says Contracts is a leaf and `/v1/routes` is contract truth. Lines 25-29 require letter-prefixed change slugs and strict validation. Preserve the read-act-read rule: a dispatched transport is never proof of effect.

## Commands you will need

| Purpose | Command | Expected on success |
|---|---|---|
| Symbol inventory | `grep -R "dlsym(\|@_silgen_name" Sources` | only centralized loader after cutover; no `@_silgen_name` |
| Fatal-path audit | `grep -R "fatalError.*\(SkyLight\|symbol\)\|loadRequired" Sources/BackgroundComputerUse` | no output after cutover |
| Focused tests | `swift test --filter PrivateSymbolCapabilitiesTests` | exit 0 |
| OpenSpec | `command -v openspec` then `openspec validate private-symbol-capabilities --strict` | validation exits 0 when CLI exists; otherwise record skipped |
| Build/full gate | `swift build && swift test` | both exit 0; 391 baseline plus new tests |

## Scope

**In scope** (only these files):
- `Sources/BackgroundComputerUse/Runtime/PrivateSymbolCapabilities.swift` (create)
- `Sources/BackgroundComputerUse/Contracts/BootstrapContracts.swift`
- `Sources/BackgroundComputerUse/App/RuntimeBootstrap.swift`
- `Sources/BackgroundComputerUse/API/LoopbackServer.swift`
- `Sources/BackgroundComputerUse/API/Router.swift`
- `Sources/BackgroundComputerUse/API/RouteRegistry.swift`
- `Sources/BackgroundComputerUse/Runtime/RuntimeServices.swift`
- `Sources/BackgroundComputerUse/Actions/Click/ClickRouteService.swift`
- `Sources/BackgroundComputerUse/Actions/Click/NativeBackgroundClickTransport.swift`
- `Sources/BackgroundComputerUse/Actions/Shared/NativeWindowServerPreparation.swift`
- `Sources/BackgroundComputerUse/AXFoundation/AXHelpers.swift`
- `Sources/BackgroundComputerUse/AXFoundation/AXAttachedSurfaceDiscovery.swift`
- `Sources/BackgroundComputerUse/Screenshot/CGWindowCaptureService.swift`
- `Tests/BackgroundComputerUseTests/PrivateSymbolCapabilitiesTests.swift` (create)
- `Tests/BackgroundComputerUseTests/APIDocumentationTests.swift`
- `openspec/changes/private-symbol-capabilities/proposal.md` (create)
- `openspec/changes/private-symbol-capabilities/tasks.md` (create)
- `openspec/changes/private-symbol-capabilities/specs/runtime-capabilities/spec.md` (create)
- `plans/README.md` (status only)

**Out of scope**: adding a replacement private symbol; changing click fallback order or verification thresholds; disabling the whole click route; changing health; exposing raw addresses; logging symbol pointers; notarization/deployment work; live signed smoke without operator authorization.

## Git workflow

- Branch: `advisor/014-private-symbol-capability-probe`
- Commit units: `spec: define private symbol capabilities`, `fix: make private symbol loading nonfatal`, `feat: publish runtime capability matrix`.
- Do not push or open a PR.

## Steps

### Step 1: Record the public contract change in OpenSpec

Create change slug `private-symbol-capabilities`. `proposal.md` must state: **Why** private symbol loss currently crashes coordinate click; **What Changes** startup probing, bootstrap matrix, route notes, and unsupported missing-capability responses; **Impact** additive bootstrap/click response fields and no change to semantic AX dispatch. `spec.md` must contain:

```markdown
## ADDED Requirements
### Requirement: Runtime private-symbol capabilities are observable
The runtime SHALL probe every dynamically loaded macOS symbol once and publish its availability without exposing addresses.
#### Scenario: A private symbol is absent
- **WHEN** bootstrap is requested after startup on an OS where a probed symbol is absent
- **THEN** `privateSymbolCapabilities` identifies that symbol with `available: false`
#### Scenario: Coordinate click lacks a required capability
- **WHEN** click requires native coordinate transport and one required capability is absent
- **THEN** click returns `classification: unsupported`, `failureDomain: unsupported`, and the stable `missingCapability` name without dispatching or terminating the runtime
#### Scenario: Semantic click does not need native private symbols
- **WHEN** an exact semantic AX click is eligible while native coordinate capabilities are absent
- **THEN** the semantic AX lane remains eligible and follows normal reread verification
```

`tasks.md` must checklist probe/DTO/wiring, nonfatal consumers, route docs/tests, and a final task containing `swift test`, strict OpenSpec validation, and a live-smoke result. The live item must say `SKIPPED: operator authorization required` unless the operator separately authorizes launching the signed app.

**Verify**: `if command -v openspec >/dev/null; then openspec validate private-symbol-capabilities --strict; else echo "SKIP: openspec CLI unavailable"; fi` → validation exits 0 or the exact SKIP line appears.

### Step 2: Add failing probe, route-policy, and bootstrap tests

Create `PrivateSymbolCapabilitiesTests.swift`. Model style on `APIDocumentationTests.swift:23-42`: JSON-encode and inspect dictionaries with `#require`. Add an injectable loader that opens both framework paths but returns nil for one requested symbol:

```swift
private func capabilities(missing name: String) -> PrivateSymbolCapabilities {
    let loader = DynamicSymbolLoader(
        open: { _ in UnsafeMutableRawPointer(bitPattern: 1) },
        resolve: { _, candidate in candidate == name ? nil : UnsafeMutableRawPointer(bitPattern: 1) }
    )
    return PrivateSymbolCapabilities.probe(loader: loader)
}

@Test func absentCoordinateSymbolDisablesOnlyNativeCoordinateLane() {
    let value = capabilities(missing: "SLEventPostToPid")
    #expect(value.dto.first { $0.name == "SLEventPostToPid" }?.available == false)
    #expect(ClickCapabilityPolicy.missingCapability(for: .nativeBackgroundCoordinate, capabilities: value) == "SLEventPostToPid")
    #expect(ClickCapabilityPolicy.missingCapability(for: .semanticAX, capabilities: value) == nil)
}
```

Also construct `Router(auth: .disabled, privateSymbolCapabilities: value)`, send `GET /v1/bootstrap`, and assert JSON `privateSymbolCapabilities` contains the false entry. Assert `RouteRegistry.publicRoutes(capabilities: value)` gives click a note naming unavailable native coordinate capability while retaining `implementationStatus == .implemented`. Add a pure classification test expecting `.unsupported`, `.unsupported`, and the same missing name.

**Verify**: `swift test --filter PrivateSymbolCapabilitiesTests` → fails to compile because the probe, DTO field, injection, and policy do not exist.

### Step 3: Implement one immutable startup probe

Create `PrivateSymbolCapabilities.swift` with imports for ApplicationServices, Carbon.HIToolbox, CoreGraphics, Darwin, and Foundation. Move all C function typealiases from the three consumers into this file. Use these exact signatures, loader, and capability DTO shape:

```swift
struct DynamicSymbolLoader {
    let open: (String) -> UnsafeMutableRawPointer?
    let resolve: (UnsafeMutableRawPointer?, String) -> UnsafeMutableRawPointer?
    static let system = DynamicSymbolLoader(
        open: { dlopen($0, RTLD_LAZY) },
        resolve: { handle, name in dlsym(handle ?? UnsafeMutableRawPointer(bitPattern: -2), name) }
    )
}

typealias AXUIElementGetWindowFunction = @convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError
typealias GetProcessForPIDFn = @convention(c) (pid_t, UnsafeMutableRawPointer) -> Int32
typealias SLPSPostEventRecordToFn = @convention(c) (UnsafeRawPointer, UnsafePointer<UInt8>) -> Int32
typealias CGSMainConnectionIDFn = @convention(c) () -> Int32
typealias CGSGetWindowOwnerFn = @convention(c) (Int32, UInt32, UnsafeMutablePointer<Int32>?) -> Int32
typealias CGSGetConnectionPSNFn = @convention(c) (Int32, UnsafeMutablePointer<ProcessSerialNumber>?) -> Int32
typealias SLEventPostToPidFn = @convention(c) (pid_t, CGEvent) -> Void
typealias SLEventSetIntegerValueFieldFn = @convention(c) (CGEvent, UInt32, Int64) -> Void
typealias CGEventSetWindowLocationFn = @convention(c) (CGEvent, CGPoint) -> Void
typealias CGWindowListCreateImageFn = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?

public struct PrivateSymbolCapabilityDTO: Encodable, Sendable {
    public let name: String
    public let available: Bool
}

struct PrivateSymbolCapabilities: @unchecked Sendable {
    static let current = probe(loader: .system)
    let skyLightLoaded: Bool
    let coreGraphicsLoaded: Bool
    let axUIElementGetWindow: AXUIElementGetWindowFunction?
    let getProcessForPID: GetProcessForPIDFn?
    let slpsPostEventRecordTo: SLPSPostEventRecordToFn?
    let cgsMainConnectionID: CGSMainConnectionIDFn?
    let cgsGetWindowOwner: CGSGetWindowOwnerFn?
    let cgsGetConnectionPSN: CGSGetConnectionPSNFn?
    let slEventPostToPid: SLEventPostToPidFn?
    let slEventSetIntegerValueField: SLEventSetIntegerValueFieldFn?
    let cgEventSetWindowLocation: CGEventSetWindowLocationFn?
    let cgWindowListCreateImage: CGWindowListCreateImageFn?
    let dto: [PrivateSymbolCapabilityDTO]
}
```

`probe(loader:)` opens SkyLight and CoreGraphics once, resolves each named function to an optional typed pointer with `unsafeBitCast` only when nonnil, and emits the DTO in the exact inventory order from Current state. If a framework fails to open, leave all of its pointers nil; do not fall through to the default process handle. Use the default handle only for `_AXUIElementGetWindow`. Include framework availability as `SkyLight.framework` and `CoreGraphics.framework`. Never retain or encode pointer values. `nativeCoordinateClickMissingCapability` must return the first absent dependency in inventory order.

**Verify**: `swift test --filter PrivateSymbolCapabilitiesTests` → probe availability test passes; bootstrap/policy tests still fail.

### Step 4: Replace every local loader with the shared optional pointer

Delete `NativeClickSymbols`, `loadRequired`, and both local `loadedSkyLight` policies. `NativeBackgroundClickTransport` and `NativeWindowServerRoutingResolver` receive `PrivateSymbolCapabilities`; they guard required pointers before use and throw `ClickTransportError.missingCapability(String)` before any focus/event dispatch. `NativeWindowServerPreparation` keeps its two-argument public-internal entry points for `BackgroundTextPreparation`, but delegates to an injectable overload with `.current` and returns its current non-prepared result when a capability is absent. `AXHelpers.privateGetWindow` becomes `PrivateSymbolCapabilities.current.axUIElementGetWindow`; attached-surface behavior remains optional. `CGWindowCaptureService.resolveCreateImage()` returns `.current.cgWindowListCreateImage`.

**Verify**: `grep -R "fatalError.*\(SkyLight\|symbol\)\|loadRequired\|dlsym(" Sources/BackgroundComputerUse/Actions Sources/BackgroundComputerUse/AXFoundation Sources/BackgroundComputerUse/Screenshot` → no output; `swift build` → exit 0.

### Step 5: Gate only native coordinate click and return an honest response

Add `ClickCapabilityPolicy` with two lane cases used by production and tests:

```swift
enum ClickCapabilityLane { case semanticAX, nativeBackgroundCoordinate }
enum ClickCapabilityPolicy {
    static func missingCapability(for lane: ClickCapabilityLane, capabilities: PrivateSymbolCapabilities) -> String? {
        switch lane {
        case .semanticAX: nil
        case .nativeBackgroundCoordinate: capabilities.nativeCoordinateClickMissingCapability
        }
    }
}
```

Inject capabilities through `RuntimeBootstrap` → `LoopbackServer` → `Router` → `RuntimeServices` → `ClickRouteService`; defaults may use `.current`, but production bootstrap must evaluate and pass one value. Before resolving routing or preparing the cursor for coordinate dispatch, return an outcome with `classification: .unsupported`, `failureDomain: .unsupported`, `missingCapability`, `didDispatch: false`, and no reread. Preserve semantic planning first. Add `public let missingCapability: String?` to `ClickResponse`, thread it through the single response factory with default nil, and document it in `clickActionResponse()`.

**Verify**: `swift test --filter PrivateSymbolCapabilitiesTests` → missing native lane maps to unsupported and semantic lane remains ungated.

### Step 6: Publish the matrix in bootstrap and capability-aware route notes

Add `public let privateSymbolCapabilities: [PrivateSymbolCapabilityDTO]` to `BootstrapResponse`; do not add pointers or it to `/health`. Router uses its injected probe. Keep `RouteRegistry.publicRoutes(capabilities: PrivateSymbolCapabilities = .current)` source-compatible and append a click note stating either `Native background coordinate capability is available.` or `Native background coordinate capability is unavailable: \(missingCapability). Semantic AX click remains available.` Keep click route implemented because semantic AX remains real. Update bootstrap response schema at `RouteRegistry.swift:736-745` and click response schema at `:981-1010` to match DTOs exactly. The runtime manifest may include the same public matrix only if required by an already-landed plan 001 contract; otherwise leave manifest shape unchanged.

**Verify**: `swift test --filter PrivateSymbolCapabilitiesTests && swift test --filter APIDocumentationTests` → both pass; route notes and schemas match encoded DTOs.

### Step 7: Run final inventory and regression gates

**Verify**: `grep -R "dlsym(\|@_silgen_name" Sources` → every `dlsym` is in `PrivateSymbolCapabilities.swift` and no `@_silgen_name`; `swift build && swift test` → both exit 0.

## Test plan

- New suite: one missing symbol, missing SkyLight framework, all symbols available, deterministic DTO ordering, coordinate-only gate, nonfatal unsupported classification, semantic AX independence, bootstrap JSON, and click route note.
- Existing `ClickFocusEvidenceTests.swift:9-46` must still pass: its injected prepare/post closures do not require private symbols.
- Existing `APIDocumentationTests.swift:23-42` is the schema/route JSON pattern. Never invoke an invalid fake function pointer; probe tests only inspect availability.

## Done criteria

- [ ] One startup probe inventories exactly two frameworks and ten symbols; every typed pointer is optional.
- [ ] No private-symbol `fatalError`, `loadRequired`, duplicate `dlopen`, or consumer-local `dlsym` remains.
- [ ] Missing coordinate capability returns unsupported/unsupported/missing name before dispatch; semantic AX remains eligible.
- [ ] Bootstrap matrix, `/v1/routes` notes, click DTO, and RouteRegistry schemas agree.
- [ ] OpenSpec validates when installed; focused tests, build, and full suite exit 0.
- [ ] Only in-scope files plus README status changed.

## STOP conditions

Stop if inventory differs from Current state; a symbol cannot be safely represented by its current C signature; missing symbols are discovered only after a call was dispatched; semantic AX becomes dependent on private capabilities; an additive field requires an undocumented contract-version bump; plan 001 already owns a conflicting bootstrap/manifest capability shape; or any out-of-scope change is required.

## Maintenance notes

Keep stable capability names equal to symbol/framework names, never addresses. A newly added `dlsym` must join the startup probe, bootstrap matrix, route notes for affected lanes, and injected missing-symbol tests in the same change. Reviewers should focus on lane isolation: capability loss must reduce functionality, never crash the runtime and never disable unrelated semantic AX work.
