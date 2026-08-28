import unittest

from script.benchmark_mac_parity import assess_lane, percentile, safe_runtime_summary


class BenchmarkMacParityTests(unittest.TestCase):
    def test_runtime_summary_never_exposes_auth_token(self) -> None:
        summary = safe_runtime_summary(
            {
                "authToken": "ephemeral-secret",
                "baseURL": "http://127.0.0.1:12345",
                "contractVersion": "test-contract",
                "startedAt": "2026-08-27T00:00:00Z",
                "routes": [{"url": "http://127.0.0.1:12345/health"}],
            }
        )

        self.assertNotIn("authToken", summary)
        self.assertNotIn("ephemeral-secret", str(summary))
        self.assertEqual(summary["contractVersion"], "test-contract")

    def test_percentile_interpolates_sorted_samples(self) -> None:
        samples = [100.0, 200.0, 300.0, 400.0]
        self.assertEqual(percentile(samples, 50), 250.0)
        self.assertEqual(percentile(samples, 95), 385.0)

    def test_lane_requires_latency_completion_and_zero_false_success(self) -> None:
        passing = assess_lane(
            samples=[500.0, 550.0, 600.0],
            expected_runs=3,
            p50_budget_ms=600.0,
            p95_budget_ms=1_000.0,
            completions=3,
            false_successes=0,
            foreground_violations=0,
        )
        self.assertTrue(passing["passed"])

        failing = assess_lane(
            samples=[500.0, 550.0, 600.0],
            expected_runs=3,
            p50_budget_ms=600.0,
            p95_budget_ms=1_000.0,
            completions=3,
            false_successes=1,
            foreground_violations=0,
        )
        self.assertFalse(failing["passed"])


if __name__ == "__main__":
    unittest.main()
