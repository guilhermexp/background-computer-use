# Change: Add BCU locked use

## Why

An active BCU task must be able to continue after the macOS screen locks without exposing a generic
unlock path or weakening normal login authorization.

## What changes

- Add a short-lived, one-use, signer-bound lease consumed by a root broker.
- Add a minimal authorization plug-in mechanism only to `system.login.screensaver`.
- Add full-display shields, local-input relock, heartbeat/dependency relock, and independent recovery.
- Keep locked use disabled by default and require explicit user opt-in plus qualified installation.

## Safety

Never modify `system.login.console`. Any replay, expiry, wrong session/user/boot/signer, dependency
loss, shield loss, local input, or broker error denies or relocks. Installation is dry-run first and
primary-host eligibility requires VM or secondary-Mac qualification.
