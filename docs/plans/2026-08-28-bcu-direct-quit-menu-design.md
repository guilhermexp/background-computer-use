# BCU Direct Quit Menu Design

**Date:** 2026-08-28

## Problem

The menu bar distinguishes pausing from stopping an automation session, but it has no visible command
to terminate BackgroundComputerUse itself. After `Parar sessão`, the process remains running and the
user must resort to Terminal or another process-management surface.

## Selected design

Add an always-enabled `Sair do BCU` item at the bottom of the menu, after `Ajustes…` and a separator.
Use the standard Command-Q keyboard equivalent. Activation quits immediately without confirmation,
matching the user's explicit choice and normal macOS menu-bar behavior.

The quit path first stops the current control session, which revokes mutation authority, ends active
policies, and disables Locked Use through the existing `SessionControls` cleanup. Only after that
cleanup completes does it invoke the native application termination callback.

## Architecture

`ControlViewModel` owns the ordered quit operation because it already owns the session-state commands.
It receives an injectable `onQuit` callback, exposes `quit()`, calls `stop()`, and then calls `onQuit`.
`BCUControlRuntime` supplies `NSApplication.shared.terminate(nil)` as the production callback.

`MenuBarController` adds the user-facing item and delegates its selector to `model.quit()`. The item
stays enabled even when the session is already stopped, because process termination and session state
are separate operations.

## Alternatives rejected

- Terminating directly inside `MenuBarController` is smaller but bypasses a testable cleanup boundary.
- Calling `exit` or killing the process can skip application and control-session cleanup.

## Verification

TDD covers the ordering contract: the session must be stopped before the termination callback runs.
A menu-level test covers the Portuguese label, Command-Q shortcut, and availability while stopped.
Live macOS QA opens the menu, activates `Sair do BCU`, confirms the process exits, relaunches the signed
release, and confirms the runtime becomes healthy again.
