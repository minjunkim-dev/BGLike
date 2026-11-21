"""Merge queue check: the queued PR head must be the head its review recorded (POLICY §5).

Run it in a `merge_group` job. GitHub names the queue branch `gh-readonly-queue/<base>/pr-<N>-<SHA>`; that
SHA is the queue base, not the PR head, so only N is read from it. The script reads the PR head and body with
`gh api` and compares the head with the last 「리뷰한 head와 되돌리기:」 line in the body (prompts/review.md 「보고」).
A push to a queued PR removes it from the queue, so the head read here is the head that was queued.

This catches a head that moved after review. It is not a security boundary: anyone who can edit the PR body
can write any SHA there. Two kinds of PR carry no review and pass:
- Dependabot, by the queue commit's author email (no other account can claim that noreply address).
- repo-baseline sync PRs: the Author line names tools/sync_consumers.py, the base already has the manifest
  (migration PRs need review), and every changed path is the manifest or a path the base manifest records
  (POLICY §5 lets those go to the queue without review).

Usage (environment): QUEUE_REF, QUEUE_AUTHOR, BASE_SHA, GITHUB_REPOSITORY, GH_TOKEN.
"""

import json
import os
import re
import subprocess
import sys

DEPENDABOT = "49699333+dependabot[bot]@users.noreply.github.com"
MANIFEST = ".github/repo-baseline.json"
SYNC_AUTHOR = "tools/sync_consumers.py"


def queued(ref):
    """The PR number from a merge queue ref (`refs/heads/` optional), or None."""
    match = re.fullmatch(r"(?:refs/heads/)?gh-readonly-queue/.+/pr-([0-9]+)-[0-9a-f]{40}", ref or "")
    return match.group(1) if match else None


def reviewed_head(body):
    """The SHA on the last 「리뷰한 head와 되돌리기:」 line, or None. Later review rounds come last."""
    lines = re.findall(r"^리뷰한 head와 되돌리기:(.*)$", (body or "").replace("\r\n", "\n"), re.M)
    match = re.match(r"\s*`?([0-9a-f]{40})\b", lines[-1]) if lines else None
    return match.group(1) if match else None


def managed_paths(manifest_text):
    """Paths a sync PR may change: the manifest, its copied files, and its block targets."""
    if not manifest_text:
        return set()
    manifest = json.loads(manifest_text)
    paths = {MANIFEST, *manifest.get("files", {})}
    paths.update(block["target"] for block in manifest.get("blocks", {}).values() if "target" in block)
    return paths


def is_sync(body, changed, manifest_text):
    author = next((line for line in (body or "").splitlines() if line.startswith("Author:")), "")
    allowed = managed_paths(manifest_text)
    return SYNC_AUTHOR in author and bool(changed) and set(changed) <= allowed


def verdict(ref, head, author_email, body, changed, manifest_text):
    """None when the queued head may merge, else the reason it may not.

    manifest_text is the base commit's manifest, so a migration PR (no manifest in base) is not a sync PR.
    """
    number = queued(ref)
    if not number:
        return f"머지 큐 브랜치 이름을 읽지 못했습니다: {ref!r}"
    if author_email == DEPENDABOT:
        return None
    if is_sync(body, changed, manifest_text):
        return None
    review = reviewed_head(body)
    if not review:
        return f"PR #{number} 본문 Review 칸에 「리뷰한 head와 되돌리기:」 SHA가 없습니다."
    if review != head:
        return (f"PR #{number}을 큐에 넣은 head {head[:12]}가 리뷰한 head {review[:12]}와 다릅니다. "
                "새 head를 다른 컨텍스트가 다시 리뷰하고 그 SHA로 큐에 넣습니다.")
    return None


def main():
    ref = os.environ.get("QUEUE_REF", "")
    number = queued(ref)
    head = body = manifest = ""
    changed = []
    if number:
        pr = json.loads(subprocess.check_output(
            ["gh", "api", f"repos/{os.environ['GITHUB_REPOSITORY']}/pulls/{number}",
             "--jq", "{head: .head.sha, body: (.body // \"\")}"], text=True))
        head, body = pr["head"], pr["body"]
        base = os.environ["BASE_SHA"]
        changed = subprocess.check_output(["git", "diff", "--no-renames", "--name-only", "-z", base, "HEAD"],
                                          text=True).split("\0")[:-1]
        shown = subprocess.run(["git", "show", f"{base}:{MANIFEST}"], capture_output=True, text=True)
        manifest = shown.stdout if shown.returncode == 0 else ""
    reason = verdict(ref, head, os.environ.get("QUEUE_AUTHOR", ""), body, changed, manifest)
    if reason:
        print(f"::error::{reason}")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
