"""Exercise engine selection and its fail-closed history fallback."""

import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

from ci_scope import game_required, main, select_game


class ScopeTests(unittest.TestCase):
    def test_document_and_known_maintenance_changes(self):
        self.assertFalse(select_game(["README.md", "COPYRIGHT.md", "docs/images/example.png",
                                     ".github/workflows/discord-pr.yml", "scripts/review_context.py"]))

    def test_game_and_unknown_changes(self):
        for path in ["project.godot", "scenes/combat/main.tscn", "tests/combat_hud_test.gd",
                     "scenes/combat/art/floor_tiles.svg", ".gitattributes", "addons/new/plugin.cfg",
                     "scripts/ci_scope.py", "scripts/test_ci_scope.py",
                     ".github/workflows/godot.yml", ".github/workflows/pr-lint.yml", "new.config"]:
            with self.subTest(path=path):
                self.assertTrue(select_game([path]))

    def test_mixed_document_and_game_changes(self):
        self.assertTrue(select_game(["docs/COMBAT_DESIGN.md", "scenes/combat/combat.gd"]))

    def test_missing_or_invalid_base_selects_game(self):
        for event in [{}, {"before": "0" * 40}, {"before": "invalid"}, {"before": 1}]:
            with self.subTest(event=event):
                self.assertTrue(game_required(event))

    def test_missing_git_history_selects_game(self):
        with patch("ci_scope.subprocess.check_output", side_effect=subprocess.CalledProcessError(1, "git")):
            self.assertTrue(game_required({"before": "a" * 40}))

    def test_full_pull_request_diff_uses_no_renames(self):
        with patch("ci_scope.subprocess.check_output", return_value="README.md\n") as run:
            self.assertFalse(game_required({"pull_request": {"base": {"sha": "b" * 40}}}))
            self.assertEqual(run.call_args.args[0], ["git", "diff", "--no-renames", "--name-only", "b" * 40, "HEAD"])

    def test_move_from_game_to_docs_still_selects_game(self):
        original = Path.cwd()
        with tempfile.TemporaryDirectory() as directory:
            try:
                os.chdir(directory)
                def git(*args):
                    return subprocess.check_output(["git", "-c", "user.name=CI Test",
                        "-c", "user.email=ci@example.invalid", "-c", "commit.gpgsign=false", *args],
                        text=True, stderr=subprocess.DEVNULL).strip()
                git("init")
                Path("scenes").mkdir()
                Path("scenes/example.gd").write_text("example\n")
                git("add", ".")
                git("commit", "-m", "baseline")
                base = git("rev-parse", "HEAD")
                Path("docs").mkdir()
                git("mv", "scenes/example.gd", "docs/example.md")
                git("commit", "-m", "move game to docs")
                self.assertTrue(game_required({"before": base}))
            finally:
                os.chdir(original)

    def test_fallback_detects_whitespace_in_a_pull_request_merge(self):
        original = Path.cwd()
        with tempfile.TemporaryDirectory() as directory:
            try:
                os.chdir(directory)
                def git(*args):
                    return subprocess.check_output(["git", "-c", "user.name=CI Test",
                        "-c", "user.email=ci@example.invalid", "-c", "commit.gpgsign=false", *args],
                        text=True, stderr=subprocess.DEVNULL).strip()
                git("init", "-b", "main")
                Path("README.md").write_text("baseline\n")
                git("add", ".")
                git("commit", "-m", "baseline")
                git("checkout", "-b", "feature")
                Path("example.gd").write_text("bad trailing space \n")
                git("add", ".")
                git("commit", "-m", "feature")
                git("checkout", "main")
                git("merge", "--no-ff", "feature", "-m", "PR merge")
                Path("event.json").write_text("{}")
                with patch.dict(os.environ, {"GITHUB_EVENT_PATH": "event.json",
                                            "GITHUB_EVENT_NAME": "pull_request",
                                            "GITHUB_OUTPUT": "output.txt"}):
                    with self.assertRaises(subprocess.CalledProcessError):
                        main()
                self.assertEqual(Path("output.txt").read_text(), "game=true\n")
            finally:
                os.chdir(original)


if __name__ == "__main__":
    unittest.main()
