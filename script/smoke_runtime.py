#!/usr/bin/env python3
import argparse
import json
import math
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request
from pathlib import Path
from typing import Optional


AUTH_HEADER = "X-Background-Computer-Use-Token"

# Apple Vision can pay a one-off cold-start cost in the first disposable OCR worker after boot.
DEFAULT_TIMEOUT = 30
COLD_OCR_TIMEOUT = 90
# A later worker must stay under this budget; anything slower is a real regression, not a cold start.
WARM_OCR_BUDGET_SECONDS = 5.0
# Every window read and web action shares one node ceiling; the fixture tree fits well inside it.
MAX_NODES = 6500


def list_windows_request(pid: int) -> dict:
    if pid <= 0:
        raise ValueError("pid must be positive")
    return {"pid": pid}


def text_result_is_background_safe(payload: dict) -> bool:
    return (
        payload.get("classification") == "success"
        and payload.get("backgroundSafety", {}).get("foregroundPreserved") is True
        and payload.get("foregroundFallbackUsed") is False
        and type_text_retry_contract_is_valid(payload)
    )


def safari_adaptive_type_strategy_is_valid(payload: dict) -> bool:
    strategies = payload.get("strategiesAttempted", [])
    return (
        payload.get("fallbackReason") == "unchanged_ax_noop"
        and strategies == ["ax_value", "ax_text_operation"]
    )


def type_text_retry_contract_is_valid(payload: dict) -> bool:
    if "strategiesAttempted" not in payload:
        return False
    attempted = payload["strategiesAttempted"]
    retry_safe = payload.get("retrySafe")
    dispatch_succeeded = payload.get("dispatchSucceeded")
    if not isinstance(retry_safe, bool):
        return False
    if dispatch_succeeded is not None and not isinstance(dispatch_succeeded, bool):
        return False
    if not isinstance(attempted, list) or not all(
        isinstance(strategy, str) and bool(strategy.strip()) for strategy in attempted
    ):
        return False
    if not attempted:
        return dispatch_succeeded is not True and retry_safe
    return not retry_safe


def controlled_type_fallback_is_valid(payload: dict) -> bool:
    if (
        payload.get("foregroundFallbackUsed") is not True
        or payload.get("dispatchSucceeded") is not True
        or not type_text_retry_contract_is_valid(payload)
    ):
        return False
    if payload.get("classification") == "success":
        return payload.get("verification", {}).get("exactValueMatch") is True
    return payload.get("classification") == "verifier_ambiguous"


def _numeric_marker(text: str, label: str) -> Optional[int]:
    match = re.search(rf"{re.escape(label)}\s*(\d+)", text)
    return int(match.group(1)) if match else None


def _marker_increased(before: str, after: str, label: str) -> bool:
    """A marker proves an effect only when both reads parse and the value grew."""
    before_value = _numeric_marker(before, label)
    after_value = _numeric_marker(after, label)
    return before_value is not None and after_value is not None and after_value > before_value


def scroll_marker_increased(before: str, after: str) -> bool:
    return _marker_increased(before, after, "scroll-top:")


def page_scroll_marker_increased(before: str, after: str) -> bool:
    return _marker_increased(before, after, "page-scroll:")


def generation_incremented(before: str, after: str) -> bool:
    return _marker_increased(before, after, "generation:")


def strict_click_oracle_is_valid(payload: dict, before_marker: str, after_marker: str) -> bool:
    return (
        payload.get("classification") == "success"
        and payload.get("ok") is True
        and _marker_increased(before_marker, after_marker, "Button clicked ")
    )


def lane_status_for_effect(name: str, payload: dict, oracle_observed: bool) -> str:
    classification = payload.get("classification")
    if classification == "success":
        return "pass" if oracle_observed else "fail"
    if (
        name.endswith("-known-limitation")
        and classification in {"effect_not_verified", "verifier_ambiguous"}
    ):
        return "known_limitation"
    return "fail"


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
        self.chrome_process: Optional[subprocess.Popen] = None
        self.chrome_profile: Optional[Path] = None
        self.fixture_path: Optional[Path] = None
        self.safari_fixture_opened = False
        self.safari_was_running = False
        self.original_frontmost_bundle: Optional[str] = None
        self.original_frontmost_pid: Optional[int] = None

    def pass_(self, name: str, detail: str = "") -> None:
        self.results.append({"name": name, "status": "pass", "detail": detail})

    def fail(self, name: str, detail: str) -> None:
        self.results.append({"name": name, "status": "fail", "detail": detail})

    def skip(self, name: str, detail: str) -> None:
        self.results.append({"name": name, "status": "skip", "detail": detail})

    def known_limitation(self, name: str, detail: str) -> None:
        if not name.endswith("-known-limitation"):
            raise ValueError("known-limitation lane names must end in '-known-limitation'")
        self.results.append({"name": name, "status": "known_limitation", "detail": detail})

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
        try:
            self.require_status("health-open", "GET", "/health", 200, auth=False)
            self.require_status("v1-requires-auth", "GET", "/v1/routes", 401, auth=False)
            self.require_status("v1-routes-authenticated", "GET", "/v1/routes", 200)
            if include_apps:
                self.chrome_fixture()
                self.safari_text_fixture()
            return self.summary()
        finally:
            self.cleanup_fixture()

    def chrome_fixture(self) -> None:
        chrome_pid = self.open_chrome_fixture()
        if chrome_pid is None:
            return

        window_id = self.wait_for_window(
            chrome_pid,
            title_contains="BCU Smoke Fixture",
            check_name="chrome",
        )
        if window_id is None:
            self.fail("chrome-window", f"no visible window for pid {chrome_pid}")
            return
        self.pass_("chrome-window", f"pid={chrome_pid} window={window_id}")

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

        # The OCR lane leaves the button already clicked, and the fixture button is
        # idempotent, so the AX lane needs a pristine document to observe an effect.
        self.reload_fixture(window_id)
        state = self.get_state(window_id, "chrome-pre-ax-state", include_ocr=True) or state
        input_target = self.find_target(
            state,
            ["bcu-smoke-input", "Smoke input"],
            require_value_settable=True,
            role_contains="text field",
        )
        button_target = self.find_target(state, ["BCU Smoke Button", "Smoke Button"], role_contains="button")
        scroll_target = self.find_scroll_target(state)

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
                    "maxNodes": MAX_NODES,
                },
            )
            if status == 200 and set_value.get("ok") is True:
                self.pass_("chrome-set-value")
            elif status is not None:
                self.fail("chrome-set-value", f"HTTP {status}: {set_value}")

            state = self.get_state(window_id, "chrome-post-set-state", include_ocr=True) or state
            click_marker_before = self.rendered_text(state)
            status, click = self.call(
                "chrome-click",
                "POST",
                "/v1/click",
                self.click_body(window_id, state["stateToken"], button_target),
            )
            if status == 200:
                self.check_verification_honesty("chrome-ax-click-honesty", click)
            post_click_state = self.await_page_oracle(
                window_id,
                status,
                lambda after: strict_click_oracle_is_valid(click, click_marker_before, after),
                include_ocr=True,
            )
            if post_click_state is not None:
                self.pass_("chrome-click", "classification=success and Button clicked N increased")
                state = post_click_state
            elif status is not None:
                self.fail("chrome-click", f"strict click oracle failed; HTTP {status}: {click}")
        else:
            self.fail(
                "chrome-find-ax-targets",
                "AX surface did not expose both the input and the button; only the OCR path ran",
            )

        state = self.get_state(window_id, "chrome-post-click-state", include_ocr=True) or state
        scroll_target = self.find_scroll_target(state) or scroll_target
        if scroll_target is None:
            self.fail(
                "chrome-find-scroll-target",
                "no scroll container was exposed for the fixture window",
            )
            return
        self.pass_("chrome-find-scroll-target", json.dumps(scroll_target))

        # Chromium does not expose the fixture's inner overflow div (#scroll-region,
        # role=region) in the accessibility tree, so no AX target can move it from the
        # background. Record that gap instead of pretending the scroll engine failed.
        if self.find_target(state, ["BCU Scroll Region"]) is None:
            self.known_limitation(
                "chrome-inner-scroll-known-limitation",
                "Chromium exposes no AX node for the inner overflow region, so only the "
                "document scroll surface is reachable in background.",
            )

        scroll_marker_before = self.rendered_text(state)
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
                "maxNodes": MAX_NODES,
            },
        )
        post_scroll_state = self.await_page_oracle(
            window_id,
            status,
            lambda after: page_scroll_marker_increased(scroll_marker_before, after),
        )
        if (
            post_scroll_state is not None
            and scroll.get("classification") in {"success", "boundary"}
        ):
            self.pass_("chrome-scroll-fractional", str(scroll.get("classification")))
        elif status is not None:
            self.fail("chrome-scroll-fractional", f"strict scroll oracle failed; HTTP {status}: {scroll}")

    def check_warm_ocr_budget(self, window_id: str) -> None:
        """A warm OCR read must land inside the declared budget and attribute its own time."""
        name = "ocr-warm-budget"
        started = time.monotonic()
        status, payload = self.call(
            name,
            "POST",
            "/v1/get_window_state",
            self.state_body(window_id, include_ocr=True),
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

    def reload_fixture(self, window_id: str) -> None:
        """Reload and require both a verified key result and a generation increment."""
        name = "chrome-reload-known-limitation"
        before_state = self.read_state_without_result(window_id)
        before_text = self.rendered_text(before_state or {})
        status, response = self.call(
            name,
            "POST",
            "/v1/press_key",
            {"window": window_id, "key": "command+r", "maxNodes": 200},
        )
        reloaded_state = self.await_page_oracle(
            window_id,
            status,
            lambda after: generation_incremented(before_text, after),
        )
        oracle_observed = reloaded_state is not None
        lane_status = lane_status_for_effect(name, response, oracle_observed)
        detail = f"HTTP {status}; classification={response.get('classification')}; generationChanged={oracle_observed}"
        if status != 200 or lane_status == "fail":
            self.fail(name, detail)
        elif lane_status == "known_limitation":
            self.known_limitation(name, detail)
        else:
            self.pass_(name, detail)

    def scroll_fixture_to_top(self, window_id: str, state: dict) -> Optional[dict]:
        """Scroll the fixture document back to the top and return the fresh state."""
        status, _ = self.call(
            "chrome-ocr-scroll-top",
            "POST",
            "/v1/scroll",
            {
                "window": window_id,
                "stateToken": state.get("stateToken"),
                "target": {"kind": "display_index", "value": 0},
                "direction": "up",
                "pages": 6,
                "maxNodes": MAX_NODES,
            },
        )
        if status != 200:
            return None
        time.sleep(0.6)
        return self.get_state(window_id, "chrome-ocr-scroll-top", include_ocr=True)

    def exercise_visual_chrome_fixture(self, window_id: str) -> None:
        """Exercise the OCR-anchor click lane on every run and record the classification it really returns."""
        state = self.get_state(window_id, "chrome-ocr-state", include_ocr=True)
        if state is None:
            return

        button_anchor = self.find_ocr_anchor(state, ["BCU Smoke Button"])
        if button_anchor is None:
            # A tab reused across runs can be left scrolled, which puts the control
            # outside the viewport: the AX node still exists with a degenerate frame
            # while OCR sees only the rows below it. Scroll back to the top once
            # before deciding the lane cannot be exercised.
            state = self.scroll_fixture_to_top(window_id, state) or state
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
            self.click_body(
                window_id,
                state["stateToken"],
                button_anchor["target"],
                interaction_token="it_STALE",
            ),
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

        clicked_before = self.rendered_text(state)
        status, click = self.call(
            "chrome-ocr-click",
            "POST",
            "/v1/click",
            self.click_body(
                window_id,
                state["stateToken"],
                button_anchor["target"],
                interaction_token=state["interactionToken"],
            ),
        )
        if status is None:
            return
        if status != 200:
            self.fail("chrome-ocr-click", f"HTTP {status}: {click}")
            return
        if click.get("fallbackReason") == "stale_coordinate_guard":
            state = self.read_state_with_stable_interaction_token(
                window_id,
                "chrome-recover-stale-state",
                attempts=6,
                required_consecutive=2,
            )
            if state is None:
                return
            button_anchor = self.find_ocr_anchor(state, ["BCU Smoke Button"])
            if button_anchor is None:
                self.fail("chrome-recover-stale-anchor", "fresh OCR button anchor was unavailable")
                return
            status, click = self.call(
                "chrome-ocr-click-after-refresh",
                "POST",
                "/v1/click",
                self.click_body(
                    window_id,
                    state["stateToken"],
                    button_anchor["target"],
                    interaction_token=state["interactionToken"],
                ),
            )
            if status != 200 or click.get("fallbackReason") == "stale_coordinate_guard":
                self.fail("chrome-ocr-click-after-refresh", f"HTTP {status}: {click}")
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
            f" warnings={click.get('warnings')}"
            f" routeSteps={click.get('routeSteps')}"
            f" transports={click.get('transports')}"
        )

        self.check_verification_honesty("chrome-ocr-click-honesty", click)

        post_click_state = self.await_page_oracle(
            window_id,
            status,
            lambda after: strict_click_oracle_is_valid(click, clicked_before, after),
            include_ocr=True,
        )
        if post_click_state is not None:
            self.pass_("chrome-ocr-click", evidence)
        else:
            self.fail(
                "chrome-ocr-click",
                "OCR click requires classification=success and an exact Button clicked N increment "
                f"({evidence})",
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
        if classification != "success" and intent and self.action_dispatched(click):
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
        required_consecutive: int = 2,
    ) -> Optional[dict]:
        """Read state until two consecutive reads agree on interactionToken.

        The token also covers geometry and projected topology, so the first read after a layout change
        can already be superseded by the time a click reaches the runtime. Re-reading is the documented
        recovery for a stale token; this is not a blind retry of a failed action.
        """
        body = self.state_body(window_id, include_ocr=True)
        previous: Optional[dict] = None
        stable_count = 0
        for attempt in range(max(attempts, 1)):
            status, payload = self.call(name, "POST", "/v1/get_window_state", body)
            if status is None:
                return None
            if status != 200 or "interactionToken" not in payload:
                self.fail(name, f"HTTP {status}: {payload}")
                return None
            if previous is not None and previous["interactionToken"] == payload["interactionToken"]:
                stable_count += 1
            else:
                stable_count = 1
            if stable_count >= max(required_consecutive, 2):
                self.pass_(
                    name,
                    f"interactionToken stable for {stable_count} consecutive reads",
                )
                return payload
            previous = payload
            time.sleep(0.3)
        self.fail(name, f"interactionToken never stabilised across {attempts} consecutive reads")
        return previous

    def open_chrome_fixture(self) -> Optional[int]:
        chrome_binary = self.find_chrome_binary()
        if chrome_binary is None:
            self.skip("chrome-fixture", "Google Chrome is not installed")
            return None
        fixture = self.write_fixture()
        # A cache-busting query forces Chrome to load the document fresh instead of re-focusing a tab
        # that a previous run left scrolled, which would hide the fixture controls from AX and OCR.
        url = f"file://{fixture}?run={int(time.time())}"
        self.chrome_profile = Path(tempfile.mkdtemp(prefix="bcu-smoke-chrome-"))
        self.chrome_process = subprocess.Popen(
            [
                str(chrome_binary),
                f"--user-data-dir={self.chrome_profile}",
                "--no-first-run",
                "--disable-default-apps",
                "--disable-extensions",
                "--disable-sync",
                "--disable-background-networking",
                "--new-window",
                url,
            ],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
        )
        time.sleep(2.0)
        if self.chrome_process.poll() is not None:
            self.fail("chrome-fixture", "isolated Google Chrome exited before discovery")
            return None
        self.pass_("chrome-fixture", f"pid={self.chrome_process.pid} {url}")
        return self.chrome_process.pid

    def find_chrome_binary(self) -> Optional[Path]:
        standard = Path("/Applications/Google Chrome.app/Contents/MacOS/Google Chrome")
        if standard.is_file():
            return standard
        installed = subprocess.run(
            ["/usr/bin/mdfind", "kMDItemCFBundleIdentifier == 'com.google.Chrome'"],
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
            timeout=5,
        )
        for app_path in installed.stdout.splitlines():
            candidate = Path(app_path) / "Contents/MacOS/Google Chrome"
            if candidate.is_file():
                return candidate
        return None

    def write_fixture(self) -> Path:
        path = Path(tempfile.gettempdir()) / "bcu-smoke-runtime.html"
        self.fixture_path = path
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
    .scroll-region {{ height: 180px; overflow: auto; border: 1px solid #777; }}
  </style>
</head>
<body>
  <h1>BCU Smoke Fixture</h1>
  <label for="bcu-smoke-input">Input</label>
  <input
    id="bcu-smoke-input"
    aria-label="bcu-smoke-input"
    placeholder="Smoke input"
    oninput="document.getElementById('input-status').textContent='Input: '+this.value">
  <p id="input-status">Input: empty</p>
  <label for="bcu-ignored-ax-input">Ignored AX input</label>
  <input
    id="bcu-ignored-ax-input"
    aria-label="bcu-ignored-ax-input"
    placeholder="Ignored AX input"
    oninput="document.getElementById('ignored-status').textContent='Ignored: '+this.value">
  <p id="ignored-status">Ignored: empty</p>
  <label for="bcu-paste-input">Paste input</label>
  <input
    id="bcu-paste-input"
    aria-label="bcu-paste-input"
    placeholder="Paste input">
  <button
    id="bcu-smoke-button"
    data-count="0"
    onclick="this.dataset.count=String(Number(this.dataset.count)+1);document.getElementById('click-status').textContent='Button clicked '+this.dataset.count">
    BCU Smoke Button
  </button>
  <p id="click-status">Button clicked 0</p>
  <div id="scroll-region" class="scroll-region" role="region" aria-label="BCU Scroll Region">
    <main>{rows}</main>
  </div>
  <p id="scroll-marker">scroll-top:0</p>
  <p id="generation-marker">generation:1</p>
  <p id="page-scroll-marker">page-scroll:0</p>
  <!-- Page-level filler: Chromium does not expose the inner overflow div above as an
       AX node, so only the document/web area is reachable as a scroll target. The
       page marker below is the one a background scroll can actually prove. -->
  <div class="page-filler">{rows}</div>
  <script>
    const scroll=document.getElementById('scroll-region');
    scroll.addEventListener('scroll',()=>document.getElementById('scroll-marker').textContent='scroll-top:'+Math.round(scroll.scrollTop));
    const pageMarker=document.getElementById('page-scroll-marker');
    const renderPageScroll=()=>{{pageMarker.textContent='page-scroll:'+Math.round(window.scrollY);}};
    window.addEventListener('scroll',renderPageScroll,{{passive:true}});
    renderPageScroll();
    const generation=Number(sessionStorage.getItem('generation')||'0')+1;
    sessionStorage.setItem('generation',String(generation));
    document.getElementById('generation-marker').textContent='generation:'+generation;
  </script>
</body>
</html>
""",
            encoding="utf-8",
        )
        return path

    def wait_for_window(
        self,
        pid: int,
        title_contains: str,
        check_name: str,
    ) -> Optional[str]:
        for _ in range(20):
            try:
                status, payload = self.client.request(
                    "POST",
                    "/v1/list_windows",
                    list_windows_request(pid),
                )
            except Exception:
                status, payload = None, {}
            if status == 200:
                resolved_pid = payload.get("app", {}).get("pid")
                window_pids = {window.get("pid") for window in payload.get("windows", [])}
                if resolved_pid != pid or any(window_pid != pid for window_pid in window_pids):
                    self.fail(
                        f"{check_name}-pid-isolation",
                        f"requested pid={pid} resolved pid={resolved_pid} window pids={list(window_pids)}",
                    )
                    return None
                for window in payload.get("windows", []):
                    title = str(window.get("title", ""))
                    if title_contains in title:
                        self.pass_(f"{check_name}-pid-isolation", f"all windows belong to pid={pid}")
                        return str(window.get("windowID"))
            time.sleep(0.25)
        return None

    def safari_text_fixture(self) -> None:
        if self.fixture_path is None:
            self.fail("safari-fixture", "shared smoke fixture was unavailable")
            return
        apps_before = self.list_apps_payload()
        if apps_before is None:
            return
        frontmost = apps_before.get("frontmostApp") or {}
        if frontmost.get("bundleID") in {None, "com.apple.Safari"}:
            preferred_bundles = ["dev.21st.agents", "com.openai.codex", "com.apple.finder"]
            candidates = [
                app for app in apps_before.get("runningApps", [])
                if app.get("bundleID") in preferred_bundles and isinstance(app.get("pid"), int)
            ]
            candidates.sort(
                key=lambda app: preferred_bundles.index(app.get("bundleID"))
            )
            if candidates:
                frontmost = candidates[0]
        self.original_frontmost_bundle = frontmost.get("bundleID")
        self.original_frontmost_pid = frontmost.get("pid") if isinstance(frontmost.get("pid"), int) else None
        self.safari_was_running = any(
            app.get("bundleID") == "com.apple.Safari"
            for app in apps_before.get("runningApps", [])
        )

        subprocess.run(
            ["/usr/bin/open", "-a", "Safari", f"file://{self.fixture_path}"],
            check=False,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        self.safari_fixture_opened = True
        safari_pid = self.wait_for_app_pid("com.apple.Safari")
        if safari_pid is None:
            self.fail("safari-fixture", "Safari did not become targetable")
            return
        window_id = self.wait_for_window(
            safari_pid,
            title_contains="BCU Smoke Fixture",
            check_name="safari",
        )
        if window_id is None:
            self.fail("safari-window", f"fixture window was unavailable for pid={safari_pid}")
            return

        if self.original_frontmost_pid is not None:
            self.activate_pid(self.original_frontmost_pid)
        foreground_before = self.wait_for_frontmost_pid(excluding=safari_pid)
        if foreground_before is None:
            self.fail("safari-background-setup", "could not place another application in foreground")
            return

        status, found = self.call(
            "safari-find-input",
            "POST",
            "/v1/find_elements",
            {
                "window": window_id,
                "role": "textField",
                "includeMenuBar": False,
            },
        )
        matches = found.get("matches", []) if status == 200 else []
        preferred_matches = [
            match for match in matches
            if match.get("domIdentifier") == "bcu-smoke-input"
        ]
        if preferred_matches:
            matches = preferred_matches
        if not matches:
            self.fail("safari-find-input", f"HTTP {status}: {found}")
            return
        node_id = matches[0].get("nodeID")
        if not node_id:
            self.fail("safari-find-input", "matched input exposed no nodeID")
            return

        status, typed = self.call(
            "safari-background-type",
            "POST",
            "/v1/type_text",
            {
                "window": window_id,
                "stateToken": found.get("stateToken"),
                "target": {"kind": "node_id", "value": node_id},
                "text": "bcu-background-safe",
                "includeMenuBar": False,
            },
        )
        foreground_after = self.frontmost_pid()
        detail = (
            f"HTTP {status} classification={typed.get('classification')} "
            f"dispatchSucceeded={typed.get('dispatchSucceeded')} "
            f"strategies={typed.get('strategiesAttempted')} "
            f"retrySafe={typed.get('retrySafe')} "
            f"foregroundFallbackUsed={typed.get('foregroundFallbackUsed')} "
            f"foregroundRestored={typed.get('foregroundRestored')} "
            f"backgroundSafety={typed.get('backgroundSafety')} "
            f"frontmostBefore={foreground_before} frontmostAfter={foreground_after}"
        )
        if (
            status == 200
            and text_result_is_background_safe(typed)
            and foreground_after == foreground_before
        ):
            self.pass_("safari-background-type", detail)
        else:
            self.fail("safari-background-type", detail)

        self.exercise_safari_adaptive_type_and_paste(
            window_id=window_id,
            foreground_pid=foreground_before,
        )

    def exercise_safari_adaptive_type_and_paste(
        self,
        window_id: str,
        foreground_pid: int,
    ) -> None:
        status, found = self.call(
            "safari-find-ignored-ax-input",
            "POST",
            "/v1/find_elements",
            {"window": window_id, "role": "textField", "includeMenuBar": False},
        )
        ignored = next(
            (
                match for match in found.get("matches", [])
                if match.get("domIdentifier") == "bcu-ignored-ax-input"
            ),
            None,
        ) if status == 200 else None
        if ignored is None or not ignored.get("nodeID"):
            self.fail("safari-find-ignored-ax-input", f"HTTP {status}: {found}")
            return

        status, adaptive = self.call(
            "safari-adaptive-background-type",
            "POST",
            "/v1/type_text",
            {
                "window": window_id,
                "stateToken": found.get("stateToken"),
                "target": {"kind": "node_id", "value": ignored["nodeID"]},
                "text": "bcu-adaptive-safe",
                "includeMenuBar": False,
            },
        )
        adaptive_detail = (
            f"HTTP {status} classification={adaptive.get('classification')} "
            f"summary={adaptive.get('summary')} "
            f"dispatchSucceeded={adaptive.get('dispatchSucceeded')} "
            f"strategies={adaptive.get('strategiesAttempted')} "
            f"retrySafe={adaptive.get('retrySafe')} "
            f"foregroundFallbackUsed={adaptive.get('foregroundFallbackUsed')} "
            f"foregroundRestored={adaptive.get('foregroundRestored')} "
            f"fallback={adaptive.get('fallbackReason')} "
            f"performance={adaptive.get('performance')} "
            f"verification={adaptive.get('verification')} "
            f"warnings={adaptive.get('warnings')}"
        )
        if (
            status == 200
            and text_result_is_background_safe(adaptive)
            and safari_adaptive_type_strategy_is_valid(adaptive)
            and self.frontmost_pid() == foreground_pid
        ):
            self.pass_("safari-adaptive-background-type", adaptive_detail)
        else:
            self.fail("safari-adaptive-background-type", adaptive_detail)

        status, paste_found = self.call(
            "safari-find-paste-input",
            "POST",
            "/v1/find_elements",
            {"window": window_id, "role": "textField", "includeMenuBar": False},
        )
        paste_target = next(
            (
                match for match in paste_found.get("matches", [])
                if match.get("domIdentifier") == "bcu-paste-input"
            ),
            None,
        ) if status == 200 else None
        if paste_target is None or not paste_target.get("nodeID"):
            self.fail("safari-find-paste-input", f"HTTP {status}: {paste_found}")
            return

        status, pasted = self.call(
            "safari-background-paste",
            "POST",
            "/v1/paste",
            {
                "window": window_id,
                "stateToken": paste_found.get("stateToken"),
                "target": {"kind": "node_id", "value": paste_target["nodeID"]},
                "content": "<strong>Paste</strong> ok",
                "format": "html",
                "includeMenuBar": False,
            },
        )
        paste_detail = (
            f"HTTP {status} classification={pasted.get('classification')} "
            f"summary={pasted.get('summary')} "
            f"primitive={pasted.get('dispatchPrimitive')} "
            f"restored={pasted.get('pasteboardRestored')} "
            f"verification={pasted.get('verification')} "
            f"notes={pasted.get('notes')} "
            f"warnings={pasted.get('warnings')}"
        )
        if (
            status == 200
            and pasted.get("classification") == "success"
            and pasted.get("pasteboardRestored") is True
            and pasted.get("backgroundSafety", {}).get("foregroundPreserved") is True
            and pasted.get("verification", {}).get("exactValueMatch") is True
            and self.frontmost_pid() == foreground_pid
        ):
            self.pass_("safari-background-paste", paste_detail)
        else:
            self.fail("safari-background-paste", paste_detail)

    def list_apps_payload(self) -> Optional[dict]:
        try:
            status, payload = self.client.request("POST", "/v1/list_apps", {})
        except Exception as exc:
            self.fail("list-apps-runtime", f"{type(exc).__name__}: {exc}")
            return None
        if status != 200:
            self.fail("list-apps-runtime", f"HTTP {status}: {payload}")
            return None
        return payload

    def wait_for_app_pid(self, bundle_id: str) -> Optional[int]:
        for _ in range(30):
            payload = self.list_apps_payload()
            if payload is None:
                return None
            for app in payload.get("runningApps", []):
                if app.get("bundleID") == bundle_id and isinstance(app.get("pid"), int):
                    return int(app["pid"])
            time.sleep(0.2)
        return None

    def frontmost_pid(self) -> Optional[int]:
        payload = self.list_apps_payload()
        if payload is None:
            return None
        pid = (payload.get("frontmostApp") or {}).get("pid")
        return int(pid) if isinstance(pid, int) else None

    def wait_for_frontmost_pid(self, excluding: int) -> Optional[int]:
        for _ in range(30):
            pid = self.frontmost_pid()
            if pid is not None and pid != excluding:
                return pid
            time.sleep(0.2)
        return None

    def activate_pid(self, pid: int) -> bool:
        source = (
            'tell application "System Events" to set frontmost of '
            f'(first application process whose unix id is {pid}) to true'
        )
        return subprocess.run(
            ["/usr/bin/osascript", "-e", source],
            check=False,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        ).returncode == 0

    def cleanup_fixture(self) -> None:
        if self.safari_fixture_opened:
            close_script = (
                'tell application "Safari" to close every document whose name is "BCU Smoke Fixture"'
            )
            subprocess.run(
                ["/usr/bin/osascript", "-e", close_script],
                check=False,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
            if not self.safari_was_running:
                subprocess.run(
                    ["/usr/bin/osascript", "-e", 'tell application "Safari" to quit'],
                    check=False,
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                )
        if self.original_frontmost_pid is not None:
            self.activate_pid(self.original_frontmost_pid)
        if self.chrome_process is not None and self.chrome_process.poll() is None:
            self.chrome_process.terminate()
            try:
                self.chrome_process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                self.chrome_process.kill()
                self.chrome_process.wait(timeout=5)
        if self.chrome_profile is not None:
            shutil.rmtree(self.chrome_profile, ignore_errors=True)
        if self.fixture_path is not None:
            try:
                self.fixture_path.unlink()
            except FileNotFoundError:
                pass

    @staticmethod
    def state_body(window_id: str, include_ocr: bool = False) -> dict:
        body = {"window": window_id, "imageMode": "path", "maxNodes": MAX_NODES}
        if include_ocr:
            body["includeOCR"] = True
        return body

    @staticmethod
    def click_body(
        window_id: str,
        state_token: str,
        target: dict,
        interaction_token: Optional[str] = None,
    ) -> dict:
        body = {
            "window": window_id,
            "stateToken": state_token,
            "target": target,
            "clickCount": 1,
            "imageMode": "path",
            "maxNodes": MAX_NODES,
        }
        if interaction_token is not None:
            body["interactionToken"] = interaction_token
        return body

    @staticmethod
    def rendered_text(state: dict) -> str:
        return str(state.get("tree", {}).get("renderedText") or "")

    def get_state(
        self,
        window_id: str,
        name: str,
        include_ocr: bool = False,
        timeout: float = DEFAULT_TIMEOUT,
    ) -> Optional[dict]:
        status, payload = self.call(
            name,
            "POST",
            "/v1/get_window_state",
            self.state_body(window_id, include_ocr),
            timeout=timeout,
        )
        if status is None:
            return None
        if status == 200 and "stateToken" in payload:
            self.pass_(name)
            return payload
        self.fail(name, f"HTTP {status}: {payload}")
        return None

    def read_state_without_result(self, window_id: str, include_ocr: bool = False) -> Optional[dict]:
        try:
            status, payload = self.client.request(
                "POST",
                "/v1/get_window_state",
                body=self.state_body(window_id, include_ocr),
                timeout=COLD_OCR_TIMEOUT if include_ocr else DEFAULT_TIMEOUT,
            )
        except Exception:
            return None
        return payload if status == 200 and "stateToken" in payload else None

    def await_page_oracle(
        self,
        window_id: str,
        status: Optional[int],
        oracle,
        include_ocr: bool = False,
        attempts: int = 30,
    ) -> Optional[dict]:
        """Poll rendered text until the page-side oracle holds.

        Returns the state that satisfied the oracle, so no caller re-evaluates it; None
        means the action request itself failed or the effect never appeared in the page.
        """
        if status != 200:
            return None
        for _ in range(attempts):
            state = self.read_state_without_result(window_id, include_ocr=include_ocr)
            if state is not None and oracle(self.rendered_text(state)):
                return state
            time.sleep(0.1)
        return None

    def find_target(
        self,
        state: dict,
        needles: list[str],
        require_value_settable: bool = False,
        require_scroll_container: bool = False,
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
            if (
                require_scroll_container
                and node.get("interactionTraits", {}).get("isPotentialScrollContainer") is not True
            ):
                continue
            display_index = node.get("displayIndex")
            if isinstance(display_index, int):
                return {"kind": "display_index", "value": display_index}
            node_id = node.get("nodeID")
            if isinstance(node_id, str) and node_id:
                return {"kind": "node_id", "value": node_id}
        return None

    def find_scroll_target(self, state: dict) -> Optional[dict]:
        """Resolve a scroll surface the runtime can actually move.

        Prefer the fixture's labelled region when Chromium exposes it; otherwise fall
        back to whatever node the runtime itself reports as a scroll container (the web
        area). The window root is never accepted: it is not a scroll container, and
        targeting it turns a targeting miss into a bogus scroll failure.
        """
        labelled = self.find_target(
            state,
            ["BCU Scroll Region", "scroll-region"],
            require_scroll_container=True,
        )
        if labelled is not None:
            return labelled
        for node in state.get("tree", {}).get("nodes", []):
            if node.get("interactionTraits", {}).get("isPotentialScrollContainer") is not True:
                continue
            display_index = node.get("displayIndex")
            if isinstance(display_index, int):
                return {"kind": "display_index", "value": display_index}
        return None

    @staticmethod
    def action_dispatched(response: dict) -> bool:
        return any(
            transport.get("didDispatch") is True and transport.get("transportSuccess") is True
            for transport in response.get("transports", [])
        )

    def find_ocr_anchor(self, state: dict, needles: list[str], budget: int = 2) -> Optional[dict]:
        """Resolve an anchor by text, tolerating Apple Vision misreads.

        Vision returns 'BCU Smcke Button' often enough that an exact substring
        match turns a working lane into a red check, so anchors are matched on a
        normalized string with a small edit-distance budget.
        """

        def normalize(value: str) -> str:
            return "".join(char for char in value.lower() if char.isalnum() or char == " ").strip()

        def distance(left: str, right: str) -> int:
            previous = list(range(len(right) + 1))
            for i, left_char in enumerate(left, start=1):
                current = [i]
                for j, right_char in enumerate(right, start=1):
                    current.append(
                        min(
                            previous[j] + 1,
                            current[j - 1] + 1,
                            previous[j - 1] + (0 if left_char == right_char else 1),
                        )
                    )
                previous = current
            return previous[-1]

        wanted = [normalize(needle) for needle in needles]
        best: Optional[tuple[int, dict]] = None
        for anchor in state.get("ocr", {}).get("anchors", []):
            text = normalize(str(anchor.get("text", "")))
            if not text:
                continue
            score = min((0 if needle in text else distance(text, needle)) for needle in wanted)
            if score > budget:
                continue
            x = anchor.get("x")
            y = anchor.get("y")
            if not all(
                isinstance(value, (int, float))
                and not isinstance(value, bool)
                and math.isfinite(value)
                for value in (x, y)
            ):
                continue
            target = anchor.get("target")
            if not (isinstance(target, dict) and target.get("kind") == "ocr_anchor"):
                continue
            if best is None or score < best[0]:
                best = (score, {"x": x, "y": y, "target": target})
        return best[1] if best else None

    def summary(self) -> dict:
        passes = sum(1 for result in self.results if result["status"] == "pass")
        failures = sum(1 for result in self.results if result["status"] == "fail")
        skips = sum(1 for result in self.results if result["status"] == "skip")
        known_limitations = sum(
            1 for result in self.results if result["status"] == "known_limitation"
        )
        passed = failures == 0 and skips == 0
        return {
            "failures": failures,
            "passes": passes,
            "skips": skips,
            "knownLimitations": known_limitations,
            "passed": passed,
            "fullyQualified": passed and known_limitations == 0,
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
    return 0 if summary["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
