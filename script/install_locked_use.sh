#!/bin/bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
RIGHT="system.login.screensaver"
BUNDLE_SOURCE="$REPO_DIR/dist/BCUAuthorizationPlugin.bundle"
BUNDLE_DESTINATION="/Library/Security/SecurityAgentPlugins/BCUAuthorizationPlugin.bundle"
BROKER_SOURCE="$REPO_DIR/dist/BackgroundComputerUseLockedBrokerService"
BROKER_DESTINATION="/Library/PrivilegedHelperTools/xyz.dubdub.backgroundcomputeruse.locked-broker"
LAUNCHD_PLIST="/Library/LaunchDaemons/xyz.dubdub.backgroundcomputeruse.locked-broker.plist"
BACKUP_PATH="/var/db/BackgroundComputerUse/locked-use-rule-backup.json"
ALLOWED_PEERS_JSON="${BACKGROUND_COMPUTER_USE_LOCKED_ALLOWED_PEERS:-}"
ALLOWED_PEERS_BASE64="$(printf '%s' "$ALLOWED_PEERS_JSON" | /usr/bin/base64)"
MODE="dry-run"
if [[ "${1:-}" == "--install" ]]; then MODE="install"; fi

"$REPO_DIR/script/build_locked_use.sh"
codesign --verify --deep --strict "$BUNDLE_SOURCE"
TEAM_ID="$(codesign -dv --verbose=4 "$BUNDLE_SOURCE" 2>&1 | awk -F= '/^TeamIdentifier=/{print $2}')"
if [[ -z "$TEAM_ID" || "$TEAM_ID" == "not set" ]]; then
  echo "blocked: locked use requires a Developer ID signature with TeamIdentifier" >&2
  exit 3
fi
if [[ -z "$ALLOWED_PEERS_JSON" ]]; then
  echo "blocked: BACKGROUND_COMPUTER_USE_LOCKED_ALLOWED_PEERS must contain exact signed peer identities" >&2
  exit 5
fi

WORK_DIR="$(mktemp -d)"
INSTALL_STARTED=0
INSTALL_FINISHED=0
cleanup() {
  STATUS=$?
  if [[ "$INSTALL_STARTED" -eq 1 && "$INSTALL_FINISHED" -eq 0 ]]; then
    security authorizationdb write "$RIGHT" < "$CURRENT_RULE" >/dev/null 2>&1 || true
    launchctl bootout system "$LAUNCHD_PLIST" >/dev/null 2>&1 || true
    rm -rf "$BUNDLE_DESTINATION"
    rm -f "$BROKER_DESTINATION" "$LAUNCHD_PLIST"
  fi
  rm -rf "$WORK_DIR"
  return "$STATUS"
}
trap cleanup EXIT
CURRENT_RULE="$WORK_DIR/current.plist"
UPDATED_RULE="$WORK_DIR/updated.plist"
LOCAL_BACKUP="$WORK_DIR/backup.json"
security authorizationdb read "$RIGHT" > "$CURRENT_RULE"
PLAN_ARGUMENTS=(
  plan
  --right "$RIGHT"
  --rule "$CURRENT_RULE"
  --updated "$UPDATED_RULE"
  --backup "$LOCAL_BACKUP"
  --signature-valid true
)
if [[ -f "$BACKUP_PATH" ]]; then
  PLAN_ARGUMENTS+=(--existing-backup "$BACKUP_PATH")
fi
swift run -c release BackgroundComputerUseLockedRecovery "${PLAN_ARGUMENTS[@]}"

diff -u <(plutil -convert xml1 -o - "$CURRENT_RULE") <(plutil -convert xml1 -o - "$UPDATED_RULE") || true
if [[ "$MODE" == "dry-run" ]]; then
  echo "dry-run only; no authorization database or system file was changed"
  exit 0
fi

if [[ "$EUID" -ne 0 ]]; then
  echo "blocked: rerun this already-reviewed command as an administrator" >&2
  exit 4
fi
install -d -o root -g wheel -m 700 "$(dirname "$BACKUP_PATH")"
install -o root -g wheel -m 600 "$LOCAL_BACKUP" "$BACKUP_PATH"
INSTALL_STARTED=1
ditto "$BUNDLE_SOURCE" "$BUNDLE_DESTINATION"
chown -R root:wheel "$BUNDLE_DESTINATION"
install -o root -g wheel -m 755 "$BROKER_SOURCE" "$BROKER_DESTINATION"
plutil -create xml1 "$LAUNCHD_PLIST"
plutil -insert Label -string xyz.dubdub.backgroundcomputeruse.locked-broker "$LAUNCHD_PLIST"
plutil -insert ProgramArguments -json "[\"$BROKER_DESTINATION\"]" "$LAUNCHD_PLIST"
plutil -insert MachServices -json '{"xyz.dubdub.backgroundcomputeruse.locked-broker":true}' "$LAUNCHD_PLIST"
plutil -insert EnvironmentVariables -json '{}' "$LAUNCHD_PLIST"
plutil -insert EnvironmentVariables.BCU_LOCKED_ALLOWED_PEERS_BASE64 -string "$ALLOWED_PEERS_BASE64" "$LAUNCHD_PLIST"
plutil -insert RunAtLoad -bool true "$LAUNCHD_PLIST"
chown root:wheel "$LAUNCHD_PLIST"
chmod 600 "$LAUNCHD_PLIST"
launchctl bootstrap system "$LAUNCHD_PLIST"
security authorizationdb write "$RIGHT" < "$UPDATED_RULE"
INSTALL_FINISHED=1
echo "installed right=$RIGHT bundle=$BUNDLE_DESTINATION broker=$BROKER_DESTINATION backup=$BACKUP_PATH"
