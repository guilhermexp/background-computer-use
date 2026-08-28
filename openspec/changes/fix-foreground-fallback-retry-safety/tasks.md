# Tasks

## 1. Public retry and foreground contract

- [x] 1.1 Add required `retrySafe`, `foregroundFallbackUsed`, and `foregroundRestored` fields to the
  `type_text` response DTO and self-documenting route schema.
- [x] 1.2 Add required `foregroundFallbackUsed` and `foregroundRestored` fields to `launch_app`.
- [x] 1.3 Derive retry safety from actual attempted text strategies and dispatch outcome.

## 2. Controlled foreground coordination

- [x] 2.1 Capture the original foreground application and distinguish background, exact-target
  fallback, and unrelated user transition.
- [x] 2.2 Activate the exact target PID at most once when background preparation cannot proceed.
- [x] 2.3 Restore the original app only while the target is still frontmost.

## 3. One-shot type_text and launch completion

- [x] 3.1 Keep exact target-bound text strategies first and move foreground preparation to the
  PID-Unicode fallback boundary.
- [x] 3.2 Report every attempted text strategy and dispatch text at most once per request.
- [x] 3.3 Return dispatched opaque text as `verifier_ambiguous` with `retrySafe=false`.
- [x] 3.4 Preserve exact verified text success independently from foreground restoration telemetry.
- [x] 3.5 Keep a resolved or launched signed app successful and conditionally restore foreground
  without relaunching an already-running app.

## 4. Nonactivating activity presentation

- [x] 4.1 Use a transient panel that cannot become key or main, ignores mouse events, and does not
  activate BCU Control.
- [x] 4.2 Preserve the existing activity-card preference, replacement, and dismissal behavior.

## 5. Caller and qualification guidance

- [x] 5.1 Instruct callers to reread after `retrySafe=false` and never repeat `type_text` blindly.
- [x] 5.2 Add Python retry-contract policy and keep Safari background proof strict and separate from
  controlled-fallback evidence.
- [x] 5.3 Update the parity audit without claiming unrun live fallback or nonactivation evidence.

## 6. Gates

- [x] 6.1 Run the complete Python helper suite and
  `openspec validate fix-foreground-fallback-retry-safety --strict`.
- [ ] 6.2 Run the repository-wide SwiftFormat lint without findings. The installed 0.62.1 CLI
  rejects the option-first command, and its equivalent reports 88/248 pre-existing files while the
  18 changed Swift files pass 0/18.
- [x] 6.3 Run `swift build -c release` and `swift test` once at final qualification.
- [x] 6.4 Build, sign, install, and verify the universal app after the 17 changed Swift files pass
  scoped format lint; the unrelated repository-wide 88/248 baseline remains recorded separately.
- [ ] 6.5 Run live background/fallback and nonactivating-card smoke on a paused real target without
  automatic retry. Background/card behavior and opaque non-retry telemetry passed; an exact
  `foregroundFallbackUsed=true` restoration trace remains pending.
