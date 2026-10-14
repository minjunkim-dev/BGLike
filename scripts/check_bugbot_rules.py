#!/usr/bin/env python3
"""Check repository Bugbot link coverage and conservative rule-size bounds."""

from pathlib import Path
import os
import re
import subprocess
import sys
from urllib.parse import unquote, urlsplit


TOTAL_LIMIT = 95_000
RULE_LIMIT = 30_000
ROOT_RULE = ".cursor/BUGBOT.md"
REQUIRED = {
    "AGENTS.md", "docs/WORKFLOW.md", "docs/GIT_CONVENTIONS.md",
    "docs/coding-standards.md", "docs/agents/review.md", "docs/agents/domain.md",
    "docs/CI.md", "COPYRIGHT.md", "THIRD_PARTY_NOTICES.md", "CONTEXT.md",
    "docs/DRAFT_RELEASE.md", "docs/COMBAT_UIUX.md", "docs/M1_VERIFICATION.md",
}


def markdown_targets(text):
    """Read inline/reference links; examples in code and images are not rules."""
    lines = []
    fence = None
    for line in text.splitlines():
        marker = re.match(r"^ {0,3}(`{3,}|~{3,})", line)
        if marker:
            token = marker[1]
            if fence is None:
                fence = token
            elif token[0] == fence[0] and len(token) >= len(fence):
                fence = None
            continue
        if fence is None and not line.startswith(("    ", "\t")):
            lines.append(line)
    text = re.sub(r"(`+).*?\1", "", "\n".join(lines), flags=re.DOTALL)
    definitions = {}
    for match in re.finditer(r"^ {0,3}\[([^\]\n]+)\]:\s*(<[^>\n]+>|\S+)", text, re.MULTILINE):
        definitions.setdefault(" ".join(match[1].split()).casefold(), match[2])
    text = re.sub(r"^ {0,3}\[[^\]\n]+\]:[^\n]*", "", text, flags=re.MULTILINE)
    for match in re.finditer(r"(?<![!\\])\[[^\n]*?\]\(\s*(<[^>\n]+>|[^\s)]+)(?:\s+[^\n]*?)?\)", text):
        yield match[1].strip("<>")
    for match in re.finditer(r"(?<![!\\])\[([^\]\n]+)\](?:\[([^\]\n]*)\])?(?!\()", text):
        label = " ".join((match[2] or match[1]).split()).casefold()
        if label in definitions:
            yield definitions[label].strip("<>")


def check_rules(root):
    root = root.resolve()
    tracked = set(subprocess.check_output(
        ["git", "ls-files", "-z"], cwd=root, text=True).split("\0")) - {""}
    if ROOT_RULE not in tracked:
        raise ValueError(f"Missing tracked root rule: {ROOT_RULE}")
    texts = {}

    def document(name):
        path = root / name
        if name not in tracked or not path.is_file() or path.resolve() != path:
            raise ValueError(f"Missing, untracked or symlink rule: {name!r}")
        if name not in texts:
            texts[name] = path.read_text(encoding="utf-8")
        return texts[name]

    def closure(seeds):
        pending = list(seeds)
        seen = set()
        while pending:
            name = pending.pop()
            if name in seen:
                continue
            seen.add(name)
            for target in markdown_targets(document(name)):
                url = urlsplit(target)
                if url.scheme or url.netloc or url.path.startswith("/") or not url.path:
                    continue
                path = unquote(url.path, errors="strict")
                if Path(path).suffix not in {".md", ".mdc"}:
                    continue
                if url.query or "\0" in path or "\\" in path:
                    raise ValueError(f"Unsupported rule link in {name!r}: {target!r}")
                resolved = Path(os.path.normpath(root / name / ".." / path))
                if not resolved.is_relative_to(root):
                    raise ValueError(f"Rule link escapes repository in {name!r}: {target!r}")
                pending.append(resolved.relative_to(root).as_posix())
        return seen

    reachable = closure([ROOT_RULE])
    missing = REQUIRED - reachable
    if missing:
        raise ValueError(f"Required rules are not included from root: {sorted(missing)!r}")
    # Count all nested roots together, even if a particular PR visits fewer scopes.
    roots = {name for name in tracked if name == ROOT_RULE or name.endswith("/" + ROOT_RULE)}
    included = closure(roots)
    sizes = {name: len(texts[name]) for name in included}
    oversized = {name: size for name, size in sizes.items() if size > RULE_LIMIT}
    if oversized:
        raise ValueError(f"Rule exceeds {RULE_LIMIT} characters: {oversized!r}")
    total = sum(sizes.values())
    if total > TOTAL_LIMIT:
        raise ValueError(f"Rule total {total} exceeds {TOTAL_LIMIT} characters")
    return sizes


def main():
    try:
        sizes = check_rules(Path.cwd())
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        print(f"Bugbot rules FAILED: {error}", file=sys.stderr)
        return 1
    print(f"Bugbot rules PASS: {len(sizes)} documents, {sum(sizes.values())}/{TOTAL_LIMIT} characters; "
          f"largest {max(sizes.values())}/{RULE_LIMIT}; required root coverage complete")
    return 0


if __name__ == "__main__":
    sys.exit(main())
