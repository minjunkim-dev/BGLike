"""Exercise the merge queue reviewed-head check."""

import json
import unittest

from reviewed_head import DEPENDABOT, reviewed_head, verdict

HEAD = "a" * 40
OTHER = "b" * 40
BASE = "c" * 40
# The SHA in a queue branch name is the queue base, not the PR head (BGLike pr-711 run, 2026-11-20).
REF = f"refs/heads/gh-readonly-queue/main/pr-12-{BASE}"
MANIFEST = json.dumps({"files": {".github/pull_request_template.md": {}},
                       "blocks": {"ops": {"target": "AGENTS.md"}}})


def body(*heads, author="Claude Code / opus"):
    lines = [f"Author: {author}", "## Review"]
    lines += [f"리뷰한 head와 되돌리기: {head}, 쉬움" for head in heads]
    return "\n".join(lines)


class ReviewedHeadTests(unittest.TestCase):
    def test_matching_head_passes(self):
        self.assertIsNone(verdict(REF, HEAD, "me@example.invalid", body(HEAD), ["src/a.py"], ""))

    def test_moved_head_fails(self):
        self.assertIn("다릅니다", verdict(REF, HEAD, "me@example.invalid", body(OTHER), ["src/a.py"], ""))

    def test_last_review_round_wins(self):
        self.assertIsNone(verdict(REF, HEAD, "x", body(OTHER, HEAD), ["a"], ""))
        self.assertIsNotNone(verdict(REF, HEAD, "x", body(HEAD, OTHER), ["a"], ""))

    def test_missing_or_placeholder_review_fails(self):
        for text in ["", body(), "리뷰한 head와 되돌리기: <커밋 SHA>, <쉬움 | 어려움>"]:
            with self.subTest(text=text):
                self.assertIn("없습니다", verdict(REF, HEAD, "x", text, ["a"], ""))

    def test_queue_ref_with_or_without_refs_heads_prefix(self):
        bare = REF.removeprefix("refs/heads/")
        self.assertIsNone(verdict(bare, HEAD, "x", body(HEAD), ["a"], ""))
        self.assertIn("다릅니다", verdict(REF, HEAD, "x", body(BASE), ["a"], ""))

    def test_last_review_line_without_full_sha_fails(self):
        text = body(HEAD) + "\n리뷰한 head와 되돌리기: aaaaaaa, 쉬움"
        self.assertIn("없습니다", verdict(REF, HEAD, "x", text, ["a"], ""))

    def test_unreadable_queue_ref_fails(self):
        self.assertIn("읽지 못했습니다", verdict("main", HEAD, "x", body(HEAD), ["a"], ""))

    def test_dependabot_passes_by_email_only(self):
        self.assertIsNone(verdict(REF, HEAD, DEPENDABOT, "", ["a"], ""))
        self.assertIsNotNone(verdict(REF, HEAD, "dependabot[bot]", "", ["a"], ""))

    def test_sync_pr_passes_only_on_managed_paths(self):
        sync = body(author="스크립트 / 없음 (repo-baseline tools/sync_consumers.py)")
        self.assertIsNone(verdict(REF, HEAD, "x", sync, [".github/repo-baseline.json", "AGENTS.md"], MANIFEST))
        self.assertIsNotNone(verdict(REF, HEAD, "x", sync, [".github/repo-baseline.json", "src/a.py"], MANIFEST))
        # A migration PR: the base has no manifest, so it needs a review.
        self.assertIsNotNone(verdict(REF, HEAD, "x", sync, [".github/repo-baseline.json"], ""))
        self.assertIsNotNone(verdict(REF, HEAD, "x", body(), [".github/repo-baseline.json"], MANIFEST))

    def test_reviewed_head_accepts_backticks_and_crlf(self):
        self.assertEqual(reviewed_head(f"x\r\n리뷰한 head와 되돌리기: `{HEAD}`, 어려움 (이유)\r\n"), HEAD)


if __name__ == "__main__":
    unittest.main()
