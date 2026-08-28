# BCU macOS Product Parity Design

**Date:** 2026-08-27
**Status:** Approved by the active user objective

## Goal

Make BackgroundComputerUse equivalent or superior to Codex Computer Use on macOS as both an
automation engine and a desktop product. Completion requires live, requirement-by-requirement proof;
API shape or unit tests alone are insufficient.

## Current Evidence

A controlled Safari comparison established the baseline:

- Both products read and click a background window without changing the foreground app.
- Native Computer Use completed `click + type_text` in about 507 ms.
- Native `set_value` returned without error but produced no value.
- BCU returned honest `effect_not_verified` for the same ignored AX value write, but lacked the
  adaptive `click + postToPid` fallback needed to complete the task.
- BCU produced richer evidence, exact PID/window targeting, foreground telemetry, and verifier
  classifications; native actions returned no action verdict and required a state reread.

The product target is therefore broader completion without weakening BCU's honest verification.

## Scope

### Engine parity

- Adaptive background text entry.
- Text, Markdown, and HTML paste with clipboard restoration.
- Approved application launch with exact PID return.
- Condition-based settle and action performance telemetry.
- Same-app multi-instance targeting by PID and stable window ID.
- Existing OCR, wait, read, window motion, audit, and verifier surfaces remain authoritative.

### Control product

- Menu bar app and settings window.
- Per-app `ask`, `always_allow`, and `deny` policies.
- Persistent identity based on bundle ID, Team ID, and designated code requirement; PID is runtime
  identity only.
- PiP preview stack for every active app/window.
- Pause, resume, stop, history, and current-action explanation.
- Protected-app and sensitive-action policy.

### Locked use

- Opt-in continuation of an already active, authenticated BCU task after the Mac locks.
- Authorization plug-in, privileged broker, short-lived leases, display shields, local-input relock,
  and recovery/uninstall tooling.
- No generic remote-unlock API and no reuse of the permanent loopback token.

## Architecture

### BCU Core

The current loopback runtime remains the only UI action engine. It owns PID/window resolution,
capture, action strategies, verification, OCR, audit, sessions, and performance measurements.

### BCU Control

The signed desktop/menu bar process owns policy, approvals, PiP, user controls, and settings. Core
consults Control through authenticated local XPC before launching or first using an app. If Control is
unavailable and no valid persisted decision exists, the action fails closed.

### BCU Locked Use Broker

A root-owned helper validates Control/Core code signatures and issues one-use, short-lived leases for
an already active task. It owns the locked-use state machine, local-input monitoring, relock request,
and recovery metadata. Core and Control never write privileged state directly.

### Authorization Plug-in

A separate bundle implements `AuthorizationPluginCreate` and narrowly participates in the configured
authorization mechanism. Apple documents that authorization plug-ins are loaded in dedicated host
processes, installed in `/Library/Security/SecurityAgentPlugins`, registered with
`AuthorizationRightSet`, and report decisions through `SetResult`.

The plug-in validates a broker-issued nonce and lease. It has no network listener, no loopback token,
no action engine, and no authority outside the current unlock attempt.

References:

- <https://developer.apple.com/documentation/security/authorization-plug-ins>
- <https://developer.apple.com/documentation/security/extending-authorization-services-with-plug-ins>

## Engine Data Flow

### Adaptive type_text

1. Resolve the exact semantic text target and snapshot its value/selection.
2. Prepare the target window without raising it and confirm foreground preservation.
3. Prefer direct AX value write when the target claims it is writable.
4. Immediately reread the same live element.
5. If the exact expected value is present, finish verification.
6. If the value is unchanged from the prepared baseline, first attempt the exact target's advertised
   `AXTextOperation` and reread. If it completes the exact expected value, stop there.
7. If the target-bound lane is unavailable, fails without mutation, or still leaves the complete
   baseline unchanged, focus the exact target and perform one PID-scoped Unicode dispatch, then reread.
8. If the value changed partially or ambiguously, do not retry; fail closed to prevent duplication.
9. Return the strategy, timing, foreground evidence, exact value/selection evidence, and post token.

### paste

1. Snapshot all pasteboard items and types.
2. Encode the requested `text`, `markdown`, or `html` representation.
3. Prepare the exact target and dispatch Command-V to its PID.
4. Verify the target state or return `verifier_ambiguous` when the surface is opaque.
5. Restore the complete original pasteboard in `defer`, including on timeout or failure.

### launch_app

1. Resolve an installed bundle by bundle ID or explicit app bundle path.
2. Validate its code signature identity.
3. Consult the Control policy and request approval when required.
4. Launch without forcing foreground unless the request explicitly permits it.
5. Return the exact new/existing PID and targetable windows.

### Condition-based performance

Fixed action delays become bounded polls over route-specific evidence. Polling stops on the first
sound signal and reports resolve, capture, preparation, transport, settle, verification, and total
milliseconds. The maximum wait remains fail-closed.

## Control Data Flow

1. Core emits an authenticated activity envelope containing app identity, PID, window ID, action
   summary, cursor state, and screenshot reference.
2. Control verifies the caller audit token/code signature and updates the PiP stack.
3. A first-use app pauses at an approval gate; the UI records `allow_once`, `always_allow`, or `deny`.
4. Pause prevents new dispatch but keeps read-only state available. Stop revokes the session and all
   locked-use leases.
5. Settings can revoke persisted decisions and display current macOS Accessibility/Screen Recording
   state without attempting to approve TCC prompts.

## Locked Use State Machine

States: `disabled -> armed -> locked -> authorizing -> shielded_active -> relocking -> locked`.

- `armed` requires an active BCU task, explicit opt-in, healthy Control/Core, and a lease shorter than
  the configured maximum.
- On lock, Control installs opaque shield windows on every display before any temporary unlock.
- The plug-in permits only a broker nonce bound to the current task, user, boot session, code
  signatures, and expiration.
- The broker monitors local keyboard/pointer events. Any local input, lease expiry, process death,
  signature mismatch, display-shield loss, or user stop triggers immediate relock.
- A heartbeat loss fails closed. Repeated unlock attempts are rate limited and audited.
- The permanent BCU auth token is never available to the broker or plug-in.

## Security and Recovery

- App policy identities include Team ID and designated requirement to prevent bundle-ID spoofing.
- Control/Core XPC validates audit tokens and rejects unsigned or differently signed clients.
- Protected apps default to deny. Security, authentication, credential, payment, and system-policy
  actions require approval at action time.
- `run_script` remains an explicit administrative capability of the authenticated token and is
  separately visible in policy/history.
- Locked-use installation requires an explicit administrator handoff.
- Installer creates a versioned backup of the changed authorization rule before registration.
- An independently runnable recovery tool restores the exact prior rule and removes the plug-in.
- Plug-in crash, malformed state, missing broker, or invalid lease always returns deny.
- Initial locked-use testing occurs only in a disposable VM or secondary Mac. The primary host is not
  modified until install, unlock, local-input relock, crash recovery, and uninstall all pass there.

## Performance Targets

Measured on the same warm Safari fixture and host:

- Background read p50 <= 250 ms without OCR.
- Semantic click completion plus verifier p50 <= 600 ms and p95 <= 1,000 ms.
- Adaptive background text completion plus exact verifier p50 <= 650 ms and p95 <= 1,100 ms.
- Warm OCR p50 <= 500 ms; cold OCR remains isolated and bounded.
- PiP update after state receipt <= 150 ms.
- No optimization may remove foreground checks, exact rereads, or intent-signal requirements.

## Testing

### Engine

- RED tests for ignored AX writes, unchanged/partial/exact outcomes, single fallback, no duplicate
  fallback, clipboard restoration, launch policy, and condition-based waits.
- Repeated real Safari and Chromium fixtures with another app continuously frontmost.
- Ten-run benchmark with p50/p95 comparison against the recorded native baseline.
- Duplicate-instance PID selection and opaque renderer coverage.

### Control

- Code-signature identity fixtures, approval transitions, persistence/revocation, protected apps,
  XPC caller validation, PiP stacking, pause, stop, and crash recovery.
- Native visual QA for menu bar, approval prompt, settings, and PiP on every connected display.

### Locked use

- Pure lease/nonce/state-machine tests.
- Plug-in protocol tests in a dedicated test host.
- Signed install/uninstall and authorization-database round trip in a disposable VM/secondary Mac.
- Lock -> temporary shielded activity -> local-input relock.
- Expired/replayed nonce, broker death, plug-in crash, Control/Core death, display changes, and reboot.
- Recovery from a deliberately broken plug-in registration before primary-host eligibility.

## Completion Criteria

Completion is not a code-complete claim. Every native macOS capability in the comparison matrix must
be either matched or exceeded by live evidence. BCU must retain its unique exact PID/window targeting,
auditable verification, OCR anchors, window control, wait/read routes, and script lane. The goal is
complete only when engine benchmarks, Control visual QA, locked-use security gates, signed packaging,
and recovery tests all pass with no unverified requirement.

## Rejected Approaches

- Monolithic runtime/UI/plug-in bundle: weakens security boundaries and makes recovery harder.
- AX-only typing: reproduces the observed Safari silent no-op.
- Unconditional Unicode fallback: can duplicate partially inserted text.
- Fixed smaller sleeps: improves a benchmark without making state convergence faster or safer.
- Primary-host-first locked-use testing: unacceptable lockout risk.
