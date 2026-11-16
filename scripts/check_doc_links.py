#!/usr/bin/env python3
"""Fail when a Markdown link, image or docs/ path in code points at nothing (docs/README.md)."""

from pathlib import Path
import re
import subprocess
import sys
from urllib.parse import unquote

FENCE = re.compile(r"^ {0,3}(`{3,}|~{3,})")
INLINE_CODE = re.compile(r"(`+)[^`\n]*?\1")
INLINE_LINK = re.compile(r"!?\[[^\]\n]*\]\(\s*<?([^)\s>]+)>?(?:\s+\"[^\"]*\")?\s*\)")
DEFINITION = re.compile(r"^ {0,3}\[[^\]\n]+\]:\s*<?(\S+?)>?(?:\s+\"[^\"]*\")?\s*$")
HEADING = re.compile(r"^ {0,3}#{1,6}[ \t]+(.*?)(?:[ \t]+#+)?[ \t]*$")
SCHEME = re.compile(r"^(?:[a-zA-Z][a-zA-Z0-9+.-]*:|//)")
# Plain-text references to docs files in code, scripts and workflows. Partial names such as
# "docs/adr/0003" are not checked: only a full file name can be proven missing.
CODE_REFERENCE = re.compile(r"docs/[\w./-]*\w\.(?:md|png|svg)")
CODE_FILES = ("*.gd", "*.py", "*.sh", "*.yml", "Makefile", ".githooks/*")


def tracked(root, *patterns):
    listed = subprocess.run(["git", "ls-files", "-z", "--", *patterns], cwd=root, check=True,
                            capture_output=True, text=True).stdout.split("\0")
    return [name for name in listed if name]


def prose_lines(text):
    """Yield (line number, text) outside fenced code blocks."""
    fence = None
    for number, line in enumerate(text.splitlines(), 1):
        opening = FENCE.match(line)
        if fence is None and opening:
            fence = opening[1][0] * len(opening[1])
        elif fence is not None and opening and opening[1].startswith(fence):
            fence = None
        elif fence is None:
            yield number, line


def slug(heading):
    """GitHub's heading anchor: plain text, lower case, no punctuation, spaces to hyphens."""
    text = re.sub(r"!?\[([^\]]*)\]\([^)]*\)", r"\1", heading)
    text = re.sub(r"<[^>]+>", "", text.replace("`", "").replace("*", "").replace("~~", ""))
    return re.sub(r"[^\w\- ]", "", text.strip().lower()).replace(" ", "-")


def anchors(text):
    seen = {}
    found = set()
    for _, line in prose_lines(text):
        heading = HEADING.match(line)
        if heading:
            base = slug(heading[1])
            count = seen.get(base, 0)
            seen[base] = count + 1
            found.add(base if count == 0 else f"{base}-{count}")
    return found


def link_targets(text):
    for number, line in prose_lines(text):
        for match in INLINE_LINK.finditer(INLINE_CODE.sub("X", line)):
            yield number, match[1]
        definition = DEFINITION.match(line)
        if definition:
            yield number, definition[1]


def check_markdown(root, name, anchor_cache):
    source = (root / name).read_text(encoding="utf-8")
    problems = []
    for number, target in link_targets(source):
        if SCHEME.match(target):
            continue
        path, _, fragment = target.partition("#")
        path = unquote(path)
        if not path:
            resolved = root / name
        elif path.startswith("/"):
            resolved = root / path.lstrip("/")
        else:
            resolved = (root / name).parent / path
        if not resolved.exists():
            problems.append(f"{name}:{number}: 링크 대상이 없음: {target}")
        elif fragment and resolved.suffix == ".md" and resolved.is_file():
            if resolved not in anchor_cache:
                anchor_cache[resolved] = anchors(resolved.read_text(encoding="utf-8"))
            if unquote(fragment).lower() not in anchor_cache[resolved]:
                problems.append(f"{name}:{number}: 제목이 없음: {target}")
    return problems


def check_code_references(root, name):
    problems = []
    for number, line in enumerate((root / name).read_text(encoding="utf-8").splitlines(), 1):
        for reference in CODE_REFERENCE.findall(line):
            if not (root / reference).exists():
                problems.append(f"{name}:{number}: docs 경로가 없음: {reference}")
    return problems


def check(root):
    anchor_cache = {}
    problems = []
    for name in tracked(root, "*.md"):
        problems += check_markdown(root, name, anchor_cache)
    # Tests may use made-up paths as fixtures, so only real code and automation are scanned.
    for name in tracked(root, *CODE_FILES):
        if not Path(name).name.startswith("test_") and not name.startswith("docs/"):
            problems += check_code_references(root, name)
    return problems


def main():
    problems = check(Path(__file__).resolve().parents[1])
    for problem in problems:
        print(problem, file=sys.stderr)
    if problems:
        print("문서를 옮기거나 지웠으면 그 문서를 가리키던 링크와 경로를 함께 고칩니다 (docs/README.md).",
              file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
