"""Exercise aggregate outcomes through the helper and its workflow interface."""

import itertools
import os
from pathlib import Path
import subprocess
import sys
import unittest

from ci_gate import ci_passed


ROOT = Path(__file__).resolve().parents[1]


class CIGateTests(unittest.TestCase):
    def test_only_selected_success_or_intentional_document_skip_pass(self):
        outcomes = ["success", "failure", "cancelled", "skipped", "unknown", "", None]
        scopes = ["true", "false", "unknown", "", None, True, False]
        accepted = {("success", "true", "success"), ("success", "false", "skipped")}
        for policy, scope, smoke in itertools.product(outcomes, scopes, outcomes):
            with self.subTest(policy=policy, scope=scope, smoke=smoke):
                self.assertEqual(ci_passed(policy, scope, smoke),
                                 (policy, scope, smoke) in accepted)

    def test_cli_exit_status_handles_success_failure_and_missing_results(self):
        cases = [
            ({"POLICY_RESULT": "success", "GAME_REQUIRED": "true",
              "SMOKE_RESULT": "success"}, 0),
            ({"POLICY_RESULT": "success", "GAME_REQUIRED": "false",
              "SMOKE_RESULT": "skipped"}, 0),
            ({"POLICY_RESULT": "success", "GAME_REQUIRED": "true",
              "SMOKE_RESULT": "cancelled"}, 1),
            ({"POLICY_RESULT": "failure", "GAME_REQUIRED": "false",
              "SMOKE_RESULT": "skipped"}, 1),
            ({}, 1),
        ]
        env = {key: value for key, value in os.environ.items()
               if key not in {"POLICY_RESULT", "GAME_REQUIRED", "SMOKE_RESULT"}}
        for inputs, expected in cases:
            with self.subTest(inputs=inputs):
                result = subprocess.run([sys.executable, "scripts/ci_gate.py"],
                                        cwd=ROOT, env=dict(env, **inputs),
                                        capture_output=True, text=True)
                self.assertEqual(result.returncode, expected, result.stderr)
                self.assertIn("CI passed." if expected == 0 else "CI failed:", result.stdout)


if __name__ == "__main__":
    unittest.main()
