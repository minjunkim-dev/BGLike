"""Verify authorization happens before a job receives credentials."""

import copy
import unittest

from review_context import review_request


REPO = "minjunkim-dev/BGLike"
SHA = "a" * 40


class ReviewTests(unittest.TestCase):
    def setUp(self):
        self.event = {"sender": {"type": "User", "login": "writer"}, "action": "created",
                      "comment": {"body": "@claude review"},
                      "issue": {"number": 29, "pull_request": {"url": "https://api.github.com/repos/minjunkim-dev/BGLike/pulls/29"}}}
        self.responses = {"collaborators/writer/permission": {"permission": "write"},
                          "issues/29": {"state": "open", "labels": [], "pull_request": {"url": "https://api.github.com/repos/minjunkim-dev/BGLike/pulls/29"}},
                          "pulls/29": {"draft": False, "state": "open", "base": {"ref": "main"},
                                       "head": {"repo": {"full_name": REPO}, "sha": SHA}}}
        self.requests = []

    def get(self, endpoint):
        self.requests.append(endpoint)
        return self.responses[endpoint]

    def test_writer_review_records_current_sha(self):
        result, _ = review_request("issue_comment", self.event, REPO, self.get)
        self.assertEqual(result, {"kind": "pr", "number": "29", "sha": SHA, "mode": "review"})

    def test_external_user_is_rejected_before_pr_fetch(self):
        self.responses["collaborators/writer/permission"] = {"permission": "read"}
        self.assertIsNone(review_request("issue_comment", self.event, REPO, self.get)[0])
        self.assertEqual(self.requests, ["collaborators/writer/permission"])

    def test_bot_and_implementation_commands_are_rejected(self):
        for update in [{"sender": {"type": "Bot", "login": "bot"}},
                       {"comment": {"body": "@claude implement this"}},
                       {"comment": {"body": "text before @claude review"}}]:
            with self.subTest(update=update):
                event = copy.deepcopy(self.event)
                event.update(update)
                self.assertIsNone(review_request("issue_comment", event, REPO, self.get)[0])

    def test_fork_draft_closed_and_non_main_are_rejected(self):
        pr = copy.deepcopy(self.responses["pulls/29"])
        for update in [{"draft": True}, {"state": "closed"}, {"base": {"ref": "other"}},
                       {"head": {"repo": {"full_name": "outside/BGLike"}, "sha": SHA}}]:
            with self.subTest(update=update):
                self.responses["pulls/29"] = dict(pr, **update)
                self.assertIsNone(review_request("issue_comment", self.event, REPO, self.get)[0])

    def test_skip_label_is_rejected(self):
        self.responses["issues/29"]["labels"] = [{"name": "ai:skip"}]
        self.assertIsNone(review_request("issue_comment", self.event, REPO, self.get)[0])

    def test_security_review_mode(self):
        self.event["comment"]["body"] = "@claude security review"
        self.assertEqual(review_request("issue_comment", self.event, REPO, self.get)[0]["mode"], "security")

    def test_legacy_claude_label_requests_review(self):
        event = {"sender": self.event["sender"], "action": "labeled", "label": {"name": "claude"},
                 "issue": {"number": 29}}
        self.responses["issues/29"].pop("pull_request")
        result, _ = review_request("issues", event, REPO, self.get)
        self.assertEqual(result["kind"], "issue")

    def test_dispatch_is_rejected_even_for_valid_writer_and_target(self):
        for ref in ["refs/heads/main", "refs/heads/untrusted"]:
            for kind in ["issue", "pr"]:
                event = {"sender": self.event["sender"], "ref": ref,
                         "inputs": {"kind": kind, "number": "29"}}
                with self.subTest(ref=ref, kind=kind):
                    self.assertIsNone(review_request("workflow_dispatch", event, REPO, self.get)[0])

    def test_invalid_sha_is_rejected(self):
        self.responses["pulls/29"]["head"]["sha"] = "invalid"
        self.assertIsNone(review_request("issue_comment", self.event, REPO, self.get)[0])


if __name__ == "__main__":
    unittest.main()
