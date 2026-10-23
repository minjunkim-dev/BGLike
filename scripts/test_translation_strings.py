"""Keep Korean screen text behind tr() and in the POT template sources."""

from pathlib import Path
import subprocess
import tempfile
import unittest

from check_translation_strings import check, untranslated

ROOT = Path(__file__).resolve().parents[1]


class UntranslatedTests(unittest.TestCase):
    def test_direct_tr_arguments_pass(self):
        source = ('label.text = tr("턴 종료")\n'
                  'note = tr("피해 %d") % amount\n'
                  'name = TranslationServer.tr("공격")\n'
                  'line = tr_n("%d칸", "%d칸", count) % count\n')
        self.assertEqual(untranslated(source), [])

    def test_bare_or_nested_literals_fail(self):
        source = ('label.text = "턴 종료"\n'
                  'note = tr("%s 장판") % ["불"]\n'
                  'mode = tr("유리" if better else "불리")\n')
        self.assertEqual(untranslated(source), [(1, '"턴 종료"'), (2, '"불"'), (3, '"유리"'), (3, '"불리"')])

    def test_debug_messages_comments_and_marked_lines_pass(self):
        source = ('# 화면 밖 설명\n'
                  'assert(ok, "데이터가 비어 있습니다: %s"\n'
                  '\t% [path])\n'
                  'push_error("읽을 수 없음")\n'
                  'var id := "내부값"  # NO_TRANSLATE\n'
                  'var plain := "Space"\n')
        self.assertEqual(untranslated(source), [])

    def test_quotes_and_escapes_stay_inside_one_literal(self):
        source = ('a = tr("\\"가\\" (b)")\n'
                  "c = '나'\n"
                  'd = tr("""다 "e" 라""")\n')
        self.assertEqual(untranslated(source), [(2, "'나'")])

    def test_line_numbers_follow_multiline_strings(self):
        source = 'var a := """첫\n둘"""\nvar b := "셋"\n'
        self.assertEqual(untranslated(source), [(1, '"""첫\n둘"""'), (3, '"셋"')])


class RepositoryTests(unittest.TestCase):
    def test_unlisted_game_file_fails(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            subprocess.run(["git", "init", "-q"], cwd=root, check=True)
            (root / "project.godot").write_text(
                'locale/translations_pot_files=PackedStringArray("res://listed.gd")\n', encoding="utf-8")
            (root / "listed.gd").write_text('var a := tr("가")\n', encoding="utf-8")
            (root / "new.tscn").write_text("[gd_scene]\n", encoding="utf-8")
            (root / "tests").mkdir()
            (root / "tests" / "case_test.gd").write_text('var a := "검사용"\n', encoding="utf-8")
            subprocess.run(["git", "add", "."], cwd=root, check=True)
            self.assertEqual(check(root), ["new.tscn: project.godot의 템플릿 생성 대상(translations_pot_files)에 없음"])

    def test_repository_screen_text_is_translatable(self):
        self.assertEqual(check(ROOT), [])


if __name__ == "__main__":
    unittest.main()
