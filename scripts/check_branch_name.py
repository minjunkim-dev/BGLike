"""Validate PR branch names or the destination refs received by a pre-push hook."""
import re
import sys


TYPES = "feat|fix|refactor|perf|test|docs|build|ci|chore|revert"
DESCRIPTION = r"[a-z0-9]+(-[a-z0-9]+)*"


def check_branch(branch):
    if re.match(r"^(claude|codex|dependabot)/", branch):
        return
    if not re.fullmatch(rf"(({TYPES})/[0-9]+-{DESCRIPTION}|(docs|build|ci|chore)/[a-z]{DESCRIPTION})", branch):
        raise ValueError(f"Invalid branch name: {branch!r}; expected <type>/<issue>-<description> "
                         "(docs/build/ci/chore may omit the issue)")


def check_push(stream, default_branch):
    for line in stream:
        fields = line.split()
        if len(fields) != 4:
            raise ValueError("Invalid pre-push input: expected four fields")
        local_ref, local_sha, remote_ref, remote_sha = fields
        if not re.fullmatch(r"[0-9a-f]{40}|[0-9a-f]{64}", local_sha) or not re.fullmatch(r"[0-9a-f]{40}|[0-9a-f]{64}", remote_sha):
            raise ValueError("Invalid pre-push object ID")
        if set(local_sha) == {"0"} or not remote_ref.startswith("refs/heads/"):
            continue
        branch = remote_ref.removeprefix("refs/heads/")
        if branch != default_branch:
            check_branch(branch)


def main(argv):
    try:
        if len(argv) == 2 and argv[1] != "--pre-push":
            check_branch(argv[1])
        elif len(argv) == 3 and argv[1] == "--pre-push":
            check_push(sys.stdin, argv[2])
        else:
            raise ValueError("Usage: check_branch_name.py BRANCH | --pre-push DEFAULT_BRANCH")
    except ValueError as error:
        print(f"branch-name: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
