#!/usr/bin/env bash
set -euo pipefail

APP_NAME="${BCU_APP_NAME:-BackgroundComputerUse}"
INSTALL_DIR="${BACKGROUND_COMPUTER_USE_INSTALL_DIR:-$HOME/Applications}"
APP_BUNDLE="${BCU_APP_BUNDLE:-$INSTALL_DIR/$APP_NAME.app}"
if [ -n "${TMPDIR:-}" ]; then
  TMP_ROOT="$TMPDIR"
else
  TMP_ROOT="$(getconf DARWIN_USER_TEMP_DIR 2>/dev/null || true)"
  TMP_ROOT="${TMP_ROOT:-/tmp}"
fi
TMP_ROOT="${TMP_ROOT%/}"
MANIFEST_PATH="${BCU_MANIFEST_PATH:-$TMP_ROOT/background-computer-use/runtime-manifest.json}"
WAIT_ATTEMPTS="${BCU_WAIT_ATTEMPTS:-120}"
WAIT_INTERVAL="${BCU_WAIT_INTERVAL:-0.25}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

read_base_url() {
  python3 - "$MANIFEST_PATH" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
if not path.exists():
    sys.exit(1)
try:
    value = json.loads(path.read_text()).get("baseURL", "")
except Exception:
    sys.exit(1)
if not value:
    sys.exit(1)
print(value)
PY
}

read_auth_token() {
  python3 - "$MANIFEST_PATH" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
if not path.exists():
    sys.exit(1)
try:
    value = json.loads(path.read_text()).get("authToken", "")
except Exception:
    sys.exit(1)
if not value:
    sys.exit(1)
print(value)
PY
}

read_build_identity() {
  python3 - "$MANIFEST_PATH" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
if not path.exists():
    sys.exit(1)
try:
    value = json.loads(path.read_text()).get("build", {}).get("identity", "")
except Exception:
    sys.exit(1)
if not value:
    sys.exit(1)
print(value)
PY
}

expected_build_identity() {
  python3 "$BCU_SOURCE_DIR/script/build_fingerprint.py" \
    --repo "$BCU_SOURCE_DIR" \
    --format json \
    | python3 -c 'import json,sys; print(json.load(sys.stdin)["identity"])'
}

source_identity_matches() {
  local actual expected
  actual="$(read_build_identity 2>/dev/null || true)"
  expected="$(expected_build_identity)"
  [ -n "$actual" ] && [ "$actual" = "$expected" ]
}

health_ok() {
  local base_url="$1"
  curl -fsS "$base_url/health" >/dev/null 2>&1
}

current_runtime_ok() {
  local base_url
  base_url="$(read_base_url 2>/dev/null || true)"
  [ -n "$base_url" ] || return 1
  health_ok "$base_url" || return 1
  if [ -n "${BCU_SOURCE_DIR:-}" ]; then
    source_identity_matches
  fi
}

wait_for_runtime() {
  local base_url=""
  for _ in $(seq 1 "$WAIT_ATTEMPTS"); do
    if current_runtime_ok; then
      base_url="$(read_base_url)"
      printf '%s\n' "$base_url"
      return 0
    fi
    sleep "$WAIT_INTERVAL"
  done
  return 1
}

stop_stale_runtime() {
  if ! /usr/bin/pgrep -x "$APP_NAME" >/dev/null 2>&1; then
    return 0
  fi

  /usr/bin/pkill -TERM -x "$APP_NAME" >/dev/null 2>&1 || true
  for _ in $(seq 1 40); do
    if ! /usr/bin/pgrep -x "$APP_NAME" >/dev/null 2>&1; then
      return 0
    fi
    sleep 0.1
  done

  /usr/bin/pkill -KILL -x "$APP_NAME" >/dev/null 2>&1 || true
  for _ in $(seq 1 10); do
    if ! /usr/bin/pgrep -x "$APP_NAME" >/dev/null 2>&1; then
      return 0
    fi
    sleep 0.1
  done

  echo "Could not stop stale $APP_NAME process." >&2
  return 1
}

start_from_source() {
  local source_dir="$1"
  local selected_script="${BCU_START_SCRIPT:-$source_dir/script/start.sh}"
  if [ ! -x "$selected_script" ]; then
    echo "BCU source start script is not executable: $selected_script" >&2
    return 1
  fi
  "$selected_script"
}

launch_installed_app() {
  if [ ! -d "$APP_BUNDLE" ]; then
    return 1
  fi
  stop_stale_runtime || return 1
  rm -f "$MANIFEST_PATH"
  /usr/bin/open -n "$APP_BUNDLE"
}

if current_runtime_ok; then
  BASE_URL="$(read_base_url)"
else
  if [ -n "${BCU_SOURCE_DIR:-}" ]; then
    ACTUAL_BUILD_IDENTITY="$(read_build_identity 2>/dev/null || true)"
    EXPECTED_BUILD_IDENTITY="$(expected_build_identity)"
    printf 'Refreshing source runtime: manifest identity=%s expected identity=%s\n' \
      "${ACTUAL_BUILD_IDENTITY:-missing}" "$EXPECTED_BUILD_IDENTITY" >&2
    stop_stale_runtime
    rm -f "$MANIFEST_PATH"
    start_from_source "$BCU_SOURCE_DIR"
  elif launch_installed_app; then
    :
  else
    "$SCRIPT_DIR/install-runtime.sh"
    launch_installed_app
  fi
  BASE_URL="$(wait_for_runtime)" || {
    echo "BackgroundComputerUse did not become healthy." >&2
    echo "Expected manifest: $MANIFEST_PATH" >&2
    echo "Set BCU_SOURCE_DIR=/path/to/background-computer-use for local source builds, or set BCU_RELEASE_URL to an app zip." >&2
    exit 1
  }
fi

echo "BackgroundComputerUse running at $BASE_URL"
echo "Runtime manifest: $MANIFEST_PATH"
echo
echo "Bootstrap:"
AUTH_TOKEN="$(read_auth_token)"
curl -fsS -H "X-Background-Computer-Use-Token: $AUTH_TOKEN" "$BASE_URL/v1/bootstrap" | python3 -m json.tool
