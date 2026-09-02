# Plan 026: Make RouteRegistry drive HTTP dispatch

> **Executor instructions**: Follow this plan step by step. Run every verification command and confirm its expected result before continuing. If a STOP condition occurs, stop and report; do not improvise. When done, update this plan's row in `plans/README.md` unless a reviewer owns the index.
>
> **Drift check (run first)**: `git diff --stat 0110ffb..HEAD -- Sources/BackgroundComputerUse/API/Router.swift Sources/BackgroundComputerUse/API/RouteRegistry.swift Tests/BackgroundComputerUseTests/APIDocumentationTests.swift Tests/BackgroundComputerUseTests/ActivityControlTests.swift openspec/project.md`
> Compare the excerpts below with live code. The known Router authorization fix is expected; any unrelated dispatch/guard drift is a STOP condition.
>
> **Required baseline check**: Run `git status --short`. The baseline fixes in `API/Router.swift`, `App/BackgroundComputerUseControlBridge.swift`, `BackgroundComputerUseControlShared/CodeSignatureIdentity.swift`, `Runtime/RuntimeExecutionQueue.swift`, `Actions/TypeText/AdaptiveTextDispatcher.swift`, `StatePipeline/InteractionToken.swift`, `Runtime/Process/BoundedProcessRunner.swift`, `skills/background-computer-use/scripts/bcu-request.py`, `InteractionTokenTests.swift`, and `RuntimeExecutionQueueTests.swift` must be committed or still locally modified. STOP if any was lost; never reset operator work.

## Status

- **Priority**: P3
- **Effort**: M
- **Risk**: MED
- **Depends on**: none
- **Category**: tech-debt
- **Planned at**: commit `0110ffb`, 2026-09-02

## Why this matters

The runtime advertises routes from `RouteRegistry`, but Router independently repeats every method/path and request DTO in a 24-arm switch. Descriptor-count tests can pass while `/v1/routes` advertises an unwired endpoint or Router decodes a different DTO. A once-built lookup table will derive matching keys from registry descriptors and attach typed handlers with machine-checked parity, while leaving the security/control guard order and explicit error mapping untouched.

## Current state

- `RouteID` declares 24 routes, while descriptors separately provide their HTTP identity:

```swift
// API/RouteRegistry.swift:3-28,31-49
enum RouteID: String, CaseIterable {
    case health
    case bootstrap
    case routes
    case listApps = "list_apps"
    case listWindows = "list_windows"
// lines 9-27 omitted
static let descriptors: [RouteDescriptorDTO] = [
    RouteDescriptorDTO(
        id: RouteID.health.rawValue,
        method: "GET",
        path: "/health",
```

- Registry documentation then switches on the ID again. It supplies strict-decode field names from the request schema:

```swift
// API/RouteRegistry.swift:444-451,488-503
static func descriptor(for routeID: RouteID) -> RouteDescriptorDTO {
    descriptors.first(where: { $0.id == routeID.rawValue })!
}
static func requestFieldNames(for routeID: RouteID) -> [String] {
    (requestSchema(for: routeID.rawValue)?.fields ?? []).map(\.name)
}
private static func requestSchema(for routeID: String) -> RouteBodySchemaDTO? {
    switch routeID {
    case RouteID.health.rawValue, RouteID.bootstrap.rawValue, RouteID.routes.rawValue:
        return nil
    case RouteID.listApps.rawValue:
        return json([])
```

- Router performs global host/auth/control-read guards, then repeats method/path and typed service bindings:

```swift
// API/Router.swift:90,126-142
switch (request.method, request.path) {
case (.post, "/v1/list_apps"):
    return decodeAndExecute(
        ListAppsRequest.self,
        routeID: .listApps,
        from: request,
        work: { _ in services.listApps() }
    )
case (.post, "/v1/list_windows"):
    return decodeAndExecute(
        ListWindowsRequest.self,
        routeID: .listWindows,
        from: request,
        work: { payload in try services.listWindows(payload) }
    )
```

- The generic execution seam already exists and must be reused, not reimplemented:

```swift
// API/Router.swift:351-356
private func decodeAndExecute<Request: Decodable>(
    _: Request.Type,
    routeID: RouteID,
    from request: HTTPRequest,
    work: (Request) throws -> some Encodable
) -> HTTPResponse
```

- Its exact guard/processing order is load-bearing (`Router.swift:357-526`):
  1. create request ID;
  2. reject unknown top-level fields (including script audit handling);
  3. for action routes, require `mutationAllowed`;
  4. for `run_script`, require `arbitraryScriptAllowed`;
  5. authorize the requested window (except `launch_app`);
  6. call `sessionLimiter.beforeAction()` for rate limiting;
  7. acquire the named session, with `defer` release;
  8. decode JSON;
  9. execute service, publish activity, record artifact;
  10. map decode/service errors.

  Together with the outer host → auth → control-read order, this sequence must remain byte-for-byte in `decodeAndExecute` except access-control changes needed for binding.

- Unknown method/path returns the explicit 404 at `Router.swift:334-347`. `errorResponse(for:routeID:requestID:)` starts at `Router.swift:822` and is an intentional associated-error switch; it is not part of this refactor.
- Existing API documentation coverage only checks count parity:

```swift
// Tests/APIDocumentationTests.swift:8-18
@Test
func everyPublicRouteIncludesOperationalDocumentation() {
    let routes = RouteRegistry.publicRoutes()
    #expect(routes.count == RouteID.allCases.count)
    for route in routes {
        #expect(!route.usage.whenToUse.isEmpty)
        #expect(!route.errors.isEmpty)
    }
}
```

- `openspec/project.md:17-23` currently tells maintainers to add a Router switch arm as wiring point 3. Update that rule after the clean cutover.

## Commands you will need

| Purpose | Command | Expected on success |
|---|---|---|
| Baseline | `git status --short` | operator work is preserved |
| Dispatch parity | `swift test --filter RouteDispatchParityTests` | selected tests pass |
| Guard order | `swift test --filter ActivityControlTests` | selected tests pass |
| API docs | `swift test --filter APIDocumentationTests` | selected tests pass |
| Each route migration | `swift test` | full suite passes before next route |
| Final source check | `git grep -n 'switch (request.method, request.path)' -- Sources/BackgroundComputerUse/API/Router.swift` | no matches |

## Scope

**In scope** (only these files):
- `Sources/BackgroundComputerUse/API/RouteRegistry.swift`
- `Sources/BackgroundComputerUse/API/Router.swift`
- Create `Tests/BackgroundComputerUseTests/RouteDispatchParityTests.swift`.
- `Tests/BackgroundComputerUseTests/APIDocumentationTests.swift`
- `Tests/BackgroundComputerUseTests/ActivityControlTests.swift`
- `openspec/project.md`

**Out of scope**:
- `RuntimeServices`, route services, public request/response DTO fields, route paths/methods, or execution-lane policy.
- Replacing `RouteID`, rewriting APIDocumentation prose, or generating schemas through reflection.
- Tabling `errorResponse(for:)`; its associated error patterns are clearer as a switch.
- Changing auth, control, authorization, rate/session limiting, script audit, artifact, or activity semantics.
- Live smoke, app installation, or signed runtime launch.

## Git workflow

- Branch: `advisor/026-route-table-dispatch`.
- Commit infrastructure/tests, then route migrations in reviewable groups only after every individual route passes `swift test`; final commit example: `refactor: dispatch routes from registry table`.
- Do not push/open a PR without operator instruction. Do not reset pre-existing changes.

## Steps

### Step 1: Add typed schema metadata and type-erased definitions

In `RouteRegistry.swift`, add internal types:

```swift
struct RouteKey: Hashable {
    let method: String
    let path: String
}
typealias RouteHandler = (HTTPRequest, RouterContext) throws -> HTTPResponse
struct BoundRoute {
    let requestTypeID: ObjectIdentifier?
    let requestTypeName: String?
    let handler: RouteHandler
}
struct RouteRequestSchema {
    let dtoTypeID: ObjectIdentifier
    let dtoTypeName: String
    let body: RouteBodySchemaDTO
}
struct RouteDefinition {
    let id: RouteID
    let descriptor: RouteDescriptorDTO
    let requestSchema: RouteRequestSchema?
    let responseSchema: RouteBodySchemaDTO
    let handler: RouteHandler
    let requestTypeID: ObjectIdentifier?
    var key: RouteKey { RouteKey(method: descriptor.method, path: descriptor.path) }
}
```

Change request-schema branches to pair each POST schema with its concrete request DTO via a helper such as `typed(ListWindowsRequest.self, json([...]))`; GET system routes remain nil. `publicRoute` exposes only `.body`. Do not add Swift type names to public JSON.

Add `RouteRegistry.validationIssue(descriptors:boundRoutes:) -> RouteRegistryValidationIssue?` for missing/duplicate IDs, duplicate keys, and request-type/schema mismatches. Tests call it directly. `definitions(boundRoutes:)` preconditions that validation returns nil, then iterates `RouteID.allCases`; both type IDs are nil for GET. The returned definitions are the sole dispatch source.

**Verify**: `swift test --filter APIDocumentationTests` → existing public route/schema tests pass unchanged.

### Step 2: Add bind helpers and build the table once

Make `Router` a `final class` so it can initialize an immutable-after-init handler table without a lazy-property race. Give `routeTable` an empty declaration default, initialize all existing stored dependencies, then eagerly assign definitions/table before `init` returns. Handlers capture `[unowned self]`; they are owned by Router and never escape it.

Add overloads whose output includes runtime request-type identity:

```swift
private func bind<Response: Encodable>(
    _ routeID: RouteID,
    execute: @escaping (RouterContext) throws -> Response
) -> (RouteID, BoundRoute) // GET; request type nil

private func bind<Request: Decodable, Response: Encodable>(
    _ routeID: RouteID,
    _ requestType: Request.Type,
    execute: @escaping (Request) throws -> Response
) -> (RouteID, BoundRoute) {
    (routeID, BoundRoute(
        requestTypeID: ObjectIdentifier(Request.self),
        requestTypeName: String(reflecting: Request.self),
        handler: { [unowned self] request, _ in
            self.decodeAndExecute(requestType, routeID: routeID, from: request, work: execute)
        }
    ))
}
```

Build `[RouteID: BoundRoute]` using these helpers and existing `services` methods; combine through `RouteRegistry.definitions`, then create `[RouteKey: RouteDefinition]` once. Do not construct a table per request.

**Verify**: `swift test --filter RouteDispatchParityTests` → compile succeeds and initial infrastructure tests pass.

### Step 3: Lock parity and guard order with tests

`RouteDispatchParityTests` must assert: 24 unique RouteIDs, descriptor IDs, definition IDs, and method/path keys; every descriptor key resolves; every definition has a descriptor; GET handlers have nil request/schema type; every POST handler type ID/name equals its typed request-schema DTO; duplicate/missing bindings fail the builder deterministically. Dispatch GET `/health`, `/v1/bootstrap`, `/v1/routes`, and a wrong-method request to prove 200/200/200/404 without live AX state.

Extend `ActivityControlTests` with an event-recording policy to prove outer order (unauthorized never calls `readAllowed`; stopped control never dispatches) and inner order (unknown-field rejection occurs before mutation policy; mutation pause before window authorization; window denial before rate/session consumption). Reuse its injected `RouterControlPolicy` and request helper.

**Verify**: `swift test --filter RouteDispatchParityTests && swift test --filter ActivityControlTests` → all parity and ordering tests pass.

### Step 4: Migrate every route in explicit order

During migration, table lookup runs first and an unmigrated request temporarily falls through to the old switch. For each item below: add exactly one typed binding, remove exactly that switch arm, run `swift test`, and continue only on success. Order:

1. `health`; 2. `bootstrap`; 3. `routes`;
4. `list_apps`; 5. `list_windows`; 6. `cursor_feedback`;
7. `get_window_state`; 8. `find_elements`; 9. `wait_for`; 10. `read_text`;
11. `run_script`; 12. `annotate_window`; 13. `launch_app`;
14. `click`; 15. `scroll`; 16. `perform_secondary_action`;
17. `drag`; 18. `resize`; 19. `set_window_frame`;
20. `type_text`; 21. `paste`; 22. `press_key`; 23. `set_value`; 24. `select_text`.

The first three use the GET overload and preserve their current inline response bodies. Every POST uses its exact DTO from the old arm and the same `services` call. Do not reorder or edit `decodeAndExecute` guards.

**Verify**: after **each numbered route**, `swift test` → all tests pass before the next route is moved.

### Step 5: Remove legacy dispatch and update wiring documentation

Replace the temporary fallback with one lookup after the three outer guards:

```swift
let key = RouteKey(method: request.method.rawValue, path: request.path)
guard let definition = routeTable[key] else { return routeNotFoundResponse(for: request) }
do { return try definition.handler(request, context) }
catch { return errorResponse(for: error, routeID: definition.id, requestID: UUID().uuidString) }
```

Extract the existing 404 body to `routeNotFoundResponse`; do not change JSON. Keep `decodeAndExecute`, `isActionRoute`, and `errorResponse` switches. Update `openspec/project.md` wiring point 3: a route gets one typed binding; method/path comes from registry metadata; parity tests enforce descriptor/handler/schema agreement.

**Verify**: `git grep -n 'switch (request.method, request.path)' -- Sources/BackgroundComputerUse/API/Router.swift` → no match; `swift test --filter RouteDispatchParityTests` → pass.

### Step 6: Run final checks

Review the diff only for accidental guard/DTO/service changes, then run focused and full suites.

**Verify**: `swift test --filter ActivityControlTests && swift test --filter APIDocumentationTests && swift test` → all tests pass.

## Test plan

- New parity suite tests both directions of descriptor/handler coverage, unique keys, and handler DTO identity against typed request-schema metadata.
- System-route dispatch tests avoid Accessibility/Screen Recording dependencies.
- ActivityControl ordering tests protect the exact host/auth/read → unknown-fields/mutation/script/window/rate/session/decode/execute sequence.
- Existing strict-decode and API documentation suites ensure request fields/public JSON remain unchanged.
- Full suite runs after each route migration as explicitly required; no live smoke is authorized.

## Done criteria

- [ ] Router has no method/path switch, builds one dictionary at initialization, and all 24 descriptor keys resolve one-to-one.
- [ ] Every POST handler's request type matches its schema DTO; GET system routes have neither.
- [ ] Route methods/paths/schemas/services/JSON/404 and exact guard order are unchanged and tested.
- [ ] `errorResponse(for:)` and `isActionRoute` remain explicit switches.
- [ ] `openspec/project.md` describes the new wiring and `swift test` passes after each migration and at completion.
- [ ] Only in-scope files plus the plan index status changed.

## STOP conditions

Stop and report if converting Router to a final class introduces a strict-concurrency diagnostic not solvable without changing guard/service semantics; any descriptor has duplicate method/path; a request DTO cannot be paired with its current schema; a route requires changing RuntimeServices or public JSON; guard-order tests expose pre-existing drift; or a route's full suite fails twice.

## Maintenance notes

- Adding a route still requires a public contract, RuntimeServices/facade wiring, and one typed bound definition; it must never add a Router method/path branch.
- Keep the request type identity internal. `/v1/routes` remains schema-focused and must not expose Swift names.
- Reviewer focus: eager one-time table construction, no retain/lazy race, exact guard order, one-to-one parity, and keeping associated-error switches explicit.
