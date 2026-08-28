#!/usr/bin/env python3
"""Signed BCU Control/Core XPC smoke, including crash-state rehydration."""

from __future__ import annotations

import concurrent.futures
import json
import os
import signal
import subprocess
import time

try:
    from script.smoke_runtime import BCUClient
except ModuleNotFoundError:
    from smoke_runtime import BCUClient


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


def launch_with_optional_approval(client: BCUClient, bundle_id: str, session_id: str) -> tuple[int, dict]:
    with concurrent.futures.ThreadPoolExecutor(max_workers=1) as executor:
        future = executor.submit(
            client.request,
            "POST",
            "/v1/launch_app",
            {"bundleID": bundle_id, "sessionID": session_id},
            True,
            45,
        )
        for _ in range(60):
            if future.done():
                break
            result = subprocess.run(
                [
                    "/usr/bin/osascript",
                    "-e",
                    'tell application "System Events" to tell process "BackgroundComputerUse"',
                    "-e",
                    "repeat with candidateWindow in windows",
                    "-e",
                    'if exists button "Permitir uma vez" of candidateWindow then',
                    "-e",
                    'click button "Permitir uma vez" of candidateWindow',
                    "-e",
                    "return \"approved\"",
                    "-e",
                    "end if",
                    "-e",
                    "end repeat",
                    "-e",
                    "end tell",
                ],
                check=False,
                capture_output=True,
                text=True,
            )
            if result.returncode == 0 and result.stdout.strip():
                break
            time.sleep(0.1)
        return future.result(timeout=45)


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
        launch_status, launch_payload = launch_with_optional_approval(
            client,
            "com.apple.Safari",
            "core-xpc-smoke-resumed",
        )
        if not launch_is_background_safe(launch_status, launch_payload):
            raise RuntimeError(f"resumed launch failed: {launch_status} {launch_payload}")
        results.append({"name": "resume_after_core_crash", "status": "pass"})

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
