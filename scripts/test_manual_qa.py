"""QA must not launch broken scripts, take the user's focus or reuse incomplete evidence."""

import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import Mock, patch

import manual_qa as qa

frontmost_pid = qa.frontmost_pid
docker_preflight = qa.docker_preflight


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
                     "resolution": [1280, 720], "acceptance": "Native input and original PNG reviewed",
                     "timeout": 2, "success_marker": "[CAPTURE_CHECK] PASS:"}
        self.directory = self.root / "session"
        self.directory.mkdir()
        self.state = {"cases": {"compact": {"status": "not_run", "attempts": []}}}
        docker = patch.object(qa, "docker_preflight")
        docker.start()
        self.addCleanup(docker.stop)
        front = patch.object(qa, "frontmost_pid", return_value=None)
        front.start()
        self.addCleanup(front.stop)

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

    def test_fixture_runtime_error_with_zero_exit_blocks_native_launch(self):
        self.case.update(preflight_args=["--fixture-precheck"], preflight_success_marker="FIXTURE_SETUP_PASS")
        self.binary.write_text('#!/bin/sh\nif [ "$1" = --version ]; then echo 4.7.2.stable.official.fixture; '
                               'else case "$*" in *--check-only*) ;; *) echo "SCRIPT ERROR: Invalid assignment"; '
                               'echo FIXTURE_SETUP_PASS ;; esac; fi\n')
        with patch.object(qa, "launch", side_effect=self.native_fixture("Forward+\n[CAPTURE_CHECK] PASS:\n")) as launch, \
                patch.object(qa, "stop_native"):
            with self.assertRaisesRegex(ValueError, "Preflight failed"):
                qa.run_case(self.app, self.case, self.directory, self.state)
            launch.assert_not_called()
        self.assertEqual(self.state["cases"]["compact"]["status"], "failed")

    def test_fixture_missing_marker_and_nonzero_exit_block_native_launch(self):
        self.case.update(preflight_args=["--fixture-precheck"], preflight_success_marker="FIXTURE_SETUP_PASS")
        for output, code in (("NO_SETUP_MARKER", 0), ("FIXTURE_SETUP_PASS", 7)):
            with self.subTest(output=output, code=code):
                self.binary.write_text('#!/bin/sh\nif [ "$1" = --version ]; then echo 4.7.2.stable.official.fixture; '
                                       f'else case "$*" in *--check-only*) ;; *) echo {output}; exit {code} ;; esac; fi\n')
                with patch.object(qa, "launch") as launch:
                    with self.assertRaisesRegex(ValueError, "Preflight failed"):
                        qa.run_case(self.app, self.case, self.directory, self.state)
                    launch.assert_not_called()
                self.assertEqual(self.state["cases"]["compact"]["status"], "failed")

    def test_fixture_success_still_needs_native_visual_review(self):
        self.case.update(preflight_args=["--fixture-precheck"], preflight_success_marker="FIXTURE_SETUP_PASS")
        self.binary.write_text('#!/bin/sh\nif [ "$1" = --version ]; then echo 4.7.2.stable.official.fixture; '
                               'else case "$*" in *--check-only*) echo PARSE_OK ;; '
                               '*--fixture-precheck*) echo FIXTURE_SETUP_PASS ;; *) exit 9 ;; esac; fi\n')
        self.prepare_plan()
        qa.load_plan(self.plan)
        launch = self.run_case("Metal - Forward+\n[CAPTURE_CHECK] PASS:\n")
        launch.assert_called_once()
        attempt = self.directory / "compact/1"
        self.assertEqual((attempt / "preflight.log").read_text().strip(), "PARSE_OK")
        self.assertEqual((attempt / "fixture-preflight.log").read_text().strip(), "FIXTURE_SETUP_PASS")
        self.assertEqual(self.state["cases"]["compact"]["status"], "awaiting_review")

    def test_fixture_timeout_reaps_owned_group_before_native_launch(self):
        self.case.update(preflight_args=["--fixture-precheck"], preflight_success_marker="FIXTURE_SETUP_PASS")
        parse, runtime = Mock(pid=123), Mock(pid=456)
        parse.wait.return_value, parse.poll.return_value = 0, 0
        runtime.wait.side_effect = [subprocess.TimeoutExpired("Godot", 30), 0]
        runtime.poll.return_value = None
        with patch.object(qa.subprocess, "check_output", return_value="4.7.2.stable.official.fixture"), \
                patch.object(qa.subprocess, "Popen", side_effect=[parse, runtime]), \
                patch.object(qa.os, "killpg") as kill, patch.object(qa, "launch") as launch:
            with self.assertRaises(subprocess.TimeoutExpired):
                qa.run_case(self.app, self.case, self.directory, self.state)
            kill.assert_called_once_with(runtime.pid, signal.SIGKILL)
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

    def test_native_command_requests_background_launch(self):
        with patch.object(qa.subprocess, "Popen") as launch:
            qa.launch(self.app, self.case, self.root / "game.log", self.root / "frames")
        command = launch.call_args.args[0]
        self.assertEqual(command[:4], ["open", "-g", "-n", "-W"])
        self.assertIn("forward_plus", command)
        self.assertIn("1280x720", command)

    def test_foreground_game_is_stopped_and_kill_failure_recorded(self):
        for failure in (None, RuntimeError("Owned Godot instance did not stop")):
            with self.subTest(failure=failure), \
                    patch.object(qa, "launch", side_effect=self.native_fixture("Metal - Forward+\n")), \
                    patch.object(qa, "frontmost_pid", return_value=4242), \
                    patch.object(qa, "native_pids", return_value=[4242]), \
                    patch.object(qa, "stop_native", side_effect=failure) as stop:
                with self.assertRaisesRegex(Exception, "did not stop" if failure else "frontmost"):
                    qa.run_case(self.app, self.case, self.directory, self.state)
                stop.assert_called_once()
                attempt = self.state["cases"]["compact"]["attempts"][-1]
                self.assertEqual(attempt["status"], "failed")
                self.assertIn("frontmost", attempt["foreground"])
                self.assertIn("frontmost", attempt["reason"])
                self.assertEqual("did not stop" in attempt.get("cleanup_error", ""), failure is not None)

    def test_other_frontmost_app_does_not_stop_game(self):
        with patch.object(qa, "frontmost_pid", return_value=1), patch.object(qa, "native_pids", return_value=[4242]):
            self.run_case("Metal - Forward+\n[CAPTURE_CHECK] PASS:\n")
        self.assertEqual(self.state["cases"]["compact"]["status"], "awaiting_review")

    def test_approved_foreground_case_records_consent_and_still_requires_review(self):
        self.case["foreground_approval"] = "User allowed focus for compact only, 2026-10-26"
        self.prepare_plan()
        with patch.object(qa, "launch", side_effect=self.native_fixture("Metal - Forward+\n[CAPTURE_CHECK] PASS:\n")) as launch, \
                patch.object(qa, "frontmost_pid", return_value=4242), \
                patch.object(qa, "native_pids", return_value=[4242]), patch.object(qa, "stop_native") as stop:
            self.assertEqual(self.cli("run", "--mode", "macos", "--app", str(self.app)), 0)
        self.assertEqual(launch.call_args.args[0], self.app.resolve())
        _, state = qa.session(self.plan, self.directory, "macos")
        entry = state["cases"]["compact"]
        self.assertEqual(entry["status"], "awaiting_review")
        self.assertEqual(entry["attempts"][-1]["foreground_approval"], self.case["foreground_approval"])
        self.assertEqual(entry["attempts"][-1]["foreground_pid"], 4242)
        stop.assert_called_once()

    def test_foreground_approval_does_not_extend_to_another_case_or_hide_game_errors(self):
        approved = dict(self.case, foreground_approval="User allowed compact only, 2026-10-26")
        with patch.object(qa, "frontmost_pid", return_value=4242), \
                patch.object(qa, "native_pids", return_value=[4242]), patch.object(qa, "stop_native") as stop:
            with patch.object(qa, "launch", side_effect=self.native_fixture("Metal - Forward+\n[CAPTURE_CHECK] PASS:\n")):
                qa.run_case(self.app, approved, self.directory, self.state)
                other = dict(self.case, id="other")
                self.state["cases"]["other"] = {"status": "not_run", "attempts": []}
                with self.assertRaisesRegex(ValueError, "frontmost"):
                    qa.run_case(self.app, other, self.directory, self.state)
            with patch.object(qa, "launch", side_effect=self.native_fixture(
                    "Metal - Forward+\nSCRIPT ERROR: fixture failed\n[CAPTURE_CHECK] PASS:\n")):
                with self.assertRaisesRegex(ValueError, "Godot error"):
                    qa.run_case(self.app, approved, self.directory, self.state)
        self.assertEqual(self.state["cases"]["other"]["status"], "failed")
        self.assertEqual(self.state["cases"]["compact"]["status"], "failed")
        self.assertEqual(stop.call_count, 3)

    def test_frontmost_pid_reads_lsappinfo(self):
        outputs = ["ASN:0x0-0x62062:\n", '"Godot" ASN:0x0-0x62062: (in front)\n    pid = 1398 !cgsConnection\n']
        with patch.object(qa.subprocess, "check_output", side_effect=outputs) as run:
            self.assertEqual(frontmost_pid(), 1398)
        self.assertEqual(run.call_args.args[0], ["lsappinfo", "info", "-only", "pid", "ASN:0x0-0x62062:"])

    def test_docker_unavailable_blocks_build_and_cleanup(self):
        for error in (FileNotFoundError("docker"), subprocess.CalledProcessError(1, ["docker", "info"]),
                      subprocess.TimeoutExpired(["docker", "info"], 5)):
            with self.subTest(error=type(error).__name__), \
                    patch.object(qa, "docker_preflight", docker_preflight), \
                    patch.object(qa.subprocess, "run", side_effect=error) as run, \
                    patch.object(qa, "start_container") as build, \
                    patch.object(qa, "stop_container") as stop:
                with self.assertRaisesRegex(ValueError, "Docker"):
                    qa.run_case(self.app, self.case, self.directory, self.state, offscreen=True)
                build.assert_not_called()
                stop.assert_not_called()
                self.assertEqual(run.call_args.kwargs["timeout"], 5)
                self.assertEqual(run.call_args.args[0], ["docker", "info", "--format", "{{.ServerVersion}}"])
                self.assertEqual(self.state["cases"]["compact"]["status"], "failed")

    def test_docker_check_passes_with_bounded_server_query(self):
        with patch.object(qa.subprocess, "run") as run:
            docker_preflight()
        self.assertEqual(run.call_args.args[0], ["docker", "info", "--format", "{{.ServerVersion}}"])
        self.assertTrue(run.call_args.kwargs["check"])
        self.assertEqual(run.call_args.kwargs["timeout"], 5)

    def test_offscreen_command_never_opens_macos_window(self):
        self.case["args"] = ["--profile=compact"]
        with patch.object(qa.subprocess, "Popen") as launch:
            qa.launch_offscreen("bglike-qa-test", self.case)
        command = launch.call_args.args[0]
        self.assertEqual(command[:3], ["docker", "exec", "bglike-qa-test"])
        self.assertIn("xvfb-run", command)
        self.assertIn("-screen 0 1280x720x24", command)
        self.assertNotIn("open", command)
        self.assertNotIn("--manual", command)
        for flag, value in (("--rendering-method", "forward_plus"), ("--resolution", "1280x720"),
                            ("--log-file", "/out/game.log")):
            self.assertEqual(command[command.index(flag) + 1], value)
        self.assertEqual(command[-2:], ["--capture-dir=/out/frames", "--profile=compact"])

    def offscreen_fixture(self, text):
        launch = self.native_fixture(text)
        return lambda _name, case: launch(None, case, self.directory / "compact/1/game.log", None)

    def test_offscreen_runs_godot_in_container_and_removes_it(self):
        with patch.object(qa, "start_container", return_value="sha256:image") as start, \
                patch.object(qa, "import_offscreen"), \
                patch.object(qa.subprocess, "check_output", return_value="4.7.2.stable.official.fixture"), \
                patch.object(qa, "preflight") as preflight, \
                patch.object(qa, "launch_offscreen", side_effect=self.offscreen_fixture(
                    "Vulkan - Forward+ - llvmpipe\nCombat capture: 9 checks, 0 failures\n")), \
                patch.object(qa, "stop_container") as stop, patch.object(qa, "launch") as native:
            self.case["success_marker"] = "0 failures"
            qa.run_case(self.app, self.case, self.directory, self.state, offscreen=True)
        attempt = self.state["cases"]["compact"]["attempts"][-1]
        name = attempt["container"]
        start.assert_called_once_with(name, self.directory / "compact/1")
        self.assertEqual(preflight.call_args.args[:2], (["docker", "exec", name, "godot"], "/work"))
        stop.assert_called_once_with(name)
        native.assert_not_called()
        self.assertNotIn("app", attempt)
        self.assertEqual((attempt["image"], attempt["status"]), ("sha256:image", "awaiting_review"))

    def test_offscreen_failure_before_launch_still_removes_container(self):
        with patch.object(qa, "start_container", return_value="sha256:image"), \
                patch.object(qa, "import_offscreen", side_effect=ValueError("Offscreen import failed")), \
                patch.object(qa, "launch_offscreen") as launch, patch.object(qa, "stop_container") as stop:
            with self.assertRaisesRegex(ValueError, "import failed"):
                qa.run_case(self.app, self.case, self.directory, self.state, offscreen=True)
        launch.assert_not_called()
        stop.assert_called_once_with(self.state["cases"]["compact"]["attempts"][-1]["container"])
        self.assertEqual(self.state["cases"]["compact"]["status"], "failed")

    def test_marker_written_just_before_exit_is_success(self):
        log = self.directory / "compact/1/game.log"
        launcher = Mock(pid=999999)

        def exit_after_marker():
            log.write_text("Vulkan - Forward+ - llvmpipe\n[CAPTURE_CHECK] PASS:\n")
            return 0
        launcher.poll.side_effect = exit_after_marker
        with patch.object(qa, "launch", return_value=launcher), patch.object(qa, "stop_native"):
            qa.run_case(self.app, self.case, self.directory, self.state)
        self.assertEqual(self.state["cases"]["compact"]["status"], "awaiting_review")

    def test_container_liveness_uses_exact_name_and_blocks_failed_removal(self):
        with patch.object(qa.subprocess, "check_output", return_value="1085826332dd\n") as ps, \
                patch.object(qa.subprocess, "run") as remove:
            with self.assertRaisesRegex(RuntimeError, "did not stop"):
                qa.stop_container("bglike-qa-test")
        self.assertEqual(remove.call_args.args[0], ["docker", "rm", "-f", "bglike-qa-test"])
        self.assertEqual(ps.call_args.args[0], ["docker", "ps", "-q", "--filter", "name=^bglike-qa-test$"])
        with patch.object(qa.subprocess, "check_output", return_value="\n"):
            self.assertFalse(qa.container_alive("bglike-qa-test"))

    def test_interrupted_cleanup_keeps_original_failure(self):
        with patch.object(qa, "start_container", return_value="sha256:image"), \
                patch.object(qa, "import_offscreen", side_effect=ValueError("Offscreen import failed")), \
                patch.object(qa, "stop_container", side_effect=KeyboardInterrupt):
            with self.assertRaises(KeyboardInterrupt):
                qa.run_case(self.app, self.case, self.directory, self.state, offscreen=True)
        attempt = self.state["cases"]["compact"]["attempts"][-1]
        self.assertEqual(attempt["status"], "interrupted")
        self.assertEqual((attempt["reason"], attempt["cleanup_error"]),
                         ("Offscreen import failed", "Interrupted during process cleanup"))

    def test_offscreen_import_script_error_blocks_launch(self):
        def run(_command, stdout, **_kwargs):
            stdout.write("SCRIPT ERROR: Parse Error\n")
            return Mock(returncode=0)
        with patch.object(qa.subprocess, "run", side_effect=run):
            with self.assertRaisesRegex(ValueError, "import failed"):
                qa.import_offscreen("bglike-qa-test", self.directory)

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

    def test_fixture_preflight_plan_requires_args_and_marker(self):
        self.prepare_plan()
        for fields in ({"preflight_args": []}, {"preflight_success_marker": "PASS"},
                       {"preflight_args": "--fixture-precheck", "preflight_success_marker": "PASS"},
                       {"preflight_args": [1], "preflight_success_marker": "PASS"},
                       {"preflight_args": [], "preflight_success_marker": "  "}):
            with self.subTest(fields=fields):
                self.plan.write_text(json.dumps({"source_sha": "a" * 40, "cases": [dict(self.case, **fields)]}))
                with self.assertRaisesRegex(ValueError, "Fixture preflight"):
                    qa.load_plan(self.plan)

    def test_changed_inputs_refuse_reuse(self):
        self.prepare_plan()
        qa.session(self.plan, self.directory)
        self.case["acceptance"] = "Changed scope"
        self.plan.write_text(json.dumps({"source_sha": "a" * 40, "cases": [self.case]}))
        with self.assertRaisesRegex(ValueError, "inputs changed"):
            qa.session(self.plan, self.directory)

    def test_foreground_approval_requires_nonempty_user_consent(self):
        self.prepare_plan()
        for approval in (None, False, True, "", "  ", {"allowed": True}):
            with self.subTest(approval=approval):
                self.plan.write_text(json.dumps({"source_sha": "a" * 40, "cases": [
                    dict(self.case, foreground_approval=approval)]}))
                with patch.object(qa, "launch") as launch:
                    self.assertEqual(self.cli("run", "--mode", "macos"), 1)
                    launch.assert_not_called()

    def test_foreground_approval_is_rejected_outside_macos_mode(self):
        self.case["foreground_approval"] = "User allowed focus for compact only, 2026-10-26"
        self.prepare_plan()
        with patch.object(qa, "run_case") as run:
            self.assertEqual(self.cli("run"), 1)
            run.assert_not_called()

    def test_changed_or_revoked_foreground_approval_refuses_evidence_reuse(self):
        self.case["foreground_approval"] = "User allowed focus for compact only, 2026-10-26"
        self.prepare_plan()
        qa.session(self.plan, self.directory, "macos")
        for fields in ({}, {"foreground_approval": "New authorization with another scope"}):
            with self.subTest(fields=fields):
                changed = {key: value for key, value in self.case.items() if key != "foreground_approval"}
                changed.update(fields)
                self.plan.write_text(json.dumps({"source_sha": "a" * 40, "cases": [changed]}))
                with self.assertRaisesRegex(ValueError, "inputs changed"):
                    qa.session(self.plan, self.directory, "macos")

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
            self.assertEqual(run.call_args.args[3]["cases"]["compact"]["status"], "interrupted")

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

    def test_session_keeps_one_run_mode(self):
        self.prepare_plan()
        qa.session(self.plan, self.directory, "offscreen")
        with self.assertRaisesRegex(ValueError, "offscreen mode; pass that --mode"):
            qa.session(self.plan, self.directory, "macos")
        state = json.loads((self.directory / "state.json").read_text())
        del state["mode"]
        qa.save(self.directory, state)
        qa.session(self.plan, self.directory, "macos")
        with self.assertRaisesRegex(ValueError, "macos mode"):
            qa.session(self.plan, self.directory, "offscreen")

    def test_resume_refuses_live_container(self):
        self.prepare_plan()
        _, state = qa.session(self.plan, self.directory)
        state["cases"]["compact"].update(status="running", attempts=[
            {"container": "bglike-qa-test", "directory": str(self.root)}])
        qa.save(self.directory, state)
        with patch.object(qa, "container_alive", return_value=True) as alive, patch.object(qa, "run_case") as run:
            self.assertEqual(self.cli("run"), 1)
            run.assert_not_called()
        alive.assert_called_with("bglike-qa-test")

    def test_resume_docker_query_has_five_second_limit(self):
        self.prepare_plan()
        _, state = qa.session(self.plan, self.directory)
        state["cases"]["compact"].update(status="failed", attempts=[
            {"container": "bglike-qa-test", "directory": str(self.root)}])
        qa.save(self.directory, state)

        def query(argv, **kwargs):
            self.assertEqual(argv[:2], ["docker", "ps"])
            self.assertEqual(kwargs.get("timeout"), 5)
            raise subprocess.TimeoutExpired(argv, 5)

        with patch.object(qa.subprocess, "check_output", side_effect=query), patch.object(qa, "run_case") as run:
            self.assertEqual(self.cli("run"), 1)
            run.assert_not_called()

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
