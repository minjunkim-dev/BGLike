"""A script that fails to load must fail the Godot check even when Godot exits 0."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
# Godot 4.7.2 prints this pair for a parse error and still exits 0.
FAKE_GODOT = """#!/bin/sh
printf '%s\\n' "$*" >> "$CALL_LOG"
case "$*" in
  --version) echo 4.7.2.stable.official.fixture ;;
  *"$BROKEN"*)
    echo 'SCRIPT ERROR: Parse Error: Identifier "x" not declared in the current scope.'
    echo 'ERROR: Failed to load script "res://broken.gd" with error "Parse error".' >&2 ;;
  *--script*) echo 'Fixture: 1 checks, 0 failures' ;;
esac
"""


class GodotCheckTests(unittest.TestCase):
    def run_check(self, broken):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            binary = root / "godot"
            log = root / "calls"
            binary.write_text(FAKE_GODOT)
            binary.chmod(0o755)
            result = subprocess.run(["bash", "scripts/check_godot.sh"], cwd=ROOT,
                                    env=dict(os.environ, GODOT=str(binary), CALL_LOG=str(log),
                                             BROKEN=broken),
                                    text=True, capture_output=True)
            return result, log.read_text().splitlines()

    def test_clean_output_passes_every_step(self):
        result, calls = self.run_check("no-such-step")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(len(calls), 10)
        self.assertIn("Fixture: 1 checks, 0 failures", result.stderr)

    def test_script_error_fails_each_step(self):
        for step in ["--import", "--quit-after", "combat_turns_test", "combat_loot_test"]:
            with self.subTest(step=step):
                result, calls = self.run_check(step)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("SCRIPT ERROR", result.stderr)
                self.assertIn("Godot script error during:", result.stderr)
                self.assertIn(step, calls[-1])


if __name__ == "__main__":
    unittest.main()
