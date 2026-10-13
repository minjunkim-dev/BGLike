import copy
import hashlib
import json
from pathlib import Path
import tempfile
import unittest
import urllib.error
from unittest.mock import patch
import zipfile

from draft_release import GitHub, create_draft, eligibility, inputs, verify_bundle


SHA = "a" * 40
VERSION = "v0.1.0-alpha.1"
ENGINE_HASH = "b" * 64


class API:
    def __init__(self):
        self.calls = []
        self.responses = {"": {"default_branch": "main"}, f"commits/{SHA}": {"sha": SHA},
            f"compare/{SHA}...main": {"status": "ahead", "merge_base_commit": {"sha": SHA}},
            "actions/workflows/godot.yml": {"id": 2, "state": "active", "path": ".github/workflows/godot.yml"},
            f"actions/workflows/godot.yml/runs?event=push&branch=main&head_sha={SHA}&per_page=100":
                {"total_count": 1, "workflow_runs": [{"id": 3, "run_number": 5, "workflow_id": 2,
                    "head_sha": SHA, "head_branch": "main", "event": "push", "status": "completed", "conclusion": "success"}]},
            "actions/runs/3/jobs?filter=latest&per_page=100": {"total_count": 1, "jobs": [{"name": "CI", "status": "completed", "conclusion": "success"}]},
            f"git/ref/tags/{VERSION}": None, f"releases/tags/{VERSION}": None}
        self.releases = []
        self.release = None
        self.race = False

    def request(self, method, path, data=None, **kwargs):
        self.calls.append((method, path, data))
        if method == "POST" and path == "releases":
            self.release = dict(data, id=10, assets=[])
            self.releases.append(self.release)
            return copy.deepcopy(self.release)
        if method == "POST" and path.startswith("releases/10/assets?"):
            name = path.split("name=")[1]
            asset = {"name": name, "size": len(data), "state": "uploaded", "digest": "sha256:" + hashlib.sha256(data).hexdigest()}
            self.release["assets"].append(asset)
            return asset
        if path == "releases/10":
            return self.release
        if self.race and self.release and path.startswith("git/ref/"):
            return {"object": {"sha": SHA}}
        return copy.deepcopy(self.responses[path])

    def all(self, path):
        return self.releases


def bundle(directory):
    files = {"bglike.pck": b"packed game", "COPYRIGHT.md": b"copyright", "THIRD_PARTY_NOTICES.md": b"notices", "kenney_license.txt": b"CC0"}
    metadata = {"version": VERSION, "source_sha": SHA, "engine_archive_sha256": ENGINE_HASH,
                "engine": "4.7.2.stable.official.test", "preset": "Verification PCK",
                "files": {name: hashlib.sha256(data).hexdigest() for name, data in files.items()}}
    files["metadata.json"] = json.dumps(metadata).encode()
    files["RUN.txt"] = b"instructions"
    path = directory / f"bglike-{VERSION}-pck.zip"
    with zipfile.ZipFile(path, "w") as archive:
        for name, data in files.items():
            archive.writestr(name, data)
    (directory / "SHA256SUMS").write_text(f"{hashlib.sha256(path.read_bytes()).hexdigest()}  {path.name}\n")
    return path


class DraftTests(unittest.TestCase):
    def test_version_and_source_reject_branch_short_sha_and_shell_text(self):
        for version, sha in [("v0.1.0", SHA), (VERSION, "main"), (VERSION, SHA[:8]), ("v0.1.0-alpha.1;echo", SHA)]:
            with self.subTest(version=version, sha=sha), self.assertRaises(ValueError):
                inputs(version, sha)

    def test_exact_ci_and_ancestry(self):
        self.assertEqual(eligibility(API(), VERSION, SHA), 3)
        for path, response in [(f"compare/{SHA}...main", {"status": "diverged"}),
                               ("actions/runs/3/jobs?filter=latest&per_page=100", {"jobs": []}),
                               (f"git/ref/tags/{VERSION}", {"object": {}}),
                               (f"commits/{SHA}", {"sha": "c" * 40})]:
            with self.subTest(path=path):
                api = API()
                api.responses[path] = response
                with self.assertRaises(ValueError):
                    eligibility(api, VERSION, SHA)

    def test_failure_cancel_missing_aggregate_and_wrong_ci_event(self):
        for conclusion in ["failure", "cancelled", None, "skipped"]:
            api = API()
            api.responses["actions/runs/3/jobs?filter=latest&per_page=100"]["jobs"][0]["conclusion"] = conclusion
            with self.subTest(conclusion=conclusion), self.assertRaises(ValueError):
                eligibility(api, VERSION, SHA)
        for field, value in [("event", "pull_request"), ("head_branch", "other"), ("head_sha", "c" * 40), ("status", "in_progress"), ("conclusion", "failure")]:
            api = API()
            runs = api.responses[f"actions/workflows/godot.yml/runs?event=push&branch=main&head_sha={SHA}&per_page=100"]["workflow_runs"]
            runs[0][field] = value
            with self.subTest(field=field), self.assertRaises(ValueError):
                eligibility(api, VERSION, SHA)

    def test_draft_collision(self):
        api = API()
        api.releases = [{"tag_name": VERSION, "draft": True}]
        with self.assertRaises(ValueError):
            eligibility(api, VERSION, SHA)

    def test_api_only_explicit_404_is_missing(self):
        api = GitHub("owner/repo", "fake-test-token")
        for code in [401, 403, 429, 500]:
            with patch.object(api.opener, "open", side_effect=urllib.error.HTTPError("url", code, "error", {}, None)):
                with self.subTest(code=code), self.assertRaises(ValueError):
                    api.request("GET", "releases/tags/test", missing=True)
        with patch.object(api.opener, "open", side_effect=urllib.error.HTTPError("url", 404, "missing", {}, None)):
            self.assertIsNone(api.request("GET", "releases/tags/test", missing=True))
            with self.assertRaises(ValueError):
                api.request("GET", "commits/test")

    def test_archive_round_trip_and_provenance_mismatch(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            bundle(directory)
            self.assertEqual(len(verify_bundle(directory, VERSION, SHA, ENGINE_HASH)), 2)
            with self.assertRaises(ValueError):
                verify_bundle(directory, VERSION, "c" * 40, ENGINE_HASH)
            (directory / "SHA256SUMS").write_text("wrong")
            with self.assertRaises(ValueError):
                verify_bundle(directory, VERSION, SHA, ENGINE_HASH)

    def test_fixed_draft_fields_uploads_and_final_race(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            bundle(directory)
            api = API()
            self.assertEqual(create_draft(api, directory, VERSION, SHA, ENGINE_HASH), 10)
            self.assertIs(api.release["draft"], True)
            self.assertIs(api.release["prerelease"], True)
            self.assertEqual(api.release["target_commitish"], SHA)
            self.assertEqual(len(api.release["assets"]), 2)
            api = API()
            api.race = True
            with self.assertRaises(ValueError):
                create_draft(api, directory, VERSION, SHA, ENGINE_HASH)
            self.assertIs(api.release["draft"], True)
            self.assertFalse(any(call[0] in {"PATCH", "DELETE"} for call in api.calls))

    def test_failed_precondition_never_creates_release(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            bundle(directory)
            api = API()
            api.responses[f"git/ref/tags/{VERSION}"] = {"object": {}}
            with self.assertRaises(ValueError):
                create_draft(api, directory, VERSION, SHA, ENGINE_HASH)
            self.assertFalse(any(call[0] == "POST" for call in api.calls))

    def test_asset_failure_leaves_unpublished_draft_without_cleanup(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            bundle(directory)
            api = API()
            request = api.request

            def failed_upload(method, path, data=None, **kwargs):
                if method == "POST" and "/assets?" in path:
                    raise ValueError("HTTP 502")
                return request(method, path, data, **kwargs)

            api.request = failed_upload
            with self.assertRaises(ValueError):
                create_draft(api, directory, VERSION, SHA, ENGINE_HASH)
            self.assertIs(api.release["draft"], True)
            self.assertFalse(any(call[0] in {"PATCH", "DELETE"} for call in api.calls))

    def test_member_tamper_with_updated_outer_checksum_is_rejected(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            path = bundle(directory)
            with zipfile.ZipFile(path) as source:
                files = {name: source.read(name) for name in source.namelist()}
            files["bglike.pck"] = b"changed payload"
            with zipfile.ZipFile(path, "w") as archive:
                for name, data in files.items():
                    archive.writestr(name, data)
            (directory / "SHA256SUMS").write_text(f"{hashlib.sha256(path.read_bytes()).hexdigest()}  {path.name}\n")
            with self.assertRaisesRegex(ValueError, "member checksum"):
                verify_bundle(directory, VERSION, SHA, ENGINE_HASH)


if __name__ == "__main__":
    unittest.main()
