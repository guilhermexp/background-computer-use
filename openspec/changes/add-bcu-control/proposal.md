# Change: Add BCU Control

## Why

The background engine now matches the native macOS action lanes, but it lacks a user-owned policy
authority, explicit app approvals, session controls, activity UI, and nonactivating app launch.

## What changes

- Add signature-bound app identity and `ask`, allow-once, persistent allow, and deny decisions.
- Add a fail-closed Control/Core authority boundary.
- Add `launch_app`, menu-bar approval, protected-app defaults, PiP activity, pause, resume, and stop.
- Preserve the loopback API while requiring Control authorization for newly accessed apps.

## Safety

PID is never persisted as identity. Missing Control, invalid signatures, timeout, dismissal, and
protected-app requests deny. Stop revokes the session and every locked-use lease.
