import io
from pathlib import Path
import subprocess
import sys
import unittest

from check_branch_name import check_branch, check_push


class BranchNameTests(unittest.TestCase):
    def test_existing_ci_acceptance_rules(self):
        for branch in ["test/142-pck-bundle-regression", "feat/12-combat-base", "docs/issue-flow",
                       "build/export-preset", "ci/shared-check", "chore/ai-agents",
                       "claude/anything", "codex/anything", "dependabot/github_actions/action-1"]:
            with self.subTest(branch=branch):
                check_branch(branch)

    def test_missing_issue_and_invalid_names_are_rejected(self):
        for branch in ["test/pck-bundle-regression", "feat/combat", "Test/12-combat", "test/12-bad_name",
                       "test/12-double--dash", "test/12-trailing-", "test/12-extra/slash", "", "main",
                       "docs/x", "docs/1invalid", "test/12-valid\nother"]:
            with self.subTest(branch=branch), self.assertRaises(ValueError):
                check_branch(branch)

    def test_destination_branch_is_checked_instead_of_source(self):
        with self.assertRaisesRegex(ValueError, "test/no-issue"):
            check_push(io.StringIO(f"refs/heads/main {'a' * 40} refs/heads/test/no-issue {'0' * 40}\n"), "main")
        check_push(io.StringIO(f"refs/heads/unconventional {'a' * 40} refs/heads/test/142-valid {'0' * 40}\n"), "main")

    def test_default_branch_tags_and_deletions_keep_working(self):
        for length in [40, 64]:
            with self.subTest(length=length):
                check_push(io.StringIO(f"refs/heads/main {'a' * length} refs/heads/main {'0' * length}\n"
                                      f"refs/tags/v1 {'a' * length} refs/tags/v1 {'0' * length}\n"
                                      f"(delete) {'0' * length} refs/heads/old-name {'a' * length}\n"), "main")
        check_push(io.StringIO(""), "main")

    def test_all_refs_are_checked_and_malformed_input_fails(self):
        for data in [f"HEAD {'a' * 40} refs/heads/test/142-valid {'0' * 40}\nHEAD {'a' * 40} refs/heads/invalid {'0' * 40}\n",
                     "not four fields\n", "HEAD invalid refs/heads/main invalid\n"]:
            with self.subTest(data=data), self.assertRaises(ValueError):
                check_push(io.StringIO(data), "main")

    def test_cli_exit_status_for_ci_and_hook_modes(self):
        checker = str(Path(__file__).with_name("check_branch_name.py"))
        for args, data, expected in [(["test/142-valid"], "", 0), (["test/no-issue"], "", 1),
                                     (["--pre-push", "main"], f"HEAD {'a' * 40} refs/heads/invalid {'0' * 40}\n", 1),
                                     (["--pre-push", "main"], "", 0), ([], "", 1)]:
            with self.subTest(args=args):
                result = subprocess.run([sys.executable, checker, *args], input=data, capture_output=True, text=True)
                self.assertEqual(result.returncode, expected, result.stderr)


if __name__ == "__main__":
    unittest.main()
