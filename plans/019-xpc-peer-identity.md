# Plan 019: Pin Core XPC admission to the exact embedded Control identity

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**: `git diff --stat 0110ffb..HEAD -- Sources/BackgroundComputerUseCoreXPCService/main.swift Sources/BackgroundComputerUseControlShared/CodeSignatureIdentity.swift Sources/BackgroundComputerUseControlShared/XPCPeerValidator.swift Tests/BackgroundComputerUseTests/XPCPeerValidatorTests.swift script/bootstrap_signing_identity.sh`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.
>
> Also run `git status --short` and `git diff --name-only 0110ffb..HEAD`. The union must show the baseline fixes in `Sources/BackgroundComputerUse/API/Router.swift`, `Sources/BackgroundComputerUse/App/BackgroundComputerUseControlBridge.swift`, `Sources/BackgroundComputerUseControlShared/CodeSignatureIdentity.swift`, `Sources/BackgroundComputerUse/Runtime/RuntimeExecutionQueue.swift`, `Sources/BackgroundComputerUse/Actions/TypeText/AdaptiveTextDispatcher.swift`, `Sources/BackgroundComputerUse/StatePipeline/InteractionToken.swift`, `Sources/BackgroundComputerUse/Runtime/Process/BoundedProcessRunner.swift`, `skills/background-computer-use/scripts/bcu-request.py`, `Tests/BackgroundComputerUseTests/InteractionTokenTests.swift`, and `Tests/BackgroundComputerUseTests/RuntimeExecutionQueueTests.swift`. STOP if any is neither committed after `0110ffb` nor present as a working-tree change.

## Status

- **Priority**: P1
- **Effort**: M
- **Risk**: MED
- **Depends on**: none
- **Category**: security
- **Planned at**: commit `0110ffb`, 2026-09-02

## Why this matters

The Core XPC service currently accepts a client after resolving a mutable PID and checking only bundle ID plus signer namespace. The repository already carries the peer's designated requirement and a validator that compares it, but this listener bypasses both. Exact embedded-identity derivation, a public connection-level code-signing requirement, first-message revalidation, and a codesign-only development-key ACL close the impersonation/PID-reuse window without private KVC.

## Current state

- `Sources/BackgroundComputerUseCoreXPCService/main.swift:41-63` keeps one service object and admits a connection from `connection.processIdentifier` with only two comparisons:
  ```swift
  guard let ownIdentity,
        let client = try? identityResolver.resolve(pid: connection.processIdentifier),
        client.bundleID == "xyz.dubdub.backgroundcomputeruse",
        client.teamID == ownIdentity.teamID
  else { return false }
  ```
- `Sources/BackgroundComputerUseControlShared/XPCPeerValidator.swift:17-35` already validates `bundleID`, `teamID`, and exact `designatedRequirement`; use this implementation rather than recreating comparisons in the executable target.
- `XPCPeerValidator.swift:37-54` has an `audit_token_t` overload, but it extracts a PID and calls the PID resolver. It is not an immutable audit-token SecCode lookup and must not be represented as one.
- The public macOS 14 `NSXPCConnection` surface provides `processIdentifier` and `setCodeSigningRequirement(_:)` (available since macOS 13), but no public Swift `auditToken`. Do not use KVC for the private `auditToken` key. Set the exact requirement before `resume()` and retain first-message PID revalidation as defense in depth.
- `Sources/BackgroundComputerUseControlShared/CodeSignatureIdentity.swift:50-55` defines `EmbeddedCoreIdentityPolicy.accepts` as exact Control/Core bundle IDs plus equal signer ID. It currently returns only Bool and does not return the trusted Control requirement.
- `CodeSignatureIdentity.swift:93-117` can resolve and strictly validate a bundle URL, so the Core service can resolve its containing `.app` rather than guessing a requirement string.
- `Tests/BackgroundComputerUseTests/XPCPeerValidatorTests.swift:12-57` covers exact acceptance, signer mismatch, and unsigned code. Lines 83-103 cover only the Bool embedded-pair policy; there is no Core admission test for a same-team designated-requirement mismatch.
- `script/bootstrap_signing_identity.sh:96-102` imports the development PKCS#12 with `-A`, then also grants `/usr/bin/codesign` and `/usr/bin/security`. Lines 111-116 set broad key partitions.
- `openspec/project.md:31-35` treats signed identity and the loopback token as security boundaries. This fix must fail closed; silently downgrading to bundle/team matching is not acceptable.

## Commands you will need

| Purpose | Command | Expected on success |
|---|---|---|
| Identity/admission tests | `swift test --filter XPCPeerValidatorTests` | exit 0; exact DR and revalidation cases pass |
| Core service compile | `swift build --product BackgroundComputerUseCoreXPCService` | exit 0 under Swift 6 strict concurrency |
| Signing script syntax | `bash -n script/bootstrap_signing_identity.sh` | exit 0 |
| ACL static gate | `python3 -c 'from pathlib import Path; s=Path("script/bootstrap_signing_identity.sh").read_text(); block=s[s.index("security import"):s.index("security add-trusted-cert")]; assert " -A" not in block and "/usr/bin/security" not in block and block.count("-T /usr/bin/codesign")==1'` | exit 0 |
| Final suite | `swift test` | exit 0; complete suite passes |

## Scope

**In scope** (the only files you should modify):
- `Sources/BackgroundComputerUseControlShared/CodeSignatureIdentity.swift`
- `Sources/BackgroundComputerUseControlShared/XPCPeerValidator.swift`
- `Sources/BackgroundComputerUseCoreXPCService/main.swift`
- `Tests/BackgroundComputerUseTests/XPCPeerValidatorTests.swift`
- `script/bootstrap_signing_identity.sh`
- `plans/README.md` (status row only)

**Out of scope** (do NOT touch, even though related):
- Locked-use broker peer validation and its root-owned identity configuration.
- Control's client-side validation of the embedded Core service.
- App authorization policy, HTTP token authorization, or ad-hoc app approval semantics.
- Private `auditToken` KVC, `xpc_connection_get_audit_token`, unsafe selector calls, or a new C shim. The public connection requirement is available on the deployment target.
- Generating/importing a new key during verification; only syntax and static ACL checks are permitted.

## Git workflow

- Branch: `advisor/019-xpc-peer-identity`
- Commit logical units with messages such as `fix: pin core xpc peer identity` and `fix: narrow development signing key acl`.
- Do NOT push or open a PR unless the operator instructed it.

## Steps

### Step 1: Extract a testable exact Core admission policy

Add a public value type in `XPCPeerValidator.swift` so the executable does not own security comparisons:

```swift
public struct XPCPeerRequirement: Equatable, Sendable {
    public let bundleID: String
    public let teamID: String
    public let designatedRequirement: String
}

public struct CoreXPCAdmissionPolicy: Sendable {
    public let requiredControl: XPCPeerRequirement

    @discardableResult
    public func validate(pid: pid_t, with validator: XPCPeerValidator) throws -> AppIdentity {
        try validator.validate(
            pid: pid,
            requiredBundleID: requiredControl.bundleID,
            requiredTeamID: requiredControl.teamID,
            requiredDesignatedRequirement: requiredControl.designatedRequirement
        )
    }
}
```

Extend `EmbeddedCoreIdentityPolicy` with `makeCoreAdmission(control:core:) -> CoreXPCAdmissionPolicy?`. It must call the existing `accepts` predicate, then copy all three exact fields from the resolved Control identity. A rejected embedded pair returns nil. Do not derive a designated requirement by string substitution from the Core requirement; signed requirement syntax varies across Developer ID, local certificate, Apple platform, and ad-hoc builds.

**Verify**: `swift test --filter XPCPeerValidatorTests` → exact requirement derivation accepts the real pair shape and rejects wrong Control bundle or mismatched signer.

### Step 2: Make the Core listener derive and enforce the embedded Control requirement

At Core service startup, resolve both identities with `CodeSignatureIdentity`:

```swift
let coreURL = Bundle.main.bundleURL
let controlURL = coreURL
    .deletingLastPathComponent() // XPCServices
    .deletingLastPathComponent() // Contents
    .deletingLastPathComponent() // BackgroundComputerUse.app
let coreIdentity = try resolver.resolve(url: coreURL)
let controlIdentity = try resolver.resolve(url: controlURL)
let admission = EmbeddedCoreIdentityPolicy.makeCoreAdmission(
    control: controlIdentity,
    core: coreIdentity
)
```

Store a nil admission state if any lookup or pair validation fails; the listener then rejects every connection. Never fall back to a hard-coded team or bundle-only policy.

In `shouldAcceptNewConnection`, run `admission.validate(pid: connection.processIdentifier, with: validator)`. Before assigning the exported object or resuming, call:

```swift
connection.setCodeSigningRequirement(admission.requiredControl.designatedRequirement)
```

The requirement comes from `SecRequirementCopyString` for the actually embedded Control app. This public API lets XPC invalidate messages whose sender no longer satisfies the requirement and is stronger than reading a private KVC audit token.

**Verify**: `swift build --product BackgroundComputerUseCoreXPCService` → executable compiles and links without private APIs.

### Step 3: Revalidate the first delivered message and fail closed

Create one `CoreXPCService` per accepted connection instead of sharing the global exported service. Give it a `CoreXPCFirstMessageGuard` (place the testable state machine in `XPCPeerValidator.swift`) holding PID, initially resolved identity, admission policy, resolver/validator, and an `NSLock`.

On the first exported method invocation, use `NSXPCConnection.current()?.processIdentifier`, require it equals the admitted PID, rerun exact admission, and require the second `AppIdentity` equals the initial identity. Cache only success. On failure or missing current connection, reply with the existing fail-closed defaults (`false` or `.unavailable`) and invalidate that connection. Subsequent methods rely on XPC's installed code-signing requirement. Do not run user/session authority logic before the guard succeeds.

This explicitly mitigates the PID lookup interval without claiming PID is immutable; the connection requirement remains the primary credential. Keep methods synchronous as the current protocol expects and make lock-protected guard state Swift 6 `Sendable`.

**Verify**: `swift test --filter XPCPeerValidatorTests` → a sequence resolver that changes only designated requirement between listener admission and first message is rejected; exact repeated identity validates once and remains accepted.

### Step 4: Narrow development key access to codesign only

In `script/bootstrap_signing_identity.sh`, change the import block to exactly one trusted application:

```bash
security import "$TMP_DIR/leaf.p12" \
  -k "$KEYCHAIN" \
  -P codexdev \
  -T /usr/bin/codesign \
  >/dev/null
```

Remove `-A` and `-T /usr/bin/security`. Narrow `security set-key-partition-list` to `-S codesign:` rather than `apple-tool:,apple:,codesign:` so the partition list does not undo the application ACL. Preserve keychain path/password behavior and never print key material or the password.

**Verify**: `bash -n script/bootstrap_signing_identity.sh && python3 -c 'from pathlib import Path; s=Path("script/bootstrap_signing_identity.sh").read_text(); block=s[s.index("security import"):s.index("security add-trusted-cert")]; assert " -A" not in block and "/usr/bin/security" not in block and block.count("-T /usr/bin/codesign")==1; assert "-S codesign:" in s'` → exit 0 without touching a keychain.

### Step 5: Run the complete non-destructive gate

Run the focused tests, build the XPC product, and then the repository test suite. Do not run the signing bootstrap to test it; it creates/imports credential material.

**Verify**: `swift test --filter XPCPeerValidatorTests && swift build --product BackgroundComputerUseCoreXPCService && swift test` → all commands exit 0.

## Test plan

- Extend `XPCPeerValidatorTests.swift` with exact admission success, same-bundle/same-team/wrong-DR rejection, wrong embedded Control bundle, wrong Core bundle, and mismatched signer.
- Add a sequence resolver test for first-message revalidation: exact/exact succeeds; exact/different-DR, exact/unsigned, and changed PID fail closed.
- Keep `StubIdentityResolver` injection; do not launch a real XPC service or sign fixtures in unit tests.
- Assert the resulting `requiredControl.designatedRequirement` is copied from the resolved Control identity rather than synthesized from team/bundle strings.
- Verification: `swift test --filter XPCPeerValidatorTests` → all existing and new tests pass.

## Done criteria

- [ ] Core admission uses `XPCPeerValidator` with bundle, signer, and exact designated requirement.
- [ ] The expected requirement comes from the strictly validated containing Control app and accepted embedded pair.
- [ ] `setCodeSigningRequirement` is called before `resume`; no private audit-token KVC or C shim exists.
- [ ] First-message PID/identity revalidation fails closed before touching `CoreSessionAuthority`.
- [ ] The development key import has no `-A`, no `/usr/bin/security` ACL, and only the `codesign:` partition.
- [ ] `swift build --product BackgroundComputerUseCoreXPCService` and `swift test` exit 0.
- [ ] `git status --short` shows only in-scope files and pre-existing baseline changes.
- [ ] `plans/README.md` status row is updated.

## STOP conditions

Stop and report back (do not improvise) if:

- The containing bundle is not exactly `<Control.app>/Contents/XPCServices/<Core.xpc>` at runtime; do not guess another trust root.
- `setCodeSigningRequirement(_:)` is unavailable when compiling for the declared macOS 14 target.
- The legitimate embedded Control and Core fail `EmbeddedCoreIdentityPolicy.accepts`; signing/package assembly drift must be fixed separately.
- A proposed fallback weakens validation to bundle/team, synthesizes a DR string, or accesses private KVC.
- Narrowing the key partition makes noninteractive `/usr/bin/codesign` impossible; report the exact Security error instead of adding `-A` back.
- A focused verification fails twice after a reasonable fix attempt.

## Maintenance notes

- The designated requirement is intentionally exact and build-derived. Release/signing pipeline changes must run the focused admission tests and an operator-authorized packaged-app XPC check.
- Reviewer focus: requirement installed before resume, no authority call before first-message validation, no fallback branch, and no credential material in errors/logs.
- The audit-token overload remains a PID convenience and must not be documented as immutable until it resolves SecCode directly from a supported audit-token API.