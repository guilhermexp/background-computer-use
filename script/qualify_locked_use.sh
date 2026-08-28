#!/bin/bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
EXECUTE=0
if [[ "${1:-}" == "--execute-on-disposable-host" ]]; then EXECUTE=1; fi

cd "$REPO_DIR"
script/build_locked_use.sh
codesign --verify --deep --strict dist/BCUAuthorizationPlugin.bundle
codesign --verify --strict dist/BackgroundComputerUseLockedBrokerService
nm -gU dist/BCUAuthorizationPlugin.bundle/Contents/MacOS/BCUAuthorizationPlugin | grep '_AuthorizationPluginCreate'

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT
security authorizationdb read system.login.screensaver > "$WORK_DIR/original.plist"
shasum -a 256 "$WORK_DIR/original.plist"

if [[ "$EXECUTE" -eq 0 ]]; then
  echo "qualification_build=pass"
  echo "qualification_install=not_run"
  echo "next=run --execute-on-disposable-host only on a disposable VM or secondary Mac"
  exit 0
fi

if [[ "${BCU_DISPOSABLE_HOST_CONFIRMED:-}" != "YES" ]]; then
  echo "blocked: set BCU_DISPOSABLE_HOST_CONFIRMED=YES only on a disposable VM or secondary Mac" >&2
  exit 6
fi
if [[ -z "${BACKGROUND_COMPUTER_USE_LOCKED_ALLOWED_PEERS:-}" ]]; then
  echo "blocked: exact Control and authorization-host peer identities are required" >&2
  exit 5
fi

sudo -n true 2>/dev/null || {
  echo "administrator handoff required; this script never captures credentials" >&2
  exit 7
}
sudo -n script/install_locked_use.sh --install
security authorizationdb read system.login.screensaver > "$WORK_DIR/installed.plist"
plutil -extract mechanisms json -o - "$WORK_DIR/installed.plist" | grep 'xyz.dubdub.backgroundcomputeruse.AuthorizationPlugin:remote'

echo "interactive gates required: lock, one-use consume, shield coverage, local-input relock, process-death relock, reboot"
echo "after interactive gates run: sudo -n script/uninstall_locked_use.sh"
echo "then compare semantic plist equality with $WORK_DIR/original.plist before declaring qualification"
