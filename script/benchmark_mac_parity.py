#!/usr/bin/env python3
"""Run the signed macOS BCU parity latency and honesty benchmark."""

from __future__ import annotations

import argparse
import json
import math
import os
import subprocess
import time
from typing import Optional

try:
    from script.smoke_runtime import Smoke, text_result_is_background_safe
except ModuleNotFoundError:
    from smoke_runtime import Smoke, text_result_is_background_safe


def percentile(samples: list[float], value: float) -> float:
    if not samples:
        raise ValueError("percentile requires at least one sample")
    if value < 0 or value > 100:
        raise ValueError("percentile must be between 0 and 100")
    ordered = sorted(float(sample) for sample in samples)
    if len(ordered) == 1:
        return ordered[0]
    position = (len(ordered) - 1) * value / 100
    lower = math.floor(position)
    upper = math.ceil(position)
    if lower == upper:
        return ordered[lower]
    weight = position - lower
    return ordered[lower] * (1 - weight) + ordered[upper] * weight


def assess_lane(
    *,
    samples: list[float],
    expected_runs: int,
    p50_budget_ms: float,
    p95_budget_ms: float,
    completions: int,
    false_successes: int,
    foreground_violations: int,
) -> dict:
    p50 = percentile(samples, 50) if samples else None
    p95 = percentile(samples, 95) if samples else None
    passed = (
        len(samples) == expected_runs
        and completions == expected_runs
        and false_successes == 0
        and foreground_violations == 0
        and p50 is not None
        and p50 <= p50_budget_ms
        and p95 is not None
        and p95 <= p95_budget_ms
    )
    return {
        "passed": passed,
        "runs": expected_runs,
        "samplesMs": samples,
        "p50Ms": p50,
        "p95Ms": p95,
        "p50BudgetMs": p50_budget_ms,
        "p95BudgetMs": p95_budget_ms,
        "completions": completions,
        "falseSuccesses": false_successes,
        "foregroundViolations": foreground_violations,
    }


def safe_runtime_summary(manifest: dict) -> dict:
    """Return only non-secret runtime metadata suitable for benchmark logs."""
    allowed_keys = ("baseURL", "contractVersion", "startedAt", "permissions")
    return {key: manifest[key] for key in allowed_keys if key in manifest}


class MacParityBenchmark:
    def __init__(self, runs: int) -> None:
        self.runs = runs
        self.smoke = Smoke()
        self.caffeinate_process: Optional[subprocess.Popen] = None

    def run(self) -> dict:
        try:
            self.caffeinate_process = subprocess.Popen(
                ["/usr/bin/caffeinate", "-dimsu", "-w", str(os.getpid())],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
            window_id, safari_pid, foreground_pid = self._open_fixture()
            self._run_type(window_id, foreground_pid, record=False)
            self._run_click(window_id, foreground_pid, record=False)
            self._run_paste(window_id, foreground_pid, record=False)

            type_records = [self._run_type(window_id, foreground_pid, record=True) for _ in range(self.runs)]
            click_records = [self._run_click(window_id, foreground_pid, record=True) for _ in range(self.runs)]
            paste_records = [self._run_paste(window_id, foreground_pid, record=True) for _ in range(self.runs)]

            type_lane = self._assess_records(
                type_records,
                p50_budget_ms=450,
                p95_budget_ms=900,
            )
            click_lane = self._assess_records(
                click_records,
                p50_budget_ms=350,
                p95_budget_ms=750,
            )
            paste_lane = self._assess_records(
                paste_records,
                p50_budget_ms=400,
                p95_budget_ms=800,
            )
            return {
                "passed": type_lane["passed"] and click_lane["passed"] and paste_lane["passed"],
                "runtime": safe_runtime_summary(self.smoke.client._read_manifest()),
                "safariPID": safari_pid,
                "foregroundPID": foreground_pid,
                "typeText": type_lane,
                "semanticClick": click_lane,
                "paste": paste_lane,
            }
        finally:
            self.smoke.cleanup_fixture()
            if self.caffeinate_process is not None and self.caffeinate_process.poll() is None:
                self.caffeinate_process.terminate()

    def _open_fixture(self) -> tuple[str, int, int]:
        fixture = self.smoke.write_fixture()
        apps_before: Optional[dict] = None
        for _ in range(60):
            try:
                status, payload = self.smoke.client.request("POST", "/v1/list_apps", {})
            except Exception:
                status, payload = None, {}
            if status == 200:
                apps_before = payload
                break
            time.sleep(0.2)
        if apps_before is None:
            raise RuntimeError("list_apps failed before benchmark setup")
        frontmost = apps_before.get("frontmostApp") or {}
        if frontmost.get("bundleID") in {None, "com.apple.Safari"}:
            preferred_bundles = ["dev.21st.agents", "com.openai.codex", "com.apple.finder"]
            candidates = [
                app for app in apps_before.get("runningApps", [])
                if app.get("bundleID") in preferred_bundles and isinstance(app.get("pid"), int)
            ]
            candidates.sort(key=lambda app: preferred_bundles.index(app.get("bundleID")))
            if candidates:
                frontmost = candidates[0]
        self.smoke.original_frontmost_bundle = frontmost.get("bundleID")
        self.smoke.original_frontmost_pid = frontmost.get("pid") if isinstance(frontmost.get("pid"), int) else None
        self.smoke.safari_was_running = any(
            app.get("bundleID") == "com.apple.Safari"
            for app in apps_before.get("runningApps", [])
        )
        subprocess.run(
            ["/usr/bin/open", "-a", "Safari", f"file://{fixture}"],
            check=False,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        self.smoke.safari_fixture_opened = True
        safari_pid = self.smoke.wait_for_app_pid("com.apple.Safari")
        if safari_pid is None:
            raise RuntimeError("Safari did not become targetable")
        window_id = self.smoke.wait_for_window(safari_pid, "BCU Smoke Fixture", "benchmark-safari")
        if window_id is None:
            raise RuntimeError("Safari fixture window was unavailable")

        if self.smoke.original_frontmost_pid is not None:
            self.smoke.activate_pid(self.smoke.original_frontmost_pid)
        foreground_pid = self.smoke.wait_for_frontmost_pid(excluding=safari_pid)
        if foreground_pid is None:
            raise RuntimeError("could not preserve a non-Safari foreground app")
        return window_id, safari_pid, foreground_pid

    def _find_node(self, window_id: str, role: str, identifier: str) -> tuple[str, str]:
        last_payload: dict = {}
        for _ in range(20):
            status, payload = self.smoke.client.request(
                "POST",
                "/v1/find_elements",
                {"window": window_id, "role": role, "includeMenuBar": False},
            )
            last_payload = payload
            if status != 200:
                raise RuntimeError(f"find_elements returned HTTP {status}: {payload}")
            match = next(
                (item for item in payload.get("matches", []) if item.get("domIdentifier") == identifier),
                None,
            )
            if match is not None and isinstance(match.get("nodeID"), str):
                return match["nodeID"], payload["stateToken"]
            time.sleep(0.25)
        raise RuntimeError(f"could not find {identifier} in {last_payload}")

    def _run_type(self, window_id: str, foreground_pid: int, record: bool) -> dict:
        node_id, state_token = self._find_node(window_id, "textField", "bcu-ignored-ax-input")
        started = time.perf_counter()
        status, response = self.smoke.client.request(
            "POST",
            "/v1/type_text",
            {
                "window": window_id,
                "stateToken": state_token,
                "target": {"kind": "node_id", "value": node_id},
                "text": "x",
                "includeMenuBar": False,
            },
        )
        wall_ms = (time.perf_counter() - started) * 1_000
        completion = status == 200 and text_result_is_background_safe(response)
        exact = (response.get("verification") or {}).get("exactValueMatch") is True
        claimed = response.get("classification") == "success"
        foreground_after = self.smoke.frontmost_pid()
        foreground_ok = foreground_after == foreground_pid
        return {
            "record": record,
            "latencyMs": float((response.get("performance") or {}).get("totalMs", wall_ms)),
            "wallMs": wall_ms,
            "completion": completion and exact,
            "falseSuccess": claimed and not exact,
            "foregroundViolation": not foreground_ok,
            "foregroundPIDAfter": foreground_after,
            "classification": response.get("classification"),
        }

    def _run_click(self, window_id: str, foreground_pid: int, record: bool) -> dict:
        node_id, state_token = self._find_node(window_id, "button", "bcu-smoke-button")
        started = time.perf_counter()
        status, response = self.smoke.client.request(
            "POST",
            "/v1/click",
            {
                "window": window_id,
                "stateToken": state_token,
                "target": {"kind": "node_id", "value": node_id},
                "clickCount": 1,
                "imageMode": "omit",
                "includeMenuBar": False,
            },
        )
        wall_ms = (time.perf_counter() - started) * 1_000
        verification = response.get("verification") or {}
        intent = verification.get("intentSignals") or []
        claimed = response.get("classification") == "success"
        foreground_after = self.smoke.frontmost_pid()
        foreground_ok = foreground_after == foreground_pid
        return {
            "record": record,
            "latencyMs": float((response.get("performance") or {}).get("totalMs", wall_ms)),
            "wallMs": wall_ms,
            "completion": status == 200 and claimed and bool(intent),
            "falseSuccess": claimed and not bool(intent),
            "foregroundViolation": not foreground_ok,
            "foregroundPIDAfter": foreground_after,
            "classification": response.get("classification"),
            "intentSignals": intent,
        }

    def _run_paste(self, window_id: str, foreground_pid: int, record: bool) -> dict:
        node_id, state_token = self._find_node(window_id, "textField", "bcu-paste-input")
        started = time.perf_counter()
        status, response = self.smoke.client.request(
            "POST",
            "/v1/paste",
            {
                "window": window_id,
                "stateToken": state_token,
                "target": {"kind": "node_id", "value": node_id},
                "content": "!",
                "format": "text",
                "includeMenuBar": False,
            },
        )
        wall_ms = (time.perf_counter() - started) * 1_000
        verification = response.get("verification") or {}
        exact = verification.get("exactValueMatch") is True
        claimed = response.get("classification") == "success"
        foreground_after = self.smoke.frontmost_pid()
        foreground_ok = foreground_after == foreground_pid
        return {
            "record": record,
            "latencyMs": wall_ms,
            "wallMs": wall_ms,
            "completion": status == 200 and claimed and exact and response.get("pasteboardRestored") is True,
            "falseSuccess": claimed and not exact,
            "foregroundViolation": not foreground_ok,
            "foregroundPIDAfter": foreground_after,
            "classification": response.get("classification"),
        }

    def _assess_records(self, records: list[dict], p50_budget_ms: float, p95_budget_ms: float) -> dict:
        samples = [record["latencyMs"] for record in records]
        wall_samples = [record["wallMs"] for record in records]
        lane = assess_lane(
            samples=samples,
            expected_runs=self.runs,
            p50_budget_ms=p50_budget_ms,
            p95_budget_ms=p95_budget_ms,
            completions=sum(1 for record in records if record["completion"]),
            false_successes=sum(1 for record in records if record["falseSuccess"]),
            foreground_violations=sum(1 for record in records if record["foregroundViolation"]),
        )
        wall_p50 = percentile(wall_samples, 50)
        wall_p95 = percentile(wall_samples, 95)
        lane["wallSamplesMs"] = wall_samples
        lane["wallP50Ms"] = wall_p50
        lane["wallP95Ms"] = wall_p95
        lane["wallPassed"] = wall_p50 <= p50_budget_ms and wall_p95 <= p95_budget_ms
        lane["passed"] = lane["passed"] and lane["wallPassed"]
        lane["records"] = records
        return lane


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--runs", type=int, default=10)
    args = parser.parse_args()
    if args.runs <= 0:
        parser.error("--runs must be positive")
    result = MacParityBenchmark(args.runs).run()
    print(json.dumps(result, sort_keys=True))
    return 0 if result["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
