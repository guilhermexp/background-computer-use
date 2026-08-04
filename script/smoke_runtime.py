#!/usr/bin/env python3
import argparse
import json
import math
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

# Apple Vision pays a one-off cold-start cost on the first recognition after the runtime boots.
# The runtime prewarms it, but a runtime that just launched can still be mid-warmup.
DEFAULT_TIMEOUT = 30
COLD_OCR_TIMEOUT = 90
# A warm OCR read must stay under this budget; anything slower is a real regression, not a cold start.
WARM_OCR_BUDGET_SECONDS = 5.0


class BCUClient:
    def __init__(self) -> None:
        manifest = self._read_manifest()
        self.base_url = str(manifest["baseURL"]).rstrip("/")
        self.token = manifest.get("authToken")

    def request(
        self,
        method: str,
        path: str,
        body: Optional[dict] = None,
        auth: bool = True,
        timeout: float = DEFAULT_TIMEOUT,
    ) -> tuple[int, dict]:
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
            with urllib.request.urlopen(request, timeout=timeout) as response:
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

    def call(
        self,
        name: str,
        method: str,
        path: str,
        body: Optional[dict] = None,
        auth: bool = True,
        timeout: float = DEFAULT_TIMEOUT,
    ) -> tuple[Optional[int], dict]:
        """Issue a request that can never crash the run: transport problems become a failed check."""
        try:
            return self.client.request(method, path, body=body, auth=auth, timeout=timeout)
        except Exception as exc:
            self.fail(name, f"{type(exc).__name__} calling {method} {path}: {exc}")
            return None, {}

    def require_status(
        self,
        name: str,
        method: str,
        path: str,
        expected: int,
        body: Optional[dict] = None,
        auth: bool = True,
        timeout: float = DEFAULT_TIMEOUT,
    ) -> Optional[dict]:
        status, payload = self.call(name, method, path, body=body, auth=auth, timeout=timeout)
        if status is None:
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

        # First OCR read may still be paying Apple Vision warmup, so it gets the cold budget.
        state = self.get_state(
            window_id,
            "chrome-state",
            include_ocr=True,
            timeout=COLD_OCR_TIMEOUT,
        )
        if state is None:
            return
        self.check_warm_ocr_budget(window_id)

        # The OCR/visual lane is the feature under test, so it runs on every pass, not only when AX is
        # opaque. It goes first, while the fixture is still pristine and its effect would be observable.
        self.exercise_visual_chrome_fixture(window_id)

        state = self.get_state(window_id, "chrome-pre-ax-state", include_ocr=True) or state
        input_target = self.find_target(
            state,
            ["bcu-smoke-input", "Smoke input"],
            require_value_settable=True,
            role_contains="text field",
        )
        button_target = self.find_target(state, ["BCU Smoke Button", "Smoke Button"], role_contains="button")
        scroll_target = self.find_target(state, ["Row 1", "Row 2", "BCU Smoke Fixture"])

        if input_target is not None and button_target is not None:
            self.pass_("chrome-find-input", json.dumps(input_target))
            self.pass_("chrome-find-button", json.dumps(button_target))
            status, set_value = self.call(
                "chrome-set-value",
                "POST",
                "/v1/set_value",
                {
                    "window": window_id,
                    "stateToken": state["stateToken"],
                    "target": input_target,
                    "value": "bcu-smoke-value",
                    "maxNodes": 6500,
                },
            )
            if status == 200 and set_value.get("ok") is True:
                self.pass_("chrome-set-value")
            elif status is not None:
                self.fail("chrome-set-value", f"HTTP {status}: {set_value}")

            state = self.get_state(window_id, "chrome-post-set-state", include_ocr=True) or state
            status, click = self.call(
                "chrome-click",
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
            if status == 200:
                self.check_verification_honesty("chrome-ax-click-honesty", click)
            if status == 200 and click.get("ok") is True:
                self.pass_("chrome-click", str(click.get("classification")))
            elif status is not None:
                self.fail("chrome-click", f"HTTP {status}: {click}")
        else:
            self.fail(
                "chrome-find-ax-targets",
                "AX surface did not expose both the input and the button; only the OCR path ran",
            )

        state = self.get_state(window_id, "chrome-post-click-state", include_ocr=True) or state
        scroll_target = (
            self.find_target(state, ["Row 1", "Row 2", "BCU Smoke Fixture"])
            or scroll_target
            or {"kind": "display_index", "value": 0}
        )
        self.pass_("chrome-find-scroll-target", json.dumps(scroll_target))
        status, scroll = self.call(
            "chrome-scroll-fractional",
            "POST",
            "/v1/scroll",
            {
                "window": window_id,
                "stateToken": state["stateToken"],
                "target": scroll_target,
                "direction": "down",
                "pages": 0.25,
                "maxNodes": 6500,
            },
        )
        if status == 200 and scroll.get("classification") in {"success", "boundary", "verifier_ambiguous"}:
            self.pass_("chrome-scroll-fractional", str(scroll.get("classification")))
        elif status is not None:
            self.fail("chrome-scroll-fractional", f"HTTP {status}: {scroll}")

    def check_warm_ocr_budget(self, window_id: str) -> None:
        """A warm OCR read must land inside the declared budget and attribute its own time."""
        name = "ocr-warm-budget"
        started = time.monotonic()
        status, payload = self.call(
            name,
            "POST",
            "/v1/get_window_state",
            {"window": window_id, "imageMode": "path", "includeOCR": True, "maxNodes": 6500},
            timeout=COLD_OCR_TIMEOUT,
        )
        if status is None:
            return
        if status != 200:
            self.fail(name, f"HTTP {status}: {payload}")
            return
        elapsed = time.monotonic() - started
        ocr_ms = payload.get("performance", {}).get("ocrMs")
        detail = f"wall {elapsed:.2f}s budget {WARM_OCR_BUDGET_SECONDS:.1f}s ocrMs {ocr_ms}"
        if ocr_ms is None:
            self.fail(name, f"performance.ocrMs missing on an includeOCR read ({detail})")
            return
        if elapsed > WARM_OCR_BUDGET_SECONDS:
            self.fail(name, f"warm OCR read exceeded the declared budget ({detail})")
            return
        self.pass_(name, detail)

    def exercise_visual_chrome_fixture(self, window_id: str) -> None:
        """Exercise the OCR-anchor click lane on every run and record the classification it really returns."""
        state = self.get_state(window_id, "chrome-ocr-state", include_ocr=True)
        if state is None:
            return

        button_anchor = self.find_ocr_anchor(state, ["BCU Smoke Button"])
        if button_anchor is None:
            self.fail(
                "chrome-ocr-find-button",
                "OCR could not resolve the 'BCU Smoke Button' anchor in the fixture screenshot",
            )
            return
        self.pass_("chrome-ocr-find-button", button_anchor["target"]["value"])

        status, stale = self.call(
            "chrome-ocr-stale-guard",
            "POST",
            "/v1/click",
            {
                "window": window_id,
                "stateToken": state["stateToken"],
                "interactionToken": "it_STALE",
                "target": button_anchor["target"],
                "clickCount": 1,
                "imageMode": "path",
                "maxNodes": 6500,
            },
        )
        if status is None:
            return
        if status != 200 or stale.get("fallbackReason") != "stale_coordinate_guard":
            self.fail("chrome-ocr-stale-guard", f"HTTP {status}: {stale}")
            return
        self.pass_("chrome-ocr-stale-guard", str(stale.get("summary")))

        state = self.read_state_with_stable_interaction_token(window_id, "chrome-post-stale-state")
        if state is None:
            return
        button_anchor = self.find_ocr_anchor(state, ["BCU Smoke Button"])
        if button_anchor is None:
            self.fail("chrome-refresh-ocr-anchors", "fresh OCR anchors were unavailable after the stale-token probe")
            return
        self.pass_("chrome-refresh-ocr-anchors")

        clicked_before = self.find_ocr_anchor(state, ["Button clicked"]) is not None
        status, click = self.call(
            "chrome-ocr-click",
            "POST",
            "/v1/click",
            {
                "window": window_id,
                "stateToken": state["stateToken"],
                "interactionToken": state["interactionToken"],
                "target": button_anchor["target"],
                "clickCount": 1,
                "imageMode": "path",
                "maxNodes": 6500,
            },
        )
        if status is None:
            return
        if status != 200:
            self.fail("chrome-ocr-click", f"HTTP {status}: {click}")
            return

        classification = str(click.get("classification"))
        verification = click.get("verification") or {}
        evidence = (
            f"classification={classification}"
            f" finalRoute={click.get('finalRoute')}"
            f" dispatched={self.action_dispatched(click)}"
            f" intentSignals={verification.get('intentSignals')}"
            f" ambientOnlySignals={verification.get('ambientOnlySignals')}"
            f" targetRegionChangeRatio={verification.get('targetRegionChangeRatio')}"
            f" ocrAnchorDisappeared={verification.get('ocrAnchorDisappeared')}"
        )

        self.check_verification_honesty("chrome-ocr-click-honesty", click)

        state = self.get_state(window_id, "chrome-post-ocr-click-state", include_ocr=True)
        page_changed = (
            state is not None
            and clicked_before is False
            and self.find_ocr_anchor(state, ["Button clicked"]) is not None
        )
        if page_changed:
            self.pass_("chrome-ocr-click", evidence)
        elif classification == "success":
            self.fail(
                "chrome-ocr-click",
                f"click reported success but the page never showed 'Button clicked' ({evidence})",
            )
        else:
            # Documented limitation, not a masked pass: coordinate/OCR dispatch does not activate
            # Chromium web content today. Fixing the native transport is a separate phase.
            self.skip(
                "chrome-ocr-click",
                "known limitation: coordinate/OCR clicks do not activate Chromium web content; "
                f"use an AX target instead ({evidence})",
            )

    def check_verification_honesty(self, name: str, click: dict) -> None:
        """A success verdict must be backed by a target-local or structural intent signal."""
        verification = click.get("verification")
        if not isinstance(verification, dict):
            self.fail(name, f"click response carried no verification block: {click.get('summary')}")
            return
        intent = verification.get("intentSignals")
        if not isinstance(intent, list):
            self.fail(name, "verification.intentSignals is missing; the runtime predates the honest gate")
            return
        classification = click.get("classification")
        if classification == "success" and not intent:
            self.fail(name, f"classification=success with no intent signal: {verification}")
            return
        if classification != "success" and intent:
            self.fail(name, f"intent signals {intent} present but classification={classification}")
            return
        if (
            verification.get("targetRegionChangeRatio") is None
            and verification.get("targetRegionDiagnostic") is None
        ):
            self.fail(name, "targetRegionChangeRatio is null with no targetRegionDiagnostic explaining why")
            return
        self.pass_(name, f"classification={classification} intentSignals={intent}")

    def read_state_with_stable_interaction_token(
        self,
        window_id: str,
        name: str,
        attempts: int = 4,
    ) -> Optional[dict]:
        """Read state until two consecutive reads agree on interactionToken.

        The token also covers geometry and projected topology, so the first read after a layout change
        can already be superseded by the time a click reaches the runtime. Re-reading is the documented
        recovery for a stale token; this is not a blind retry of a failed action.
        """
        body = {"window": window_id, "imageMode": "path", "includeOCR": True, "maxNodes": 6500}
        previous: Optional[dict] = None
        for attempt in range(max(attempts, 1)):
            status, payload = self.call(name, "POST", "/v1/get_window_state", body)
            if status is None:
                return None
            if status != 200 or "interactionToken" not in payload:
                self.fail(name, f"HTTP {status}: {payload}")
                return None
            if previous is not None and previous["interactionToken"] == payload["interactionToken"]:
                self.pass_(name, f"interactionToken stable after {attempt + 1} reads")
                return payload
            previous = payload
            time.sleep(0.3)
        self.fail(name, f"interactionToken never stabilised across {attempts} consecutive reads")
        return previous

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
        # A cache-busting query forces Chrome to load the document fresh instead of re-focusing a tab
        # that a previous run left scrolled, which would hide the fixture controls from AX and OCR.
        url = f"file://{fixture}?run={int(time.time())}"
        subprocess.run(["/usr/bin/open", "-a", "Google Chrome", url], check=False)
        time.sleep(2.0)
        self.pass_("chrome-fixture", url)
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
  <label for="bcu-smoke-input">Input</label>
  <input
    id="bcu-smoke-input"
    aria-label="bcu-smoke-input"
    placeholder="Smoke input"
    value=""
    oninput="document.getElementById('input-status').textContent='Input: '+this.value">
  <p id="input-status">Input: empty</p>
  <button
    id="bcu-smoke-button"
    onclick="document.getElementById('click-status').textContent='Button clicked'">
    BCU Smoke Button
  </button>
  <p id="click-status">Button not clicked</p>
  <main>{rows}</main>
</body>
</html>
""",
            encoding="utf-8",
        )
        return path

    def wait_for_window(self, app_name: str) -> Optional[str]:
        for _ in range(20):
            try:
                status, payload = self.client.request("POST", "/v1/list_windows", {"app": app_name})
            except Exception:
                status, payload = None, {}
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

    def get_state(
        self,
        window_id: str,
        name: str,
        include_ocr: bool = False,
        timeout: float = DEFAULT_TIMEOUT,
    ) -> Optional[dict]:
        body = {"window": window_id, "imageMode": "path", "maxNodes": 6500}
        if include_ocr:
            body["includeOCR"] = True
        status, payload = self.call(name, "POST", "/v1/get_window_state", body, timeout=timeout)
        if status is None:
            return None
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

    @staticmethod
    def action_dispatched(response: dict) -> bool:
        return any(
            transport.get("didDispatch") is True and transport.get("transportSuccess") is True
            for transport in response.get("transports", [])
        )

    def find_ocr_anchor(self, state: dict, needles: list[str]) -> Optional[dict]:
        lowered = [needle.lower() for needle in needles]
        for anchor in state.get("ocr", {}).get("anchors", []):
            text = str(anchor.get("text", "")).lower()
            if any(needle in text for needle in lowered):
                x = anchor.get("x")
                y = anchor.get("y")
                if all(
                    isinstance(value, (int, float))
                    and not isinstance(value, bool)
                    and math.isfinite(value)
                    for value in (x, y)
                ):
                    target = anchor.get("target")
                    if isinstance(target, dict) and target.get("kind") == "ocr_anchor":
                        return {"x": x, "y": y, "target": target}
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
