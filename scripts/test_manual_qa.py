"""Native QA must not launch broken scripts or reuse incomplete evidence."""

import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

import manual_qa as qa


class ManualQATests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.app = self.root / "Godot.app"
        self.binary = self.app / "Contents/MacOS/Godot"
        self.binary.parent.mkdir(parents=True)
        self.binary.write_text("#!/bin/sh\nif [ \"$1\" = --version ]; then echo 4.7.2.stable.official.fixture; fi\n")
        self.binary.chmod(0o755)
        self.case = {"id": "compact", "script": "res://tests/combat_capture_test.gd",
                     "resolution": [640, 360], "acceptance": "Native input and original PNG reviewed",
                     "timeout": 2, "success_marker": "[CAPTURE_CHECK] PASS:"}
        self.directory = self.root / "session"
        self.directory.mkdir()
        self.state = {"cases": {"compact": {"status": "not_run", "attempts": []}}}

    def native_fixture(self, text, wait=True):
        def launch(_app, _case, log, _frames):
            log.write_text(text)
            process = subprocess.Popen([sys.executable, "-c", "import time; time.sleep(30)" if wait else ""],
                                       start_new_session=True)
            self.addCleanup(self.reap, process)
            return process
        return launch

    def reap(self, process):
        if process.poll() is None:
            os.killpg(process.pid, signal.SIGKILL)
        process.wait()

    def run_case(self, text):
        with patch.object(qa, "launch", side_effect=self.native_fixture(text)) as launch, \
                patch.object(qa, "stop_native"):
            qa.run_case(self.app, self.case, self.directory, self.state)
        return launch

    def test_parse_error_with_zero_exit_blocks_native_launch(self):
        for error in ("SCRIPT ERROR: Parse Error", "ERROR: Failed to load script"):
            with self.subTest(error=error):
                self.binary.write_text(f"#!/bin/sh\nif [ \"$1\" = --version ]; then echo 4.7.2.stable.official.fixture; else echo '{error}'; fi\n")
                with patch.object(qa, "launch") as launch:
                    with self.assertRaisesRegex(ValueError, "Preflight failed"):
                        qa.run_case(self.app, self.case, self.directory, self.state)
                    launch.assert_not_called()
                self.assertEqual(self.state["cases"]["compact"]["status"], "failed")

    def test_success_needs_visual_review_and_stops_launcher(self):
        self.run_case("Metal - Forward+\n[CAPTURE_CHECK] PASS: review original frames\n")
        saved = json.loads((self.directory / "state.json").read_text())
        self.assertEqual(saved["cases"]["compact"]["status"], "awaiting_review")
        pid = saved["cases"]["compact"]["attempts"][-1]["launcher_pid"]
        with self.assertRaises(ProcessLookupError):
            os.kill(pid, 0)

    def test_error_overrides_later_positive_events(self):
        for error in ("ERROR: Native scrollbar drag moves content", "SCRIPT ERROR: runtime", "QA: 5 checks, 2 failures"):
            with self.subTest(error=error), self.assertRaisesRegex(ValueError, "Godot error"):
                self.run_case(f"Metal - Forward+\n{error}\nQA_SCROLLED_RIGHT\n[CAPTURE_CHECK] PASS:\n")
            self.assertEqual(self.state["cases"]["compact"]["status"], "failed")

    def test_exit_without_marker_and_timeout_fail(self):
        for exited in (True, False):
            with self.subTest(exited=exited), patch.object(qa, "launch", side_effect=self.native_fixture("", not exited)), \
                    patch.object(qa, "stop_native"), patch.object(qa.time, "monotonic", side_effect=[0, 3]):
                with self.assertRaisesRegex(ValueError, "timeout|without success_marker"):
                    qa.run_case(self.app, self.case, self.directory, self.state)
                self.assertEqual(self.state["cases"]["compact"]["status"], "failed")

    def test_interruption_preserves_attempt_and_retries_in_new_directory(self):
        with patch.object(qa, "launch", side_effect=KeyboardInterrupt):
            with self.assertRaises(KeyboardInterrupt):
                qa.run_case(self.app, self.case, self.directory, self.state)
        self.assertEqual(self.state["cases"]["compact"]["status"], "interrupted")
        self.run_case("Forward+\n[CAPTURE_CHECK] PASS:\n")
        attempts = self.state["cases"]["compact"]["attempts"]
        self.assertEqual([Path(item["directory"]).name for item in attempts], ["1", "2"])
        self.assertEqual([item["status"] for item in attempts], ["interrupted", "awaiting_review"])
        self.assertTrue(all((Path(item["directory"]) / "preflight.log").exists() for item in attempts))

    def test_interruption_after_launch_stops_owned_launcher(self):
        with patch.object(qa, "launch", side_effect=self.native_fixture("Forward+\n")), \
                patch.object(qa, "stop_native"), patch.object(qa, "ERROR") as errors:
            errors.search.side_effect = [None, KeyboardInterrupt()]
            with self.assertRaises(KeyboardInterrupt):
                qa.run_case(self.app, self.case, self.directory, self.state)
        attempt = self.state["cases"]["compact"]["attempts"][-1]
        self.assertEqual(attempt["status"], "interrupted")
        with self.assertRaises(ProcessLookupError):
            os.kill(attempt["launcher_pid"], 0)

    def test_shutdown_error_invalidates_success_marker(self):
        def shutdown(_app, log):
            with log.open("a") as output:
                output.write("ERROR: late failure\n")
        with patch.object(qa, "launch", side_effect=self.native_fixture("Forward+\n[CAPTURE_CHECK] PASS:\n")), \
                patch.object(qa, "stop_native", side_effect=shutdown):
            with self.assertRaisesRegex(ValueError, "shutdown"):
                qa.run_case(self.app, self.case, self.directory, self.state)
        self.assertEqual(self.state["cases"]["compact"]["status"], "failed")

    def test_interruption_during_cleanup_is_not_reviewable(self):
        with patch.object(qa, "launch", side_effect=self.native_fixture("Forward+\n[CAPTURE_CHECK] PASS:\n")), \
                patch.object(qa, "stop_native", side_effect=KeyboardInterrupt):
            with self.assertRaises(KeyboardInterrupt):
                qa.run_case(self.app, self.case, self.directory, self.state)
        self.assertEqual(self.state["cases"]["compact"]["status"], "interrupted")

    def test_cleanup_failure_still_reaps_launcher(self):
        with patch.object(qa, "launch", side_effect=self.native_fixture("Forward+\n[CAPTURE_CHECK] PASS:\n")), \
                patch.object(qa, "stop_native", side_effect=RuntimeError("Owned Godot instance did not stop")):
            with self.assertRaisesRegex(RuntimeError, "did not stop"):
                qa.run_case(self.app, self.case, self.directory, self.state)
        entry = self.state["cases"]["compact"]
        self.assertEqual(entry["status"], "failed")
        with self.assertRaises(ProcessLookupError):
            os.kill(entry["attempts"][-1]["launcher_pid"], 0)

    def test_native_command_never_activates_game(self):
        with patch.object(qa.subprocess, "Popen") as launch:
            qa.launch(self.app, self.case, self.root / "game.log", self.root / "frames")
        command = launch.call_args.args[0]
        self.assertEqual(command[:4], ["open", "-g", "-n", "-W"])
        self.assertIn("forward_plus", command)
        self.assertIn("640x360", command)

    def test_cleanup_matches_executable_and_exact_log_argument(self):
        log = self.root / "game.log"
        rows = (f" 10 {self.binary} --log-file {log} --script a\n"
                f" 11 {self.binary} --log-file {log}.other --script a\n"
                f" 12 /other/Godot --log-file {log} --script a\n")
        with patch.object(qa.subprocess, "check_output", return_value=rows):
            self.assertEqual(qa.native_pids(self.app, log), [10])

    def prepare_plan(self):
        self.plan = self.root / "plan.json"
        self.plan.write_text(json.dumps({"source_sha": "a" * 40, "cases": [self.case]}))
        self.git = patch.object(qa, "git", side_effect=lambda *args: b"a" * 40 if args[0] == "rev-parse" else b"")
        self.git.start()
        self.addCleanup(self.git.stop)

    def cli(self, action, *extra):
        with patch.object(sys, "argv", ["manual_qa.py", action, str(self.plan), str(self.directory), *extra]):
            return qa.main()

    def test_changed_inputs_refuse_reuse(self):
        self.prepare_plan()
        qa.session(self.plan, self.directory)
        self.case["acceptance"] = "Changed scope"
        self.plan.write_text(json.dumps({"source_sha": "a" * 40, "cases": [self.case]}))
        with self.assertRaisesRegex(ValueError, "inputs changed"):
            qa.session(self.plan, self.directory)

    def test_ignored_helper_change_invalidates_evidence(self):
        self.prepare_plan()
        helper = self.root / "helper.gd"
        helper.write_text("before")
        plan = json.loads(self.plan.read_text())
        plan["inputs"] = ["res://ignored/helper.gd"]
        self.plan.write_text(json.dumps(plan))
        with patch.object(qa, "source_path", side_effect=lambda name: helper if "helper" in name else qa.ROOT / "tests/combat_capture_test.gd"), \
                patch.object(qa, "ROOT", self.root):
            # Case source uses the real tracked script; only helper content changes.
            tracked = self.root / "tests/combat_capture_test.gd"
            tracked.parent.mkdir()
            tracked.write_text("extends SceneTree")
            _, before = qa.load_plan(self.plan)
            helper.write_text("after")
            _, after = qa.load_plan(self.plan)
        self.assertNotEqual(before, after)

    def test_review_is_required_and_passed_cases_are_skipped(self):
        self.prepare_plan()
        with patch.object(qa, "run_case") as run:
            self.assertEqual(self.cli("run"), 0)
            self.assertEqual(run.call_count, 1)
        _, state = qa.session(self.plan, self.directory)
        state["cases"]["compact"]["status"] = "awaiting_review"
        state["cases"]["compact"]["attempts"] = [{"app": str(self.app), "directory": str(self.root)}]
        qa.save(self.directory, state)
        with patch.object(qa, "run_case") as run:
            self.assertEqual(self.cli("run"), 1)
            run.assert_not_called()
        self.assertEqual(self.cli("accept", "--case", "compact"), 1)
        evidence = self.root / "review.md"
        evidence.write_text("CUA input and frame/event correspondence checked")
        self.assertEqual(self.cli("accept", "--case", "compact", "--evidence", str(evidence)), 0)
        with patch.object(qa, "run_case") as run:
            self.assertEqual(self.cli("run"), 0)
            run.assert_not_called()

    def test_resume_refuses_live_game_and_recovers_dead_attempt(self):
        self.prepare_plan()
        _, state = qa.session(self.plan, self.directory)
        state["cases"]["compact"].update(status="running", attempts=[{"app": str(self.app), "directory": str(self.root)}])
        qa.save(self.directory, state)
        with patch.object(qa, "native_pids", return_value=[10]), patch.object(qa, "run_case") as run:
            self.assertEqual(self.cli("run"), 1)
            run.assert_not_called()
        with patch.object(qa, "native_pids", return_value=[]), patch.object(qa, "run_case") as run:
            self.assertEqual(self.cli("run"), 0)
            self.assertEqual(run.call_args.args[-1]["cases"]["compact"]["status"], "interrupted")

    def test_cleanup_failure_and_pending_review_cannot_bypass_live_game_check(self):
        self.prepare_plan()
        _, state = qa.session(self.plan, self.directory)
        evidence = self.root / "review.md"
        evidence.write_text("Review must not bypass the live instance check")
        for status in ("failed", "interrupted", "awaiting_review", "passed"):
            with self.subTest(status=status):
                state["cases"]["compact"].update(status=status, attempts=[
                    {"app": str(self.app), "directory": str(self.root / "older-attempt")},
                    {"app": str(self.app), "directory": str(self.root / "newer-attempt")}])
                qa.save(self.directory, state)
                with patch.object(qa, "native_pids", return_value=[10]), patch.object(qa, "run_case") as run:
                    self.assertEqual(self.cli("run"), 1)
                    run.assert_not_called()
                    self.assertEqual(self.cli("accept", "--case", "compact", "--evidence", str(evidence)), 1)

    def test_failure_stops_before_next_case(self):
        self.prepare_plan()
        second = dict(self.case, id="full", resolution=[1920, 1080])
        self.plan.write_text(json.dumps({"source_sha": "a" * 40, "cases": [self.case, second]}))
        for error in (ValueError("step failed"), RuntimeError("cleanup failed")):
            with self.subTest(error=error), patch.object(qa, "run_case", side_effect=error) as run:
                self.assertEqual(self.cli("run"), 1)
                self.assertEqual(run.call_count, 1)


if __name__ == "__main__":
    unittest.main()
