# Plan 021: Preserve external clipboard writes and make approval/install trust explicit

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**: `git diff --stat 0110ffb..HEAD -- Sources/BackgroundComputerUse/Actions/Paste Sources/BackgroundComputerUse/Contracts/PasteContracts.swift Sources/BackgroundComputerUse/API/RouteRegistry.swift Sources/BackgroundComputerUse/API/APIDocumentation.swift Sources/BackgroundComputerUseControlShared/CodeSignatureIdentity.swift Sources/BackgroundComputerUseControl/ControlViewModel.swift Tests/BackgroundComputerUseTests/PasteRouteTests.swift Tests/BackgroundComputerUseTests/ControlViewModelTests.swift script/install_locked_use.sh docs/locked-use-recovery.md openspec/changes/protect-user-data-and-install-trust`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.
>
> Also run `git status --short` and `git diff --name-only 0110ffb..HEAD`. The union must show the baseline fixes in `Sources/BackgroundComputerUse/API/Router.swift`, `Sources/BackgroundComputerUse/App/BackgroundComputerUseControlBridge.swift`, `Sources/BackgroundComputerUseControlShared/CodeSignatureIdentity.swift`, `Sources/BackgroundComputerUse/Runtime/RuntimeExecutionQueue.swift`, `Sources/BackgroundComputerUse/Actions/TypeText/AdaptiveTextDispatcher.swift`, `Sources/BackgroundComputerUse/StatePipeline/InteractionToken.swift`, `Sources/BackgroundComputerUse/Runtime/Process/BoundedProcessRunner.swift`, `skills/background-computer-use/scripts/bcu-request.py`, `Tests/BackgroundComputerUseTests/InteractionTokenTests.swift`, and `Tests/BackgroundComputerUseTests/RuntimeExecutionQueueTests.swift`. STOP if any is neither committed after `0110ffb` nor present as a working-tree change.

## Status

- **Priority**: P2
- **Effort**: S
- **Risk**: LOW/MED
- **Depends on**: none
- **Category**: security
- **Planned at**: commit `0110ffb`, 2026-09-02

## Why this matters

BCU can overwrite a clipboard value copied by the user during its temporary Command-V transaction, labels certificate/ad-hoc identity fallbacks as an undifferentiated “verified signer,” and installs root locked-use artifacts after incomplete trust checks. These are three human-boundary failures: preserve newer user data, describe exactly what “Always allow” binds to, and prove the bytes being privileged are trusted immediately before and after copy. The changes are narrow and fail closed; no new automation authority is introduced.

## Current state

- `Sources/BackgroundComputerUse/Actions/Paste/PasteTransaction.swift:17-25` captures, writes, dispatches, and unconditionally restores, returning only three booleans.
- `Sources/BackgroundComputerUse/Actions/Paste/PasteboardSnapshot.swift:21-33` begins restore with `pasteboard.clearContents()` and does not inspect `NSPasteboard.changeCount`.
- `Sources/BackgroundComputerUse/Actions/Paste/PasteboardSnapshot.swift:71-72` also clears before writing BCU's payload; the transaction must distinguish BCU's generation from a later external generation.
- `Sources/BackgroundComputerUse/Actions/Paste/PasteRouteService.swift:326-350` classifies any `restoreSucceeded == false` as generic verification failure. Lines 353-372 expose only `pasteboardRestored: Bool`; lines 276-280 always claim the fallback restored the snapshot.
- `Sources/BackgroundComputerUse/Contracts/PasteContracts.swift:58-77` has no machine-readable reason for `pasteboardRestored == false`. `RouteRegistry.swift:892-896` documents the Bool but no reason.
- `Tests/BackgroundComputerUseTests/PasteRouteTests.swift:7-31,57-80` already uses a unique named `NSPasteboard` and verifies complete binary-item restoration. Extend that real AppKit pattern rather than mocking the global pasteboard.
- `Sources/BackgroundComputerUseControlShared/CodeSignatureIdentity.swift:24-46` produces four signer namespaces: plain team ID, `apple-platform:`, `certificate-sha256:`, and `adhoc-cdhash:`. The comment correctly says an ad-hoc cdhash changes per build.
- `Sources/BackgroundComputerUseControl/ControlViewModel.swift:90-101` renders every namespace as `Assinante verificado` and gives every request the same `Sempre permitir` label.
- `Sources/BackgroundComputerUseControlShared/AppPolicy.swift:43-58,86-95` persists decisions by the full `AppIdentity`. The ad-hoc policy is already hash/designated-requirement bound; do not weaken or redesign persistence.
- `script/install_locked_use.sh:17-27` builds, verifies only the plugin with `--deep --strict`, and treats any nonempty `TeamIdentifier` as enough. Lines 73-87 copy the plugin/broker and bootstrap/mutate authorization state without re-verifying installed bytes.
- `script/build_locked_use.sh:28-31` verifies both artifacts after signing, but that earlier check does not cover replacement between build and privileged copy.
- `docs/locked-use-recovery.md:43-50` says not to reconstruct authorization rules and declares a primary Mac ineligible until disposable VM/secondary-Mac qualification. Implementation verification must remain non-installing.
- `openspec/project.md:13-15` requires verifier-honest outcomes and `/v1/routes` fields to match DTOs; lines 25-29 require a valid OpenSpec delta for the additive paste response reason.

## Commands you will need

| Purpose | Command | Expected on success |
|---|---|---|
| Paste regression | `swift test --filter PasteRouteTests` | exit 0; external copy survives and reason is documented |
| Approval copy | `swift test --filter ControlViewModelTests` | exit 0; all four provenance forms have distinct PT-BR copy |
| Installer syntax | `bash -n script/install_locked_use.sh` | exit 0 |
| Installer dry-run | `BACKGROUND_COMPUTER_USE_LOCKED_ALLOWED_PEERS='[]' BCU_LOCKED_USE_ALLOW_LOCAL_SIGNING=1 script/install_locked_use.sh --dry-run` | exit 0; loud local-signing warning and dry-run-only message; no privileged mutation |
| OpenSpec | `openspec validate protect-user-data-and-install-trust --strict` | exit 0 when CLI exists |
| Final suite | `swift test` | exit 0; complete suite passes |

## Scope

**In scope** (the only files you should modify):
- `Sources/BackgroundComputerUse/Actions/Paste/PasteTransaction.swift`
- `Sources/BackgroundComputerUse/Actions/Paste/PasteRouteService.swift`
- `Sources/BackgroundComputerUse/Contracts/PasteContracts.swift`
- `Sources/BackgroundComputerUse/API/RouteRegistry.swift`
- `Sources/BackgroundComputerUse/API/APIDocumentation.swift`
- `Sources/BackgroundComputerUseControlShared/CodeSignatureIdentity.swift`
- `Sources/BackgroundComputerUseControl/ControlViewModel.swift`
- `Tests/BackgroundComputerUseTests/PasteRouteTests.swift`
- `Tests/BackgroundComputerUseTests/ControlViewModelTests.swift`
- `script/install_locked_use.sh`
- `docs/locked-use-recovery.md`
- `openspec/changes/protect-user-data-and-install-trust/proposal.md` (create)
- `openspec/changes/protect-user-data-and-install-trust/tasks.md` (create)
- `openspec/changes/protect-user-data-and-install-trust/specs/runtime-security/spec.md` (create)
- `plans/README.md` (status row only)

**Out of scope** (do NOT touch, even though related):
- `PasteboardSnapshot.restore` serialization; keep its byte-for-byte restore behavior and put generation ownership in `PasteTransaction`.
- The paste dispatch ladder, focus acquisition, verification settle, or foreground fallback behavior.
- App policy key/persistence semantics; exact `AppIdentity` persistence is already the desired ad-hoc expiry behavior.
- Building/signing changes in `script/build_locked_use.sh`, locked broker logic, Authorization Plugin logic, or the uninstall recovery algorithm.
- Running `--install`, `sudo`, `launchctl bootstrap`, or `security authorizationdb write` on this host.
- Treating local/ad-hoc signing as production trust or silently enabling its override.

## Git workflow

- Branch: `advisor/021-clipboard-guard-approval-copy-install-trust`
- Commit logical units with messages such as `fix: preserve external clipboard writes`, `fix: clarify signer provenance`, and `fix: verify locked-use install trust`.
- Do NOT push or open a PR unless the operator instructed it.

## Steps

### Step 1: Specify user-data and trust behavior

Create the OpenSpec change with three requirements: (1) BCU restores its snapshot only while its pasteboard generation is still current and leaves later external data untouched; (2) the paste response reports `pasteboardRestoreReason`; (3) approval copy distinguishes signer provenance and locked-use installation verifies source and installed artifacts against the selected trust mode before privileged activation.

Define response reason values exactly as `external_write_detected`, `restore_failed`, or null. State that external-write detection returns `pasteboardRestored=false`, leaves current bytes untouched, and classifies the action `effect_not_verified` even if Command-V dispatched.

**Verify**: `if command -v openspec >/dev/null; then openspec validate protect-user-data-and-install-trust --strict; else echo 'openspec unavailable; validation skipped'; fi` → strict validation passes, or the exact skip message is printed.

### Step 2: Guard snapshot restoration with pasteboard generation ownership

Replace `restoreSucceeded` with an explicit internal outcome:

```swift
enum PasteboardRestoreOutcome: Equatable, Sendable {
    case notModified
    case restored
    case externalWriteDetected
    case restoreFailed

    var originalRestoredOrUntouched: Bool {
        self == .notModified || self == .restored
    }
}
```

In `PasteTransaction.perform`, capture `changeCount` before BCU writes, call `PasteboardPayload.write`, then record `ownedChangeCount` immediately after that call. Run dispatch only on successful payload write. Determine restoration as follows:

```swift
if pasteboard.changeCount == beforeWriteChangeCount {
    outcome = .notModified
} else if pasteboard.changeCount != ownedChangeCount {
    outcome = .externalWriteDetected       // do not call clearContents or restore
} else {
    outcome = snapshot.restore(to: pasteboard) ? .restored : .restoreFailed
}
```

This also safely handles a failed payload write that did mutate/clear the board: restore only if its post-write generation is still current. Keep `PasteboardSnapshot.restore` byte-for-byte behavior; generation ownership belongs to the transaction around it.

**Verify**: `swift test --filter PasteRouteTests` → original restoration still passes, and an external write made inside the dispatch closure remains current after `perform` returns.

### Step 3: Report external-write detection honestly in the paste contract

Add to `PasteContracts.swift`:

```swift
public enum PasteboardRestoreReasonDTO: String, Encodable, Sendable {
    case externalWriteDetected = "external_write_detected"
    case restoreFailed = "restore_failed"
}
```

Add `pasteboardRestoreReason: PasteboardRestoreReasonDTO?` beside `pasteboardRestored`. Map `.notModified`/`.restored` to true/nil, `.externalWriteDetected` to false/external reason, and `.restoreFailed` to false/failed reason.

In `PasteRouteService`, distinguish summaries and notes. For external detection say the newer clipboard was left untouched; never claim BCU restored the original. Both false outcomes remain `effect_not_verified` in verification domain. Add the response field and enum values to RouteRegistry and update APIDocumentation success signals.

**Verify**: `swift test --filter PasteRouteTests && swift test --filter APIDocumentationTests` → encoded response/schema contain the exact reason values and no fallback note falsely claims restoration.

### Step 4: Test the real named pasteboard race

Extend the serialized `PasteRouteTests` pattern with `NSPasteboard(name: .init("bcu-paste-test-\(UUID().uuidString)"))`. Start with `original`; in `PasteTransaction.perform`'s dispatch closure clear/write `user-new-copy`, then return true. Assert payload/dispatch succeeded, outcome is `.externalWriteDetected`, and the final `.string` is exactly `user-new-copy`. Add a no-external-write case asserting `.restored`, and keep the failed-dispatch complete representation test.

Add a response encoding/schema assertion for `pasteboardRestoreReason == "external_write_detected"`. Do not use `.general` in tests.

**Verify**: `swift test --filter PasteRouteTests` → deterministic named-pasteboard cases pass repeatedly without touching the user's clipboard.

### Step 5: Model and render signer provenance

Add a public `SignerProvenance: Equatable, Sendable` in `CodeSignatureIdentity.swift` with cases `teamID(String)`, `applePlatform(String)`, `certificateSHA256(String)`, and `adHocCDHash(String)`. Its initializer parses only the exact generated prefixes; an unprefixed signer is `.teamID`. Keep `AppIdentity.teamID` serialized storage unchanged.

Update `ApprovalPresentationCopy.make` to render distinct PT-BR text and accessibility copy:

- team: `Equipe de assinatura: <ID>`;
- Apple platform: `Código assinado pela plataforma Apple: <ID>`;
- certificate: `Impressão digital do certificado (SHA-256): <digest>` plus `A equipe Apple não pôde ser identificada.`;
- ad-hoc: `Binário assinado ad hoc (hash): <hash>` plus exact warning `Sempre permitir vale só para este binário (hash) e expira ao recompilar`.

For ad-hoc only, change the second button label to `Sempre permitir este binário`; keep its decision `.alwaysAllow`. Never call certificate fingerprint or ad-hoc hash “Assinante verificado.” Preserve scope, bundle ID, and accessible labels.

**Verify**: `swift test --filter ControlViewModelTests` → table-driven cases for all four raw signer forms assert distinct message/accessibility copy and the exact ad-hoc expiry warning.

### Step 6: Enforce production versus local locked-use trust before copy

Make argument parsing explicit: only `--dry-run` and `--install`; reject anything else. Keep dry-run nonprivileged. Production mode requires `BACKGROUND_COMPUTER_USE_LOCKED_TEAM_ID` and verifies both source artifacts with `codesign --verify --strict` (`--deep` for the bundle), prints each designated requirement with `codesign -d -r -`, and applies this requirement with `codesign --verify -R`:

```text
anchor apple generic and certificate leaf[subject.OU] = "<EXPECTED_TEAM_ID>"
```

Also require each artifact's reported `TeamIdentifier` equals the expected environment value. Do not derive the expected trust anchor from the artifact being checked.

Immediately before `ditto`/`install`, rerun source verification for both artifacts. After copy/chown, run the same strict integrity and production requirement checks on both destination artifacts before `launchctl bootstrap` or `security authorizationdb write`. Any failure exits through existing rollback.

`BCU_LOCKED_USE_ALLOW_LOCAL_SIGNING=1` is a separate development mode: print a loud warning containing `UNSAFE LOCAL SIGNING; DISPOSABLE VM/SECONDARY MAC ONLY`, require strict integrity and designated-requirement display for both artifacts, but skip the Apple-anchor requirement that local/ad-hoc code cannot satisfy. Never default this variable or persist it.

**Verify**: `bash -n script/install_locked_use.sh` → exit 0; inspection shows both source and destination verification occur before launchctl/authorizationdb mutation.

### Step 7: Exercise only the safe dry-run path and document the boundary

Run local-signing dry-run with a nonempty test peer payload; it may build/sign files under repo `dist/` but must exit before root checks, copies, launchctl, or authorizationdb writes. Keep the existing dry-run diff/plan output and ensure it prints the unsafe warning.

Update `docs/locked-use-recovery.md` with the production TEAM variable, explicit local override, and the existing primary-host prohibition. State that dry-run is not qualification and real install belongs only on a disposable VM or secondary Mac.

**Verify**: `BACKGROUND_COMPUTER_USE_LOCKED_ALLOWED_PEERS='[]' BCU_LOCKED_USE_ALLOW_LOCAL_SIGNING=1 script/install_locked_use.sh --dry-run` → exits 0, prints the unsafe warning plus `dry-run only; no authorization database or system file was changed`, and performs no privileged mutation.

### Step 8: Run the final non-live gate

Run the two focused suites, shell syntax, then the full test suite. Do not execute the real installer.

**Verify**: `swift test --filter PasteRouteTests && swift test --filter ControlViewModelTests && bash -n script/install_locked_use.sh && swift test` → all commands exit 0.

## Test plan

- `PasteRouteTests.swift`: named pasteboard preserves all original types, restores after failed dispatch, leaves an external dispatch-time copy byte-for-byte untouched, and maps both failure reasons into DTO/schema.
- `ControlViewModelTests.swift`: table-drive plain team, Apple platform, certificate SHA-256, and ad-hoc cdhash; assert PT-BR visual/accessibility copy and ad-hoc button/warning.
- Shell verification is syntax plus `--dry-run` only. It must never use `--install`, sudo, launchctl bootstrap, or authorizationdb write in this plan.
- OpenSpec scenarios cover generation unchanged, external generation changed, copy trust failure, installed-byte recheck failure, and explicit unsafe local mode.
- Verification: `swift test --filter PasteRouteTests && swift test --filter ControlViewModelTests` → all existing and new tests pass.

## Done criteria

- [ ] Paste restoration occurs only when BCU's post-write `changeCount` is still current.
- [ ] A dispatch-time external copy remains untouched and produces `pasteboardRestored=false` plus `external_write_detected`.
- [ ] `/v1/routes`, DTOs, APIDocumentation, and OpenSpec agree on the additive paste reason field.
- [ ] Four signer namespaces render distinct PT-BR copy; ad-hoc copy includes the exact rebuild-expiry warning.
- [ ] App policy remains keyed by full `AppIdentity`; no persistence migration was added.
- [ ] Production locked-use mode requires an operator-provided expected Team ID and Apple-anchored requirement for both artifacts.
- [ ] Both source and installed plugin/broker are reverified before launchctl or authorizationdb mutation.
- [ ] Local signing requires the explicit unsafe override and emits the loud disposable-host warning.
- [ ] Only dry-run was exercised; `swift test` exits 0.
- [ ] `git status --short` shows only in-scope files and pre-existing baseline changes.
- [ ] `plans/README.md` status row is updated.

## STOP conditions

Stop and report back (do not improvise) if:

- `NSPasteboard.changeCount` does not advance for BCU writes on the unique test pasteboard; do not substitute timing guesses.
- Preserving an external copy would require clearing or reading it after generation mismatch.
- Any change would broaden `alwaysAllow` beyond exact `AppIdentity` persistence.
- Production artifact verification cannot use an expected Team ID supplied independently of the artifacts.
- Dry-run reaches a privileged copy, `launchctl bootstrap`, or `security authorizationdb write` path.
- Testing would require a primary-host locked-use install; `docs/locked-use-recovery.md:46-50` forbids qualification there.
- A focused verification fails twice after a reasonable fix attempt.

## Maintenance notes

- Clipboard generation is an ownership heuristic, not a lock. Future paste transports must preserve the “mismatch means leave current data untouched” invariant.
- If a new signer namespace is added to `CodeSignatureSignerID`, add a provenance case and human/accessibility copy in the same change.
- Review installer ordering, not just presence of commands: source verify → copy → destination verify → launchctl/auth mutation.
- The local-signing escape hatch is deliberately noisy and unsuitable for release instructions or a primary host.