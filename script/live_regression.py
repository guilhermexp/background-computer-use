#!/usr/bin/env python3
import argparse
import json
import os
import platform
import re
import shutil
import signal
import subprocess
import sys
import tempfile
import time
import uuid
from datetime import datetime, timezone
from pathlib import Path
from typing import Callable, Optional

from smoke_runtime import BCUClient

ROOT = Path(__file__).resolve().parents[1]
FIXTURE_DIR = ROOT / "Tests/Fixtures/Apps/BCUElectronFixture"
ELECTRON_APP = FIXTURE_DIR / "node_modules/electron/dist/Electron.app"
MAX_NODES = 6500


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def atomic_write(path: Path, payload: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(f".{path.name}.{uuid.uuid4().hex}.tmp")
    temporary.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n")
    os.replace(temporary, path)


def state_text(state: dict) -> str:
    return str((state.get("tree") or {}).get("renderedText") or "")


def scroll_top(state: dict) -> Optional[int]:
    match = re.search(r"scroll-top:(\d+)", state_text(state))
    return int(match.group(1)) if match else None


def ocr_comparable(text: object) -> str:
    return "".join(char for char in str(text).lower() if char.isalnum() or char == " ").strip()


def find_ocr_anchor(state: dict, needle: str) -> Optional[dict]:
    normalized = ocr_comparable(needle)
    for anchor in (state.get("ocr") or {}).get("anchors", []):
        target = anchor.get("target")
        if (
            normalized in ocr_comparable(anchor.get("text", ""))
            and isinstance(target, dict)
            and target.get("kind") == "ocr_anchor"
        ):
            return target
    return None


class LiveRegression:
    def __init__(self) -> None:
        self.client = BCUClient()
        self.lanes: list[dict] = []
        self.process: Optional[subprocess.Popen] = None
        self.temporary: Optional[tempfile.TemporaryDirectory] = None
        self.fixture_pid: Optional[int] = None
        self.window_id: Optional[str] = None
        self.electron_version = "unknown"

    def request(self, method: str, path: str, body: Optional[dict] = None, timeout: float = 60) -> tuple[int, dict]:
        return self.client.request(method, path, body=body, timeout=timeout)

    def frontmost_pid(self) -> Optional[int]:
        status, payload = self.request("POST", "/v1/list_apps", {})
        if status != 200:
            return None
        pid = (payload.get("frontmostApp") or {}).get("pid")
        return pid if isinstance(pid, int) else None

    def ensure_unrelated_foreground(self) -> None:
        if self.frontmost_pid() != self.fixture_pid:
            return
        subprocess.run(
            ["/usr/bin/open", "-a", "Finder"],
            check=True,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        deadline = time.monotonic() + 5
        while time.monotonic() < deadline:
            if self.frontmost_pid() not in {None, self.fixture_pid}:
                return
            time.sleep(0.05)
        raise RuntimeError("Could not establish an unrelated foreground application")

    def record(
        self,
        name: str,
        status: str,
        started: float,
        *,
        classification: Optional[str] = None,
        foreground_before: Optional[int] = None,
        foreground_after: Optional[int] = None,
        oracle: object = None,
        detail: str = "",
    ) -> None:
        self.lanes.append({
            "name": name,
            "status": status,
            "durationMs": round((time.monotonic() - started) * 1000, 3),
            "classification": classification,
            "foregroundPIDBefore": foreground_before,
            "foregroundPIDAfter": foreground_after,
            "oracle": oracle,
            "detail": detail,
        })

    def setup_fixture(self) -> None:
        if not ELECTRON_APP.is_dir():
            raise RuntimeError(
                f"Pinned Electron is missing at {ELECTRON_APP}; run npm ci --prefix {FIXTURE_DIR}"
            )
        version = subprocess.run(
            [str(ELECTRON_APP / "Contents/MacOS/Electron"), "--version"],
            check=True,
            capture_output=True,
            text=True,
        ).stdout.strip()
        self.electron_version = version.removeprefix("v")
        self.temporary = tempfile.TemporaryDirectory(prefix="bcu-live-regression-")
        copied_app = Path(self.temporary.name) / "BCUElectronFixture.app"
        shutil.copytree(ELECTRON_APP, copied_app, symlinks=True)
        inert_resource = copied_app / "Contents/Resources" / f"bcu-fixture-{uuid.uuid4().hex}"
        inert_resource.write_text("identity-only\n")
        subprocess.run(
            ["/usr/bin/codesign", "--force", "--deep", "--sign", "-", str(copied_app)],
            check=True,
            capture_output=True,
            text=True,
        )
        executable = copied_app / "Contents/MacOS/Electron"
        self.process = subprocess.Popen(
            [str(executable), str(FIXTURE_DIR)],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            start_new_session=True,
        )
        self.fixture_pid = self.process.pid
        self.window_id = self.wait_for_window(self.process.pid)

    def wait_for_window(self, pid: int) -> str:
        deadline = time.monotonic() + 20
        while time.monotonic() < deadline:
            if self.process and self.process.poll() is not None:
                stderr = self.process.stderr.read() if self.process.stderr else ""
                raise RuntimeError(f"Electron fixture exited before discovery: {stderr.strip()}")
            status, apps = self.request("POST", "/v1/list_apps", {})
            running = apps.get("runningApps", []) if status == 200 else []
            if sum(1 for app in running if app.get("pid") == pid) == 1:
                status, windows = self.request("POST", "/v1/list_windows", {"pid": pid})
                candidates = windows.get("windows", []) if status == 200 else []
                window_id = candidates[0].get("windowID") if candidates else None
                if isinstance(window_id, str) and window_id:
                    return window_id
            time.sleep(0.1)
        raise RuntimeError(f"Could not match Electron main pid {pid} to one BCU window")

    def state(self, include_ocr: bool = False) -> dict:
        body = {
            "window": self.window_id,
            "imageMode": "path" if include_ocr else "omit",
            "includeOCR": include_ocr,
            "maxNodes": MAX_NODES,
        }
        status, payload = self.request(
            "POST", "/v1/get_window_state", body, timeout=90 if include_ocr else 60
        )
        if status != 200:
            raise RuntimeError(f"get_window_state returned HTTP {status}: {payload}")
        return payload

    def poll_state(self, predicate: Callable[[dict], bool], timeout: float = 5) -> tuple[bool, dict]:
        deadline = time.monotonic() + timeout
        latest: dict = {}
        while time.monotonic() < deadline:
            latest = self.state()
            if predicate(latest):
                return True, latest
            time.sleep(0.1)
        return False, latest

    def find_target(self, role: str, text: str) -> dict:
        status, payload = self.request(
            "POST",
            "/v1/find_elements",
            {"window": self.window_id, "role": role, "text": text, "maxNodes": MAX_NODES},
        )
        if status != 200 or not payload.get("matches"):
            raise RuntimeError(f"find_elements({role!r}, {text!r}) returned HTTP {status}: {payload}")
        match = payload["matches"][0]
        node_id = match.get("nodeID")
        if isinstance(node_id, str) and node_id:
            return {"kind": "node_id", "value": node_id}
        display_index = match.get("displayIndex")
        if isinstance(display_index, int):
            return {"kind": "display_index", "value": display_index}
        raise RuntimeError(f"find_elements returned an untargetable match: {match}")

    def action(
        self,
        name: str,
        path: str,
        body: dict,
        oracle: Callable[[dict], tuple[bool, object]],
        *,
        known_limitation: bool = False,
        allowed_classifications: tuple[str, ...] = ("success",),
        timeout: float = 60,
    ) -> None:
        started = time.monotonic()
        self.ensure_unrelated_foreground()
        before = self.frontmost_pid()
        status, payload = self.request("POST", path, body, timeout=timeout)
        after = self.frontmost_pid()
        classification = payload.get("classification")
        foreground_ok = before is not None and before == after and before != self.fixture_pid
        oracle_ok, oracle_value = oracle(payload)
        detail = f"HTTP {status}; summary={payload.get('summary')}"
        if not foreground_ok:
            lane_status = "fail"
            detail += "; unrelated foreground PID was not preserved"
        elif status != 200:
            lane_status = "fail"
        elif classification == "success" and not oracle_ok:
            lane_status = "fail"
            detail += "; success lacked its target-app oracle"
        elif known_limitation and classification == "effect_not_verified":
            lane_status = "known_limitation"
        elif classification not in allowed_classifications or not oracle_ok:
            lane_status = "fail"
        else:
            lane_status = "pass"
        self.record(
            name,
            lane_status,
            started,
            classification=classification,
            foreground_before=before,
            foreground_after=after,
            oracle=oracle_value,
            detail=detail,
        )

    def interaction_token_lane(self) -> None:
        started = time.monotonic()
        states = [self.state() for _ in range(3)]
        tokens = [state.get("interactionToken") for state in states]
        valid = all(isinstance(token, str) and token for token in tokens) and len(set(tokens)) == 1
        self.record(
            "interaction-token-stability",
            "pass" if valid else "fail",
            started,
            oracle={"tokens": tokens},
            detail="Three pristine reads must preserve interaction identity.",
        )

    def type_text_lane(self, composer: dict) -> None:
        expected = 'value:"bcu-once"'

        def oracle(payload: dict) -> tuple[bool, object]:
            def typed_once(item: dict) -> bool:
                text = state_text(item)
                return expected in text and "input-events:1" in text

            matched, fresh = self.poll_state(typed_once)
            settled = state_text(fresh)
            strategies = payload.get("strategiesAttempted")
            value = {
                "valueMarker": expected in settled,
                "inputEvents": "input-events:1" in settled,
                "strategies": strategies,
            }
            return matched and isinstance(strategies, list) and len(strategies) == 1, value

        state = self.state()
        self.action(
            "type-text-exactly-once",
            "/v1/type_text",
            {
                "window": self.window_id,
                "stateToken": state["stateToken"],
                "target": composer,
                "text": "bcu-once",
                "maxNodes": MAX_NODES,
            },
            oracle,
        )

    def key_lane(self, name: str, key: str, marker: Callable[[str], bool]) -> None:
        def oracle(_: dict) -> tuple[bool, object]:
            matched, state = self.poll_state(lambda item: marker(state_text(item)))
            return matched, {"renderedTextMatched": matched, "stateToken": state.get("stateToken")}

        state = self.state()
        self.action(
            name,
            "/v1/press_key",
            {"window": self.window_id, "stateToken": state["stateToken"], "key": key, "maxNodes": MAX_NODES},
            oracle,
            known_limitation=True,
        )

    def ocr_click_lane(self) -> None:
        state = self.state(include_ocr=True)
        target = find_ocr_anchor(state, "BCU Fixture Button")
        if target is None:
            started = time.monotonic()
            self.record("ocr-anchor-click", "fail", started, oracle=False, detail="OCR button anchor missing")
            return

        def oracle(_: dict) -> tuple[bool, object]:
            matched, fresh = self.poll_state(lambda item: "clicked:true" in state_text(item))
            return matched, {"clicked": matched, "stateToken": fresh.get("stateToken")}

        self.action(
            "ocr-anchor-click",
            "/v1/click",
            {
                "window": self.window_id,
                "stateToken": state["stateToken"],
                "interactionToken": state["interactionToken"],
                "target": target,
                "clickCount": 1,
                "imageMode": "path",
                "maxNodes": MAX_NODES,
            },
            oracle,
            timeout=90,
        )

    def scroll_lane(self) -> None:
        target = self.find_target("static text", "Row 40")
        state = self.state()
        before_value = scroll_top(state)

        def increased(item: dict) -> bool:
            current = scroll_top(item)
            return current is not None and before_value is not None and current > before_value

        def oracle(_: dict) -> tuple[bool, object]:
            matched, fresh = self.poll_state(increased)
            return matched, {"before": before_value, "after": scroll_top(fresh)}

        self.action(
            "scroll-marker-increase",
            "/v1/scroll",
            {
                "window": self.window_id,
                "stateToken": state["stateToken"],
                "target": target,
                "direction": "down",
                "pages": 0.5,
                "maxNodes": MAX_NODES,
            },
            oracle,
            allowed_classifications=("success", "boundary"),
        )

    def run(self) -> dict:
        started_at = utc_now()
        try:
            self.setup_fixture()
            self.interaction_token_lane()
            composer = self.find_target("text entry area", "Composer")
            self.type_text_lane(composer)
            self.key_lane("command-a-known-limitation", "command+a", lambda text: "selection:0:8" in text)
            self.key_lane("delete-known-limitation", "delete", lambda text: 'value:""' in text)
            self.key_lane(
                "return-known-limitation",
                "return",
                lambda text: '"key":"Enter"' in text or 'value:"\\n"' in text,
            )
            self.ocr_click_lane()
            self.scroll_lane()
        except Exception as exc:
            started = time.monotonic()
            self.record("harness", "skip", started, oracle=False, detail=f"{type(exc).__name__}: {exc}")
        finally:
            self.cleanup()
        passed = all(lane["status"] not in {"fail", "skip"} for lane in self.lanes)
        fully_qualified = passed and all(lane["status"] != "known_limitation" for lane in self.lanes)
        return {
            "schemaVersion": 1,
            "startedAt": started_at,
            "finishedAt": utc_now(),
            "host": {"osVersion": platform.mac_ver()[0]},
            "fixture": {
                "electronVersion": self.electron_version,
                "pid": self.fixture_pid,
                "windowID": self.window_id,
            },
            "passed": passed,
            "fullyQualified": fully_qualified,
            "lanes": self.lanes,
        }

    def cleanup(self) -> None:
        if self.process and self.process.poll() is None:
            try:
                os.killpg(self.process.pid, signal.SIGTERM)
                self.process.wait(timeout=5)
            except (ProcessLookupError, subprocess.TimeoutExpired):
                if self.process.poll() is None:
                    os.killpg(self.process.pid, signal.SIGKILL)
                    self.process.wait(timeout=5)
        if self.temporary:
            self.temporary.cleanup()


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Run strict live BCU regression lanes against the pinned Electron fixture."
    )
    parser.add_argument("--output", type=Path, help="Atomically write the emitted JSON result to PATH.")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    result = LiveRegression().run()
    if args.output:
        atomic_write(args.output, result)
    print(json.dumps(result, indent=2, sort_keys=True))
    return 0 if result["passed"] else 1


if __name__ == "__main__":
    sys.exit(main())
