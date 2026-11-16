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

    def test_balanced_parentheses_angle_destinations_and_quoted_titles(self):
        self.write("docs/dir/a(1).md", "# 제목\n")
        self.write("docs/dir/space name.md", "# 제목\n")
        self.write("docs/a.md", "[p](dir/a(1).md) [q](<dir/space name.md>) [r](dir/a(1).md 'title') "
                                "![alt [nested]](dir/a(1).md) [s](<dir/gone name.md>)\n")
        self.assertEqual(self.problems(), ["docs/a.md:1: 링크 대상이 없음: dir/gone name.md"])

    def test_html_attributes_are_checked(self):
        self.write("docs/a.md", '<img src="gone.png"> <a href="https://example.com">x</a> <a href="a.md">ok</a>\n')
        self.assertEqual(self.problems(), ["docs/a.md:1: 링크 대상이 없음: gone.png"])

    def test_fence_with_info_string_does_not_close_a_block(self):
        self.write("docs/a.md", "```\n```python\n[hidden](gone.md)\n```\n[shown](gone.md)\n")
        self.assertEqual(self.problems(), ["docs/a.md:5: 링크 대상이 없음: gone.md"])

    def test_backticks_on_one_line_are_inline_code_not_a_fence(self):
        self.write("docs/a.md", "```not a fence``` [shown](gone.md)\n")
        self.assertEqual(self.problems(), ["docs/a.md:1: 링크 대상이 없음: gone.md"])

    def test_file_deleted_but_still_tracked_is_skipped(self):
        self.write("docs/a.md", "[b](b.md)\n")
        self.write("docs/b.md", "[c](gone.md)\n")
        subprocess.run(["git", "init", "-q"], cwd=self.root, check=True)
        subprocess.run(["git", "add", "-A"], cwd=self.root, check=True)
        (self.root / "docs/b.md").unlink()
        self.assertEqual(check(self.root), ["docs/a.md:1: 링크 대상이 없음: b.md"])

    def test_file_that_is_not_utf8_does_not_crash(self):
        self.write("docs/a.md")
        (self.root / "docs/a.md").write_bytes(b"\xff\xfe\n[x](gone.md)\n")
        self.assertEqual(self.problems(), ["docs/a.md:2: 링크 대상이 없음: gone.md"])

    def test_data_files_are_scanned_for_docs_paths(self):
        self.write("scenes/art/source.json", '{"note": "see docs/PIXEL_ART.md"}\n')
        self.assertEqual(self.problems(), ["scenes/art/source.json:1: docs 경로가 없음: docs/PIXEL_ART.md"])

    def test_slug_follows_github_rules(self):
        self.assertEqual(slug("2-2-2. 2026-10-15 기획 논의 결정"), "2-2-2-2026-10-15-기획-논의-결정")
        self.assertEqual(slug("6. 사각 높이 격자"), "6-사각-높이-격자")
        self.assertEqual(slug("Draft **CD** 와 [링크](x.md)"), "draft-cd-와-링크")
        # Like GitHub, removing a trailing emoji leaves its space behind as a hyphen.
        self.assertEqual(slug("스킬_횟수 ✅"), "스킬_횟수-")

    def test_code_span_closes_only_with_a_run_of_the_same_length(self):
        self.write("docs/a.md", "``[no](missing.md) ` `` 그리고 [yes](a.md)\n")
        self.assertEqual(self.problems(), [])

    def test_emphasis_markers_are_dropped_from_anchors(self):
        self.write("docs/a.md", "[go](#setup) [keep](#스킬_횟수)\n\n## _Setup_\n\n## 스킬_횟수\n")
        self.assertEqual(self.problems(), [])
        self.assertEqual(slug("__init__ 와 *강조*"), "init-와-강조")

    def test_generated_anchor_that_collides_gets_the_next_suffix(self):
        self.write("docs/a.md", "[third](#foo-1-1)\n\n## Foo\n\n## Foo\n\n## Foo-1\n")
        self.assertEqual(self.problems(), [])

    def test_query_string_is_not_part_of_the_file_name(self):
        self.write("docs/a.md", "[source](b.md?plain=1) [gone](c.md?plain=1)\n")
        self.write("docs/b.md", "# 제목\n")
        self.assertEqual(self.problems(), ["docs/a.md:1: 링크 대상이 없음: c.md?plain=1"])

    def test_docs_path_inside_an_external_url_is_not_a_local_reference(self):
        self.write("scripts/tool.py", '"https://example.com/docs/guide.md" docs/gone.md\n')
        self.assertEqual(self.problems(), ["scripts/tool.py:1: docs 경로가 없음: docs/gone.md"])

    def test_repository_doc_links_resolve(self):
        self.assertEqual(check(ROOT), [])


if __name__ == "__main__":
    unittest.main()
