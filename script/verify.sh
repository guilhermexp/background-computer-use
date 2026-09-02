#!/usr/bin/env bash
set -uo pipefail

usage() {
  cat <<'EOF'
usage: ./script/verify.sh [--live]

Default: run deterministic Swift and Python verification only.

--live  Also run strict Electron, Chrome, and Control qualification.
        Requires BCU_LIVE_AUTHORIZED=1 and an already running, healthy,
        signed BackgroundComputerUse runtime. This command never installs or
        starts the runtime. JSON evidence is written under
        ${BCU_VERIFY_ARTIFACT_DIR:-.build/verification}.

A live run passes only when no command fails or skips. Declared known
limitations keep passed=true but set fullyQualified=false.
EOF
}

LIVE=false
case "$#" in
  0) ;;
  1)
    case "$1" in
      --live) LIVE=true ;;
      --help|-h) usage; exit 0 ;;
      *) usage >&2; exit 2 ;;
    esac
    ;;
  *) usage >&2; exit 2 ;;
esac

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if [ "$LIVE" = true ]; then
  if [ "${BCU_LIVE_AUTHORIZED:-}" != "1" ]; then
    echo "--live requires BCU_LIVE_AUTHORIZED=1" >&2
    exit 2
  fi
  if ! python3 - <<'PY'
import json
import os
import subprocess
import sys
import urllib.request
from pathlib import Path

default_manifest = Path(os.environ.get("TMPDIR", "/tmp")) / "background-computer-use" / "runtime-manifest.json"
manifest_path = Path(os.environ.get("BCU_MANIFEST_PATH", default_manifest))
try:
    manifest = json.loads(manifest_path.read_text())
    pid = int(manifest["pid"])
    os.kill(pid, 0)
    with urllib.request.urlopen(str(manifest["baseURL"]).rstrip("/") + "/health", timeout=3) as response:
        if response.status != 200 or not json.load(response).get("ok"):
            raise RuntimeError("health endpoint did not report ok")
    executable = subprocess.run(
        ["/bin/ps", "-p", str(pid), "-o", "comm="],
        check=True,
        capture_output=True,
        text=True,
    ).stdout.strip()
    if not executable:
        raise RuntimeError("runtime executable path is unavailable")
    subprocess.run(
        ["/usr/bin/codesign", "--verify", "--strict", executable],
        check=True,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
except Exception as exc:
    print(f"--live requires an already healthy signed runtime: {exc}", file=sys.stderr)
    raise SystemExit(1)
PY
  then
    exit 2
  fi
fi

COMMIT="$(git rev-parse --short=12 HEAD)"
DIRTY=false
if [ -n "$(git status --porcelain --untracked-files=all)" ]; then
  DIRTY=true
fi
SWIFT_VERSION="$(swift --version 2>&1 | python3 -c 'import sys; print(" ".join(sys.stdin.read().splitlines()))')"
MACOS_VERSION="$(sw_vers -productVersion)"
TIMESTAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
LANES_FILE="$(mktemp "${TMPDIR:-/tmp}/bcu-verify-lanes.XXXXXX")"
RESULT_TEMP="$(mktemp "$ROOT_DIR/.verify-result.XXXXXX")"
trap 'rm -f "$LANES_FILE" "$RESULT_TEMP"' EXIT

overall_exit=0

record_lane() {
  local name="$1"
  local exit_code="$2"
  local artifact="$3"
  local status=pass
  if [ "$exit_code" -ne 0 ]; then
    status=fail
    overall_exit=1
  fi
  printf '%s\t%s\t%s\t%s\n' "$name" "$status" "$exit_code" "$artifact" >>"$LANES_FILE"
}

# run_lane <name> <artifact|''> <command...>
# The command writes its own artifact, when it produces one at all.
run_lane() {
  local name="$1"
  local artifact="$2"
  shift 2
  printf '\n==> %s\n' "$name"
  "$@"
  record_lane "$name" "$?" "$artifact"
}

# run_json_lane <name> <artifact> <command...>
# Like run_lane, except the command emits its JSON artifact on stdout, which is
# kept only when the command produced something.
run_json_lane() {
  local name="$1"
  local artifact="$2"
  shift 2
  local temporary="${artifact}.tmp.$$"
  printf '\n==> %s\n' "$name"
  "$@" >"$temporary"
  local exit_code=$?
  if [ -s "$temporary" ]; then
    mv "$temporary" "$artifact"
  else
    rm -f "$temporary"
  fi
  record_lane "$name" "$exit_code" "$artifact"
}

run_lane swift-build '' swift build
run_lane swift-test '' swift test
run_lane python-unit '' python3 -m unittest \
  script.test_smoke_runtime script.test_smoke_control script.test_benchmark_mac_parity

if [ "$LIVE" = true ]; then
  ARTIFACT_DIR="${BCU_VERIFY_ARTIFACT_DIR:-.build/verification}"
  mkdir -p "$ARTIFACT_DIR"
  LIVE_REGRESSION="$ARTIFACT_DIR/live-regression.json"

  run_lane live-electron-regression "$LIVE_REGRESSION" \
    python3 script/live_regression.py --output "$LIVE_REGRESSION"
  run_json_lane live-runtime-smoke "$ARTIFACT_DIR/smoke-runtime.json" \
    python3 script/smoke_runtime.py --json
  run_json_lane live-control-smoke "$ARTIFACT_DIR/smoke-control.json" \
    python3 script/smoke_control.py
  RESULT_PATH="$ARTIFACT_DIR/aggregate.json"
else
  RESULT_PATH="$ROOT_DIR/verify-result.json"
fi

python3 - "$COMMIT" "$DIRTY" "$SWIFT_VERSION" "$MACOS_VERSION" "$TIMESTAMP" "$LIVE" "$LANES_FILE" >"$RESULT_TEMP" <<'PY'
import json
import sys
from pathlib import Path

commit, dirty, swift_version, macos_version, timestamp, live, lanes_path = sys.argv[1:]


def artifact_summary(artifact):
    """Summarize a lane artifact; None when it cannot be read as JSON."""
    try:
        payload = json.loads(Path(artifact).read_text())
    except Exception:
        return None
    if not isinstance(payload, dict):
        return {}
    statuses = [
        item.get("status")
        for key in ("lanes", "results")
        for item in payload.get(key, [])
        if isinstance(item, dict)
    ]
    return {
        "artifactPassed": payload.get("passed") is True,
        "artifactFullyQualified": payload.get("fullyQualified", payload.get("passed")) is True,
        "containsSkip": "skip" in statuses,
        "knownLimitations": sum(status == "known_limitation" for status in statuses),
    }


lanes = []
for line in Path(lanes_path).read_text().splitlines():
    name, status, exit_code, artifact = line.split("\t")
    lane = {"name": name, "status": status, "exitCode": int(exit_code)}
    if artifact:
        lane["artifact"] = artifact
        summary = artifact_summary(artifact)
        if summary is None:
            lane["status"] = "fail"
        else:
            lane.update(summary)
    lanes.append(lane)

passed = all(
    lane["status"] == "pass"
    and lane.get("artifactPassed", True)
    and not lane.get("containsSkip", False)
    for lane in lanes
)
fully_qualified = passed and all(
    lane.get("artifactFullyQualified", True)
    and lane.get("knownLimitations", 0) == 0
    for lane in lanes
)
result = {
    "commit": commit,
    "dirty": dirty == "true",
    "timestamp": timestamp,
    "os": {"macOSVersion": macos_version},
    "swiftVersion": swift_version,
    "live": live == "true",
    "lanes": lanes,
    "passed": passed,
    "fullyQualified": fully_qualified,
}
json.dump(result, sys.stdout, indent=2, sort_keys=True)
print()
raise SystemExit(0 if passed else 1)
PY
result_exit=$?
mv "$RESULT_TEMP" "$RESULT_PATH"
if [ "$result_exit" -ne 0 ]; then
  overall_exit=1
fi

exit "$overall_exit"
