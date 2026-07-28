# BCU Web Reliability Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make BCU reliably target and verify AX-opaque web controls while improving token stability, sheet capture, and keyboard diagnostics without external browser bridges.

**Architecture:** Extend the existing native state/action contracts additively. OCR anchors receive stable action targets, actions receive a structural interaction token, click verification gains target-local visual evidence, and AX sheets become canonical attached surfaces used by discovery and screenshots. Existing transports remain unchanged; only targeting, evidence, and diagnostics change.

**Tech Stack:** Swift 6.2, Swift Testing, AppKit Accessibility, Apple Vision, CoreGraphics, existing Python smoke runtime.

## Global Constraints

- No CDP, browser-harness, browser plugin, foreground stealing, or new dependency.
- Existing JSON request forms and response fields remain valid.
- `dispatchSucceeded` alone never means action success.
- Destructive wording continues to require `confirm=true`.
- Every production behavior starts with a failing test.
- Keep direct-module imports and existing file naming conventions.

---

### Task 1: Explicit OCR Results and Reusable OCR Targets

**Files:**
- Modify: `Sources/BackgroundComputerUse/OCR/OCRAnchorSummary.swift`
- Modify: `Sources/BackgroundComputerUse/OCR/OCRRecognitionService.swift`
- Modify: `Sources/BackgroundComputerUse/Contracts/RouteRequestContracts.swift`
- Modify: `Sources/BackgroundComputerUse/StatePipeline/WindowStateService.swift`
- Modify: `Sources/BackgroundComputerUse/API/APIDocumentation.swift`
- Modify: `Sources/BackgroundComputerUse/API/RouteRegistry.swift`
- Test: `Tests/BackgroundComputerUseTests/RuntimeEnhancementTests.swift`
- Test: `Tests/BackgroundComputerUseTests/AgentAPICorrectnessTests.swift`
- Test: `Tests/BackgroundComputerUseTests/APIDocumentationTests.swift`

**Interfaces:**
- Produces: `OCRRecognitionStatusDTO`, `OCRAnchorDTO.id`, `OCRAnchorDTO.box`, `OCRAnchorDTO.target`, and `ActionTargetKindDTO.ocrAnchor`.
- Produces: `OCRRecognitionService.recognize(imagePath:interactionToken:) -> OCRAnchorSummaryDTO`.
- Preserves: current `text`, `x`, `y`, `confidence`, `promptHint`, `anchors`, and `matchesCount` fields.

- [ ] **Step 1: Write failing contract and builder tests**

Add Swift Testing cases that require:

```swift
@Test func ocrAnchorCarriesStableClickTarget() throws {
    let lines = [OCRLineDTO(text: "Update Server", confidence: 0.99, box: .init(x: 100, y: 200, width: 120, height: 32))]
    let result = OCRAnchorSummaryBuilder.summary(lines: lines, interactionToken: "it_ABC")
    let anchor = try #require(result.anchors.first)
    #expect(result.status == .success)
    #expect(anchor.box == lines[0].box)
    #expect(anchor.target.kind == .ocrAnchor)
    #expect(anchor.target.value == anchor.id)
}

@Test func ocrNoTextIsExplicit() {
    let result = OCRAnchorSummaryBuilder.summary(lines: [], interactionToken: "it_ABC")
    #expect(result.status == .noText)
    #expect(result.anchors.isEmpty)
}
```

Add decoding coverage for `{"kind":"ocr_anchor","value":"ocr_..."}` and reject an empty value.

- [ ] **Step 2: Run targeted tests and verify RED**

Run: `swift test --filter 'ocrAnchorCarriesStableClickTarget|ocrNoTextIsExplicit|ocr_anchor'`

Expected: compile/test failure because the status, fields, and target kind do not exist.

- [ ] **Step 3: Implement minimal OCR contracts**

Implement:

```swift
public enum OCRRecognitionStatusDTO: String, Codable, Sendable {
    case success
    case noText = "no_text"
    case imageUnavailable = "image_unavailable"
    case recognitionFailed = "recognition_failed"
}
```

Extend anchors with a deterministic `ocr_` identifier derived from normalized text, same-text occurrence, quantized box, and interaction token. Return an `OCRAnchorSummaryDTO` for every requested OCR outcome rather than collapsing failures into `nil`. Keep Vision errors as a short public diagnostic without exposing paths or private data.

- [ ] **Step 4: Update state/API documentation**

Pass the interaction token into OCR building, return explicit OCR status, and document `ocr_anchor` as click-only. Non-click target resolvers must return a clear unsupported-target diagnostic.

- [ ] **Step 5: Run targeted tests and verify GREEN**

Run: `swift test --filter 'RuntimeEnhancementTests|AgentAPICorrectnessTests|APIDocumentationTests'`

Expected: all selected tests pass.

- [ ] **Step 6: Commit**

```bash
git add Sources/BackgroundComputerUse/OCR Sources/BackgroundComputerUse/Contracts/RouteRequestContracts.swift Sources/BackgroundComputerUse/StatePipeline/WindowStateService.swift Sources/BackgroundComputerUse/API Tests/BackgroundComputerUseTests
git commit -m "feat: expose actionable OCR targets"
```

---

### Task 2: Structural Interaction Tokens

**Files:**
- Create: `Sources/BackgroundComputerUse/StatePipeline/InteractionToken.swift`
- Modify: `Sources/BackgroundComputerUse/StatePipeline/AXPipelineV2/State/StatePipelineExperiment.swift`
- Modify: `Sources/BackgroundComputerUse/Contracts/WindowStateContracts.swift`
- Modify: `Sources/BackgroundComputerUse/Contracts/RouteRequestContracts.swift`
- Modify: `Sources/BackgroundComputerUse/Actions/Shared/AXActionTargetResolver.swift`
- Modify: `Sources/BackgroundComputerUse/API/RouteRegistry.swift`
- Test: `Tests/BackgroundComputerUseTests/RuntimeEnhancementTests.swift`
- Test: `Tests/BackgroundComputerUseTests/RuntimeFacadePublicAPITests.swift`

**Interfaces:**
- Produces: `InteractionToken.make(windowID:title:frame:projectedTree:pixelWidth:pixelHeight:) -> String` with prefix `it_`.
- Produces: `interactionToken` on state/action captures and optional `interactionToken` on mutating requests.
- Preserves: full `stateToken` semantics and legacy callers.

- [ ] **Step 1: Write failing token behavior tests**

Create fixtures whose only difference is rendered clock text and assert equal interaction tokens. Change a target frame, role, node ID, or parent/child topology and assert unequal tokens. Assert the existing state token still changes for rendered text.

- [ ] **Step 2: Run token tests and verify RED**

Run: `swift test --filter 'interactionToken'`

Expected: failure because `InteractionToken` and response/request fields do not exist.

- [ ] **Step 3: Implement the structural digest**

Hash only window identity, frame, pixel dimensions, projection profile, projected topology, canonical/node/refetch identity, roles, target frames, flags that affect action eligibility, and secondary actions. Exclude rendered text, values, descriptions, selected text, and volatile labels.

- [ ] **Step 4: Wire additive request/response fields**

Add optional `interactionToken` decoding to click, scroll, secondary action, type text, press key, set value, and select text requests. Include the current token in state/action responses where their contracts expose pre/post state. Add resolver logic:

```swift
if let suppliedInteractionToken, suppliedInteractionToken != liveInteractionToken {
    return .staleInteractionTarget
}
```

A stale full `stateToken` is only a warning when the structural interaction token matches.

- [ ] **Step 5: Run token and public API tests and verify GREEN**

Run: `swift test --filter 'RuntimeEnhancementTests|RuntimeFacadePublicAPITests|AgentAPICorrectnessTests'`

Expected: all selected tests pass and old JSON fixtures decode unchanged.

- [ ] **Step 6: Commit**

```bash
git add Sources/BackgroundComputerUse/StatePipeline Sources/BackgroundComputerUse/Contracts Sources/BackgroundComputerUse/Actions/Shared Sources/BackgroundComputerUse/API/RouteRegistry.swift Tests/BackgroundComputerUseTests
git commit -m "feat: add stable interaction tokens"
```

---

### Task 3: OCR Click Resolution and Local Visual Verification

**Files:**
- Create: `Sources/BackgroundComputerUse/Actions/Shared/VisualChangeAnalyzer.swift`
- Create: `Sources/BackgroundComputerUse/Actions/Click/OCRClickTargetResolver.swift`
- Modify: `Sources/BackgroundComputerUse/Actions/Click/ClickRouteService.swift`
- Modify: `Sources/BackgroundComputerUse/Contracts/ClickActionContracts.swift`
- Modify: `Sources/BackgroundComputerUse/Actions/PressKey/PressKeyRouteService.swift`
- Test: `Tests/BackgroundComputerUseTests/RuntimeEnhancementTests.swift`
- Test: `Tests/BackgroundComputerUseTests/AgentAPICorrectnessTests.swift`

**Interfaces:**
- Produces: `OCRClickTargetResolver.resolve(requestedID:interactionToken:anchors:)` with exact, relocated, ambiguous, and missing outcomes.
- Produces: `VisualChangeAnalyzer.compare(before:after:normalizedRegion:)` returning full and regional ratios.
- Adds click verification fields: `ocrAnchorMatched`, `ocrAnchorDisappeared`, `targetRegionChangeRatio`, `fullImageChangeRatio`.

- [ ] **Step 1: Write failing OCR matcher tests**

Cover exact ID match, one geometrically relocated same-text match, ambiguous same-text candidates, and stale interaction token. Ambiguous/missing/stale outcomes must not produce coordinates.

- [ ] **Step 2: Write failing visual analyzer tests**

Generate deterministic in-memory images. Change pixels inside the target region and assert a regional change with a low full-image ratio; change pixels outside and assert no target-region change.

- [ ] **Step 3: Run matcher/analyzer tests and verify RED**

Run: `swift test --filter 'OCRClickTargetResolver|VisualChangeAnalyzer'`

Expected: compile failure because both types are absent.

- [ ] **Step 4: Implement the shared analyzer and OCR resolver**

Use RGBA sampling with bounds-checked normalized crops. Reuse the analyzer in `press_key`; do not create a third pixel-diff implementation. Match OCR anchors by exact ID first, then normalized text plus occurrence and bounded center displacement. Fail closed on ties.

- [ ] **Step 5: Add the OCR click lane**

For `ocr_anchor`:

1. Require a matching interaction token.
2. Capture a model-facing screenshot internally even when response `imageMode` is `omit`.
3. Run OCR and resolve the anchor.
4. Map its center through the existing screenshot coordinate contract.
5. Apply existing safety confirmation.
6. Dispatch through `NativeBackgroundClickTransport`.
7. Recapture AX, image, and OCR.
8. Verify AX effect, sheet/modal transition, anchor disappearance, or target-region visual change.

Do not accept full-image-only change when the target region is unchanged; this avoids clocks and animations producing false success.

- [ ] **Step 6: Run click and key tests and verify GREEN**

Run: `swift test --filter 'RuntimeEnhancementTests|AgentAPICorrectnessTests|PressKeyParserTests|ClickDialogEffectVerifierTests'`

Expected: all selected tests pass.

- [ ] **Step 7: Commit**

```bash
git add Sources/BackgroundComputerUse/Actions/Shared Sources/BackgroundComputerUse/Actions/Click Sources/BackgroundComputerUse/Actions/PressKey Sources/BackgroundComputerUse/Contracts/ClickActionContracts.swift Tests/BackgroundComputerUseTests
git commit -m "feat: verify OCR clicks visually"
```

---

### Task 4: Canonical Attached Sheets and Composite Capture

**Files:**
- Create: `Sources/BackgroundComputerUse/AXFoundation/AXAttachedSurfaceDiscovery.swift`
- Modify: `Sources/BackgroundComputerUse/Contracts/DiscoveryContracts.swift`
- Modify: `Sources/BackgroundComputerUse/Contracts/WindowStateContracts.swift`
- Modify: `Sources/BackgroundComputerUse/Discovery/WindowListService.swift`
- Modify: `Sources/BackgroundComputerUse/StatePipeline/AXPipelineV2/Projection/AXProjectedTreeBuilder.swift`
- Modify: `Sources/BackgroundComputerUse/Window/CGWindowInventory.swift`
- Modify: `Sources/BackgroundComputerUse/Screenshot/CGWindowCaptureService.swift`
- Modify: `Sources/BackgroundComputerUse/Screenshot/ScreenshotCaptureService.swift`
- Test: `Tests/BackgroundComputerUseTests/RuntimeEnhancementTests.swift`
- Test: `Tests/BackgroundComputerUseTests/AgentAPICorrectnessTests.swift`

**Interfaces:**
- Produces: `AttachedSurfaceDTO { role, title, frameAppKit, nodeID, isLiveActionSurface }`.
- Produces: `AXAttachedSurfaceDiscovery.surfaces(windowElement:pid:)`.
- Produces: same-PID composite capture rooted at the main window frame.

- [ ] **Step 1: Write failing sheet canonicalization fixtures**

Create a projected fixture with duplicate dialog groups and one live `AXSheet` containing the same normalized title and actionable button signature. Assert one visible sheet subtree, preserved canonical indices, and `is_live_action_surface` metadata. A dialog with different actions must remain separate.

- [ ] **Step 2: Write failing attached-surface discovery and composition tests**

Use injectable AX/CG records to prove only same-PID, on-screen surfaces intersecting the root frame are returned/composited. Reject other-process overlays and non-intersecting windows.

- [ ] **Step 3: Run sheet tests and verify RED**

Run: `swift test --filter 'attachedSurface|duplicateSheet|compositeCapture'`

Expected: failures because discovery, DTOs, and canonicalization are absent.

- [ ] **Step 4: Implement attached-surface discovery**

Read `kAXSheetsAttribute` and sheet/dialog children from the resolved root window. Deduplicate by AX identity, then by role/title/frame/action signature. Add attached surfaces to list/state responses without creating fake top-level window IDs.

- [ ] **Step 5: Fold duplicate projected dialog subtrees**

Only fold when a live sheet exists and normalized title plus ordered actionable labels match. Preserve every folded canonical index on the surviving projected node so semantic target resolution remains valid.

- [ ] **Step 6: Implement safe same-PID composition**

Extend the CG inventory to retain layer and alpha internally. Capture eligible same-PID surfaces individually and composite them in window order into the root frame. Keep the existing coordinate contract rooted at the main window. Fall back to the existing single-window capture with a diagnostic when composition is unavailable.

- [ ] **Step 7: Run discovery, state, and screenshot tests and verify GREEN**

Run: `swift test --filter 'RuntimeEnhancementTests|AgentAPICorrectnessTests|CursorScreenshotCompositorTests'`

Expected: all selected tests pass.

- [ ] **Step 8: Commit**

```bash
git add Sources/BackgroundComputerUse/AXFoundation Sources/BackgroundComputerUse/Contracts Sources/BackgroundComputerUse/Discovery Sources/BackgroundComputerUse/StatePipeline/AXPipelineV2/Projection Sources/BackgroundComputerUse/Window Sources/BackgroundComputerUse/Screenshot Tests/BackgroundComputerUseTests
git commit -m "feat: expose and capture attached sheets"
```

---

### Task 5: Focus-Surface Diagnostics and Recovery Hints

**Files:**
- Create: `Sources/BackgroundComputerUse/Actions/PressKey/FocusSurfaceClassifier.swift`
- Modify: `Sources/BackgroundComputerUse/Contracts/PressKeyActionContracts.swift`
- Modify: `Sources/BackgroundComputerUse/Actions/PressKey/PressKeyRouteService.swift`
- Modify: `Sources/BackgroundComputerUse/API/APIDocumentation.swift`
- Modify: `Sources/BackgroundComputerUse/API/RouteRegistry.swift`
- Test: `Tests/BackgroundComputerUseTests/RuntimeEnhancementTests.swift`
- Test: `Tests/BackgroundComputerUseTests/APIDocumentationTests.swift`

**Interfaces:**
- Produces: `FocusSurfaceKindDTO` values `native_text`, `web_content`, `browser_chrome`, `attached_sheet`, `opaque_renderer`, `unknown`.
- Adds `focusSurface`, `recoveryCode`, and concise recovery steps to press-key verification.

- [ ] **Step 1: Write failing classifier tests**

Build focused-node/window fixtures for native text fields, web descendants, browser chrome controls, sheets, window-only opaque renderers, and unknown surfaces. Assert exact classification.

- [ ] **Step 2: Write failing failure-domain test**

Simulate successful native dispatch with unchanged AX/text/visual state on an opaque renderer. Expect `classification=effect_not_verified`, `failureDomain=app_specific_semantics`, and `recoveryCode=opaque_renderer_focus_unconfirmed`.

- [ ] **Step 3: Run focus tests and verify RED**

Run: `swift test --filter 'FocusSurfaceClassifier|opaque_renderer_focus_unconfirmed'`

Expected: compile/test failures because classifier and recovery fields are absent.

- [ ] **Step 4: Implement minimal classification and diagnostics**

Classify from the focused projected node, ancestry flags, attached-sheet metadata, app bundle, and window-only profile. Keep native dispatch unchanged. Replace the generic safe-click warning only when the new classification identifies a more precise cause.

- [ ] **Step 5: Update route documentation and verify GREEN**

Run: `swift test --filter 'RuntimeEnhancementTests|APIDocumentationTests|PressKeyParserTests'`

Expected: all selected tests pass.

- [ ] **Step 6: Commit**

```bash
git add Sources/BackgroundComputerUse/Actions/PressKey Sources/BackgroundComputerUse/Contracts/PressKeyActionContracts.swift Sources/BackgroundComputerUse/API Tests/BackgroundComputerUseTests
git commit -m "fix: diagnose opaque renderer key focus"
```

---

### Task 6: End-to-End BCU-Only Regression

**Files:**
- Modify: `script/smoke_runtime.py`
- Modify: `skills/background-computer-use/SKILL.md`
- Test: `Tests/BackgroundComputerUseTests/RuntimeEnhancementTests.swift`

**Interfaces:**
- Consumes: OCR targets, interaction tokens, local visual verification, attached sheets, and focus diagnostics from Tasks 1–5.
- Produces: deterministic smoke checks and agent-facing examples that use only the loopback BCU API.

- [ ] **Step 1: Extend the smoke fixture before changing the runner**

Add an AX-opaque web-style modal with a visible `Update Server` button, a dynamic clock outside the button region, and an observable post-click state. Add a native attached-sheet fixture when the runtime environment exposes one.

- [ ] **Step 2: Write failing smoke assertions**

Require the runner to:

1. Request OCR and obtain a reusable target.
2. Click the OCR target with the interaction token.
3. Verify target-local change despite the unrelated clock changing.
4. Reject a stale/ambiguous target.
5. Report a precise opaque-renderer key diagnostic.
6. Preserve the frontmost application.

- [ ] **Step 3: Run smoke and verify RED**

Run: `python3 script/smoke_runtime.py`

Expected: new checks fail before all prior tasks are integrated.

- [ ] **Step 4: Complete fixture integration and skill examples**

Document the exact read → OCR target → click → reread loop. Remove guidance that suggests blind coordinate retries when an OCR target or attached sheet is available.

- [ ] **Step 5: Run full verification**

Run:

```bash
swift test
python3 -m py_compile script/smoke_runtime.py skills/background-computer-use/scripts/bcu-request.py
python3 script/smoke_runtime.py
```

Expected: Swift suite passes; Python compilation passes; smoke reports zero failures/skips for supported local capabilities.

- [ ] **Step 6: Commit**

```bash
git add script/smoke_runtime.py skills/background-computer-use/SKILL.md Tests/BackgroundComputerUseTests/RuntimeEnhancementTests.swift
git commit -m "test: cover opaque web modal interactions"
```

---

## Self-Review

- Spec coverage: OCR targeting, local verification, interaction tokens, sheet canonicalization/capture, list/state surfaces, focus diagnostics, recovery hints, and BCU-only smoke each have a task.
- Compatibility: all existing fields remain; new request fields are optional; legacy state tokens remain accepted.
- Type consistency: `ocr_anchor`, `interactionToken`, `AttachedSurfaceDTO`, `VisualChangeAnalyzer`, and `FocusSurfaceKindDTO` have one declared producer and explicit consumers.
- Placeholder scan: no deferred implementation steps or unspecified error handling remain.
