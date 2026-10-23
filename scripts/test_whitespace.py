import subprocess
import tempfile
import unittest
from pathlib import Path


SCRIPT = Path(__file__).with_name("check_whitespace.py")


class WhitespaceTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.git("init", "-q", "--initial-branch=main")
        self.git("config", "user.name", "Fixture")
        self.git("config", "user.email", "fixture@example.invalid")
        self.git("config", "commit.gpgsign", "false")
        self.git("config", "core.hooksPath", str(self.root / "empty-hooks"))
        self.file = self.root / "sample.txt"
        self.file.write_text("original\n")
        self.git("add", ".")
        self.git("commit", "-qm", "fixture")
        self.git("update-ref", "refs/remotes/origin/main", "HEAD")

    def git(self, *args):
        return subprocess.check_output(["git", *args], cwd=self.root, text=True).strip()

    def check(self, *args):
        return subprocess.run(["python3", str(SCRIPT), *args], cwd=self.root,
                              text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)

    def test_clean_checkout_passes(self):
        result = self.check()
        self.assertEqual(result.returncode, 0, result.stdout)

    def test_committed_eof_error_fails_in_clean_checkout(self):
        self.file.write_text("original\n\n")
        self.git("add", ".")
        self.git("commit", "-qm", "bad whitespace")
        self.assertEqual(self.git("status", "--porcelain"), "")
        result = self.check()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("new blank line at EOF", result.stdout)

    def test_staged_whitespace_fails(self):
        self.file.write_text("staged \n")
        self.git("add", ".")
        result = self.check()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("trailing whitespace", result.stdout)

    def test_unstaged_whitespace_fails(self):
        self.file.write_text("unstaged \n")
        result = self.check()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("trailing whitespace", result.stdout)

    def test_explicit_base_works_without_origin_main(self):
        self.git("update-ref", "-d", "refs/remotes/origin/main")
        result = self.check("--base", "HEAD")
        self.assertEqual(result.returncode, 0, result.stdout)

    def test_missing_default_and_invalid_explicit_base_fail(self):
        self.git("update-ref", "-d", "refs/remotes/origin/main")
        self.assertNotEqual(self.check().returncode, 0)
        self.assertNotEqual(self.check("--base", "missing-ref").returncode, 0)


if __name__ == "__main__":
    unittest.main()
