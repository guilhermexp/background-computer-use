from __future__ import annotations

import json
import os
import subprocess
import tempfile
import threading
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
ENSURE_RUNTIME = ROOT / "skills/background-computer-use/scripts/ensure-runtime.sh"
FINGERPRINT = ROOT / "script/build_fingerprint.py"
REQUEST = ROOT / "skills/background-computer-use/scripts/bcu-request.py"


class Handler(BaseHTTPRequestHandler):
    def do_GET(self) -> None:
        if self.path == "/health":
            payload = {"ok": True}
        elif self.path == "/v1/bootstrap":
            payload = {"ok": True}
        else:
            self.send_error(404)
            return
        body = json.dumps(payload).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, format: str, *args: object) -> None:
        pass


class EnsureRuntimeTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        cls.server_thread = threading.Thread(target=cls.server.serve_forever, daemon=True)
        cls.server_thread.start()
        cls.base_url = f"http://127.0.0.1:{cls.server.server_port}"
        result = subprocess.run(
            ["python3", str(FINGERPRINT), "--repo", str(ROOT), "--format", "json"],
            check=True,
            capture_output=True,
            text=True,
        )
        cls.expected_identity = json.loads(result.stdout)["identity"]

    @classmethod
    def tearDownClass(cls) -> None:
        cls.server.shutdown()
        cls.server.server_close()
        cls.server_thread.join(timeout=5)

    def manifest(self, identity: str, pid: int | None = None) -> dict[str, object]:
        return {
            "baseURL": self.base_url,
            "authToken": "fixture-secret",
            "pid": os.getpid() if pid is None else pid,
            "build": {"identity": identity},
        }

    def environment(self, directory: Path, manifest: Path, marker: Path) -> dict[str, str]:
        start_script = directory / "start-fixture.sh"
        start_script.write_text(
            "#!/bin/sh\n"
            "printf '%s' \"$TEST_MANIFEST_JSON\" > \"$BCU_MANIFEST_PATH\"\n"
            "touch \"$TEST_MARKER\"\n"
        )
        start_script.chmod(0o755)
        environment = os.environ.copy()
        environment.update(
            {
                "BCU_MANIFEST_PATH": str(manifest),
                "BCU_SOURCE_DIR": str(ROOT),
                "BCU_APP_NAME": f"BCUFixture-{os.getpid()}",
                "BCU_START_SCRIPT": str(start_script),
                "BCU_WAIT_ATTEMPTS": "8",
                "BCU_WAIT_INTERVAL": "0.01",
                "TEST_MANIFEST_JSON": json.dumps(self.manifest(self.expected_identity)),
                "TEST_MARKER": str(marker),
            }
        )
        return environment

    def run_ensure(self, environment: dict[str, str]) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            ["bash", str(ENSURE_RUNTIME)],
            env=environment,
            capture_output=True,
            text=True,
            timeout=10,
        )

    def test_matching_source_runtime_is_reused(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            manifest = directory / "runtime-manifest.json"
            marker = directory / "started"
            manifest.write_text(json.dumps(self.manifest(self.expected_identity)))

            result = self.run_ensure(self.environment(directory, manifest, marker))

            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertFalse(marker.exists())

    def test_mismatching_source_runtime_is_replaced(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            manifest = directory / "runtime-manifest.json"
            marker = directory / "started"
            manifest.write_text(json.dumps(self.manifest("stale-build")))

            result = self.run_ensure(self.environment(directory, manifest, marker))

            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertTrue(marker.exists())
            self.assertEqual(json.loads(manifest.read_text())["build"]["identity"], self.expected_identity)

    def test_dead_manifest_pid_fails_before_http(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            manifest = directory / "runtime-manifest.json"
            manifest.write_text(json.dumps(self.manifest(self.expected_identity, pid=999_999_999)))
            environment = os.environ.copy()
            environment["BCU_MANIFEST_PATH"] = str(manifest)
            environment.pop("BCU_BASE_URL", None)

            result = subprocess.run(
                ["python3", str(REQUEST), "GET", "/health"],
                env=environment,
                capture_output=True,
                text=True,
                timeout=10,
            )

            self.assertNotEqual(result.returncode, 0)
            self.assertIn(str(manifest), result.stderr)
            self.assertTrue(
                result.stderr.rstrip().endswith(
                    "Run skills/background-computer-use/scripts/ensure-runtime.sh "
                    "to start or refresh the runtime."
                ),
                result.stderr,
            )


if __name__ == "__main__":
    unittest.main()
