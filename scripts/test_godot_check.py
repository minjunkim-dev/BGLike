"""A script that fails to load must fail the Godot check even when Godot exits 0."""
import os
from pathlib import Path
import signal
import subprocess
import tempfile
import time
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
        # --version, --import, --quit-after, the eleven combat tests, the save, title, pause and continue tests.
        self.assertEqual(len(calls), 18)
        self.assertTrue(any("title_test.gd" in call for call in calls))
        self.assertTrue(any("combat_capture_test.gd" in call for call in calls))
        self.assertTrue(any("combat_feedback_test.gd" in call for call in calls))
        self.assertTrue(any("combat_save_test.gd" in call for call in calls))
        self.assertTrue(any("combat_preparation_save_test.gd" in call for call in calls))
        self.assertTrue(any("save_test.gd" in call for call in calls))
        self.assertTrue(any("pause_test.gd" in call for call in calls))
        self.assertTrue(any("continue_test.gd" in call for call in calls))
        self.assertIn("Fixture: 1 checks, 0 failures", result.stdout)

    def test_script_error_fails_each_step(self):
        steps = ["--import", "--quit-after", "combat_turns_test", "combat_loot_test",
                 "combat_capture_test", "combat_feedback_test"]
        for step in steps:
            for line in [SCRIPT_ERROR, LOAD_ERROR]:
                with self.subTest(step=step, line=line):
                    result, calls = self.run_check(step, line)
                    self.assertNotEqual(result.returncode, 0)
                    self.assertIn(line, result.stdout)
                    self.assertIn("Godot script error during:", result.stderr)
                    self.assertTrue(any(step in call for call in calls))

    def test_nonzero_godot_exit_still_fails(self):
        result, calls = self.run_check("combat_hud_test", broken_exit="3")
        self.assertEqual(result.returncode, 3)
        self.assertTrue(any("combat_hud_test" in call for call in calls))

    def test_hud_and_ai_run_concurrently_after_import(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            binary = root / "godot"
            binary.write_text(FAKE_GODOT + """
case "$*" in
  *--import*) touch "$PROBE/imported" ;;
  *combat_hud_test*|*combat_ai_test*)
    test -f "$PROBE/imported" || exit 12
    case "$*" in
      *combat_hud_test*) own=hud; other=ai ;;
      *) own=ai; other=hud ;;
    esac
    touch "$PROBE/$own"
    attempt=0
    while [ ! -f "$PROBE/$other" ]; do
      attempt=$((attempt + 1))
      [ "$attempt" -lt 100 ] || exit 13
      sleep 0.02
    done ;;
esac
""")
            binary.chmod(0o755)
            result = subprocess.run(["bash", "scripts/check_godot.sh"], cwd=ROOT,
                                    env=dict(os.environ, GODOT=str(binary), CALL_LOG=str(root / "calls"),
                                             BROKEN="no-such-step", ERROR_LINE="", BROKEN_EXIT="0",
                                             PROBE=str(root)), text=True, capture_output=True, timeout=10)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_cancellation_stops_owned_godot_processes(self):
        for signum in (signal.SIGINT, signal.SIGTERM):
            with self.subTest(signum=signum), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                binary = root / "godot"
                binary.write_text(FAKE_GODOT + """
case "$*" in
  *combat_hud_test*) echo $$ > "$PROBE/hud.pid"; exec sleep 30 ;;
  *combat_ai_test*) echo $$ > "$PROBE/ai.pid"; exec sleep 30 ;;
esac
""")
                binary.chmod(0o755)
                process = subprocess.Popen(["bash", "scripts/check_godot.sh"], cwd=ROOT,
                                           env=dict(os.environ, GODOT=str(binary), CALL_LOG=str(root / "calls"),
                                                    BROKEN="no-such-step", ERROR_LINE="", BROKEN_EXIT="0",
                                                    PROBE=str(root)), stdout=subprocess.PIPE,
                                           stderr=subprocess.PIPE, text=True, start_new_session=True)
                children = []
                try:
                    deadline = time.monotonic() + 5
                    while not all((root / f"{name}.pid").exists() for name in ("hud", "ai")):
                        self.assertLess(time.monotonic(), deadline, "Parallel tests did not start")
                        time.sleep(0.02)
                    children = [int((root / f"{name}.pid").read_text()) for name in ("hud", "ai")]
                    os.kill(process.pid, signum)
                    process.communicate(timeout=3)
                    self.assertEqual(process.returncode, 130)
                    for child in children:
                        with self.assertRaises(ProcessLookupError):
                            os.kill(child, 0)
                finally:
                    if process.poll() is None:
                        os.killpg(process.pid, signal.SIGKILL)
                        process.communicate()
                    for child in children:
                        try:
                            os.killpg(child, signal.SIGKILL)
                        except ProcessLookupError:
                            pass


if __name__ == "__main__":
    unittest.main()
