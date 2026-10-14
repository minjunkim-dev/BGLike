"""Reject oversized or unreachable Bugbot rules using real tracked documents."""

from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

from check_bugbot_rules import REQUIRED, ROOT_RULE, check_rules


class BugbotRulesTests(unittest.TestCase):
    def setUp(self):
        self.folder = tempfile.TemporaryDirectory()
        self.addCleanup(self.folder.cleanup)
        self.root = Path(self.folder.name).resolve()
        subprocess.run(["git", "init", "-q"], cwd=self.root, check=True)
        self.links = "\n".join(f"[{name}](../{name})" for name in sorted(REQUIRED))
        self.write(ROOT_RULE, self.links)
        for name in REQUIRED:
            self.write(name, "rule\n")

    def write(self, name, text, tracked=True):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")
        if tracked:
            subprocess.run(["git", "add", "--", name], cwd=self.root, check=True)

    def test_normal_rules_count_characters_and_deduplicate_cycles(self):
        self.write("AGENTS.md", "한글\n[shared](docs/CI.md)\n[root](.cursor/BUGBOT.md)")
        self.write(ROOT_RULE, self.links + "\n[duplicate](../docs/CI.md)")
        sizes = check_rules(self.root)
        self.assertEqual(set(sizes), REQUIRED | {ROOT_RULE})
        self.assertEqual(sizes["AGENTS.md"], len((self.root / "AGENTS.md").read_text()))

    def test_total_boundary_and_one_extra_character(self):
        remaining = 95_000 - sum(check_rules(self.root).values())
        for name in sorted(REQUIRED):
            text = (self.root / name).read_text()
            extra = min(remaining, 30_000 - len(text))
            self.write(name, text + "x" * extra)
            remaining -= extra
        self.assertEqual(remaining, 0)
        self.assertEqual(sum(check_rules(self.root).values()), 95_000)
        self.write("docs/coding-standards.md", (self.root / "docs/coding-standards.md").read_text() + "x")
        with self.assertRaisesRegex(ValueError, "total 95001 exceeds"):
            check_rules(self.root)

    def test_individual_boundary_and_one_extra_character(self):
        self.write("AGENTS.md", "x" * 30_000)
        self.assertEqual(check_rules(self.root)["AGENTS.md"], 30_000)
        self.write("AGENTS.md", "x" * 30_001)
        with self.assertRaisesRegex(ValueError, "Rule exceeds 30000"):
            check_rules(self.root)

    def test_each_required_document_must_be_reachable_from_root(self):
        for name in REQUIRED:
            with self.subTest(name=name):
                self.write(ROOT_RULE, self.links.replace(f"[{name}](../{name})", ""))
                with self.assertRaisesRegex(ValueError, "not included from root"):
                    check_rules(self.root)

    def test_external_link_cannot_replace_required_local_link(self):
        self.write(ROOT_RULE, self.links.replace("../docs/COMBAT_UIUX.md",
                   "https://github.com/minjunkim-dev/BGLike/blob/main/docs/COMBAT_UIUX.md"))
        with self.assertRaisesRegex(ValueError, "not included from root"):
            check_rules(self.root)

    def test_reference_links_fragment_and_percent_encoded_path(self):
        self.write("docs/space name.mdc", "extra rule")
        self.write(ROOT_RULE, self.links + '\n[extra][Rule File]\n[rule file]: <../docs/space%20name.mdc#part> "title"')
        self.assertIn("docs/space name.mdc", check_rules(self.root))

    def test_code_examples_and_images_do_not_add_rules(self):
        self.write(ROOT_RULE, self.links + "\n`[inline](../missing.md)`\n```md\n[fence](../missing.md)\n```\n"
                   "    [indented](../missing.md)\n![image](../missing.md)")
        self.assertEqual(set(check_rules(self.root)), REQUIRED | {ROOT_RULE})

    def test_nested_roots_count_even_without_root_link(self):
        self.write("scenes/.cursor/BUGBOT.md", "[extra](../../extra.md)")
        self.write("extra.md", "x" * 30_001)
        with self.assertRaisesRegex(ValueError, "Rule exceeds 30000"):
            check_rules(self.root)

    def test_nested_root_cannot_supply_global_required_coverage(self):
        self.write(ROOT_RULE, self.links.replace("[docs/M1_VERIFICATION.md](../docs/M1_VERIFICATION.md)", ""))
        self.write("scenes/.cursor/BUGBOT.md", "[M1](../../docs/M1_VERIFICATION.md)")
        with self.assertRaisesRegex(ValueError, "not included from root"):
            check_rules(self.root)

    def test_missing_untracked_and_symlink_documents_fail(self):
        for kind in ["missing", "untracked", "symlink"]:
            with self.subTest(kind=kind):
                self.write(ROOT_RULE, self.links + "\n[extra](../extra.md)")
                extra = self.root / "extra.md"
                if extra.exists() or extra.is_symlink():
                    extra.unlink()
                if kind == "untracked":
                    self.write("extra.md", "untracked", tracked=False)
                elif kind == "symlink":
                    extra.symlink_to(self.root / "AGENTS.md")
                    subprocess.run(["git", "add", "extra.md"], cwd=self.root, check=True)
                with self.assertRaisesRegex(ValueError, "Missing, untracked or symlink"):
                    check_rules(self.root)

    def test_repository_escape_is_rejected(self):
        self.write(ROOT_RULE, self.links + "\n[outside](../../outside.md)")
        with self.assertRaisesRegex(ValueError, "escapes repository"):
            check_rules(self.root)

    def test_missing_root_and_deleted_required_file_fail(self):
        (self.root / ROOT_RULE).unlink()
        with self.assertRaisesRegex(ValueError, "Missing, untracked or symlink"):
            check_rules(self.root)
        self.write(ROOT_RULE, self.links)
        (self.root / "docs/COMBAT_UIUX.md").unlink()
        with self.assertRaisesRegex(ValueError, "Missing, untracked or symlink"):
            check_rules(self.root)

    def test_cli_returns_nonzero_for_missing_coverage(self):
        self.write(ROOT_RULE, "no links")
        result = subprocess.run([sys.executable, str(Path(__file__).with_name("check_bugbot_rules.py"))],
                                cwd=self.root, text=True, capture_output=True)
        self.assertEqual(result.returncode, 1)
        self.assertIn("not included from root", result.stderr)
        self.assertNotIn("Traceback", result.stderr)


if __name__ == "__main__":
    unittest.main()
