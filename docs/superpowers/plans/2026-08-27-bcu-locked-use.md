# BCU Locked Use Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Continue an active BCU task through the macOS lock screen with safeguards equivalent or stronger than native Codex locked use.

**Architecture:** Add a root-owned broker, a narrowly scoped authorization plug-in, Control display shields, and a short-lived lease protocol. Integrate only with `system.login.screensaver`; never modify `system.login.console`. Installation and first validation occur in a disposable VM or secondary Mac with an independently runnable rollback tool.

**Tech Stack:** Swift 6.2 plus C-compatible AuthorizationPlugin entry points, Security framework, NSXPCConnection, SMAppService/LaunchDaemon packaging, CGEventTap, AppKit display shields, Swift Testing.

**Spec:** `docs/plans/2026-08-27-bcu-macos-product-parity-design.md`

## Global Constraints

- Locked use is disabled by default and opt-in.
- The plug-in has no network listener, no BCU API token, and no generic unlock command.
- Every decision is bound to user, boot session, task session, nonce, signer identities, and expiration.
- Replayed, expired, malformed, missing-broker, or unsigned requests deny.
- Any local keyboard/pointer event relocks and disables automatic unlock until manual unlock.
- All displays are shielded before temporary unlock and remain shielded until relock.
- Modify only `system.login.screensaver`; preserve and restore its exact prior plist.
- VM/secondary-Mac install, crash, reboot, and uninstall gates precede primary-host eligibility.
- Installation requires administrator handoff; never capture or automate the credential.
- Do not commit or push without explicit authorization.

---

### Task 1: OpenSpec, rule snapshot, and pure locked-use state machine

**Files:**
- Create: `openspec/changes/add-bcu-locked-use/proposal.md`
- Create: `openspec/changes/add-bcu-locked-use/tasks.md`
- Create: `openspec/changes/add-bcu-locked-use/specs/locked-use/spec.md`
- Create: `Sources/BackgroundComputerUseLockedShared/LockedUseStateMachine.swift`
- Create: `Sources/BackgroundComputerUseLockedShared/AuthorizationRuleSnapshot.swift`
- Create: `Tests/BackgroundComputerUseTests/LockedUseStateMachineTests.swift`
- Modify: `Package.swift`

**Interfaces:**
- Produces states `disabled`, `armed`, `locked`, `authorizing`, `shieldedActive`, `relocking`.
- Produces events `enable`, `lockObserved`, `leasePresented`, `unlockAllowed`, `localInput`, `leaseExpired`, `dependencyLost`, `relocked`, `disable`.
- Produces exact plist snapshot/compare/restore data for `system.login.screensaver`.

- [x] **Step 1: Write failing transition tests**

Require only valid transitions, deny on invalid ordering, immediate relocking on local input/expiry/death,
and manual-unlock requirement after local input.

- [x] **Step 2: Write failing authorization-rule round-trip tests**

Use fixture plists containing the existing native Codex mechanism. Inserting BCU must preserve every
unknown key and existing rule order; removal must reproduce byte-equivalent semantic plist content.

- [x] **Step 3: Verify RED**

Run `swift test --filter 'LockedUseStateMachineTests'`.

- [x] **Step 4: Implement pure state/rule models**

No SecurityAgent, filesystem, or process calls in these types. All nondeterminism is injected.

- [x] **Step 5: Verify GREEN**

Run focused tests and plist property-list format validation.

### Task 2: Lease protocol and privileged broker

**Files:**
- Create: `Sources/BackgroundComputerUseLockedShared/LockedUseLease.swift`
- Create: `Sources/BackgroundComputerUseLockedBroker/BrokerService.swift`
- Create: `Sources/BackgroundComputerUseLockedBroker/BrokerXPCProtocol.swift`
- Create: `Sources/BackgroundComputerUseLockedBroker/LeaseStore.swift`
- Create: `Tests/BackgroundComputerUseTests/LockedUseLeaseTests.swift`
- Modify: `Package.swift`

**Interfaces:**
- Lease fields: version, taskSessionID, uid, bootSessionID, nonce, issuedAt, expiresAt, Core/Control designated requirements, oneUse.
- Broker XPC: `arm`, `consume`, `revoke`, `heartbeat`, `relock`.

- [x] **Step 1: Write failing lease tests**

Test one-use consumption, replay denial, expiry, wrong uid/boot/session/signer, heartbeat loss, revoke,
concurrent consume, and nonce entropy length.

- [x] **Step 2: Verify RED**

Run `swift test --filter LockedUseLeaseTests`.

- [x] **Step 3: Implement broker validation and owner-only state**

Validate XPC audit tokens/signatures. Generate nonces with `SecRandomCopyBytes`. Keep leases in memory;
persist only crash-recovery revocation metadata under a root-owned 0700 directory with 0600 files.

- [x] **Step 4: Implement relock and dependency monitoring**

Monitor Core/Control process identity and heartbeat. Relock is idempotent and transitions the state
machine before invoking the OS session-lock operation. No caller can request unlock through broker XPC.

- [x] **Step 5: Verify GREEN**

Run lease/broker concurrency, permission, and crash tests in an unprivileged test harness.

### Task 3: Authorization plug-in protocol

**Files:**
- Create: `Sources/BCUAuthorizationPlugin/AuthorizationPluginMain.swift`
- Create: `Sources/BCUAuthorizationPlugin/Mechanism.swift`
- Create: `Sources/BCUAuthorizationPlugin/BrokerClient.swift`
- Create: `Tests/BCUAuthorizationPluginTests/MechanismTests.swift`
- Modify: `Package.swift`

**Interfaces:**
- Exports C entry point `AuthorizationPluginCreate`.
- Implements plug-in/mechanism create, invoke, deactivate, and destroy callbacks.
- Mechanism name: `xyz.dubdub.backgroundcomputeruse.AuthorizationPlugin:remote`.

- [x] **Step 1: Write failing dedicated-host tests**

Use fake AuthorizationCallbacks and broker client. Valid consumed lease calls `SetResult(allow)` once;
every error calls `SetResult(deny)` once; deactivate cancels pending work; destroy releases state.

- [x] **Step 2: Verify RED**

Run `swift test --filter BCUAuthorizationPluginTests`.

- [x] **Step 3: Implement minimal plug-in entry points**

Decode only broker context needed for the current attempt. Query the broker over authenticated XPC,
consume one lease, and set allow/deny. No UI, file access, network, action execution, or retry loop.

- [x] **Step 4: Verify GREEN and ABI**

Run tests, `nm` for `AuthorizationPluginCreate`, `otool -L`, and a dedicated authorization host that
loads/unloads the bundle repeatedly.

### Task 4: Installer, exact registration, and recovery tool

**Files:**
- Create: `Sources/BackgroundComputerUseLockedInstaller/Installer.swift`
- Create: `Sources/BackgroundComputerUseLockedInstaller/AuthorizationDatabase.swift`
- Create: `Sources/BackgroundComputerUseLockedRecovery/main.swift`
- Create: `script/install_locked_use.sh`
- Create: `script/uninstall_locked_use.sh`
- Create: `Tests/BackgroundComputerUseTests/LockedUseInstallerTests.swift`
- Modify: `Package.swift`
- Modify: `script/build_and_run.sh`

**Interfaces:**
- Installs bundle at `/Library/Security/SecurityAgentPlugins/BCUAuthorizationPlugin.bundle`.
- Registers BCU rule before `use-login-window-ui` in `system.login.screensaver`.
- Recovery restores the versioned exact prior rule even when Control/Core are absent.

- [x] **Step 1: Write failing dry-run installer tests**

Given real fixture plist from this host, assert insertion order, coexistence with
`com.openai.sky.CUAService.AuthorizationPlugin.remote`, idempotence, signature rejection, rollback on
write failure, and exact uninstall restoration.

- [x] **Step 2: Verify RED**

Run `swift test --filter LockedUseInstallerTests`.

- [x] **Step 3: Implement dry-run-first installer**

Default command prints proposed diff and exits without mutation. Install requires an explicit flag,
verified Developer ID bundle, owner root:wheel/mode checks, backup write+fsync, bundle copy, then
`AuthorizationRightSet`. Any failure restores the prior rule and removes the partial bundle.

- [x] **Step 4: Implement independent recovery**

Recovery reads only the protected backup, verifies its digest/version, restores the right, removes the
BCU bundle, and reports literal state. It must not import Core or Control.

- [x] **Step 5: Verify GREEN in a fake authorization database**

Run installer/recovery tests without root or host mutation.

### Task 5: Display shields, local-input relock, and Control integration

**Files:**
- Create: `Sources/BackgroundComputerUseControl/DisplayShieldController.swift`
- Create: `Sources/BackgroundComputerUseLockedBroker/LocalInputMonitor.swift`
- Create: `Sources/BackgroundComputerUseControl/LockedUseCoordinator.swift`
- Create: `Tests/BackgroundComputerUseTests/LockedUseCoordinatorTests.swift`

**Interfaces:**
- Shield controller covers every active display and reports coverage generation.
- Input monitor reports trusted local keyboard/pointer events.
- Coordinator arms only after shield coverage and broker lease acknowledgment.

- [x] **Step 1: Write failing coordinator tests**

Test multi-display coverage, hot-plug invalidation, shield crash, local input, heartbeat loss, stop,
lease expiry, and manual-unlock reset.

- [x] **Step 2: Verify RED**

Run `swift test --filter LockedUseCoordinatorTests`.

- [x] **Step 3: Implement nonactivating shield windows**

Create one opaque window per display above ordinary app windows, reject missing coverage, update on
display changes, and keep BCU's per-window captures functional.

- [x] **Step 4: Implement broker input monitor and relock**

Use a trusted event tap in the privileged broker. Any local event atomically revokes the lease,
requests relock, and disables auto-unlock until Control observes manual unlock.

- [x] **Step 5: Verify GREEN and display QA**

Run tests and visual coverage checks with one, two, and dynamically attached displays in the test environment.

### Task 6: Signed VM/secondary-Mac qualification

**Files:**
- Create: `script/qualify_locked_use.sh`
- Create: `docs/locked-use-recovery.md`
- Modify: `openspec/changes/add-bcu-locked-use/tasks.md`
- Modify: `skills/background-computer-use/SKILL.md`

- [ ] **Step 1: Build and sign inside-out**

Sign broker, plug-in, Core XPC, and Control with the same expected Team ID; verify Developer ID,
hardened runtime, bundle identifiers, and designated requirements.

- [ ] **Step 2: Qualify install/uninstall on a disposable VM or secondary Mac**

Record the original `system.login.screensaver` plist, install, read back the exact rule, lock, consume
one lease, run shielded activity, relock on local input, uninstall, and prove semantic equality with the
original plist.

- [ ] **Step 3: Run failure matrix**

Exercise expired/replayed lease, plug-in crash, broker death, Control/Core death, shield loss, display
hot-plug, reboot, malformed backup, partial install, and recovery tool from a separate admin session.

- [ ] **Step 4: Run security review**

Audit plug-in ABI, XPC audit-token validation, code requirements, authorization-db mutation, file
ownership/modes, nonce handling, relock path, and absence of generic unlock surfaces.

- [ ] **Step 5: Determine primary-host eligibility**

Only after every VM/secondary-Mac gate passes, present the exact install diff, recovery command, and
remaining risks for explicit user handoff. Do not install on the primary host automatically.
