# BCU Control Product Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Add the macOS menu bar, app approval, PiP, pause, stop, history, and launch experience needed to match native Codex Computer Use.

**Architecture:** Split the app bundle into a Control host and a Core XPC service while preserving the loopback contract. Shared XPC contracts carry policy requests and activity events; Control owns all user-facing state and Core fails closed when policy authority is unavailable.

**Tech Stack:** Swift 6.2, SwiftUI/AppKit, NSXPCConnection, Security code-signing APIs, Swift Testing, existing signed app packaging.

**Spec:** `docs/plans/2026-08-27-bcu-macos-product-parity-design.md`

## Global Constraints

- App identity is bundle ID + Team ID + designated requirement; PID alone is never persisted.
- First use pauses at `ask`; no hidden default allow.
- Protected apps default to deny.
- XPC validates audit token and code signature on both sides.
- Stop revokes the runtime session and every locked-use lease.
- Control loss fails closed for new app access.
- UI must remain usable with VoiceOver, keyboard navigation, multiple displays, and reduced motion.
- Do not commit or push without explicit authorization.

---

### Task 1: OpenSpec, shared identity, and policy model

**Files:**
- Create: `openspec/changes/add-bcu-control/proposal.md`
- Create: `openspec/changes/add-bcu-control/tasks.md`
- Create: `openspec/changes/add-bcu-control/specs/app-policy/spec.md`
- Create: `Sources/BackgroundComputerUseControlShared/AppIdentity.swift`
- Create: `Sources/BackgroundComputerUseControlShared/AppPolicy.swift`
- Create: `Tests/BackgroundComputerUseTests/AppPolicyTests.swift`
- Modify: `Package.swift`

**Interfaces:**
- Produces: `AppIdentity(bundleID:teamID:designatedRequirement:)`.
- Produces: `AppPolicyDecision.ask | allowOnce | alwaysAllow | deny`.
- Produces: `AppPolicyStore.evaluate(identity:session:)`.

- [x] **Step 1: Write failing identity/policy tests**

Require same bundle with different Team ID to miss persisted allow; allow-once expires with session;
deny overrides allow; protected identities cannot persist allow.

- [x] **Step 2: Verify RED**

Run `swift test --filter AppPolicyTests`.

- [x] **Step 3: Implement shared Codable contracts and atomic persistence**

Store only signature identity and decision metadata in Application Support with owner-only permissions.
Use an injected clock and file URL in tests.

- [x] **Step 4: Verify GREEN**

Run policy tests and strict JSON round trips.

### Task 2: Code-signature identity and XPC caller validation

**Files:**
- Create: `Sources/BackgroundComputerUseControlShared/CodeSignatureIdentity.swift`
- Create: `Sources/BackgroundComputerUseControlShared/XPCPeerValidator.swift`
- Create: `Tests/BackgroundComputerUseTests/XPCPeerValidatorTests.swift`

**Interfaces:**
- Produces: `CodeSignatureIdentity.resolve(pid:) throws -> AppIdentity`.
- Produces: `XPCPeerValidator.validate(auditToken:requiredTeamID:requiredRequirement:)`.

- [x] **Step 1: Write failing signature fixtures**

Test exact team/requirement acceptance, bundle spoof rejection, missing signature rejection, and current
test executable acceptance through an injected SecCode adapter.

- [x] **Step 2: Verify RED**

Run `swift test --filter XPCPeerValidatorTests`.

- [x] **Step 3: Implement Security-framework resolution**

Use `SecCodeCopyGuestWithAttributes`, `SecCodeCopySigningInformation`, and
`SecStaticCodeCheckValidityWithErrors`. Never trust a request-supplied identity.

- [x] **Step 4: Verify GREEN**

Run focused tests and codesign fixtures.

### Task 3: Control/Core XPC boundary and launch_app

**Files:**
- Create: `Sources/BackgroundComputerUseControlShared/ControlXPCProtocol.swift`
- Create: `Sources/BackgroundComputerUseControl/ControlService.swift`
- Create: `Sources/BackgroundComputerUseCoreXPC/CoreService.swift`
- Create: `Sources/BackgroundComputerUse/Actions/LaunchApp/LaunchAppRouteService.swift`
- Create: `Sources/BackgroundComputerUse/Contracts/LaunchAppContracts.swift`
- Modify: `Package.swift`
- Modify: `Sources/BackgroundComputerUse/API/RouteRegistry.swift`
- Modify: `Sources/BackgroundComputerUse/API/Router.swift`
- Modify: `Sources/BackgroundComputerUse/Runtime/RuntimeServices.swift`
- Modify: `Sources/BackgroundComputerUse/App/BackgroundComputerUseRuntime.swift`
- Create: `Tests/BackgroundComputerUseTests/LaunchAppPolicyTests.swift`

**Interfaces:**
- XPC `authorizeApp(identity:pid:session:reply:)`.
- XPC `publishActivity(_:)`, `pauseSession(_:)`, and `stopSession(_:)`.
- Route `launch_app` returns exact PID, launch state, and windows.

- [x] **Step 1: Write failing authorization/launch tests**

Require ask to block until reply, deny to prevent `NSWorkspace.openApplication`, allow to launch without
activation, and existing-process resolution to return its exact PID.

- [x] **Step 2: Verify RED**

Run `swift test --filter LaunchAppPolicyTests`.

- [x] **Step 3: Implement fail-closed XPC authorization**

Core supplies a signature-derived identity. Control returns a decision bound to session+identity.
Timeout, interruption, invalid peer, or missing Control returns deny.

- [x] **Step 4: Implement and wire launch_app**

Resolve by bundle ID or canonical `.app` path, verify signature, authorize, call
`NSWorkspace.openApplication(at:configuration:)` with activation disabled, and return the exact PID.

- [x] **Step 5: Verify GREEN**

Run policy, route, strict-decode, facade, and XPC interruption tests.

### Task 4: Menu bar, approvals, settings, and protected apps

**Files:**
- Create: `Sources/BackgroundComputerUseControl/BCUControlApp.swift`
- Create: `Sources/BackgroundComputerUseControl/MenuBarController.swift`
- Create: `Sources/BackgroundComputerUseControl/ApprovalWindow.swift`
- Create: `Sources/BackgroundComputerUseControl/SettingsView.swift`
- Create: `Sources/BackgroundComputerUseControl/ControlViewModel.swift`
- Create: `Tests/BackgroundComputerUseTests/ControlViewModelTests.swift`

**Interfaces:**
- Produces approval actions `allowOnce`, `alwaysAllow`, `deny`.
- Produces settings operations list/revoke policies and enable/disable locked use.

- [x] **Step 1: Write failing view-model tests**

Test queued approvals, one active prompt, timeout deny, persistence, revoke, protected-app denial,
VoiceOver labels, and keyboard actions.

- [x] **Step 2: Verify RED**

Run `swift test --filter ControlViewModelTests`.

- [x] **Step 3: Implement menu bar and approval UI**

Use an accessory activation policy. Approval shows app icon/name, verified signer, requested operation,
scope, and the three explicit decisions. No approval is implied by dismissing the window.

- [x] **Step 4: Implement settings**

List app policies and macOS permission status. Revocation is immediate. TCC approval buttons only open
System Settings and never click permission prompts.

- [x] **Step 5: Verify GREEN and accessibility**

Run view-model tests plus native keyboard/VoiceOver inspection.

### Task 5: PiP, activity history, pause, and stop

**Files:**
- Create: `Sources/BackgroundComputerUseControl/ActivityModels.swift`
- Create: `Sources/BackgroundComputerUseControl/PiPWindowController.swift`
- Create: `Sources/BackgroundComputerUseControl/ActivityHistoryStore.swift`
- Create: `Sources/BackgroundComputerUseControl/SessionControls.swift`
- Create: `Tests/BackgroundComputerUseTests/ActivityControlTests.swift`

**Interfaces:**
- Produces `ActivityEnvelope(session:app:window:action:screenshot:verification:timestamp:)`.
- Produces `pause`, `resume`, and `stop` commands acknowledged by Core.

- [x] **Step 1: Write failing activity/control tests**

Test single-card latest-activity replacement, screenshot replacement, 150 ms update budget with injected clock, pause
blocking new writes, read-only state during pause, stop revocation, and history redaction.

- [x] **Step 2: Verify RED**

Run `swift test --filter ActivityControlTests`.

- [x] **Step 3: Implement PiP and controls**

Use nonactivating panels, multi-display clamping, reduced-motion transitions, and explicit current
action/verdict text. Stop invalidates session and notifies the locked broker interface.

- [x] **Step 4: Verify GREEN and visual QA**

Run tests and inspect menu bar, approval, the single transient PiP, pause/resume/stop, light/dark, scale, and displays.

### Task 6: Bundle assembly, signing, and Control smoke

**Files:**
- Modify: `script/build_and_run.sh`
- Modify: `script/package_release.sh`
- Create: `script/smoke_control.py`
- Modify: `skills/background-computer-use/SKILL.md`
- Modify: `openspec/changes/add-bcu-control/tasks.md`

- [x] **Step 1: Assemble main app and embedded XPC service**

Build Control as `CFBundleExecutable`, place Core under `Contents/XPCServices`, assign unique bundle
IDs, sign inside-out with the same Team ID, then sign the containing app.

- [x] **Step 2: Verify signatures and designated requirements**

Run `codesign --verify --deep --strict`, `spctl --assess`, and compare Team IDs/requirements expected by
the XPC validator.

- [x] **Step 3: Run signed Control smoke**

Exercise ask/allow-once/always/deny, launch background app, the PiP `1 → 0` lifecycle, pause, resume, stop, revoke, Core
crash, Control crash, and restart persistence.

- [x] **Step 4: Run final Control gates**

Run release build, full tests, OpenSpec strict, visual QA, and cleanup checks.
