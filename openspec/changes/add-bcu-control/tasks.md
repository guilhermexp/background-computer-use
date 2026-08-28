# Tasks

- [x] Implement signature-bound identity and atomic policy persistence.
- [x] Validate peers from audit tokens and designated requirements.
- [x] Add fail-closed authorization and `launch_app`.
- [x] Add menu bar, approval UI, settings, and protected-app policy.
- [x] Add PiP activity, history, pause/resume, and stop.
- [x] Move session authority into a signed embedded Core XPC service and repeat crash-boundary smoke.

Signed Control evidence: real allow-once and always-allow dialogs passed, `launch_app` returned exact PID with `activates=false`, and PiP visual QA observed one reusable card during rapid actions and zero cards 2.3 seconds after the final action. Settings now expose an enabled-by-default persisted `Mostrar cartão de atividades` toggle; disabling it persisted across relaunch and suppressed every later card while history remained upstream. The card render consumes the invisible title-bar inset and starts at its 14-point internal padding. Pause blocked mutation while preserving reads, and stop blocked every `/v1` route while keeping `/health` alive. The embedded `BackgroundComputerUseCoreXPCService` is signed inside the app; killing it while paused preserved reads, preserved the mutation block, auto-relaunched the authority, and allowed explicit resume.
