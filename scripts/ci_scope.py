#!/usr/bin/env python3
"""Skip engine jobs only for known documentation and repository maintenance."""

import json
import os
from pathlib import Path
import re
import subprocess


MAINTENANCE = {
    ".gitignore", ".editorconfig", ".github/dependabot.yml", ".github/ISSUE_TEMPLATE/task.md",
    ".github/workflows/discord-pr.yml", ".github/repo-baseline.json",
}


def select_game(paths):
    return any(not (path.endswith(".md") or path.startswith("docs/") or path in MAINTENANCE)
               for path in paths)


def base_sha(event):
    base = (event.get("pull_request", {}).get("base", {}).get("sha")
            or event.get("merge_group", {}).get("base_sha") or event.get("before"))
    return base if isinstance(base, str) and re.fullmatch(r"[0-9a-f]{40}", base) and set(base) != {"0"} else None


def diff_base(event):
    """The commit the event's changes start from. A pull request runs on GitHub's test merge, whose first
    parent is the base branch now; the event's base SHA can be older, and main's newer files would count."""
    base = base_sha(event)
    if base and "pull_request" in event and subprocess.run(
            ["git", "rev-parse", "--verify", "-q", "HEAD^2"], stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL).returncode == 0:
        return subprocess.check_output(["git", "rev-parse", "HEAD^1"], text=True).strip()
    return base


def game_required(event):
    base = diff_base(event)
    if not base:
        return True
    try:
        paths = subprocess.check_output(
            ["git", "diff", "--no-renames", "--name-only", base, "HEAD"],
            text=True, stderr=subprocess.DEVNULL,
        ).splitlines()
    except subprocess.CalledProcessError:
        return True
    return select_game(paths)


def main():
    event = json.loads(Path(os.environ["GITHUB_EVENT_PATH"]).read_text())
    # A dispatch requests an engine check even if its selected commit changed only docs.
    game = os.environ["GITHUB_EVENT_NAME"] == "workflow_dispatch" or game_required(event)
    with open(os.environ["GITHUB_OUTPUT"], "a") as output:
        output.write(f"game={str(game).lower()}\n")
    base = diff_base(event)
    if base and subprocess.run(["git", "cat-file", "-e", base], stdout=subprocess.DEVNULL,
                               stderr=subprocess.DEVNULL).returncode == 0:
        subprocess.run(["git", "diff", "--check", "--no-renames", base, "HEAD"], check=True)
    else:
        subprocess.run(["git", "show", "--check", "--format=", "--diff-merges=first-parent", "HEAD"], check=True)
    print("Game checks selected: " + str(game).lower())


if __name__ == "__main__":
    main()
