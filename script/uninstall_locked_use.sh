#!/bin/bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
RIGHT="system.login.screensaver"
BACKUP_PATH="/var/db/BackgroundComputerUse/locked-use-rule-backup.json"
BUNDLE_DESTINATION="/Library/Security/SecurityAgentPlugins/BCUAuthorizationPlugin.bundle"
BROKER_DESTINATION="/Library/PrivilegedHelperTools/xyz.dubdub.backgroundcomputeruse.locked-broker"
LAUNCHD_PLIST="/Library/LaunchDaemons/xyz.dubdub.backgroundcomputeruse.locked-broker.plist"

if [[ "$EUID" -ne 0 ]]; then
  echo "blocked: uninstall requires an administrator" >&2
  exit 4
fi
test -f "$BACKUP_PATH"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT
RESTORED_RULE="$WORK_DIR/restored.plist"
swift run -c release BackgroundComputerUseLockedRecovery recover \
  --backup "$BACKUP_PATH" --output "$RESTORED_RULE"
security authorizationdb write "$RIGHT" < "$RESTORED_RULE"
launchctl bootout system "$LAUNCHD_PLIST" 2>/dev/null || true
rm -rf "$BUNDLE_DESTINATION"
rm -f "$BROKER_DESTINATION" "$LAUNCHD_PLIST"
rm -f "$BACKUP_PATH"
echo "uninstalled right=$RIGHT backup_removed=$BACKUP_PATH"
