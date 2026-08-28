# BCU macOS parity completion audit

Date: 2026-08-28

This audit treats completion as unproven unless current executable evidence covers the requirement.

| ID | Requirement | Authoritative evidence | Status |
| --- | --- | --- | --- |
| R1 | Exact PID/window discovery and background reads | Signed smoke isolates Chrome and Safari PIDs/windows; `get_window_state`, screenshots, OCR, and `find_elements` pass | Proven locally |
| R2 | Truthful semantic and visual click | Shared verifier requires non-empty intent signals; signed smoke passes semantic Chrome and OCR-anchor promotion; three additional cold Chrome runs passed | Proven locally |
| R3 | Background text that handles ignored AX writes | The new signed smoke passed both Safari background lanes: plain AX value and ignored-write `ax_value + ax_text_operation`, with exact value/selection, foreground preservation, named strategies, and `retrySafe=false`. A real Termio opaque post reported `pid_unicode`, `dispatchSucceeded=true`, `verifier_ambiguous`, and `retrySafe=false`; the caller reread once and did not retry. Controlled foreground activation/restoration remains covered by Swift tests rather than a live fallback-used trace | Proven locally; live foreground-fallback-used evidence pending |
| R4 | Clipboard-safe text/Markdown/HTML paste | Complete multi-item/type/byte snapshot tests; target-bound path leaves clipboard untouched; fallback restores on every exit; 10/10 signed trials | Proven locally |
| R5 | Latency equal to or better than current native Computer Use | Final universal release BCU end-to-end wall p50/p95: type 130.08/148.54 ms, click 206.06/210.48 ms, paste 204.72/209.03 ms. Current native verified batch: type about 414 ms, click about 439 ms, paste about 688 ms. Native 10-trial monolithic run lost its pipe after seven partial iterations; BCU completed 10/10 each | Proven locally |
| R6 | Zero false success and foreground preservation | Final signed smoke completed 30/30. A real opaque Termio dispatch was explicitly ambiguous and non-retryable, so no duplicate request was issued. Foreground activation waits synchronously for 2 s, then retains a 5-second recovery observer; target-late and third-app-precedence races are covered by tests. The target's internal Termio session could not be identified reliably after the dispatch, so exact same-pane delivery is not claimed | Background/retry honesty proven; exact opaque same-pane routing pending |
| R7 | Chromium/Electron cold accessibility | Signed AX bootstrap worker, per-process observer/cache, and unique same-point OCR-to-semantic promotion; full smoke and three cold Chrome runs pass | Proven locally |
| R8 | Signed app approval and nonactivating launch | Identity is bundle ID + signer + designated requirement; `launch_app` still requests `activates=false`. A new signed call against already-running Termio returned `success`, did not relaunch it, and kept the observed foreground PID unchanged. Swift tests separately prove target activation, asynchronous restoration, and third-app precedence | Proven locally; live restoration-after-target-activation pending |
| R9 | Menu bar, policy settings, permission status, PiP/history, pause/resume/stop/quit | The signed activity card was sampled immediately, at 100 ms, 600 ms, and after its 2.2-second lifecycle while ego lite remained frontmost throughout. The panel refuses key/main status and ignores mouse events; the single-card replacement, preference, history, pause/resume/stop/quit behavior remain covered by tests and prior QA | Proven locally |
| R10 | Core crash boundary | Same-signer embedded Core XPC; both sides validate identity; kill during pause relaunches/rehydrates paused state and blocks mutation until explicit resume | Proven locally |
| R11 | Security boundaries | Loopback token, strict request decode, rate/session limiting, signed-server Control requirement fails closed, protected-app deny, arbitrary `run_script` blocked under Control, exact-target focus before clipboard paste, separate broker peer roles, benchmark output allowlists non-secret runtime metadata, no secret findings | Proven locally |
| R12 | Locked-use state/lease/broker/plugin/shields/recovery implementation | One-use 256-bit lease, authenticated Control and root-configured Core bindings, replay/expiry/binding tests, pre-consume physical-input revocation, one-shot relock, manual-unlock shield removal, concurrent-deactivate denial in the plug-in model/ABI, first-backup preservation, exported `AuthorizationPluginCreate`, 5x dlopen host smoke, dry-run installer and digest-checked recovery | Proven without system installation |
| R13 | Locked-use install, actual lock/unlock, crash/reboot, uninstall, and exact restoration | Requires signed Developer ID artifacts and a disposable macOS VM or secondary Mac; no such host is available and the primary host was intentionally not modified | Missing external evidence |

## Current gates

- Python helpers: 19 tests passed after three retry-policy RED cycles, including failed dispatch,
  missing required fields, and invalid field types.
- OpenSpec strict: `fix-foreground-fallback-retry-safety` is valid.
- SwiftFormat 0.62.1: the requested option-first command was rejected by the installed CLI; the
  equivalent repository-wide lint reports 88/248 pre-existing files, while the 18 changed Swift
  files pass 0/18.
- Swift release build: pass.
- Swift: 382 tests in 58 suites passed with `--no-parallel`. Two subprocess-success tests exceeded
  their 2-second deadlines only under the fully concurrent runner and passed in isolated reruns;
  the deterministic serial full suite is authoritative.
- Signed universal build: pass; app/Core XPC are `x86_64 + arm64`, deep signature verification and
  designated-requirement checks pass, and the corrected app is installed/running.
- Signed smoke: final rerun 30 pass, 0 fail, 0 skip. An earlier run had one transient Safari plain
  input verification miss; direct background reproduction passed with exact value/selection and the
  complete unchanged rerun passed 30/30.
- Live card/launch foreground sampling: WhatsApp remained frontmost before, immediately after, at
  100 ms, 600 ms, and after 2.2 seconds on the final installed build.
- Live Termio opaque text: dispatch named `pid_unicode`, set `retrySafe=false`, returned
  `verifier_ambiguous`, and was not retried. Exact internal-session routing was not established.
- Historical evidence retained: extra cold Chrome 3/3; Core XPC crash smoke pass; plug-in host 5/5;
  secret scan reported no leaks.

The new signed evidence proves background behavior, retry honesty, and nonactivating-card behavior.
It does not prove a live `foregroundFallbackUsed=true` restoration sequence or exact routing among
multiple AX-opaque sessions inside one Termio window. AppKit offers no activation completion or
cancellation API; the accepted operational bound is 2 s synchronous observation plus 5 s retained
recovery.

## Completion decision

B1 and B2 are corrected and qualified for the observed failure modes: possible text effects are
non-retryable and named, completed launch no longer fails solely on foreground telemetry, and the
activity card does not take foreground. A separate live qualification is still needed for controlled
foreground restoration and exact routing among multiple opaque sessions in one window. Total product
parity also remains unproven for R13; the primary Mac is not an acceptable substitute for the
required disposable-host qualification.
