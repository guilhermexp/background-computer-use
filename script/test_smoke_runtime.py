import unittest

from script.smoke_runtime import safari_adaptive_type_strategy_is_valid


class AdaptiveTypeStrategyTests(unittest.TestCase):
    def test_safari_fixture_requires_target_bound_text_operation(self) -> None:
        base = {"fallbackReason": "unchanged_ax_noop"}
        self.assertTrue(safari_adaptive_type_strategy_is_valid({
            **base,
            "strategiesAttempted": ["ax_value", "ax_text_operation"],
        }))
        self.assertFalse(safari_adaptive_type_strategy_is_valid({
            **base,
            "strategiesAttempted": ["ax_value", "pid_unicode"],
        }))
        self.assertFalse(safari_adaptive_type_strategy_is_valid({
            **base,
            "strategiesAttempted": ["ax_value", "ax_text_operation", "pid_unicode"],
        }))

    def test_rejects_missing_or_unrelated_fallback_evidence(self) -> None:
        self.assertFalse(safari_adaptive_type_strategy_is_valid({
            "fallbackReason": "unchanged_ax_noop",
            "strategiesAttempted": ["ax_value"],
        }))
        self.assertFalse(safari_adaptive_type_strategy_is_valid({
            "fallbackReason": None,
            "strategiesAttempted": ["ax_value", "pid_unicode"],
        }))


if __name__ == "__main__":
    unittest.main()
