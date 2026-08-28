import unittest

from script.smoke_control import launch_is_background_safe, mutation_is_blocked


class ControlSmokeHelpersTests(unittest.TestCase):
    def test_pause_requires_exact_control_error(self) -> None:
        self.assertTrue(mutation_is_blocked(423, {"error": "control_paused"}))
        self.assertFalse(mutation_is_blocked(200, {"error": "control_paused"}))
        self.assertFalse(mutation_is_blocked(423, {"error": "control_stopped"}))

    def test_launch_requires_pid_no_activation_and_foreground_proof(self) -> None:
        self.assertTrue(
            launch_is_background_safe(
                200,
                {
                    "classification": "success",
                    "activates": False,
                    "foregroundPreserved": True,
                    "pid": 42,
                },
            )
        )
        self.assertFalse(launch_is_background_safe(200, {"classification": "success", "pid": 42}))


if __name__ == "__main__":
    unittest.main()
