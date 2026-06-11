#!/usr/bin/env python3
import argparse
import json
import os
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request
from pathlib import Path
from typing import Optional


AUTH_HEADER = "X-Background-Computer-Use-Token"


class BCUClient:
    def __init__(self) -> None:
        manifest = self._read_manifest()
        self.base_url = str(manifest["baseURL"]).rstrip("/")
        self.token = manifest.get("authToken")

    def request(self, method: str, path: str, body: Optional[dict] = None, auth: bool = True) -> tuple[int, dict]:
        data = None
        headers = {"accept": "application/json"}
        if body is not None:
            data = json.dumps(body).encode("utf-8")
            headers["content-type"] = "application/json"
        if auth and self.token:
            headers[AUTH_HEADER] = str(self.token)
        request = urllib.request.Request(
            self.base_url + path,
            data=data,
            method=method,
            headers=headers,
        )
        try:
            with urllib.request.urlopen(request, timeout=30) as response:
                payload = response.read()
                status = response.status
        except urllib.error.HTTPError as exc:
            payload = exc.read()
            status = exc.code
        parsed = json.loads(payload.decode("utf-8")) if payload else {}
        return status, parsed

    def _read_manifest(self) -> dict:
        manifest_override = os.environ.get("BCU_MANIFEST_PATH")
        if manifest_override:
            path = Path(manifest_override)
        else:
            tmpdir = os.environ.get("TMPDIR", "/tmp").rstrip("/")
            path = Path(tmpdir) / "background-computer-use" / "runtime-manifest.json"
        try:
            return json.loads(path.read_text())
        except Exception as exc:
            raise RuntimeError(f"Could not read runtime manifest at {path}: {exc}") from exc


class Smoke:
    def __init__(self) -> None:
        self.client = BCUClient()
        self.results: list[dict] = []

    def pass_(self, name: str, detail: str = "") -> None:
        self.results.append({"name": name, "status": "pass", "detail": detail})

    def fail(self, name: str, detail: str) -> None:
        self.results.append({"name": name, "status": "fail", "detail": detail})

    def skip(self, name: str, detail: str) -> None:
        self.results.append({"name": name, "status": "skip", "detail": detail})

    def require_status(
        self,
        name: str,
        method: str,
        path: str,
        expected: int,
        body: Optional[dict] = None,
        auth: bool = True,
    ) -> Optional[dict]:
        try:
            status, payload = self.client.request(method, path, body=body, auth=auth)
        except Exception as exc:
            self.fail(name, str(exc))
            return None
        if status != expected:
            self.fail(name, f"expected HTTP {expected}, got HTTP {status}: {payload}")
            return None
        self.pass_(name)
        return payload

    def run(self, include_apps: bool) -> dict:
        self.require_status("health-open", "GET", "/health", 200, auth=False)
        self.require_status("v1-requires-auth", "GET", "/v1/routes", 401, auth=False)
        self.require_status("v1-routes-authenticated", "GET", "/v1/routes", 200)
        if include_apps:
            self.chrome_fixture()
        return self.summary()

    def chrome_fixture(self) -> None:
        app_name = self.open_chrome_fixture()
        if app_name is None:
            return

        window_id = self.wait_for_window(app_name)
        if window_id is None:
            self.fail("chrome-window", f"no visible window for {app_name}")
            return
        self.pass_("chrome-window", window_id)

        state = self.get_state(window_id, "chrome-state")
        if state is None:
            return

        input_target = self.find_target(
            state,
            ["bcu-smoke-input", "Smoke input"],
            require_value_settable=True,
            role_contains="text field",
        )
        button_target = self.find_target(state, ["BCU Smoke Button", "Smoke Button"], role_contains="button")
        scroll_target = self.find_target(state, ["Row 1", "Row 2", "BCU Smoke Fixture"])
        if input_target is None:
            self.fail("chrome-find-input", "could not resolve input target")
            return
        self.pass_("chrome-find-input", json.dumps(input_target))
        if button_target is None:
            self.fail("chrome-find-button", "could not resolve button target")
            return
        self.pass_("chrome-find-button", json.dumps(button_target))
        if scroll_target is None:
            self.fail("chrome-find-scroll-target", "could not resolve scroll target")
            return
        self.pass_("chrome-find-scroll-target", json.dumps(scroll_target))

        status, set_value = self.client.request(
            "POST",
            "/v1/set_value",
            {
                "window": window_id,
                "stateToken": state["stateToken"],
                "target": input_target,
                "value": "bcu-smoke-value",
                "imageMode": "path",
                "maxNodes": 6500,
            },
        )
        if status == 200 and set_value.get("ok") is True:
            self.pass_("chrome-set-value")
        else:
            self.fail("chrome-set-value", f"HTTP {status}: {set_value}")

        state = self.get_state(window_id, "chrome-post-set-state") or state
        status, click = self.client.request(
            "POST",
            "/v1/click",
            {
                "window": window_id,
                "stateToken": state["stateToken"],
                "target": button_target,
                "clickCount": 1,
                "imageMode": "path",
                "maxNodes": 6500,
            },
        )
        if status == 200 and click.get("ok") is True:
            self.pass_("chrome-click")
        else:
            self.fail("chrome-click", f"HTTP {status}: {click}")

        state = self.get_state(window_id, "chrome-post-click-state") or state
        scroll_target = self.find_target(state, ["Row 1", "Row 2", "BCU Smoke Fixture"]) or scroll_target
        status, scroll = self.client.request(
            "POST",
            "/v1/scroll",
            {
                "window": window_id,
                "stateToken": state["stateToken"],
                "target": scroll_target,
                "direction": "down",
                "pages": 0.25,
                "imageMode": "path",
                "maxNodes": 6500,
            },
        )
        if status == 200 and scroll.get("classification") in {"success", "boundary", "verifier_ambiguous"}:
            self.pass_("chrome-scroll-fractional", str(scroll.get("classification")))
        else:
            self.fail("chrome-scroll-fractional", f"HTTP {status}: {scroll}")

    def open_chrome_fixture(self) -> Optional[str]:
        if subprocess.run(["/usr/bin/pgrep", "-x", "Google Chrome"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode != 0:
            installed = subprocess.run(
                ["/usr/bin/mdfind", "kMDItemCFBundleIdentifier == 'com.google.Chrome'"],
                stdout=subprocess.PIPE,
                stderr=subprocess.DEVNULL,
                text=True,
                timeout=5,
            )
            if not installed.stdout.strip():
                self.skip("chrome-fixture", "Google Chrome is not installed")
                return None
        fixture = self.write_fixture()
        subprocess.run(["/usr/bin/open", "-a", "Google Chrome", str(fixture)], check=False)
        time.sleep(1.5)
        self.pass_("chrome-fixture", str(fixture))
        return "Google Chrome"

    def write_fixture(self) -> Path:
        path = Path(tempfile.gettempdir()) / "bcu-smoke-runtime.html"
        rows = "\n".join(f"<div class='row'>Row {i}</div>" for i in range(1, 80))
        path.write_text(
            f"""<!doctype html>
<html>
<head>
  <meta charset="utf-8">
  <title>BCU Smoke Fixture</title>
  <style>
    body {{ font-family: -apple-system, BlinkMacSystemFont, sans-serif; padding: 24px; }}
    input, button {{ font-size: 18px; margin: 8px 0; padding: 8px; }}
    .row {{ padding: 18px 10px; border-bottom: 1px solid #ddd; width: 420px; }}
  </style>
</head>
<body>
  <h1>BCU Smoke Fixture</h1>
  <label for="bcu-smoke-input">Smoke input</label>
  <input id="bcu-smoke-input" aria-label="bcu-smoke-input" value="">
  <button id="bcu-smoke-button" onclick="document.body.dataset.clicked='yes'">BCU Smoke Button</button>
  <main>{rows}</main>
</body>
</html>
""",
            encoding="utf-8",
        )
        return path

    def wait_for_window(self, app_name: str) -> Optional[str]:
        for _ in range(20):
            status, payload = self.client.request("POST", "/v1/list_windows", {"app": app_name})
            if status == 200:
                for window in payload.get("windows", []):
                    title = str(window.get("title", ""))
                    if "BCU Smoke Fixture" in title:
                        return str(window.get("windowID"))
                windows = payload.get("windows", [])
                if windows:
                    return str(windows[0].get("windowID"))
            time.sleep(0.25)
        return None

    def get_state(self, window_id: str, name: str) -> Optional[dict]:
        status, payload = self.client.request(
            "POST",
            "/v1/get_window_state",
            {"window": window_id, "imageMode": "path", "maxNodes": 6500},
        )
        if status == 200 and "stateToken" in payload:
            self.pass_(name)
            return payload
        self.fail(name, f"HTTP {status}: {payload}")
        return None

    def find_target(
        self,
        state: dict,
        needles: list[str],
        require_value_settable: bool = False,
        role_contains: Optional[str] = None,
    ) -> Optional[dict]:
        nodes = state.get("tree", {}).get("nodes", [])
        lowered = [needle.lower() for needle in needles]
        for node in nodes:
            haystack = json.dumps(node, sort_keys=True).lower()
            if not any(needle in haystack for needle in lowered):
                continue
            if role_contains and role_contains.lower() not in str(node.get("displayRole", "")).lower():
                continue
            if require_value_settable and node.get("interactionTraits", {}).get("supportsValueSet") is not True:
                continue
            display_index = node.get("displayIndex")
            if isinstance(display_index, int):
                return {"kind": "display_index", "value": display_index}
            node_id = node.get("nodeID")
            if isinstance(node_id, str) and node_id:
                return {"kind": "node_id", "value": node_id}
        return None

    def summary(self) -> dict:
        passes = sum(1 for result in self.results if result["status"] == "pass")
        failures = sum(1 for result in self.results if result["status"] == "fail")
        skips = sum(1 for result in self.results if result["status"] == "skip")
        return {
            "failures": failures,
            "passes": passes,
            "skips": skips,
            "results": self.results,
        }


def main() -> int:
    parser = argparse.ArgumentParser(description="Run BackgroundComputerUse runtime smoke tests.")
    parser.add_argument("--json", action="store_true", help="Print a final metrics JSON line.")
    parser.add_argument("--no-apps", action="store_true", help="Only test runtime API/auth endpoints.")
    args = parser.parse_args()

    smoke = Smoke()
    summary = smoke.run(include_apps=not args.no_apps)
    if args.json:
        print(json.dumps(summary, sort_keys=True))
    else:
        for result in summary["results"]:
            print(f"{result['status']:>4} {result['name']} {result['detail']}")
        print(json.dumps(summary, sort_keys=True))
    return 1 if summary["failures"] else 0


if __name__ == "__main__":
    raise SystemExit(main())
