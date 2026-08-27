import unittest

from script.smoke_runtime import list_windows_request, text_result_is_background_safe


class SmokeRuntimeHelpersTests(unittest.TestCase):
    def test_list_windows_request_requires_positive_pid(self) -> None:
        self.assertEqual(list_windows_request(25268), {"pid": 25268})
        with self.assertRaisesRegex(ValueError, "pid must be positive"):
            list_windows_request(0)

    def test_text_result_requires_success_and_background_evidence(self) -> None:
        self.assertTrue(
            text_result_is_background_safe(
                {
                    "classification": "success",
                    "backgroundSafety": {"foregroundPreserved": True},
                }
            )
        )
        self.assertFalse(
            text_result_is_background_safe(
                {
                    "classification": "success",
                    "backgroundSafety": {"foregroundPreserved": False},
                }
            )
        )
        self.assertFalse(text_result_is_background_safe({"classification": "effect_not_verified"}))


if __name__ == "__main__":
    unittest.main()
