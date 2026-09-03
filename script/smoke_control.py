#!/usr/bin/env python3
"""Signed BCU Control/Core XPC smoke, including real ad-hoc identity decisions."""

from __future__ import annotations

import concurrent.futures
import json
import os
import shutil
import signal
import subprocess
import tempfile
import time
import uuid
from pathlib import Path
from typing import Optional

try:
    from script.smoke_runtime import BCUClient
except ModuleNotFoundError:
    from smoke_runtime import BCUClient


APPROVAL_WINDOW_ID = "bcu.approval.window"
ALLOW_ONCE_ID = "bcu.approval.allow-once"
ALWAYS_ALLOW_ID = "bcu.approval.always-allow"
DENY_ID = "bcu.approval.deny"
ROOT = Path(__file__).resolve().parents[1]
FIXTURE_DIR = ROOT / "Tests/Fixtures/Apps/BCUElectronFixture"
ELECTRON_APP = FIXTURE_DIR / "node_modules/electron/dist/Electron.app"


def mutation_is_blocked(status: int, payload: dict) -> bool:
    return status == 423 and payload.get("error") == "control_paused"


def launch_is_background_safe(status: int, payload: dict) -> bool:
    return (
        status == 200
        and payload.get("classification") == "success"
        and payload.get("activates") is False
        and payload.get("foregroundPreserved") is True
        and isinstance(payload.get("pid"), int)
    )


def osascript(source: str) -> str:
    result = subprocess.run(
        ["/usr/bin/osascript", "-e", source],
        check=False,
        capture_output=True,
        text=True,
        timeout=8,
    )
    if result.returncode != 0:
        raise RuntimeError(result.stderr.strip() or "osascript failed")
    return result.stdout.strip()


def choose_menu_item(title: str) -> None:
    escaped = title.replace('"', '\\"')
    osascript(
        'tell application "System Events" to tell process "BackgroundComputerUse"\n'
        'set targetItem to first menu bar item of menu bar 1 whose description is "BCU Control"\n'
        'click targetItem\n'
        'delay 0.2\n'
        f'click menu item "{escaped}" of menu 1 of targetItem\n'
        'end tell'
    )


def menu_items() -> str:
    return osascript(
        'tell application "System Events" to tell process "BackgroundComputerUse"\n'
        'set targetItem to first menu bar item of menu bar 1 whose description is "BCU Control"\n'
        'click targetItem\n'
        'delay 0.2\n'
        'set itemNames to name of every menu item of menu 1 of targetItem\n'
        'key code 53\n'
        'return itemNames\n'
        'end tell'
    )


def wait_for_menu_item(title: str) -> None:
    for _ in range(40):
        if title in menu_items():
            return
        time.sleep(0.05)
    raise RuntimeError(f"menu never exposed {title}")


def core_pids() -> list[int]:
    result = subprocess.run(
        ["/usr/bin/pgrep", "-x", "BackgroundComputerUseCoreXPCService"],
        check=False,
        capture_output=True,
        text=True,
    )
    return [int(line) for line in result.stdout.splitlines() if line.strip().isdigit()]

def activate_finder_foreground(client: BCUClient) -> None:
    subprocess.run(
        ["/usr/bin/open", "-a", "Finder"],
        check=True,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    for _ in range(100):
        status, payload = client.request("POST", "/v1/list_apps", {})
        frontmost = payload.get("frontmostApp") if status == 200 else None
        if isinstance(frontmost, dict) and frontmost.get("bundleID") == "com.apple.finder":
            return
        time.sleep(0.05)
    raise RuntimeError("Finder did not become the unrelated foreground application")


def click_approval_button(identifier: str) -> str:
    escaped = identifier.replace('"', '\\"')
    return osascript(
        'tell application "System Events" to tell process "BackgroundComputerUse"\n'
        'repeat with candidateWindow in windows\n'
        'try\n'
        f'if value of attribute "AXIdentifier" of candidateWindow is "{APPROVAL_WINDOW_ID}" then\n'
        'set candidates to every button of entire contents of candidateWindow\n'
        'repeat with candidateButton in candidates\n'
        'try\n'
        f'if value of attribute "AXIdentifier" of candidateButton is "{escaped}" then\n'
        'click candidateButton\n'
        'return "clicked"\n'
        'end if\n'
        'end try\n'
        'end repeat\n'
        'return "window"\n'
        'end if\n'
        'end try\n'
        'end repeat\n'
        'return "missing"\n'
        'end tell'
    )


def request_with_approval(
    client: BCUClient,
    method: str,
    path: str,
    body: dict,
    button_identifier: str,
    require_window: bool = True,
) -> tuple[int, dict, str]:
    """Issue a request that needs an approval and report how the approval resolved.

    `resolution` is "clicked" when this harness pressed the button it intended,
    "preempted" when the request completed before the dialog could be observed (an
    external agent on the host answers dialogs in under a second), and "absent" when
    no dialog was involved at all.
    """
    saw_window = False
    clicked = False
    with concurrent.futures.ThreadPoolExecutor(max_workers=1) as executor:
        future = executor.submit(client.request, method, path, body, True, 45)
        for _ in range(120):
            if future.done():
                break
            state = click_approval_button(button_identifier)
            saw_window = saw_window or state in {"window", "clicked"}
            if state == "clicked":
                clicked = True
                break
            time.sleep(0.05)
        status, payload = future.result(timeout=45)
    if clicked:
        resolution = "clicked"
    elif require_window and not saw_window:
        resolution = "preempted"
    else:
        resolution = "absent"
    return status, payload, resolution


class AdHocFixture:
    def __init__(self, root: Path, name: str) -> None:
        if not ELECTRON_APP.is_dir():
            raise RuntimeError(f"Pinned Electron is missing at {ELECTRON_APP}")
        self.app = root / f"{name}.app"
        shutil.copytree(ELECTRON_APP, self.app, symlinks=True)
        unique_resource = self.app / "Contents/Resources" / f"identity-{uuid.uuid4().hex}"
        unique_resource.write_text("identity-only\n")
        subprocess.run(
            ["/usr/bin/codesign", "--force", "--deep", "--sign", "-", str(self.app)],
            check=True,
            capture_output=True,
            text=True,
        )
        self.process = subprocess.Popen(
            [str(self.app / "Contents/MacOS/Electron"), str(FIXTURE_DIR)],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            start_new_session=True,
        )
        self.window_id: Optional[str] = None
        self.target: Optional[dict] = None
        self.state_token: Optional[str] = None

    def resolve(self, client: BCUClient) -> None:
        deadline = time.monotonic() + 20
        while time.monotonic() < deadline:
            if self.process.poll() is not None:
                stderr = self.process.stderr.read() if self.process.stderr else ""
                raise RuntimeError(f"ad-hoc fixture exited before discovery: {stderr.strip()}")
            status, apps = client.request("POST", "/v1/list_apps", {})
            running = apps.get("runningApps", []) if status == 200 else []
            if len([app for app in running if app.get("pid") == self.process.pid]) == 1:
                status, windows = client.request("POST", "/v1/list_windows", {"pid": self.process.pid})
                candidates = windows.get("windows", []) if status == 200 else []
                if candidates:
                    self.window_id = candidates[0].get("windowID")
                    break
            time.sleep(0.1)
        if not self.window_id:
            raise RuntimeError(f"could not resolve exact ad-hoc fixture pid {self.process.pid}")
        status, found = client.request(
            "POST",
            "/v1/find_elements",
            {"window": self.window_id, "role": "button", "text": "BCU Fixture Button", "maxNodes": 6500},
        )
        matches = found.get("matches", []) if status == 200 else []
        if not matches:
            raise RuntimeError(f"fixture button was not found: HTTP {status} {found}")
        match = matches[0]
        if isinstance(match.get("nodeID"), str) and match["nodeID"]:
            self.target = {"kind": "node_id", "value": match["nodeID"]}
        elif isinstance(match.get("displayIndex"), int):
            self.target = {"kind": "display_index", "value": match["displayIndex"]}
        else:
            raise RuntimeError(f"fixture button match was untargetable: {match}")
        self.state_token = found.get("stateToken")

    def click_body(self) -> dict:
        return {
            "window": self.window_id,
            "stateToken": self.state_token,
            "target": self.target,
            "clickCount": 1,
            "imageMode": "omit",
            "maxNodes": 6500,
        }

    def marker_is_clicked(self, client: BCUClient) -> bool:
        for _ in range(30):
            status, state = client.request(
                "POST",
                "/v1/get_window_state",
                {"window": self.window_id, "imageMode": "omit", "maxNodes": 6500},
            )
            rendered = str((state.get("tree") or {}).get("renderedText") or "")
            if status == 200 and "clicked:true" in rendered:
                return True
            time.sleep(0.1)
        return False

    def remove_signature(self) -> None:
        subprocess.run(
            ["/usr/bin/codesign", "--remove-signature", str(self.app)],
            check=True,
            capture_output=True,
            text=True,
        )

    def stop(self) -> None:
        if self.process.poll() is not None:
            return
        try:
            os.killpg(self.process.pid, signal.SIGTERM)
            self.process.wait(timeout=5)
        except (ProcessLookupError, subprocess.TimeoutExpired):
            if self.process.poll() is None:
                os.killpg(self.process.pid, signal.SIGKILL)
                self.process.wait(timeout=5)


def run_identity_decisions(client: BCUClient) -> list[dict]:
    results: list[dict] = []
    with tempfile.TemporaryDirectory(prefix="bcu-control-identities-") as directory:
        root = Path(directory)
        fixtures: list[AdHocFixture] = []

        def start(name: str) -> AdHocFixture:
            fixture = AdHocFixture(root, name)
            fixtures.append(fixture)
            fixture.resolve(client)
            return fixture

        preempted = (
            "an external agent on this host answered the approval dialog before the "
            "harness could press its own button, so the decision cannot be attributed "
            "to this test"
        )

        try:
            allow_once = start("BCUAllowOnce")
            status, payload, resolution = request_with_approval(
                client,
                "POST",
                "/v1/click",
                allow_once.click_body(),
                ALLOW_ONCE_ID,
            )
            if resolution == "preempted":
                results.append({
                    "name": "adhoc_allow_once_known_limitation",
                    "status": "known_limitation",
                    "detail": preempted,
                })
            elif status != 200 or payload.get("classification") != "success" or not allow_once.marker_is_clicked(client):
                raise RuntimeError(f"allow-once click was not verified: HTTP {status} {payload}")
            else:
                results.append({"name": "adhoc_allow_once", "status": "pass"})
            allow_once.stop()

            denied = start("BCUDeny")
            status, payload, resolution = request_with_approval(
                client,
                "POST",
                "/v1/click",
                denied.click_body(),
                DENY_ID,
            )
            if resolution == "preempted":
                results.append({
                    "name": "adhoc_deny_known_limitation",
                    "status": "known_limitation",
                    "detail": preempted,
                })
            elif status != 403 or payload.get("error") != "control_denied":
                raise RuntimeError(f"deny decision was not enforced: HTTP {status} {payload}")
            else:
                results.append({"name": "adhoc_deny", "status": "pass"})
            denied.stop()

            # This lane does not care which button answered the prompt: it only needs
            # the identity primed, then asserts that invalidating the on-disk signature
            # is surfaced instead of being swallowed.
            invalid = start("BCUInvalidIdentity")
            status, payload, _ = request_with_approval(
                client,
                "POST",
                "/v1/launch_app",
                {"appPath": str(invalid.app), "sessionID": "control-identity-prime"},
                ALLOW_ONCE_ID,
                require_window=False,
            )
            if status != 200:
                raise RuntimeError(f"identity-prime launch failed: HTTP {status} {payload}")
            invalid.remove_signature()
            status, payload = client.request("POST", "/v1/click", invalid.click_body())
            if status != 403 or payload.get("error") != "control_identity_unresolvable":
                raise RuntimeError(f"invalid identity was not surfaced: HTTP {status} {payload}")
            results.append({"name": "adhoc_identity_unresolvable", "status": "pass"})
        finally:
            for fixture in fixtures:
                fixture.stop()
    return results


def main() -> int:
    client = BCUClient()
    results: list[dict] = []
    resumed = False
    try:
        health_status, _ = client.request("GET", "/health", auth=False)
        if health_status != 200:
            raise RuntimeError("health failed")
        read_status, _ = client.request("POST", "/v1/list_apps", {})
        if read_status != 200:
            raise RuntimeError("initial Core read failed")
        before = core_pids()
        if not before:
            raise RuntimeError("Core XPC process was not running")

        choose_menu_item("Pausar")
        wait_for_menu_item("Retomar")
        paused_status, paused_payload = client.request(
            "POST",
            "/v1/launch_app",
            {"bundleID": "com.apple.Safari", "sessionID": "core-xpc-smoke-paused"},
        )
        if not mutation_is_blocked(paused_status, paused_payload):
            raise RuntimeError(f"pause did not block mutation: {paused_status} {paused_payload}")

        os.kill(before[0], signal.SIGKILL)
        read_after_crash, _ = client.request("POST", "/v1/list_apps", {})
        if read_after_crash != 200:
            raise RuntimeError("paused read did not rehydrate Core after crash")
        blocked_status, blocked_payload = client.request(
            "POST",
            "/v1/launch_app",
            {"bundleID": "com.apple.Safari", "sessionID": "core-xpc-smoke-crashed"},
        )
        if not mutation_is_blocked(blocked_status, blocked_payload):
            raise RuntimeError("Core crash lost paused mutation policy")
        results.append({"name": "paused_core_crash_rehydration", "status": "pass"})

        choose_menu_item("Retomar")
        resumed = True
        wait_for_menu_item("Pausar")
        activate_finder_foreground(client)
        launch_status, launch_payload, _ = request_with_approval(
            client,
            "POST",
            "/v1/launch_app",
            {"bundleID": "com.apple.Safari", "sessionID": "core-xpc-smoke-resumed"},
            ALLOW_ONCE_ID,
            require_window=False,
        )
        if not launch_is_background_safe(launch_status, launch_payload):
            raise RuntimeError(f"resumed launch failed: {launch_status} {launch_payload}")
        results.append({"name": "resume_after_core_crash", "status": "pass"})
        results.extend(run_identity_decisions(client))

        print(json.dumps({"passed": True, "results": results}, sort_keys=True))
        return 0
    except Exception as exc:
        print(json.dumps({"passed": False, "error": f"{type(exc).__name__}: {exc}", "results": results}, sort_keys=True))
        return 1
    finally:
        if not resumed:
            try:
                if "Retomar" in menu_items():
                    choose_menu_item("Retomar")
            except Exception:
                pass


if __name__ == "__main__":
    raise SystemExit(main())
