"""A script that fails to load must fail the Godot check even when Godot exits 0."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
# Godot 4.7.2 prints these lines for a parse error and still exits 0.
SCRIPT_ERROR = 'SCRIPT ERROR: Parse Error: Identifier "x" not declared in the current scope.'
LOAD_ERROR = 'ERROR: Failed to load script "res://broken.gd" with error "Parse error".'
FAKE_GODOT = """#!/bin/sh
printf '%s\\n' "$*" >> "$CALL_LOG"
case "$*" in
  --version) echo 4.7.2.stable.official.fixture ;;
  *"$BROKEN"*) echo "$ERROR_LINE" >&2; exit "$BROKEN_EXIT" ;;
  *--script*) echo 'Fixture: 1 checks, 0 failures' ;;
esac
"""


class GodotCheckTests(unittest.TestCase):
    def run_check(self, broken="no-such-step", error_line="", broken_exit="0"):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            binary = root / "godot"
            log = root / "calls"
            binary.write_text(FAKE_GODOT)
            binary.chmod(0o755)
            result = subprocess.run(["bash", "scripts/check_godot.sh"], cwd=ROOT,
                                    env=dict(os.environ, GODOT=str(binary), CALL_LOG=str(log),
                                             BROKEN=broken, ERROR_LINE=error_line,
                                             BROKEN_EXIT=broken_exit),
                                    text=True, capture_output=True)
            return result, log.read_text().splitlines()

    def test_clean_output_passes_every_step(self):
        result, calls = self.run_check()
        self.assertEqual(result.returncode, 0, result.stderr)
        # --version, --import, --quit-after and the seven combat tests.
        self.assertEqual(len(calls), 10)
        self.assertIn("Fixture: 1 checks, 0 failures", result.stdout)

    def test_script_error_fails_each_step(self):
        steps = ["--import", "--quit-after", "combat_turns_test", "combat_loot_test"]
        for step in steps:
            for line in [SCRIPT_ERROR, LOAD_ERROR]:
                with self.subTest(step=step, line=line):
                    result, calls = self.run_check(step, line)
                    self.assertNotEqual(result.returncode, 0)
                    self.assertIn(line, result.stdout)
                    self.assertIn("Godot script error during:", result.stderr)
                    self.assertIn(step, calls[-1])

    def test_nonzero_godot_exit_still_fails(self):
        result, calls = self.run_check("combat_hud_test", broken_exit="3")
        self.assertEqual(result.returncode, 3)
        self.assertIn("combat_hud_test", calls[-1])


if __name__ == "__main__":
    unittest.main()
