#!/usr/bin/env python3
"""Fail when a Markdown link, image or docs/ path in code points at nothing (docs/README.md).

Known limits: link text that spans several lines, CommonMark escapes, fences inside block quotes or
deeply nested lists, and plain-text paths that are not links are not understood.
"""

from pathlib import Path
import re
import subprocess
import sys
from urllib.parse import unquote

FENCE = re.compile(r"^ {0,3}(`{3,}|~{3,})(.*)$")
# A code span closes with a backtick run as long as the one that opened it.
INLINE_CODE = re.compile(r"(?<!`)(`+)(?!`).*?(?<!`)\1(?!`)")
LINK_TEXT = r"\[(?:[^\[\]\n]|\[[^\]\n]*\])*\]"
# Destination: <any text without ">"> or a run without spaces whose parentheses are balanced.
INLINE_LINK = re.compile(r"!?" + LINK_TEXT + r"\(\s*(?:<([^>\n]+)>|((?:[^()\s]|\([^()\s]*\))+))"
                         r"(?:\s+(?:\"[^\"]*\"|'[^']*'))?\s*\)")
HTML_ATTRIBUTE = re.compile(r"""\b(?:href|src)=["']([^"']+)["']""")
DEFINITION = re.compile(r"^ {0,3}\[[^\]\n]+\]:\s*<?(\S+?)>?(?:\s+\"[^\"]*\")?\s*$")
HEADING = re.compile(r"^ {0,3}#{1,6}[ \t]+(.*?)(?:[ \t]+#+)?[ \t]*$")
SCHEME = re.compile(r"^(?:[a-zA-Z][a-zA-Z0-9+.-]*:|//)")
# Plain-text references to docs files in code, scripts and workflows. Partial names such as
# "docs/adr/0003" are not checked: only a full file name can be proven missing.
CODE_REFERENCE = re.compile(r"docs/[\w./-]*\w\.(?:md|png|svg)")
URL = re.compile(r"[a-zA-Z][a-zA-Z0-9+.-]*://\S+")
CODE_FILES = ("*.gd", "*.py", "*.sh", "*.yml", "*.json", "*.cfg", "*.txt", "Makefile", ".githooks/*")


def tracked(root, *patterns):
    """Tracked files that are still on disk: a file deleted but not yet staged is skipped."""
    listed = subprocess.run(["git", "ls-files", "-z", "--", *patterns], cwd=root, check=True,
                            capture_output=True, text=True).stdout.split("\0")
    return [name for name in listed if name and (root / name).is_file()]


def read(path):
    return path.read_text(encoding="utf-8", errors="replace")


def prose_lines(text):
    """Yield (line number, text) outside fenced code blocks."""
    fence = None
    for number, line in enumerate(text.splitlines(), 1):
        match = FENCE.match(line)
        if fence is None:
            # A backtick fence cannot have backticks in its info string: that is inline code.
            if match and not (match[1][0] == "`" and "`" in match[2]):
                fence = match[1][0] * len(match[1])
            else:
                yield number, line
        elif match and match[1].startswith(fence) and not match[2].strip():
            fence = None


def slug(heading):
    """GitHub's heading anchor: plain text, lower case, no punctuation, spaces to hyphens."""
    text = re.sub(r"!?\[([^\]]*)\]\([^)]*\)", r"\1", heading)
    text = re.sub(r"<[^>]+>", "", text.replace("`", "").replace("*", "").replace("~~", ""))
    text = re.sub(r"(?<!\w)_+|_+(?!\w)", "", text)  # emphasis, not the underscore inside a word
    return re.sub(r"[^\w\- ]", "", text.strip().lower()).replace(" ", "-")


def anchors(text):
    seen = {}
    found = set()
    for _, line in prose_lines(text):
        heading = HEADING.match(line)
        if heading:
            base = slug(heading[1])
            count = seen.get(base, 0)
            anchor = base if count == 0 else f"{base}-{count}"
            while anchor in found:  # "Foo", "Foo", "Foo-1": the third heading is already taken
                count += 1
                anchor = f"{base}-{count}"
            seen[base] = count + 1
            found.add(anchor)
    return found


def link_targets(text):
    for number, line in prose_lines(text):
        masked = INLINE_CODE.sub("X", line)
        for match in INLINE_LINK.finditer(masked):
            yield number, match[1] or match[2]
        for match in HTML_ATTRIBUTE.finditer(masked):
            yield number, match[1]
        definition = DEFINITION.match(line)
        if definition:
            yield number, definition[1]


def check_markdown(root, name, anchor_cache):
    problems = []
    for number, target in link_targets(read(root / name)):
        if SCHEME.match(target):
            continue
        path, _, fragment = target.partition("#")
        path = unquote(path.partition("?")[0])  # "b.md?plain=1" is the file b.md
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
                anchor_cache[resolved] = anchors(read(resolved))
            if unquote(fragment).lower() not in anchor_cache[resolved]:
                problems.append(f"{name}:{number}: 제목이 없음: {target}")
    return problems


def check_code_references(root, name):
    problems = []
    for number, line in enumerate(read(root / name).splitlines(), 1):
        urls = [url.span() for url in URL.finditer(line)]
        for match in CODE_REFERENCE.finditer(line):
            if any(start <= match.start() < end for start, end in urls):
                continue  # a docs/ path inside an external URL is not a file of this repository
            if not (root / match[0]).exists():
                problems.append(f"{name}:{number}: docs 경로가 없음: {match[0]}")
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
    try:
        problems = check(Path(__file__).resolve().parents[1])
    except (OSError, subprocess.CalledProcessError) as error:
        print(f"문서 링크 검사를 실행하지 못했습니다: {error}", file=sys.stderr)
        return 1
    for problem in problems:
        print(problem, file=sys.stderr)
    if problems:
        print("문서를 옮기거나 지웠으면 그 문서를 가리키던 링크와 경로를 함께 고칩니다 (docs/README.md).",
              file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
