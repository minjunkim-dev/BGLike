"""Check the branch diff, index and worktree without changing Git state."""

import argparse
import subprocess


def check(base_ref):
    commit = subprocess.check_output(
        ["git", "rev-parse", "--verify", "--end-of-options", base_ref + "^{commit}"], text=True).strip()
    base = subprocess.check_output(["git", "merge-base", "HEAD", commit], text=True).strip()
    for args in ([base, "HEAD"], ["--cached"], []):
        subprocess.run(["git", "diff", "--check", "--no-renames", *args], check=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base", default="origin/main", help="기준 ref (기본: origin/main)")
    options = parser.parse_args()
    try:
        check(options.base)
    except (OSError, subprocess.CalledProcessError) as error:
        parser.exit(1, f"Whitespace check failed: {error}\n")
