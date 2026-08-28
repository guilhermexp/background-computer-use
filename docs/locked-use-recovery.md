# BCU locked-use recovery

Locked use modifies only `system.login.screensaver`. It never modifies `system.login.console`.

The root-owned broker configuration must contain exactly one signed identity for each peer role:
`control`, `core`, and `authorization_host`. Lease arming is rejected unless its Control designated
requirement matches the authenticated Control connection and its Core designated requirement matches
the separately configured Core identity.

## Normal removal

Run the reviewed recovery command from an administrator session:

```bash
sudo script/uninstall_locked_use.sh
```

The command validates the protected backup digest, restores the exact prior authorization rule,
boots out the broker LaunchDaemon, and removes the BCU plug-in and broker executable. It never asks
for or records a password; `sudo` authentication remains an external user handoff.

Reinstallation preserves the first valid backup. If the BCU mechanism is already present but that
backup is missing or invalid, installation fails closed instead of backing up the already-modified
rule.

## If Control and Core do not start

The recovery executable is independent of both. Validate the backup and materialize the original
rule without changing the authorization database:

```bash
swift run -c release BackgroundComputerUseLockedRecovery recover \
  --backup /var/db/BackgroundComputerUse/locked-use-rule-backup.json \
  --output /tmp/bcu-restored-screensaver.plist
```

Inspect the output, then restore it from an administrator session:

```bash
sudo security authorizationdb write system.login.screensaver < /tmp/bcu-restored-screensaver.plist
```

Do not write `system.login.console`. If the backup digest fails, stop and restore from the host or VM
snapshot rather than constructing a replacement login rule by hand.

## Qualification boundary

Installation on a primary Mac is ineligible until a disposable VM or secondary Mac passes install,
one-use unlock, multi-display shields, local-input relock, expiry/replay denial, broker/Control/Core
death, reboot, uninstall, and semantic equality with the original rule.
