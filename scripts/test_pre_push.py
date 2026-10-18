import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


class PrePushTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.directory = Path(temporary.name)
        self.root = self.directory / "source with spaces"
        self.remote = self.directory / "remote.git"
        self.log = self.directory / "lfs.json"
        self.bin = self.directory / "bin"
        self.bin.mkdir()
        (self.directory / "tmp").mkdir()
        self.env = dict(os.environ, PATH=str(self.bin) + os.pathsep + os.environ["PATH"],
                        LFS_TEST_LOG=str(self.log), LFS_TEST_EXIT="0", TMPDIR=str(self.directory / "tmp"))
        fake_lfs = self.bin / "git-lfs"
        fake_lfs.write_text("#!/usr/bin/env python3\nimport json, os, sys\nfrom pathlib import Path\n"
                            "Path(os.environ['LFS_TEST_LOG']).write_text(json.dumps({'args': sys.argv[1:], 'input': sys.stdin.read()}))\n"
                            "raise SystemExit(int(os.environ['LFS_TEST_EXIT']))\n")
        fake_lfs.chmod(0o755)
        subprocess.run(["git", "init", "--quiet", "--bare", "--object-format=sha1", str(self.remote)], check=True)
        subprocess.run(["git", "init", "--quiet", "--object-format=sha1", "-b", "main", str(self.root)], check=True)
        project = Path(__file__).resolve().parents[1]
        (self.root / ".githooks").mkdir()
        (self.root / "scripts").mkdir()
        shutil.copy2(project / ".githooks/pre-push", self.root / ".githooks/pre-push")
        shutil.copy2(project / "scripts/check_branch_name.py", self.root / "scripts/check_branch_name.py")
        self.git("config", "core.hooksPath", ".githooks")
        self.git("add", ".")
        self.git("-c", "user.name=fixture", "-c", "user.email=fixture@example.invalid", "commit", "--quiet", "-m", "fixture")
        self.git("remote", "add", "origin", str(self.remote))
        self.sha = self.git("rev-parse", "HEAD").stdout.strip()

    def git(self, *args, check=True):
        return subprocess.run(["git", *args], cwd=self.root, env=self.env, check=check, capture_output=True, text=True)

    def test_invalid_destination_and_mixed_push_fail_before_lfs(self):
        for refs in [["HEAD:refs/heads/test/no-issue"],
                     ["HEAD:refs/heads/test/142-valid", "HEAD:refs/heads/test/no-issue"]]:
            with self.subTest(refs=refs):
                result = self.git("push", "origin", *refs, check=False)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("Invalid branch name", result.stderr)
                self.assertFalse(self.log.exists())
                self.assertEqual(self.git("ls-remote", "origin").stdout, "")
                self.assertEqual(list((self.directory / "tmp").iterdir()), [])

    def test_valid_destination_forwards_original_lfs_args_and_stdin(self):
        self.git("push", "origin", "HEAD:refs/heads/test/142-valid")
        call = json.loads(self.log.read_text())
        self.assertEqual(call["args"], ["pre-push", "origin", str(self.remote)])
        self.assertEqual(call["input"], f"HEAD {self.sha} refs/heads/test/142-valid {'0' * 40}\n")
        self.assertIn(self.sha, self.git("ls-remote", "origin", "refs/heads/test/142-valid").stdout)
        self.assertEqual(list((self.directory / "tmp").iterdir()), [])

    def test_default_branch_tag_and_deleting_old_branch_still_call_lfs(self):
        self.git("push", "origin", "HEAD:refs/heads/main", "HEAD:refs/tags/v1")
        call = json.loads(self.log.read_text())
        self.assertEqual(len(call["input"].splitlines()), 2)
        self.assertIn(f"{self.sha}\trefs/heads/main", self.git("ls-remote", "origin").stdout)
        self.assertIn(f"{self.sha}\trefs/tags/v1", self.git("ls-remote", "origin").stdout)
        self.git("--git-dir", str(self.remote), "update-ref", "refs/heads/old-name", self.sha)
        self.git("push", "origin", ":refs/heads/old-name")
        call = json.loads(self.log.read_text())
        self.assertEqual(call["input"], f"(delete) {'0' * 40} refs/heads/old-name {self.sha}\n")
        self.assertEqual(self.git("ls-remote", "origin", "refs/heads/old-name").stdout, "")

    def test_lfs_failure_still_blocks_push(self):
        self.env["LFS_TEST_EXIT"] = "9"
        result = self.git("push", "origin", "HEAD:refs/heads/test/142-valid", check=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertTrue(self.log.exists())
        self.assertEqual(self.git("ls-remote", "origin").stdout, "")
        self.assertEqual(list((self.directory / "tmp").iterdir()), [])


if __name__ == "__main__":
    unittest.main()
