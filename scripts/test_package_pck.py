import hashlib
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch
import zipfile

from draft_release import verify_bundle
from package_pck import command, package


class PackageTests(unittest.TestCase):
    def test_command_rejects_real_failure_and_godot_diagnostics(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            for code in ["raise SystemExit(1)", "print('ERROR: broken')", "print('WARNING: missing resource')"]:
                with self.subTest(code=code), self.assertRaises(ValueError):
                    command(["python3", "-c", code], root)
            self.assertEqual(command(["python3", "-c", "print('valid')"], root), "valid")

    def test_real_git_checkout_rejects_wrong_source_before_export(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            subprocess.run(["git", "init", "--quiet", str(root)], check=True)
            (root / "test.txt").write_text("fixture")
            subprocess.run(["git", "add", "."], cwd=root, check=True)
            subprocess.run(["git", "-c", "user.name=fixture", "-c", "user.email=fixture@example.invalid", "commit", "--quiet", "-m", "fixture"], cwd=root, check=True)
            with self.assertRaisesRegex(ValueError, "source SHA"):
                package(root, root / "output", "v0.1.0-alpha.1", "a" * 40, "must-not-run", "b" * 64)

    def test_real_git_checkout_rejects_untracked_resource_before_export(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            subprocess.run(["git", "init", "--quiet", str(root)], check=True)
            (root / "main.tscn").write_text('[gd_scene format=3]\n[node name="Main" type="Node"]\n')
            subprocess.run(["git", "add", "."], cwd=root, check=True)
            subprocess.run(["git", "-c", "user.name=fixture", "-c", "user.email=fixture@example.invalid", "commit", "--quiet", "-m", "fixture"], cwd=root, check=True)
            sha = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=root, text=True).strip()
            (root / "extra.tscn").write_text('[gd_scene format=3]\n[node name="Extra" type="Node"]\n')
            with self.assertRaisesRegex(ValueError, "uncommitted"):
                package(root, root / "output", "v0.1.0-alpha.1", sha, "must-not-run", "b" * 64)


class PackageIntegrationTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name) / "source"
        self.output = Path(temporary.name) / "output"
        self.version = "v0.1.0-alpha.1"
        self.source_sha = "a" * 40
        self.engine_hash = "b" * 64
        self.engine = "4.7.2.stable.official.test"
        self.lfs_files = "c" * 64 + " * scenes/combat/audio/hit.ogg"
        self.pck = b"packed game"
        self.verification = "PCK_CONTENT_VERIFIED"
        self.files = {"COPYRIGHT.md": b"copyright", "THIRD_PARTY_NOTICES.md": b"notices",
                      "scenes/combat/audio/kenney_license.txt": b"CC0",
                      "scenes/combat/item_data.json": b'{"items": []}\n',
                      "export_presets.cfg": b'[preset.0]\nname="Verification PCK"\n'}
        for name, data in self.files.items():
            path = self.root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(data)

    def fake_command(self, argv, cwd):
        responses = {("git", "rev-parse", "HEAD"): self.source_sha,
                     ("git", "status", "--porcelain", "--untracked-files=all"): "",
                     ("godot", "--version"): self.engine,
                     ("git", "lfs", "ls-files", "--long"): self.lfs_files,
                     ("git", "lfs", "fsck"): "",
                     ("git", "ls-files"): "\n".join(self.files),
                     ("godot", "--headless", "--path", str(self.root), "--import"): ""}
        if tuple(argv) in responses:
            return responses[tuple(argv)]
        if "--export-pack" in argv:
            if self.pck is not None:
                Path(argv[-1]).write_bytes(self.pck)
            return ""
        if "--script" in argv:
            self.assertNotEqual(cwd, self.root)
            return self.verification
        if "--quit-after" in argv:
            self.assertNotEqual(cwd, self.root)
            return ""
        self.fail(f"Unexpected command: {argv}")

    def test_generated_archive_round_trip(self):
        with patch("package_pck.command", side_effect=self.fake_command):
            archive = package(self.root, self.output, self.version, self.source_sha, "godot", self.engine_hash)
        self.assertEqual(archive, self.output / f"bglike-{self.version}-pck.zip")
        payloads = {"bglike.pck": self.pck, "COPYRIGHT.md": self.files["COPYRIGHT.md"],
                    "THIRD_PARTY_NOTICES.md": self.files["THIRD_PARTY_NOTICES.md"],
                    "kenney_license.txt": self.files["scenes/combat/audio/kenney_license.txt"]}
        with zipfile.ZipFile(archive) as bundle:
            self.assertCountEqual(bundle.namelist(), [*payloads, "metadata.json", "RUN.txt"])
            self.assertIsNone(bundle.testzip())
            for name, data in payloads.items():
                self.assertEqual(bundle.read(name), data)
            metadata = json.loads(bundle.read("metadata.json"))
            self.assertEqual(metadata, {
                "version": self.version, "source_sha": self.source_sha, "engine": self.engine,
                "engine_archive_sha256": self.engine_hash, "preset": "Verification PCK",
                "preset_sha256": hashlib.sha256(self.files["export_presets.cfg"]).hexdigest(),
                "lfs_files": [self.lfs_files], "lfs_fsck": "passed",
                "item_data_sha256": hashlib.sha256(self.files["scenes/combat/item_data.json"]).hexdigest(),
                "smoke": "headless isolated main-pack and resource verification passed",
                "files": {name: hashlib.sha256(data).hexdigest() for name, data in payloads.items()}})
            self.assertIn(b"Godot --main-pack bglike.pck", bundle.read("RUN.txt"))
        checksums = self.output / "SHA256SUMS"
        self.assertEqual(checksums.read_text(), f"{hashlib.sha256(archive.read_bytes()).hexdigest()}  {archive.name}\n")
        self.assertEqual(verify_bundle(self.output, self.version, self.source_sha, self.engine_hash), [archive, checksums])

    def test_missing_or_empty_pck_is_rejected_without_artifacts(self):
        for pck in [None, b""]:
            with self.subTest(pck=pck), patch("package_pck.command", side_effect=self.fake_command):
                self.pck = pck
                with self.assertRaisesRegex(ValueError, "Export did not create a PCK"):
                    package(self.root, self.output, self.version, self.source_sha, "godot", self.engine_hash)
                self.assertFalse(self.output.exists())

    def test_missing_content_verification_is_rejected_without_artifacts(self):
        self.verification = "Godot exited successfully"
        with patch("package_pck.command", side_effect=self.fake_command):
            with self.assertRaisesRegex(ValueError, "Missing PCK content verification"):
                package(self.root, self.output, self.version, self.source_sha, "godot", self.engine_hash)
        self.assertFalse(self.output.exists())


if __name__ == "__main__":
    unittest.main()
