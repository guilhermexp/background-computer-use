import unittest

from script.smoke_runtime import (
    controlled_type_fallback_is_valid,
    generation_incremented,
    lane_status_for_effect,
    safari_adaptive_type_strategy_is_valid,
    scroll_marker_increased,
    strict_click_oracle_is_valid,
    text_result_is_background_safe,
    type_text_retry_contract_is_valid,
)


class AdaptiveTypeStrategyTests(unittest.TestCase):
    def test_background_proof_rejects_fallback_or_unsafe_retry_telemetry(self) -> None:
        base = {
            "classification": "success",
            "backgroundSafety": {"foregroundPreserved": True},
            "foregroundFallbackUsed": False,
            "dispatchSucceeded": True,
            "strategiesAttempted": ["ax_value"],
            "retrySafe": False,
        }
        self.assertTrue(text_result_is_background_safe(base))
        self.assertFalse(text_result_is_background_safe({
            **base,
            "foregroundFallbackUsed": True,
        }))
        self.assertFalse(text_result_is_background_safe({
            **base,
            "retrySafe": True,
        }))

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


class TypeTextRetryContractTests(unittest.TestCase):
    def test_dispatched_text_requires_non_retryable_named_strategy(self) -> None:
        self.assertTrue(type_text_retry_contract_is_valid({
            "dispatchSucceeded": True,
            "strategiesAttempted": ["pid_unicode"],
            "retrySafe": False,
        }))
        self.assertFalse(type_text_retry_contract_is_valid({
            "dispatchSucceeded": True,
            "strategiesAttempted": [],
            "retrySafe": True,
        }))

    def test_dispatched_text_rejects_each_incomplete_retry_signal(self) -> None:
        self.assertFalse(type_text_retry_contract_is_valid({
            "dispatchSucceeded": True,
            "strategiesAttempted": ["pid_unicode"],
            "retrySafe": True,
        }))
        self.assertFalse(type_text_retry_contract_is_valid({
            "dispatchSucceeded": True,
            "strategiesAttempted": [],
            "retrySafe": False,
        }))
        self.assertFalse(type_text_retry_contract_is_valid({
            "dispatchSucceeded": True,
            "strategiesAttempted": "pid_unicode",
            "retrySafe": False,
        }))
        self.assertFalse(type_text_retry_contract_is_valid({
            "dispatchSucceeded": True,
            "strategiesAttempted": [""],
            "retrySafe": False,
        }))

    def test_nonempty_strategy_requires_non_retryable_even_when_dispatch_failed(self) -> None:
        self.assertFalse(type_text_retry_contract_is_valid({
            "dispatchSucceeded": False,
            "strategiesAttempted": ["pid_unicode"],
            "retrySafe": True,
        }))
        self.assertTrue(type_text_retry_contract_is_valid({
            "dispatchSucceeded": False,
            "strategiesAttempted": ["pid_unicode"],
            "retrySafe": False,
        }))

    def test_empty_strategy_requires_no_dispatch_and_explicit_retry_safety(self) -> None:
        self.assertFalse(type_text_retry_contract_is_valid({
            "dispatchSucceeded": False,
            "strategiesAttempted": [],
            "retrySafe": False,
        }))
        self.assertTrue(type_text_retry_contract_is_valid({
            "dispatchSucceeded": False,
            "strategiesAttempted": [],
            "retrySafe": True,
        }))

    def test_invalid_strategy_shape_is_rejected_before_dispatch_state(self) -> None:
        self.assertFalse(type_text_retry_contract_is_valid({
            "dispatchSucceeded": False,
            "strategiesAttempted": "pid_unicode",
            "retrySafe": True,
        }))

    def test_missing_strategies_is_rejected(self) -> None:
        self.assertFalse(type_text_retry_contract_is_valid({
            "dispatchSucceeded": False,
            "retrySafe": True,
        }))

    def test_missing_or_non_boolean_retry_safety_is_rejected(self) -> None:
        self.assertFalse(type_text_retry_contract_is_valid({
            "dispatchSucceeded": False,
            "strategiesAttempted": [],
        }))
        self.assertFalse(type_text_retry_contract_is_valid({
            "dispatchSucceeded": False,
            "strategiesAttempted": [],
            "retrySafe": "true",
        }))

    def test_non_boolean_dispatch_state_is_rejected(self) -> None:
        self.assertFalse(type_text_retry_contract_is_valid({
            "dispatchSucceeded": "false",
            "strategiesAttempted": ["pid_unicode"],
            "retrySafe": False,
        }))

    def test_null_dispatch_state_preserves_retry_truth_table(self) -> None:
        self.assertTrue(type_text_retry_contract_is_valid({
            "dispatchSucceeded": None,
            "strategiesAttempted": [],
            "retrySafe": True,
        }))
        self.assertTrue(type_text_retry_contract_is_valid({
            "dispatchSucceeded": None,
            "strategiesAttempted": ["pid_unicode"],
            "retrySafe": False,
        }))

    def test_controlled_fallback_accepts_verified_or_opaque_dispatch(self) -> None:
        shared = {
            "dispatchSucceeded": True,
            "strategiesAttempted": ["pid_unicode"],
            "retrySafe": False,
            "foregroundFallbackUsed": True,
        }
        self.assertTrue(controlled_type_fallback_is_valid({
            **shared,
            "classification": "success",
            "verification": {"exactValueMatch": True},
        }))
        self.assertTrue(controlled_type_fallback_is_valid({
            **shared,
            "classification": "verifier_ambiguous",
        }))

    def test_controlled_fallback_rejects_background_or_unverified_success(self) -> None:
        shared = {
            "dispatchSucceeded": True,
            "strategiesAttempted": ["pid_unicode"],
            "retrySafe": False,
        }
        self.assertFalse(controlled_type_fallback_is_valid({
            **shared,
            "classification": "success",
            "foregroundFallbackUsed": False,
            "verification": {"exactValueMatch": True},
        }))
        self.assertFalse(controlled_type_fallback_is_valid({
            **shared,
            "classification": "success",
            "foregroundFallbackUsed": True,
            "verification": {"exactValueMatch": False},
        }))


class StrictLiveOraclePolicyTests(unittest.TestCase):
    def test_click_requires_success_and_changed_marker(self) -> None:
        success = {"classification": "success", "ok": True}
        self.assertTrue(strict_click_oracle_is_valid(success, "Button clicked 0", "Button clicked 1"))
        self.assertFalse(strict_click_oracle_is_valid(success, "Button clicked 0", "Button clicked 0"))
        self.assertFalse(strict_click_oracle_is_valid(
            {"classification": "verifier_ambiguous", "ok": True},
            "Button clicked 0",
            "Button clicked 1",
        ))

    def test_ordinary_ambiguous_lane_fails(self) -> None:
        self.assertEqual(
            lane_status_for_effect("chrome-click", {"classification": "verifier_ambiguous"}, False),
            "fail",
        )

    def test_named_ambiguous_lane_is_known_limitation(self) -> None:
        self.assertEqual(
            lane_status_for_effect(
                "chrome-reload-known-limitation",
                {"classification": "verifier_ambiguous"},
                False,
            ),
            "known_limitation",
        )

    def test_success_without_oracle_fails_even_for_limitation_lane(self) -> None:
        self.assertEqual(
            lane_status_for_effect(
                "chrome-reload-known-limitation",
                {"classification": "success"},
                False,
            ),
            "fail",
        )

    def test_scroll_requires_numeric_increase(self) -> None:
        self.assertTrue(scroll_marker_increased("scroll-top:0", "scroll-top:42"))
        self.assertFalse(scroll_marker_increased("scroll-top:42", "scroll-top:42"))
        self.assertFalse(scroll_marker_increased("missing", "scroll-top:42"))

    def test_reload_requires_generation_increment(self) -> None:
        self.assertTrue(generation_incremented("generation:1", "generation:2"))
        self.assertFalse(generation_incremented("generation:2", "generation:2"))
        self.assertFalse(generation_incremented("generation:x", "generation:3"))


if __name__ == "__main__":
    unittest.main()
