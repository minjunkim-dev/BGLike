"""A different editor must fail before importing or executing the project."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class GodotVersionTests(unittest.TestCase):
    def test_wrong_engine_never_runs_project(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            binary = root / "godot"
            log = root / "calls"
            binary.write_text('#!/bin/sh\nprintf "%s\\n" "$*" >> "$CALL_LOG"\necho 4.8.stable.official.fixture\n')
            binary.chmod(0o755)
            result = subprocess.run(["bash", "scripts/check_godot.sh"], cwd=ROOT,
                                    env=dict(os.environ, GODOT=str(binary), CALL_LOG=str(log)),
                                    text=True, capture_output=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("Godot mismatch", result.stderr)
            self.assertEqual(log.read_text().splitlines(), ["--version"])
