"""A script that fails to load must fail the Godot check even when Godot exits 0."""
import os
from pathlib import Path
import re
import signal
import subprocess
import tempfile
import threading
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
  *"$BROKEN"*) echo "$ERROR_LINE" >&2; [ "$BROKEN_EXIT" = hang ] && exec sleep 60; exit "$BROKEN_EXIT" ;;
  *--script*) echo 'Fixture: 1 checks, 0 failures' ;;
esac
"""


class GodotCheckTests(unittest.TestCase):
    def run_check(self, broken="no-such-step", error_line="", broken_exit="0", selected=()):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            binary = root / "godot"
            log = root / "calls"
            binary.write_text(FAKE_GODOT)
            binary.chmod(0o755)
            result = subprocess.run(["bash", "scripts/check_godot.sh", *selected], cwd=ROOT,
                                    env=dict(os.environ, GODOT=str(binary), CALL_LOG=str(log),
                                             BROKEN=broken, ERROR_LINE=error_line,
                                             BROKEN_EXIT=broken_exit),
                                    text=True, capture_output=True)
            return result, log.read_text().splitlines() if log.exists() else []

    def test_selected_script_runs_alone_after_common_setup(self):
        result, calls = self.run_check(selected=("tests/combat_ai_test.gd",))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual([call for call in calls if "--script" in call],
                         ["--headless --path . --script tests/combat_ai_test.gd"])
        self.assertTrue(any("--version" in call for call in calls))
        self.assertTrue(any("--import" in call for call in calls))
        self.assertTrue(any("--quit-after" in call for call in calls))

    def test_selected_script_errors_and_nonzero_exit_fail(self):
        for line, code in [(SCRIPT_ERROR, "0"), (LOAD_ERROR, "0"), ("", "3")]:
            with self.subTest(line=line, code=code):
                result, calls = self.run_check("combat_ai_test", line, code,
                                               selected=("tests/combat_ai_test.gd",))
                self.assertEqual(result.returncode, 1 if code == "0" else 3)
                self.assertEqual(len([call for call in calls if "--script" in call]), 1)
                if line:
                    self.assertIn(line, result.stdout)
                    self.assertIn("Godot script error during:", result.stderr)

    def test_invalid_selection_is_rejected_before_running_godot(self):
        for selected in [("tests/missing_test.gd",), ("../tests/combat_ai_test.gd",),
                         ("--version",), ("tests/combat_ai_test.gd tests/save_test.gd",),
                         ("tests/combat_ai_test.gd", "tests/save_test.gd")]:
            with self.subTest(selected=selected):
                result, calls = self.run_check(selected=selected)
                self.assertEqual(result.returncode, 2)
                self.assertEqual(calls, [])

    def test_script_error_stops_a_test_that_never_ends(self):
        started = time.monotonic()
        result, _ = self.run_check("combat_ai_test", SCRIPT_ERROR, "hang")
        self.assertEqual(result.returncode, 1)
        self.assertLess(time.monotonic() - started, 30)
        self.assertIn("Godot script error during: --script tests/combat_ai_test.gd", result.stderr)
        self.assertIn("stopped after a script error", result.stdout)

    def test_selected_script_keeps_common_setup_error_gate(self):
        for step in ("--import", "--quit-after"):
            with self.subTest(step=step):
                result, calls = self.run_check(step, SCRIPT_ERROR,
                                               selected=("tests/combat_ai_test.gd",))
                self.assertNotEqual(result.returncode, 0)
                self.assertIn(SCRIPT_ERROR, result.stdout)
                self.assertFalse(any("--script" in call for call in calls))

    def test_clean_output_passes_every_step(self):
        result, calls = self.run_check()
        self.assertEqual(result.returncode, 0, result.stderr)
        # --version, --import, --quit-after, the sixteen combat tests, and save, title, pause, continue, ui_theme.
        self.assertEqual(len(calls), 24)
        self.assertTrue(any("title_test.gd" in call for call in calls))
        self.assertTrue(any("combat_capture_test.gd" in call for call in calls))
        self.assertTrue(any("combat_feedback_test.gd" in call for call in calls))
        self.assertTrue(any("combat_save_test.gd" in call for call in calls))
        self.assertTrue(any("combat_preparation_save_test.gd" in call for call in calls))
        self.assertTrue(any("combat_staging_test.gd" in call for call in calls))
        self.assertTrue(any("combat_dice_roll_test.gd" in call for call in calls))
        self.assertTrue(any("combat_oil_test.gd" in call for call in calls))
        self.assertTrue(any("combat_warrior_test.gd" in call for call in calls))
        self.assertTrue(any("combat_archer_test.gd" in call for call in calls))
        self.assertTrue(any("save_test.gd" in call for call in calls))
        self.assertTrue(any("pause_test.gd" in call for call in calls))
        self.assertTrue(any("continue_test.gd" in call for call in calls))
        self.assertTrue(any("ui_theme_test.gd" in call for call in calls))
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

    def test_save_and_hud_run_concurrently_after_import(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            binary = root / "godot"
            binary.write_text(FAKE_GODOT + """
case "$*" in
  *--import*) touch "$PROBE/imported" ;;
  *combat_save_test*|*combat_hud_test*)
    test -f "$PROBE/imported" || exit 12
    case "$*" in
      *combat_save_test*) own=save; other=hud ;;
      *) own=hud; other=save ;;
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

    def test_leftover_child_does_not_hang_or_outlive_the_check(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            binary = root / "godot"
            binary.write_text(FAKE_GODOT + """
case "$*" in
  *combat_save_test*) sleep 30 & echo $! > "$PROBE/child.pid"; echo 'no newline at end' | tr -d '\\n'; exit 0 ;;
esac
""")
            binary.chmod(0o755)
            result = subprocess.run(["bash", "scripts/check_godot.sh", "tests/combat_save_test.gd"], cwd=ROOT,
                                    env=dict(os.environ, GODOT=str(binary), CALL_LOG=str(root / "calls"),
                                             BROKEN="no-such-step", ERROR_LINE="", BROKEN_EXIT="0",
                                             PROBE=str(root)), text=True, capture_output=True, timeout=10)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn("] no newline at end\n[combat_save_test", result.stdout)
            child = int((root / "child.pid").read_text())
            deadline = time.monotonic() + 3
            # The orphaned child is reaped by init, so give it a moment to disappear.
            while True:
                try:
                    os.kill(child, 0)
                except ProcessLookupError:
                    break
                self.assertLess(time.monotonic(), deadline, "Leftover child outlived the check")
                time.sleep(0.02)

    def test_output_that_does_not_end_fails(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            binary = root / "godot"
            # A writer in its own session escapes the group kill and keeps the pipe open.
            binary.write_text(FAKE_GODOT + """
case "$*" in
  *combat_save_test*)
    python3 -c 'import os, sys, time; os.setsid(); open(sys.argv[1], "w").write(str(os.getpid())); time.sleep(30)' \\
      "$PROBE/escaped.pid" &
    while [ ! -s "$PROBE/escaped.pid" ]; do sleep 0.02; done
    exit 0 ;;
esac
""")
            binary.chmod(0o755)
            try:
                result = subprocess.run(["bash", "scripts/check_godot.sh", "tests/combat_save_test.gd"], cwd=ROOT,
                                        env=dict(os.environ, GODOT=str(binary), CALL_LOG=str(root / "calls"),
                                                 BROKEN="no-such-step", ERROR_LINE="", BROKEN_EXIT="0",
                                                 PROBE=str(root)), text=True, capture_output=True, timeout=20)
                self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
                self.assertIn("Godot output did not end during: --script tests/combat_save_test.gd", result.stderr)
            finally:
                try:
                    os.kill(int((root / "escaped.pid").read_text()), signal.SIGKILL)
                except (FileNotFoundError, ValueError, ProcessLookupError):
                    pass

    def test_second_signal_does_not_cut_cleanup_short(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            binary = root / "godot"
            # Ignoring SIGTERM keeps cleanup busy long enough for the second signal to land in it.
            binary.write_text(FAKE_GODOT + """
case "$*" in
  *combat_save_test*) trap '' TERM; echo $$ > "$PROBE/save.pid"; exec sleep 30 ;;
esac
""")
            binary.chmod(0o755)
            process = subprocess.Popen(["bash", "scripts/check_godot.sh", "tests/combat_save_test.gd"], cwd=ROOT,
                                       env=dict(os.environ, GODOT=str(binary), CALL_LOG=str(root / "calls"),
                                                BROKEN="no-such-step", ERROR_LINE="", BROKEN_EXIT="0",
                                                PROBE=str(root)), stdout=subprocess.DEVNULL,
                                       stderr=subprocess.DEVNULL, start_new_session=True)
            child = None
            try:
                deadline = time.monotonic() + 5
                while not (root / "save.pid").exists():
                    self.assertLess(time.monotonic(), deadline, "Test did not start")
                    time.sleep(0.02)
                child = int((root / "save.pid").read_text())
                os.kill(process.pid, signal.SIGINT)
                time.sleep(0.5)
                os.kill(process.pid, signal.SIGTERM)
                process.wait(timeout=10)
                self.assertEqual(process.returncode, 130)
                with self.assertRaises(ProcessLookupError):
                    os.kill(child, 0)
            finally:
                if process.poll() is None:
                    os.killpg(process.pid, signal.SIGKILL)
                    process.wait()
                if child is not None:
                    try:
                        os.killpg(child, signal.SIGKILL)
                    except ProcessLookupError:
                        pass

    def test_cancellation_stops_owned_godot_processes(self):
        for signum in (signal.SIGINT, signal.SIGTERM):
            with self.subTest(signum=signum), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                binary = root / "godot"
                binary.write_text(FAKE_GODOT + """
case "$*" in
  *combat_save_test*) echo 'save stage 1'; echo $$ > "$PROBE/save.pid"; exec sleep 30 ;;
  *combat_hud_test*) echo $$ > "$PROBE/hud.pid"; exec sleep 30 ;;
esac
""")
                binary.chmod(0o755)
                process = subprocess.Popen(["bash", "scripts/check_godot.sh"], cwd=ROOT,
                                           env=dict(os.environ, GODOT=str(binary), CALL_LOG=str(root / "calls"),
                                                    BROKEN="no-such-step", ERROR_LINE="", BROKEN_EXIT="0",
                                                    PROBE=str(root)), stdout=subprocess.PIPE,
                                           stderr=subprocess.PIPE, text=True, start_new_session=True)
                children = []
                lines = []
                def read():
                    for line in process.stdout:
                        lines.append(line)
                reader = threading.Thread(target=read, daemon=True)
                reader.start()
                try:
                    deadline = time.monotonic() + 5
                    while not all((root / f"{name}.pid").exists() for name in ("save", "hud")):
                        self.assertLess(time.monotonic(), deadline, "Parallel tests did not start")
                        time.sleep(0.02)
                    children = [int((root / f"{name}.pid").read_text()) for name in ("save", "hud")]
                    # Output is relayed as it arrives, so a cancelled run still shows how far each test got.
                    while not any(re.search(r"\[combat_save_test \d+s\] save stage 1", line) for line in lines):
                        self.assertLess(time.monotonic(), deadline, "Running test output was not relayed")
                        time.sleep(0.02)
                    os.kill(process.pid, signum)
                    process.wait(timeout=3)
                    reader.join(timeout=3)
                    self.assertEqual(process.returncode, 130)
                    for child in children:
                        with self.assertRaises(ProcessLookupError):
                            os.kill(child, 0)
                finally:
                    if process.poll() is None:
                        os.killpg(process.pid, signal.SIGKILL)
                        process.wait()
                    for child in children:
                        try:
                            os.killpg(child, signal.SIGKILL)
                        except ProcessLookupError:
                            pass


if __name__ == "__main__":
    unittest.main()
