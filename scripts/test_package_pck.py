from pathlib import Path
import subprocess
import tempfile
import unittest

from package_pck import command, package


class PackageTests(unittest.TestCase):
    def test_command_rejects_real_failure_and_godot_diagnostics(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            for code in ["raise SystemExit(1)", "print('ERROR: broken')", "print('WARNING: missing resource')"]:
                with self.subTest(code=code), self.assertRaises(ValueError):
                    command(["python3", "-c", code], root)
            self.assertEqual(command(["python3", "-c", "print('valid')"], root), "valid")

    def test_real_git_checkout_rejects_wrong_source_before_export(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            subprocess.run(["git", "init", "--quiet", str(root)], check=True)
            (root / "test.txt").write_text("fixture")
            subprocess.run(["git", "add", "."], cwd=root, check=True)
            subprocess.run(["git", "-c", "user.name=fixture", "-c", "user.email=fixture@example.invalid", "commit", "--quiet", "-m", "fixture"], cwd=root, check=True)
            with self.assertRaisesRegex(ValueError, "source SHA"):
                package(root, root / "output", "v0.1.0-alpha.1", "a" * 40, "must-not-run", "b" * 64)

    def test_real_git_checkout_rejects_untracked_resource_before_export(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            subprocess.run(["git", "init", "--quiet", str(root)], check=True)
            (root / "main.tscn").write_text('[gd_scene format=3]\n[node name="Main" type="Node"]\n')
            subprocess.run(["git", "add", "."], cwd=root, check=True)
            subprocess.run(["git", "-c", "user.name=fixture", "-c", "user.email=fixture@example.invalid", "commit", "--quiet", "-m", "fixture"], cwd=root, check=True)
            sha = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=root, text=True).strip()
            (root / "extra.tscn").write_text('[gd_scene format=3]\n[node name="Extra" type="Node"]\n')
            with self.assertRaisesRegex(ValueError, "uncommitted"):
                package(root, root / "output", "v0.1.0-alpha.1", sha, "must-not-run", "b" * 64)


if __name__ == "__main__":
    unittest.main()
