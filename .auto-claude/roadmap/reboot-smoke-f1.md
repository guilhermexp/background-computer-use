# Reboot continuation — F1 click evidence

## Repo state

- Repo: `/Users/guilhermevarela/Documents/Projetos/SelfHosting/background-computer-use`
- Branch: `fix/bcu-web-reliability`
- Change: `fix-uncontaminated-click-evidence` — 22/23 tasks; only live smoke 6.3 remains.
- Implementation commits: `e782f56` (uncontaminated cursor/focus evidence), `d8b6bec` (post-focus baseline for ambient churn).
- Change artifacts commit: `6abc7f1`.
- Installed app is the debug build from `d8b6bec`; bundle permissions were green before reboot.
- Leave pre-existing `multiplan-artifacts/` untracked and untouched.

## Proven before reboot

- `swift build -c release` passes.
- `swift test`: 204 tests, only pre-existing `ocrRecognitionReportsItsOwnDuration` fails.
- `openspec validate fix-uncontaminated-click-evidence --strict` passes.
- Live smoke on `e782f56` proved the original false positive is gone:
  - `ocrAnchorDisappeared=False` (was True).
  - `intentSignals=[]`, `classification=effect_not_verified` (was false-positive success).
  - Real AX click still reports `focused_element_changed` and succeeds.
- That smoke also found transport-created `rendered_text_changed` + `selection_summary_changed` blocked AX escalation. Commit `d8b6bec` adds a full post-focus/pre-mouse baseline without weakening `windowStillSettling` for genuine churn.

## Why reboot

The macOS AX subsystem became globally wedged before `d8b6bec` could be smoke-tested:

- BCU returned 0 AX windows for Chrome, TextEdit and Finder.
- Independent `macos-harness state TextEdit` also returned only `AXApplication`, 0 `AXWindow`.
- CGWindow still saw the real TextEdit/Chrome windows.
- `AXIsProcessTrusted` remained true in both tools.
- Restarted verified user services `universalaccessd` (PID 953 → 69365) and `AccessibilityUIServer` (1064 → 72939), then relaunched TextEdit; AX remained wedged.
- User explicitly chose a Mac reboot.

## First action after reboot

1. Start the installed BCU runtime (`script/start.sh` or the skill ensure-runtime helper) and confirm `/v1/bootstrap` ready.
2. Confirm independent AX health: launch TextEdit and ensure both BCU `list_windows` and `macos-harness state TextEdit` see an `AXWindow`.
3. Run `python3 script/smoke_runtime.py`.
4. Required F1 result: `chrome-ocr-click` must actually change the fixture. Expected recovery route is `coordinate_then_ax_hit_test` with `fallbackReason=coordinate_unverified_using_ax_hit_test`. Static-page transport churn must not appear as ambient; genuine live-page churn remains guarded.
5. If green, mark task 6.3 complete, record literal smoke output, validate OpenSpec strict, commit the task result, then decide whether to archive/push.
6. If red, do not weaken `windowStillSettling`; capture `classification`, `finalRoute`, `fallbackReason`, signals and region/full-image ratios before changing code.
