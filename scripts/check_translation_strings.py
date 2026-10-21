#!/usr/bin/env python3
"""Fail when game text bypasses tr() or POT template generation (docs/adr/0001)."""

from pathlib import Path
import re
import subprocess
import sys

HANGUL = re.compile(r"[가-힣]")
WORD = re.compile(r"\w+")
FOLLOWING = re.compile(r"\s*(.?)")
TRANSLATE = {"tr", "tr_n", "atr", "atr_n"}
# Messages for developers only; they never reach the screen.
DEBUG = {"assert", "push_error", "push_warning", "print", "printerr", "prints", "print_debug"}


def untranslated(source):
    """Return (line, literal) for Korean literals outside tr() and debug calls."""
    found = []
    calls = []  # innermost last: function name for "(", "" for "[" and "{"
    previous = ""
    line = 1
    index = 0
    while index < len(source):
        char = source[index]
        if char == "#":
            end = source.find("\n", index)
            index = len(source) if end == -1 else end
            continue
        if char in "\"'":
            quote = source[index:index + 3] if source.startswith(char * 3, index) else char
            end = index + len(quote)
            while end < len(source) and not source.startswith(quote, end):
                end += 2 if source[end] == "\\" else 1
            end += len(quote)
            text = source[index:end]
            # Only a literal that is the call's own argument reaches the POT; tr("a" if b else "c") does not.
            following = FOLLOWING.match(source, end)[1]
            direct = bool(calls) and calls[-1] in TRANSLATE and previous in ("(", ",") and following in (")", ",")
            line_end = source.find("\n", end)
            rest = source[end:len(source) if line_end == -1 else line_end]
            if (HANGUL.search(text) and not direct and not DEBUG.intersection(calls)
                    and "NO_TRANSLATE" not in rest):
                found.append((line, text))
            line += text.count("\n")
            previous = "string"
            index = end
            continue
        elif char in "([{":
            calls.append(previous if char == "(" and previous.isidentifier() else "")
            previous = char
        elif char in ")]}":
            if calls:
                calls.pop()
            previous = char
        elif char.isalpha() or char == "_":
            word = WORD.match(source, index)[0]
            previous = word
            index += len(word)
            continue
        elif char == "\n":
            line += 1
        elif not char.isspace():
            previous = char
        index += 1
    return found


def game_files(root):
    listed = subprocess.run(["git", "ls-files", "-z", "--", "*.gd", "*.tscn"], cwd=root, check=True,
                            capture_output=True, text=True).stdout.split("\0")
    return [name for name in listed if name and not name.startswith("tests/")]


def check(root):
    files = game_files(root)
    settings = (root / "project.godot").read_text(encoding="utf-8")
    sources = re.search(r"^locale/translations_pot_files=(.*)$", settings, re.MULTILINE)
    listed = set(re.findall(r'"res://([^"]+)"', sources[1])) if sources else set()
    problems = [f"{name}: project.godot의 템플릿 생성 대상(translations_pot_files)에 없음"
                for name in files if name not in listed]
    return problems + [f"{name}:{line}: {text}" for name in files if name.endswith(".gd")
                       for line, text in untranslated((root / name).read_text(encoding="utf-8"))]


def main():
    problems = check(Path(__file__).resolve().parents[1])
    for problem in problems:
        print(problem, file=sys.stderr)
    if problems:
        print("화면 문자열은 tr()/tr_n()으로 감싸고 새 장면·스크립트는 템플릿 생성 대상에 넣습니다."
              " 로그·디버그 전용이면 assert/push_error를 쓰거나 같은 줄에 # NO_TRANSLATE를 붙입니다"
              " (docs/adr/0001-gettext-localization.md).", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
