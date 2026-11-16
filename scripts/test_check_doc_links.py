import subprocess
import tempfile
import unittest
from pathlib import Path

from check_doc_links import check, slug

ROOT = Path(__file__).resolve().parents[1]


class DocLinkTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)

    def write(self, name, text=""):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")

    def problems(self):
        subprocess.run(["git", "init", "-q"], cwd=self.root, check=True)
        subprocess.run(["git", "add", "-A"], cwd=self.root, check=True)
        return check(self.root)

    def test_working_links_images_and_anchors_pass(self):
        self.write("docs/a.md", "[b](b.md) [section](b.md#둘째-절) ![pic](img/pic.png) [dir](img) [root](/docs/b.md)\n")
        self.write("docs/b.md", "# 제목\n\n## 둘째 절\n")
        self.write("docs/img/pic.png")
        self.assertEqual(self.problems(), [])

    def test_missing_file_is_reported_with_its_line(self):
        self.write("docs/a.md", "첫 줄\n[gone](gone.md)\n")
        self.assertEqual(self.problems(), ["docs/a.md:2: 링크 대상이 없음: gone.md"])

    def test_missing_image_is_reported(self):
        self.write("docs/a.md", "![pic](pic.png)\n")
        self.assertEqual(self.problems(), ["docs/a.md:1: 링크 대상이 없음: pic.png"])

    def test_missing_heading_is_reported_for_other_and_same_file(self):
        self.write("docs/a.md", "# 목차\n[x](b.md#없는-절) [y](#없는-절) [z](#목차)\n")
        self.write("docs/b.md", "# 제목\n")
        self.assertEqual(self.problems(), ["docs/a.md:2: 제목이 없음: b.md#없는-절",
                                           "docs/a.md:2: 제목이 없음: #없는-절"])

    def test_anchor_keeps_inline_code_text_in_headings(self):
        self.write("docs/a.md", "[run](#macos-창-실행---mode-macos)\n\n### macOS 창 실행 (`--mode macos`)\n")
        self.assertEqual(self.problems(), [])

    def test_duplicate_headings_get_numbered_anchors(self):
        self.write("docs/a.md", "[one](#메모) [two](#메모-1) [three](#메모-2)\n\n## 메모\n\n## 메모\n")
        self.assertEqual(self.problems(), ["docs/a.md:1: 제목이 없음: #메모-2"])

    def test_code_blocks_and_inline_code_are_ignored(self):
        self.write("docs/a.md", "```\n[no](missing.md)\n```\n`[no](missing.md)` 그리고 [yes](a.md)\n"
                                "\n```\n# 코드 안의 제목\n```\n[hidden](#코드-안의-제목)\n")
        self.assertEqual(self.problems(), ["docs/a.md:9: 제목이 없음: #코드-안의-제목"])

    def test_external_targets_are_not_checked(self):
        self.write("docs/a.md", "[web](https://example.com/x.md) [mail](mailto:a@b.c) [proto](//example.com/y)\n")
        self.assertEqual(self.problems(), [])

    def test_percent_encoded_paths_and_anchors_are_decoded(self):
        self.write("docs/a.md", "[x](my%20note.md#%EC%A0%9C%EB%AA%A9)\n")
        self.write("docs/my note.md", "# 제목\n")
        self.assertEqual(self.problems(), [])

    def test_reference_definitions_are_checked(self):
        self.write("docs/a.md", "[ref]: gone.md\n")
        self.assertEqual(self.problems(), ["docs/a.md:1: 링크 대상이 없음: gone.md"])

    def test_code_references_to_docs_files_are_checked(self):
        self.write("docs/real.md", "# 있음\n")
        self.write("scripts/tool.py", '"""See docs/real.md and docs/gone.md and docs/adr/0003."""\n')
        self.write("tests/case.gd", "# docs/also-gone.png\n")
        self.write("scripts/test_sample.py", "path = 'docs/made-up.md'\n")
        self.assertEqual(self.problems(), ["scripts/tool.py:1: docs 경로가 없음: docs/gone.md",
                                           "tests/case.gd:1: docs 경로가 없음: docs/also-gone.png"])

    def test_slug_follows_github_rules(self):
        self.assertEqual(slug("2-2-2. 2026-10-15 기획 논의 결정"), "2-2-2-2026-10-15-기획-논의-결정")
        self.assertEqual(slug("6. 사각 높이 격자"), "6-사각-높이-격자")
        self.assertEqual(slug("Draft **CD** 와 [링크](x.md)"), "draft-cd-와-링크")
        # Like GitHub, removing a trailing emoji leaves its space behind as a hyphen.
        self.assertEqual(slug("스킬_횟수 ✅"), "스킬_횟수-")

    def test_repository_doc_links_resolve(self):
        self.assertEqual(check(ROOT), [])


if __name__ == "__main__":
    unittest.main()
