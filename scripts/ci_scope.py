#!/usr/bin/env python3
"""Skip engine jobs only for known documentation and repository maintenance."""

import json
import os
from pathlib import Path
import re
import subprocess


MAINTENANCE = {
    ".gitignore", ".editorconfig", ".github/dependabot.yml", ".github/ISSUE_TEMPLATE/task.md",
    ".github/workflows/discord-pr.yml", ".github/workflows/claude.yml",
    "scripts/review_context.py", "scripts/review_failure.py",
    "scripts/test_review_context.py", "scripts/test_review_failure.py",
    "scripts/review_report.py", "scripts/test_review_report.py",
}


def select_game(paths):
    return any(not (path.endswith(".md") or path.startswith("docs/") or path in MAINTENANCE)
               for path in paths)


def base_sha(event):
    base = event.get("pull_request", {}).get("base", {}).get("sha") or event.get("before")
    return base if isinstance(base, str) and re.fullmatch(r"[0-9a-f]{40}", base) and set(base) != {"0"} else None


def game_required(event):
    base = base_sha(event)
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
    base = base_sha(event)
    if base and subprocess.run(["git", "cat-file", "-e", base], stdout=subprocess.DEVNULL,
                               stderr=subprocess.DEVNULL).returncode == 0:
        subprocess.run(["git", "diff", "--check", "--no-renames", base, "HEAD"], check=True)
    else:
        subprocess.run(["git", "show", "--check", "--format=", "--diff-merges=first-parent", "HEAD"], check=True)
    print("Game checks selected: " + str(game).lower())


if __name__ == "__main__":
    main()
