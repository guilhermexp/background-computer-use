# Plan 003: Keep README and agent examples synchronized with the route registry

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**: `git diff --stat 0110ffb..HEAD -- README.md skills/background-computer-use/SKILL.md Sources/BackgroundComputerUse/API/RouteRegistry.swift Tests/BackgroundComputerUseTests/DocumentationExamplesTests.swift docs/superpowers/plans/2026-07-27-bcu-web-reliability.md docs/parity-completion-audit.md plans/README.md`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition. Changes limited to `docs/parity-completion-audit.md`’s “Current gates” section from plan 002 do not mismatch this plan’s header-only edit.

## Status

- **Priority**: P2
- **Effort**: S
- **Risk**: LOW
- **Depends on**: none
- **Category**: docs
- **Planned at**: commit `0110ffb`, 2026-09-02

## Why this matters

BCU intentionally rejects unknown request fields, but its primary README currently sends one, while the agent skill omits a required selector. The hand-maintained route inventory has also dropped two implemented routes. Validating executable documentation against `RouteRegistry` turns these deterministic HTTP 400 failures and omissions into focused test failures, while status/fingerprint metadata prevents old evidence documents from being mistaken for current executable work.

## Current state

- README says all POST bodies are strict (`README.md:103-109`), then sends an unsupported `imageMode` to `type_text`:

  ```text
  README.md:195-198
  curl -s -X POST "$BASE/v1/type_text" \
    -H "X-Background-Computer-Use-Token: $TOKEN" \
    -H 'content-type: application/json' \
    -d '{"window":"WINDOW_ID","target":{"kind":"display_index","value":4},"text":"hello","imageMode":"path"}' | python3 -m json.tool
  ```

- The authoritative `type_text` request fields are `window`, `stateToken`, `target`, `text`, `allowOpaqueFocusedSurface`, `cursor`, `includeMenuBar`, `maxNodes`, `confirm`, and `debug`; there is no `imageMode` (`RouteRegistry.swift:639-659`). `window` and `text` are required.
- The OCR skill example omits the required window selector:

  ```text
  skills/background-computer-use/SKILL.md:91-94
  1. `POST /v1/get_window_state` with `{"includeOCR": true, "imageMode": "path"}`.
     Read `ocr.anchors[]`: each anchor carries `text`, model-facing `x`/`y`, `box`, and a ready-made
     `target` of `{"kind":"ocr_anchor","value":"ocr_..."}`. Also keep `interactionToken` from the *same*
     response.
  ```

- Registry requires the exact `window` key for that route:

  ```swift
  // Sources/BackgroundComputerUse/API/RouteRegistry.swift:517-520
  case RouteID.getWindowState.rawValue:
      return json([
          field("window", "string", required: true, "Stable window ID from list_windows."),
          field("includeMenuBar", "boolean", "Include macOS menu bar nodes in the state capture.", defaultValue: "true"),
  ```

- README’s exhaustive “Core routes” inventory (`README.md:111-134`) omits `POST /v1/launch_app` and `POST /v1/paste`. Both are implemented `RouteID` cases (`RouteRegistry.swift:3-27`) and descriptors at `RouteRegistry.swift:139-143` and `374-384`.
- The registry already exposes accepted field names to strict decode and tests:

  ```swift
  // Sources/BackgroundComputerUse/API/RouteRegistry.swift:448-452
  /// Documented top-level request field names for a route, in declaration order.
  /// Source of truth for strict request decoding (rejecting unknown top-level fields).
  static func requestFieldNames(for routeID: RouteID) -> [String] {
      (requestSchema(for: routeID.rawValue)?.fields ?? []).map(\.name)
  }
  ```

- Required flags are available on each internal `RouteFieldDTO`, but no parallel registry accessor exists. Add one by filtering the same private schema; do not duplicate required-field lists in the test.
- `APIDocumentationTests.swift:8-19` shows the repository convention: `RouteRegistry.publicRoutes()`, `RouteID.allCases`, Swift Testing `@Test`, `#expect`, and `#require` under `@testable import BackgroundComputerUse`.
- Tests need no SwiftPM resource declaration. From `Tests/BackgroundComputerUseTests/DocumentationExamplesTests.swift`, three `deletingLastPathComponent()` calls on `URL(fileURLWithPath: #filePath)` resolve the repository root.
- `docs/superpowers/plans/2026-07-27-bcu-web-reliability.md:1-22` still looks executable and all task boxes are unchecked, although commit `1ebacd4` added that plan and the corresponding web-reliability implementation in the same commit.
- `docs/parity-completion-audit.md:1-5` has only a date before mutable proof claims; its latest content is at commit `0110ffb`.
- Contract doctrine: “`GET /v1/routes` (RouteRegistry + APIDocumentation) é a fonte de verdade do contrato para o agente. Todo campo de request/response deve estar documentado lá e bater com o DTO real.” (`openspec/project.md:15`). This plan makes human/agent examples flow from that source of truth.
- This plan assumes all post-`0110ffb` working fixes named in plan 001 are present; stop if the prerequisite check emits `MISSING`.

## Commands you will need

| Purpose | Command | Expected on success |
|---|---|---|
| Check prerequisites | `for f in Sources/BackgroundComputerUse/API/Router.swift Sources/BackgroundComputerUse/App/BackgroundComputerUseControlBridge.swift Sources/BackgroundComputerUseControlShared/CodeSignatureIdentity.swift Sources/BackgroundComputerUse/Runtime/RuntimeExecutionQueue.swift Sources/BackgroundComputerUse/Actions/TypeText/AdaptiveTextDispatcher.swift Sources/BackgroundComputerUse/StatePipeline/InteractionToken.swift Sources/BackgroundComputerUse/Runtime/Process/BoundedProcessRunner.swift skills/background-computer-use/scripts/bcu-request.py Tests/BackgroundComputerUseTests/InteractionTokenTests.swift Tests/BackgroundComputerUseTests/RuntimeExecutionQueueTests.swift; do { git status --short -- "$f"; git diff --name-only 0110ffb..HEAD -- "$f"; } | grep -q . || echo "MISSING $f"; done` | no `MISSING` lines |
| Focused docs test | `swift test --filter DocumentationExamplesTests` | all tests pass after fixes |
| Existing API docs | `swift test --filter APIDocumentationTests` | all tests pass |
| Check stale field | `grep -n 'type_text.*imageMode\|"text":"hello","imageMode"' README.md` | no matches |
| Check metadata | `grep -n 'Status: implemented (commit.*1ebacd4\|As of commit.*0110ffb' docs/superpowers/plans/2026-07-27-bcu-web-reliability.md docs/parity-completion-audit.md` | two matching metadata lines |

## Scope

**In scope** (the only files you should modify):
- `README.md`
- `skills/background-computer-use/SKILL.md`
- `Sources/BackgroundComputerUse/API/RouteRegistry.swift`
- `Tests/BackgroundComputerUseTests/DocumentationExamplesTests.swift` (create)
- `docs/superpowers/plans/2026-07-27-bcu-web-reliability.md` (status line only)
- `docs/parity-completion-audit.md` (“As of commit” line only; preserve plan 002 gate edits if present)
- `plans/README.md`

**Out of scope**:
- Changing any request DTO, decoder, route behavior, or public response shape.
- Adding `README.md` or skill files as SwiftPM resources.
- Parsing prose snippets that are not fenced `json` blocks or single-quoted curl `-d '{...}'` bodies.
- Editing the historical web-reliability task boxes; the status header supersedes them without falsifying their original checklist.
- Rewriting parity claims or running live signed smoke.

## Git workflow

- Branch: `advisor/003-docs-examples-from-registry`
- Commit in one logical unit with the observed style, for example `docs: validate route examples against registry`.
- Do not push or open a PR unless instructed.
- Preserve prerequisite fixes and any plan 002 update under the parity audit’s “Current gates” section.

## Steps

### Step 1: Expose required request names from the same schema

Beside `requestFieldNames(for:)` in `RouteRegistry`, add:

```swift
/// Required top-level request field names for documentation validation.
static func requiredRequestFieldNames(for routeID: RouteID) -> [String] {
    (requestSchema(for: routeID.rawValue)?.fields ?? [])
        .filter(\.required)
        .map(\.name)
}
```

This is internal test/application API, not a new HTTP field. It must use `requestSchema`; never maintain a second table.

**Verify**: `swift build` → exit 0 with no Swift concurrency or access-control errors.

### Step 2: Add a RED documentation contract test

Create `DocumentationExamplesTests.swift` with `import Foundation`, `import Testing`, and `@testable import BackgroundComputerUse`. Define:

```swift
@Suite
struct DocumentationExamplesTests {
    private static let repositoryRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    private struct RequestExample {
        let routeID: RouteID
        let body: [String: Any]
        let source: String
    }
}
```

Implement `requestExamples(in:source:) throws -> [RequestExample]` as a line scanner:

1. Build route lookup from `RouteRegistry.descriptors` using descriptor `path` and matching `RouteID.rawValue == descriptor.id`.
2. For a line exactly ` ```json `, search at most the previous three lines for the nearest descriptor path; collect until the closing fence. If no route path is nearby, parse-check the JSON but omit it from request-schema validation because it is a nested object example.
3. For any line containing `-d '`, extract bytes between `-d '` and the next single quote. Search the current line and at most six previous lines, newest first, for the nearest route path. Require a route for every extracted curl body.
4. Parse with `JSONSerialization`; require a top-level `[String: Any]`; include file path and 1-based line in `source` so failures identify the example.

Add a synthetic parser test containing one route-context fenced block, one multiline curl command, and one context-free cursor JSON block. Assert the first two are returned with the correct route and the nested cursor block is parsed but not treated as a request.

Add the repository test over `README.md` and `skills/background-computer-use/SKILL.md`. For every returned request, assert:

```swift
let keys = Set(example.body.keys)
let accepted = Set(RouteRegistry.requestFieldNames(for: example.routeID))
let required = Set(RouteRegistry.requiredRequestFieldNames(for: example.routeID))
#expect(keys.isSubset(of: accepted), "\(example.source): unknown top-level request field")
#expect(required.isSubset(of: keys), "\(example.source): missing required request field")
```

Also assert at least seven route-bound curl bodies are found and include `list_apps`, `list_windows`, `get_window_state`, `click`, `type_text`, and `cursor_feedback`; this prevents a broken parser from passing vacuously.

**Verify**: `swift test --filter DocumentationExamplesTests` → test builds, then fails specifically on README `type_text`’s unknown `imageMode`; route inventory test added next may also report missing launch/paste.

### Step 3: Make the exhaustive README route inventory self-checking

In the same suite, read README and isolate lines after exact `Core routes:` through the next `## ` heading. Extract each bullet’s backticked `METHOD PATH`. Compare both set equality and count equality against:

```swift
let expected = RouteRegistry.descriptors.map { "\($0.method) \($0.path)" }
```

Set equality detects omissions/extras; count equality detects duplicates. Retain the human-readable exhaustive list because it is useful in the README, but make the registry test its generator/source of truth.

**Verify**: `swift test --filter DocumentationExamplesTests` → before Step 4, fails with inventory differences containing `POST /v1/launch_app` and `POST /v1/paste`.

### Step 4: Repair the examples and inventory

Apply only these content changes:

- In README `type_text`, remove `,"imageMode":"path"`; retain `window`, `target`, and `text`.
- In the skill OCR loop, use exact body `{"window":"WINDOW_ID", "includeOCR": true, "imageMode": "path"}`.
- In README “Core routes”, add `POST /v1/launch_app` immediately after `POST /v1/list_windows`, and add `POST /v1/paste` immediately after `POST /v1/type_text`.
- In README API Flow action list (`README.md:98`), add `/v1/paste` beside `/v1/type_text`; `launch_app` is discovery/startup rather than a window action and need not be inserted there.

Do not add `imageMode` to `type_text` merely to preserve the old example; strict schema rejection is correct.

**Verify**: `swift test --filter DocumentationExamplesTests` → parser, required/accepted fields, and exact route inventory all pass.

### Step 5: Mark historical evidence with exact commits

Immediately below the title in `docs/superpowers/plans/2026-07-27-bcu-web-reliability.md`, add:

```markdown
**Status: implemented (commit `1ebacd4`)**
```

Do not check its historical task boxes. In `docs/parity-completion-audit.md`, immediately after `Date: 2026-08-28`, add:

```markdown
As of commit: `0110ffb`
```

This identifies the code snapshot supporting the document; it is not a claim that later working-tree changes were live-qualified. Preserve any plan 002 edits below `## Current gates`.

**Verify**: `grep -n 'Status: implemented (commit.*1ebacd4\|As of commit:.*0110ffb' docs/superpowers/plans/2026-07-27-bcu-web-reliability.md docs/parity-completion-audit.md` → exactly two lines match.

### Step 6: Run focused gates and record completion

Run the new suite and existing API documentation suite. Confirm the test reads checkout files via `#filePath` and no `Package.swift` change exists. Update plan 003’s row in `plans/README.md` to `DONE`.

**Verify**: `swift test --filter 'DocumentationExamplesTests|APIDocumentationTests' && test -z "$(git diff --name-only -- Package.swift)"` → both suites pass and `Package.swift` has no diff.

## Test plan

- Parser unit fixture: route-context fenced JSON, multiline curl `-d` body, and context-free nested JSON.
- Live documentation scan: every route-bound fenced JSON/curl body in README and skill has only accepted top-level keys and every schema-required key.
- Parser non-vacuity: at least seven bodies and six named route IDs are discovered.
- Route inventory: exact method/path set and count match `RouteRegistry.descriptors`, catching omissions, extras, and duplicates.
- Existing `APIDocumentationTests` remains green, proving registry self-documentation was not changed.
- Final verification: `swift test --filter 'DocumentationExamplesTests|APIDocumentationTests'` → all selected tests pass.

## Done criteria

- [ ] README `type_text` example no longer sends `imageMode`.
- [ ] Skill OCR example sends required `window`.
- [ ] README lists every registry route exactly once, including `launch_app` and `paste`.
- [ ] Required and accepted field names both come from `RouteRegistry.requestSchema`.
- [ ] Documentation scanner reports file and line for malformed/invalid examples and cannot pass vacuously.
- [ ] Repository-root lookup uses `#filePath`; `Package.swift` resources remain unchanged.
- [ ] Historical web-reliability plan is marked implemented at `1ebacd4` without rewriting its checklist.
- [ ] Parity audit says `As of commit: 0110ffb` and preserves its qualifications.
- [ ] `plans/README.md` marks plan 003 `DONE`.

## STOP conditions

Stop and report back (do not improvise) if:

- Any required post-`0110ffb` working fix is missing.
- `RouteRegistry.requestFieldNames(for:)` no longer derives from the schema or route descriptors no longer map one-to-one to `RouteID`.
- The live `type_text` schema now legitimately includes `imageMode`; report the contract change instead of deleting valid documentation.
- A documentation body requires nested semantic validation beyond top-level registry fields; that is a separate DTO-decoding plan.
- Commit `1ebacd4` does not contain both the historical plan and its implementation, or parity audit content is no longer based on `0110ffb`.
- A verification fails twice after a reasonable fix attempt.

## Maintenance notes

- Any new or renamed route must update `RouteRegistry`; the README inventory test will then name the missing method/path.
- Keep route context physically close to JSON examples (three lines for fenced JSON, six for multiline curl) so the scanner can associate them without a Markdown parser dependency.
- Context-free fenced JSON remains syntax-checked but is not treated as a full request; this is intentional for nested cursor/target objects.
- Reviewers should ensure error messages include source file/line and the set difference, not just a boolean failure.
- This validation complements `/v1/routes`; it does not replace strict runtime decoding or test response schemas.
