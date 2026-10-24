"""Movement QA must reject incomplete evidence even after an engine exit of zero."""
import copy
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import Mock, patch

import qa_movement as qa


def fixture_result():
    return {"checks": 43, "failures": 0, "cases": [
        {"case": name, "returned": name != "dropped_confirm", "dice_problems": [],
         "movement_failures": ["confirmation missing"] if name == "dropped_confirm" else [],
         "record": {"outcome": outcome, "passed": name != "dropped_confirm"}}
        for name, outcome in qa.OUTCOMES.items()]}


class MovementQATests(unittest.TestCase):
    def test_all_five_including_detected_negative_control_are_required(self):
        qa.validate(fixture_result())
        for change in (lambda data: data["cases"].pop(),
                       lambda data: data["cases"].__setitem__(1, data["cases"][0]),
                       lambda data: data["cases"][-1]["record"].update(passed=True),
                       lambda data: data["cases"][1]["dice_problems"].append("d10 requested, d20 prepared"),
                       lambda data: data["cases"][0]["record"].update(outcome="failed")):
            data = copy.deepcopy(fixture_result())
            change(data)
            with self.subTest(data=data), self.assertRaises(ValueError):
                qa.validate(data)

    def test_existing_evidence_is_preserved_without_launch(self):
        with tempfile.TemporaryDirectory() as folder:
            output = Path(folder) / "evidence"
            output.mkdir()
            note = output / "result.json"
            note.write_text("keep")
            with patch.object(qa, "verify_bundle") as verify, patch.object(qa.subprocess, "Popen") as launch:
                with self.assertRaises(ValueError):
                    qa.run(Path(folder), "v0.1.0-alpha.3", "a" * 40, output, "godot")
                verify.assert_not_called()
                launch.assert_not_called()
            self.assertEqual(note.read_text(), "keep")

    def test_bundle_failure_blocks_execution(self):
        with tempfile.TemporaryDirectory() as folder, \
                patch.object(qa, "verify_bundle", side_effect=ValueError("wrong artifact")), \
                patch.object(qa.subprocess, "Popen") as launch:
            with self.assertRaisesRegex(ValueError, "wrong artifact"):
                qa.run(Path(folder), "v0.1.0-alpha.3", "a" * 40, Path(folder) / "new", "godot")
            launch.assert_not_called()

    def test_zero_exit_with_partial_cases_never_writes_success(self):
        # Reuse the real bundle validator fixture instead of duplicating its checksum tests.
        from test_draft_release import bundle, VERSION, SHA
        with tempfile.TemporaryDirectory() as folder:
            directory = Path(folder)
            assets = directory / "assets"
            assets.mkdir()
            archive = bundle(assets)
            output = directory / "new"
            def launch(command, **kwargs):
                stream = kwargs["stdout"]
                if "--version" in command:
                    stream.write("4.7.2.stable.official.fixture\n")
                if any(arg.startswith("--out=") for arg in command):
                    partial = fixture_result()
                    partial["cases"].pop()
                    (output / "fixtures.json").write_text(json.dumps(partial))
                self.assertEqual(kwargs["env"]["HOME"], str(kwargs["cwd"]))
                self.assertNotIn("GITHUB_TOKEN", kwargs["env"])
                return Mock(wait=Mock(return_value=0), poll=Mock(return_value=0))
            with patch.object(qa, "load_plan", return_value=({}, "fingerprint")), \
                    patch.object(qa, "git", return_value=("a" * 40).encode()), \
                    patch.object(qa, "verify_bundle", return_value=[archive]) as verify, \
                    patch.object(qa.subprocess, "Popen", side_effect=launch):
                with self.assertRaisesRegex(ValueError, "Incomplete"):
                    qa.run(assets, VERSION, SHA, output, "godot")
                verify.assert_called_once()
            self.assertTrue((output / "runtime.log").is_file())
            self.assertFalse((output / "result.json").exists())
