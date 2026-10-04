"""Exercise the actual workflow install script with safe command fixtures."""

import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


WORKFLOW = Path(__file__).resolve().parents[1] / ".github/workflows/godot.yml"
ARCHIVE = b"test fixture for a verified Godot archive"


def step_script(name):
    lines = WORKFLOW.read_text().splitlines()
    start = lines.index(f"      - name: {name}")
    start = lines.index("        run: |", start) + 1
    body = []
    for line in lines[start:]:
        if line and not line.startswith("          "):
            break
        body.append(line[10:] if line else "")
    return "\n".join(body)


FIXTURE = r'''
import hashlib
import json
import os
from pathlib import Path
import sys

command = Path(sys.argv[0]).name
args = sys.argv[1:]
with open(os.environ["BGLIKE_COMMAND_LOG"], "a") as log:
    log.write(json.dumps(command) + "\n")
if command == "curl":
    if os.environ.get("BGLIKE_DOWNLOAD_FAIL") == "1":
        sys.exit(22)
    Path(args[args.index("-o") + 1]).write_bytes(
        bytes.fromhex(os.environ["BGLIKE_DOWNLOAD_HEX"]))
elif command == "sha256sum":
    expected, filename = sys.stdin.read().strip().split("  ", 1)
    actual = hashlib.sha256(Path(filename).read_bytes()).hexdigest()
    print("archive: OK" if expected == actual else "archive: FAILED")
    sys.exit(0 if expected == actual else 1)
elif command == "unzip":
    target = Path(args[args.index("-d") + 1]) / os.environ["GODOT_FILE"]
    target.write_text("#!" + sys.executable + "\n" +
        "import json, os\n" +
        "with open(os.environ['BGLIKE_COMMAND_LOG'], 'a') as log:\n" +
        "    log.write(json.dumps('engine') + '\\n')\n")
'''


class GodotInstallTests(unittest.TestCase):
    def run_install(self, cached=None, downloaded=ARCHIVE, fail_download=False):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            commands = root / "commands"
            commands.mkdir()
            for name in ("curl", "sha256sum", "unzip"):
                fixture = commands / name
                fixture.write_text(f"#!{sys.executable}\n{FIXTURE}")
                fixture.chmod(0o755)
            archive = root / "godot.zip"
            if cached is not None:
                archive.write_bytes(cached)
            log = root / "commands.jsonl"
            output = root / "outputs"
            env = dict(os.environ, PATH=f"{commands}{os.pathsep}{os.environ['PATH']}",
                       RUNNER_TEMP=str(root), GODOT_FILE="fixture_godot",
                       GODOT_SHA256=hashlib.sha256(ARCHIVE).hexdigest(),
                       GITHUB_OUTPUT=str(output), BGLIKE_COMMAND_LOG=str(log),
                       BGLIKE_DOWNLOAD_HEX=downloaded.hex(),
                       BGLIKE_DOWNLOAD_FAIL="1" if fail_download else "0")
            result = subprocess.run(["bash", "-e", "-o", "pipefail", "-c",
                                     step_script("Install Godot 4.7.2")],
                                    env=env, capture_output=True, text=True)
            calls = [json.loads(line) for line in log.read_text().splitlines()]
            outputs = output.read_text() if output.exists() else ""
            return result, calls, outputs

    def assert_not_executed(self, calls):
        self.assertNotIn("unzip", calls)
        self.assertNotIn("engine", calls)

    def test_missing_cache_downloads_and_verifies_before_execution(self):
        result, calls, outputs = self.run_install()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(calls, ["curl", "sha256sum", "unzip", "engine"])
        self.assertIn("archive-source=downloaded", outputs)

    def test_valid_cache_is_verified_without_download(self):
        result, calls, outputs = self.run_install(cached=ARCHIVE)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn("curl", calls)
        self.assertLess(calls.index("sha256sum"), calls.index("unzip"))
        self.assertEqual(calls[-1], "engine")
        self.assertIn("archive-source=restored", outputs)

    def test_corrupt_cache_recovers_once_and_reverifies(self):
        result, calls, outputs = self.run_install(cached=b"corrupt")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(calls, ["sha256sum", "curl", "sha256sum", "unzip", "engine"])
        self.assertIn("archive-source=recovered", outputs)

    def test_invalid_new_download_is_never_extracted_or_executed(self):
        result, calls, outputs = self.run_install(downloaded=b"untrusted")
        self.assertNotEqual(result.returncode, 0)
        self.assert_not_executed(calls)
        self.assertIn("archive-source=downloaded", outputs)

    def test_invalid_recovery_is_not_retried_or_executed(self):
        result, calls, outputs = self.run_install(cached=b"corrupt", downloaded=b"untrusted")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(calls.count("curl"), 1)
        self.assert_not_executed(calls)
        self.assertIn("archive-source=recovered", outputs)

    def test_download_failure_stops_before_execution(self):
        result, calls, outputs = self.run_install(cached=b"corrupt", fail_download=True)
        self.assertNotEqual(result.returncode, 0)
        self.assert_not_executed(calls)
        self.assertIn("archive-source=recovered", outputs)

    def test_failed_restore_is_not_reported_as_a_cache_miss(self):
        with tempfile.TemporaryDirectory() as directory:
            summary = Path(directory) / "summary"
            env = dict(os.environ, GITHUB_STEP_SUMMARY=str(summary),
                       CACHE_HIT="", CACHE_RESULT="failure", ARCHIVE_SOURCE="",
                       INSTALL_RESULT="skipped")
            result = subprocess.run(["bash", "-e", "-o", "pipefail", "-c",
                                     step_script("Record engine cache state")],
                                    env=env, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("cache restore: failure; cache hit: unknown", summary.read_text())


if __name__ == "__main__":
    unittest.main()
