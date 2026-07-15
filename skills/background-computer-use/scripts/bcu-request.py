#!/usr/bin/env python3
import json
import math
import os
import subprocess
import sys
import urllib.error
import urllib.request
from pathlib import Path
from typing import Optional


def usage() -> int:
    print(
        "usage: bcu-request.py METHOD PATH [JSON_BODY]\n"
        "examples:\n"
        "  bcu-request.py GET /v1/bootstrap\n"
        "  bcu-request.py POST /v1/list_apps '{}'",
        file=sys.stderr,
    )
    return 2


def manifest_path() -> Path:
    if os.environ.get("BCU_MANIFEST_PATH"):
        return Path(os.environ["BCU_MANIFEST_PATH"])
    tmpdir = os.environ.get("TMPDIR") or darwin_user_temp_directory()
    tmpdir = tmpdir.rstrip("/")
    return Path(tmpdir) / "background-computer-use" / "runtime-manifest.json"


def darwin_user_temp_directory() -> str:
    try:
        value = subprocess.check_output(
            ["getconf", "DARWIN_USER_TEMP_DIR"],
            text=True,
            stderr=subprocess.DEVNULL,
        ).strip()
    except (OSError, subprocess.CalledProcessError):
        value = ""
    return value or "/tmp"


def configured_timeout() -> float:
    raw_value = os.environ.get("BCU_TIMEOUT", "30")
    try:
        value = float(raw_value)
    except ValueError as exc:
        raise SystemExit(f"BCU_TIMEOUT must be a positive number, got {raw_value!r}") from exc
    if not math.isfinite(value) or value <= 0:
        raise SystemExit(f"BCU_TIMEOUT must be a positive number, got {raw_value!r}")
    return value


def request_timeout(route_path: str, body: object) -> float:
    timeout = configured_timeout()
    if route_path == "/v1/wait_for" and isinstance(body, dict):
        wait_timeout = body.get("timeoutSeconds")
        if (
            isinstance(wait_timeout, (int, float))
            and not isinstance(wait_timeout, bool)
            and math.isfinite(float(wait_timeout))
        ):
            timeout = max(timeout, float(wait_timeout) + 5.0)
    return timeout


def base_url() -> str:
    if os.environ.get("BCU_BASE_URL"):
        return os.environ["BCU_BASE_URL"].rstrip("/")
    path = manifest_path()
    try:
        data = json.loads(path.read_text())
        return str(data["baseURL"]).rstrip("/")
    except Exception as exc:
        raise SystemExit(f"Could not read baseURL from {path}: {exc}") from exc


def auth_token() -> Optional[str]:
    if os.environ.get("BCU_AUTH_TOKEN"):
        return os.environ["BCU_AUTH_TOKEN"]
    path = manifest_path()
    try:
        data = json.loads(path.read_text())
        value = data.get("authToken")
        return str(value) if value else None
    except Exception:
        return None


def main(argv: list[str]) -> int:
    if len(argv) not in (3, 4):
        return usage()

    method = argv[1].upper()
    route_path = argv[2]
    if not route_path.startswith("/"):
        route_path = "/" + route_path

    body = None
    parsed_body: object = None
    headers = {"accept": "application/json"}
    token = auth_token()
    if token:
        headers["X-Background-Computer-Use-Token"] = token
    if len(argv) == 4:
        try:
            parsed_body = json.loads(argv[3])
        except json.JSONDecodeError as exc:
            raise SystemExit(f"JSON body is invalid: {exc}") from exc
        body = json.dumps(parsed_body).encode("utf-8")
        headers["content-type"] = "application/json"

    request = urllib.request.Request(
        base_url() + route_path,
        data=body,
        method=method,
        headers=headers,
    )

    try:
        with urllib.request.urlopen(request, timeout=request_timeout(route_path, parsed_body)) as response:
            payload = response.read()
            status = response.status
    except urllib.error.HTTPError as exc:
        payload = exc.read()
        status = exc.code
    except urllib.error.URLError as exc:
        raise SystemExit(f"Request failed: {exc}") from exc

    try:
        print(json.dumps(json.loads(payload), indent=2, sort_keys=True))
    except json.JSONDecodeError:
        sys.stdout.buffer.write(payload)
        if payload and not payload.endswith(b"\n"):
            print()

    return 0 if 200 <= status < 300 else 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
