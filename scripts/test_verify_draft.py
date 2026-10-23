import copy
import hashlib
import io
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch
import zipfile

from test_draft_release import API, SHA, VERSION, bundle
import verify_draft as verifier


class DraftVerificationTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        source = self.root / "source"
        source.mkdir()
        archive = bundle(source)
        with zipfile.ZipFile(archive) as zipped:
            contents = {name: zipped.read(name) for name in zipped.namelist()}
        notices = b"System Reference Document 5.1 https://creativecommons.org/licenses/by/4.0/"
        contents["THIRD_PARTY_NOTICES.md"] = notices
        metadata = json.loads(contents["metadata.json"])
        metadata["files"]["THIRD_PARTY_NOTICES.md"] = hashlib.sha256(notices).hexdigest()
        pins = dict(line.split("=", 1) for line in Path(verifier.__file__).with_name("godot.env").read_text().splitlines() if "=" in line and not line.startswith("#"))
        metadata["engine_archive_sha256"] = pins["GODOT_LINUX_X86_64_SHA256"]
        contents["metadata.json"] = json.dumps(metadata).encode()
        with zipfile.ZipFile(archive, "w") as zipped:
            for name, data in contents.items():
                zipped.writestr(name, data)
        (source / "SHA256SUMS").write_text(f"{hashlib.sha256(archive.read_bytes()).hexdigest()}  {archive.name}\n")
        self.data = {index: path.read_bytes() for index, path in enumerate(sorted(source.iterdir()), 1)}
        self.api = API()
        self.api.repo = "minjunkim-dev/BGLike"
        assets = [{"id": index, "name": path.name, "size": len(self.data[index]), "state": "uploaded",
                   "digest": "sha256:" + hashlib.sha256(self.data[index]).hexdigest()}
                  for index, path in enumerate(sorted(source.iterdir()), 1)]
        self.release = {"id": 10, "name": VERSION, "tag_name": VERSION, "target_commitish": SHA,
                        "draft": True, "prerelease": True, "assets": assets}
        self.api.release = self.release
        self.downloads = []

        def asset(asset_id):
            self.downloads.append(asset_id)
            return self.data[asset_id]
        self.api.asset = asset
        self.output = self.root / "evidence"
        self.godot = self.root / "godot"
        self.godot.write_text("#!/bin/sh\nif [ \"$1\" = --version ]; then echo 4.7.2.stable.official.test; else echo smoke-passed; fi\n")
        self.godot.chmod(0o755)

    def verify(self, request_id=None, build_id=None):
        return verifier.verify(self.api, 10, VERSION, SHA, self.output, str(self.godot), request_id, build_id)

    def add_runs(self):
        workflow = "actions/workflows/draft-release.yml"
        self.api.responses[workflow] = {"id": 7, "state": "active", "path": ".github/workflows/draft-release.yml"}
        for run_id, event, workflow in ((11, "workflow_dispatch", "draft-release.yml"), (12, "workflow_run", "draft-build.yml")):
            self.api.responses[f"actions/runs/{run_id}"] = {
                "id": run_id, "run_attempt": 1, "workflow_id": 7, "event": event, "path": f".github/workflows/{workflow}",
                "head_sha": SHA, "head_branch": "main", "head_repository": {"full_name": self.api.repo},
                "status": "completed", "conclusion": "success"}
        self.api.responses["actions/runs/12/jobs?filter=latest&per_page=100"] = {"total_count": 2, "jobs": [
            {"name": name, "status": "completed", "conclusion": "success"} for name in ("build", "draft")]}
        self.api.responses["actions/runs/11/artifacts?per_page=100"]["artifacts"][0]["workflow_run"]["head_sha"] = SHA
        data = io.BytesIO()
        with zipfile.ZipFile(data, "w") as archive:
            archive.writestr("request.json", json.dumps({"version": VERSION, "source_sha": SHA,
                "request_run_id": 11, "request_attempt": 1, "request_sha": SHA}))
        self.api.download = lambda path: data.getvalue()

    def test_download_smoke_and_resume_keep_exact_identity(self):
        self.add_runs()
        result = self.verify(11, 12)
        self.assertEqual(result["status"], "passed")
        self.assertEqual(result["source_sha"], SHA)
        self.assertEqual(result["request_run_id"], 11)
        self.assertEqual(len(self.downloads), 2)
        self.release["assets"][0]["download_count"] = 100
        self.assertEqual(self.verify(11, 12), result)
        self.assertEqual(len(self.downloads), 2)
        self.assertIn("smoke-passed", (self.output / "runtime.log").read_text())
        self.assertTrue(all(call[0] == "GET" for call in self.api.calls))

    def test_wrong_identity_public_release_and_path_names_fail_before_download(self):
        original = copy.deepcopy(self.release)
        for key, value in (("draft", False), ("target_commitish", "b" * 40), ("tag_name", "wrong")):
            with self.subTest(key=key):
                self.release.update(original)
                self.release[key] = value
                with self.assertRaises(ValueError):
                    self.verify()
        self.release.update(original)
        self.release["assets"][0]["name"] = "../escape"
        with self.assertRaises(ValueError):
            self.verify()
        self.assertEqual(self.downloads, [])

    def test_request_artifact_source_must_match_release(self):
        self.add_runs()
        data = io.BytesIO()
        with zipfile.ZipFile(data, "w") as archive:
            archive.writestr("request.json", json.dumps({"version": VERSION, "source_sha": "b" * 40,
                "request_run_id": 11, "request_attempt": 1, "request_sha": SHA}))
        self.api.download = lambda path: data.getvalue()
        with self.assertRaisesRegex(ValueError, "Request source"):
            self.verify(11, 12)
        self.assertEqual(self.downloads, [])

    def test_timeout_retains_failure_log_and_no_success(self):
        self.verify()
        with patch.object(verifier, "command", return_value="4.7.2.stable.official.test"), patch.object(
                verifier.subprocess, "run", side_effect=subprocess.TimeoutExpired("godot", 30, output=b"starting\n")):
            with self.assertRaisesRegex(ValueError, "timed out"):
                self.verify()
        self.assertEqual((self.output / "runtime.log").read_bytes(), b"starting\n")
        self.assertFalse((self.output / "result.json").exists())

    def test_digest_mismatch_never_produces_success(self):
        self.release["assets"][0]["digest"] = "sha256:" + "0" * 64
        with self.assertRaisesRegex(ValueError, "digest"):
            self.verify()
        self.assertFalse((self.output / "result.json").exists())

    def test_invalid_input_clears_previous_success(self):
        self.verify()
        with self.assertRaises(ValueError):
            verifier.verify(self.api, 10, VERSION, "main", self.output, str(self.godot))
        self.assertFalse((self.output / "result.json").exists())

    def test_unowned_output_is_preserved(self):
        self.output.mkdir()
        report = self.output / "result.json"
        report.write_text("user data")
        with self.assertRaises(ValueError):
            self.verify()
        self.assertEqual(report.read_text(), "user data")

    def test_changed_identity_and_corrupt_resume_reject_without_download(self):
        self.verify()
        self.release["assets"][0]["id"] = 42
        with self.assertRaisesRegex(ValueError, "another Draft"):
            self.verify()
        self.assertFalse((self.output / "result.json").exists())
        self.assertEqual(len(self.downloads), 2)

    def test_corrupt_existing_asset_is_preserved_and_failed(self):
        self.verify()
        damaged = self.output / "assets" / "SHA256SUMS"
        damaged.write_bytes(b"damaged")
        with self.assertRaises(ValueError):
            self.verify()
        self.assertEqual(damaged.read_bytes(), b"damaged")
        self.assertFalse((self.output / "result.json").exists())
        self.assertEqual(len(self.downloads), 2)

    def test_run_ids_require_both_and_exact_role_success_jobs(self):
        with self.assertRaises(ValueError):
            self.verify(11)
        self.add_runs()
        self.api.responses["actions/runs/12"]["event"] = "push"
        with self.assertRaisesRegex(ValueError, "build run"):
            self.verify(11, 12)
        self.add_runs()
        self.api.responses["actions/runs/12/jobs?filter=latest&per_page=100"]["jobs"][1]["conclusion"] = "skipped"
        with self.assertRaisesRegex(ValueError, "draft job"):
            self.verify(11, 12)
        self.assertEqual(self.downloads, [])

    def test_runtime_warning_invalidates_previous_success_and_isolates_home(self):
        self.verify()
        self.godot.write_text("#!/bin/sh\nif [ \"$1\" = --version ]; then echo 4.7.2.stable.official.test; else echo WARNING:bad; echo $HOME; fi\n")
        with self.assertRaisesRegex(ValueError, "smoke failed"):
            self.verify()
        self.assertFalse((self.output / "result.json").exists())
        runtime = (self.output / "runtime.log").read_text()
        self.assertIn("bglike-draft-", runtime)
        self.assertNotIn(str(Path.home()), runtime)

    def test_wrong_engine_and_missing_rights_fail(self):
        self.godot.write_text("#!/bin/sh\necho 4.6.0.stable.official.test\n")
        with self.assertRaisesRegex(ValueError, "Godot 4.7.2"):
            self.verify()
        archive = self.root / "missing-rights.zip"
        with zipfile.ZipFile(archive, "w") as zipped:
            zipped.writestr("THIRD_PARTY_NOTICES.md", "missing")
        with patch.object(verifier, "command", return_value="4.7.2.stable.official.test"):
            with self.assertRaisesRegex(ValueError, "attribution"):
                verifier.smoke(archive, str(self.godot), self.output)

    def test_symlink_output_rejected(self):
        self.output.symlink_to(self.root, target_is_directory=True)
        with self.assertRaisesRegex(ValueError, "symlink"):
            self.verify()
        self.assertEqual(self.downloads, [])

    def test_gh_transport_uses_only_explicit_get_and_asset_id(self):
        api = verifier.GitHub()
        with patch.object(verifier.subprocess, "run", return_value=subprocess.CompletedProcess([], 0, b"{}")) as run:
            self.assertEqual(api.request("GET", "releases/10"), {})
            self.assertEqual(api.asset(2), b"{}")
            api.download("actions/artifacts/3/zip")
            self.assertIn("Accept: application/octet-stream", run.call_args_list[1].args[0])
            self.assertIn("Accept: application/json", run.call_args_list[2].args[0])
            for call in run.call_args_list:
                self.assertEqual(call.args[0][:4], ["gh", "api", "--method", "GET"])
                self.assertNotIn("shell", call.kwargs)
            with self.assertRaises(ValueError):
                api.request("POST", "releases")


if __name__ == "__main__":
    unittest.main()
