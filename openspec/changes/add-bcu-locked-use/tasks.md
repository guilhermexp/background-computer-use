# Tasks

- [x] Implement state machine and exact authorization-rule snapshot.
- [x] Implement one-use leases and privileged broker validation.
- [x] Implement minimal AuthorizationPlugin callbacks and dedicated-host tests.
- [x] Implement dry-run installer, exact registration, and independent recovery.
- [x] Implement shields, local-input relock, and Control integration.
- [ ] Qualify signed install/crash/reboot/uninstall on a disposable VM or secondary Mac.

Local non-mutating qualification: release plug-in/broker/recovery builds pass, `_AuthorizationPluginCreate` is exported, a dedicated host loaded/invoked/deactivated/destroyed/unloaded the real bundle five times and observed deny without a broker, current `system.login.screensaver` was read only, and install was not run. This host has no disposable VM or secondary Mac.
