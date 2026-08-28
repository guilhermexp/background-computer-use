# BCU macOS parity completion audit

Date: 2026-08-27

This audit treats completion as unproven unless current executable evidence covers the requirement.

| ID | Requirement | Authoritative evidence | Status |
| --- | --- | --- | --- |
| R1 | Exact PID/window discovery and background reads | Signed smoke isolates Chrome and Safari PIDs/windows; `get_window_state`, screenshots, OCR, and `find_elements` pass | Proven locally |
| R2 | Truthful semantic and visual click | Shared verifier requires non-empty intent signals; signed smoke passes semantic Chrome and OCR-anchor promotion; three additional cold Chrome runs passed | Proven locally |
| R3 | Background text that handles ignored AX writes | AX value fast path plus target-bound WebKit text operation in signed Safari smoke; focused PID Unicode orchestration is covered separately by Swift tests; both retain exact same-element value/selection verification and partial-mutation fail-closed behavior | Proven locally |
| R4 | Clipboard-safe text/Markdown/HTML paste | Complete multi-item/type/byte snapshot tests; target-bound path leaves clipboard untouched; fallback restores on every exit; 10/10 signed trials | Proven locally |
| R5 | Latency equal to or better than current native Computer Use | Final universal release BCU end-to-end wall p50/p95: type 130.08/148.54 ms, click 206.06/210.48 ms, paste 204.72/209.03 ms. Current native verified batch: type about 414 ms, click about 439 ms, paste about 688 ms. Native 10-trial monolithic run lost its pipe after seven partial iterations; BCU completed 10/10 each | Proven locally |
| R6 | Zero false success and foreground preservation | Final benchmark: 10/10 completions per lane, zero false success, zero foreground violations | Proven locally |
| R7 | Chromium/Electron cold accessibility | Signed AX bootstrap worker, per-process observer/cache, and unique same-point OCR-to-semantic promotion; full smoke and three cold Chrome runs pass | Proven locally |
| R8 | Signed app approval and nonactivating launch | Identity is bundle ID + signer + designated requirement; real allow-once/always dialogs; `launch_app` returns exact PID/windows with `activates=false` | Proven locally |
| R9 | Menu bar, policy settings, permission status, PiP/history, pause/resume/stop/quit | Real menu/approval QA; one reusable PiP card was observed during rapid actions and zero cards remained 2.3 seconds after the final action; its empty title-bar inset was removed; an enabled-by-default persisted setting can suppress cards without suppressing history; settings expose macOS permission panes; pause allows reads and blocks mutations; stop revokes `/v1` while `/health` remains; `Sair do BCU` is always enabled with Command-Q, stops the session, terminates the process, and the signed app relaunches healthy | Proven locally |
| R10 | Core crash boundary | Same-signer embedded Core XPC; both sides validate identity; kill during pause relaunches/rehydrates paused state and blocks mutation until explicit resume | Proven locally |
| R11 | Security boundaries | Loopback token, strict request decode, rate/session limiting, signed-server Control requirement fails closed, protected-app deny, arbitrary `run_script` blocked under Control, exact-target focus before clipboard paste, separate broker peer roles, benchmark output allowlists non-secret runtime metadata, no secret findings | Proven locally |
| R12 | Locked-use state/lease/broker/plugin/shields/recovery implementation | One-use 256-bit lease, authenticated Control and root-configured Core bindings, replay/expiry/binding tests, pre-consume physical-input revocation, one-shot relock, manual-unlock shield removal, concurrent-deactivate denial in the plug-in model/ABI, first-backup preservation, exported `AuthorizationPluginCreate`, 5x dlopen host smoke, dry-run installer and digest-checked recovery | Proven without system installation |
| R13 | Locked-use install, actual lock/unlock, crash/reboot, uninstall, and exact restoration | Requires signed Developer ID artifacts and a disposable macOS VM or secondary Mac; no such host is available and the primary host was intentionally not modified | Missing external evidence |

## Current gates

- Swift: 339 tests in 57 suites passed.
- Python helpers: 7 focused smoke/benchmark tests passed.
- Universal release signed app smoke: 30 pass, 0 fail, 0 skip.
- Extra cold Chrome reliability: 3/3 pass.
- Core XPC crash smoke: pass.
- Plug-in dedicated host smoke: 5/5 load/invoke/deactivate/destroy/unload; deny without broker.
- OpenSpec strict: engine, Control, and locked-use changes valid.
- Universal release app/Core XPC contain arm64 + x86_64, pass deep signature verification, and run on the current arm64 host. Authorization plug-in, broker, and recovery tool also build in release.
- Secret scan: no leaks.

## Completion decision

Unlocked-session macOS parity is proven and exceeds the current native verified latency on the tested
Safari/Chrome fixtures. Total product parity remains unproven only for R13. The primary Mac is not an
acceptable substitute for the required disposable-host qualification.
