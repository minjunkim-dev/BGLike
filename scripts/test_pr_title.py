import contextlib
import io
import unittest

from check_pr_title import check_title, main, queued_title


class PrTitleTests(unittest.TestCase):
    def test_valid_titles(self):
        for title in ["feat(combat): add initiative turn order", "fix!: drop old saves", "ci: skip lint on body edits"]:
            with self.subTest(title=title):
                check_title(title, "someone")

    def test_invalid_titles(self):
        for title in ["전투 프로토타입", "Add combat prototype", "feat: Add x", "feature: add x",
                      "fix: add x.", "chore: " + "a" * 70]:
            with self.subTest(title=title), self.assertRaises(ValueError):
                check_title(title, "someone")

    def test_only_dependabot_may_exceed_72(self):
        check_title("chore: " + "a" * 70, "dependabot[bot]")

    def test_queue_commit_title_drops_the_pr_number(self):
        self.assertEqual(queued_title("chore(baseline): sync (#710)\n\nAuthor: x"), "chore(baseline): sync")
        self.assertEqual(main(["queue", "chore: add x (#7)\n\nbody.", "someone"]), 0)
        with contextlib.redirect_stdout(io.StringIO()) as out:
            self.assertEqual(main(["queue", "Bad title (#7)", "someone"]), 1)
        self.assertIn("::error::", out.getvalue())
        self.assertEqual(main(["pr", "chore: add x (#7)", "someone"]), 0)


if __name__ == "__main__":
    unittest.main()
