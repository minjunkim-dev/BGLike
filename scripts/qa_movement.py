"""Replay five controlled movement cases against a verified PCK bundle, without a window."""
import argparse
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import tempfile
import zipfile

from draft_release import verify_bundle
from manual_qa import ERROR, ROOT, cancel, git, load_plan

OUTCOMES = {"multi_step": "arrived", "opportunity_miss": "arrived",
            "opportunity_incapacitated": "interrupted_incapacitated",
            "battle_end": "interrupted_battle_end", "dropped_confirm": "failed"}


def validate(result):
    cases = result["cases"]
    if (result["failures"] != 0 or result["checks"] <= 0
            or [case["case"] for case in cases] != list(OUTCOMES)):
        raise ValueError("Incomplete or failed movement cases")
    for case in cases:
        negative = case["case"] == "dropped_confirm"
        if (case["returned"] is not (not negative) or case["record"]["passed"] is not (not negative)
                or case["record"]["outcome"] != OUTCOMES[case["case"]]
                or case["dice_problems"] or len(case["movement_failures"]) != int(negative)):
            raise ValueError(f"Movement oracle or dice contract failed: {case['case']}")


def run(bundle, version, source_sha, output, godot):
    if output.exists() or output.is_symlink() or output.resolve().is_relative_to(ROOT):
        raise ValueError("Use a new output directory outside the checkout")
    pins = dict(line.split("=", 1) for line in (ROOT / "scripts/godot.env").read_text().splitlines()
                if "=" in line and not line.startswith("#"))
    archive = verify_bundle(bundle, version, source_sha, pins["GODOT_LINUX_X86_64_SHA256"])[0]
    engine = str(Path(shutil.which(godot) or godot).resolve())
    output = output.resolve()
    output.mkdir(parents=True)
    with tempfile.TemporaryDirectory(prefix="bglike-movement-") as folder:
        temporary = Path(folder)
        plan = {"source_sha": git("rev-parse", "HEAD").decode().strip(),
                "inputs": ["tests/scripted_dice.gd", "scripts/qa_movement.py"],
                "cases": [{"id": "movement", "script": "res://tests/movement_qa.gd",
                           "resolution": [1280, 720], "timeout": 30,
                           "acceptance": "Five controlled cases including a rejected confirmation omission",
                           "success_marker": "[MOVEMENT_FIXTURES]"}]}
        plan_path = temporary / "plan.json"
        plan_path.write_text(json.dumps(plan))
        _, fingerprint = load_plan(plan_path)
        with zipfile.ZipFile(archive) as package:
            pck = temporary / "bglike.pck"
            pck.write_bytes(package.read("bglike.pck"))
            pck_hash = json.loads(package.read("metadata.json"))["files"]["bglike.pck"]
        for name in ("movement_qa.gd", "scripted_dice.gd"):
            shutil.copyfile(ROOT / "tests" / name, temporary / name)
        inputs = dict(plan=plan, fingerprint=fingerprint, artifact_source_sha=source_sha,
                      artifact_pck_sha256=pck_hash, bundle=str(bundle.resolve()), version=version, engine=engine)
        (output / "inputs.json").write_text(json.dumps(inputs, indent=2) + "\n")
        environment = {"PATH": os.defpath, "HOME": folder, "TMPDIR": folder,
                       "XDG_DATA_HOME": folder + "/data", "XDG_CONFIG_HOME": folder + "/config",
                       "XDG_CACHE_HOME": folder + "/cache"}
        base = [engine, "--headless", "--audio-driver", "Dummy", "--main-pack", str(pck),
                "--fixed-fps", "60", "--resolution", "1280x720", "--script", str(temporary / "movement_qa.gd")]
        # The five cases are the fixture check itself; there is no initialization-only success phase.
        phases = [("engine", [engine, "--version"]), ("parse", base + ["--check-only"]),
                  ("runtime", base + ["--", f"--out={output}"])]
        for phase, command in phases:
            log = output / (phase + ".log")
            with log.open("x") as stream:
                process = subprocess.Popen(command, cwd=temporary, env=environment, stdout=stream,
                                           stderr=subprocess.STDOUT, start_new_session=True)
                try:
                    code = process.wait(timeout=30)
                finally:
                    if process.poll() is None:
                        try:
                            os.killpg(process.pid, signal.SIGKILL)
                        except ProcessLookupError:
                            pass
                        process.wait()
            text = log.read_text(errors="replace")
            if code or ERROR.search(text):
                raise ValueError(f"Movement {phase} failed; inspect {log}")
            if phase == "engine" and not text.strip().startswith(pins["GODOT_VERSION"] + ".stable.official."):
                raise ValueError("Pinned official Godot required")
        result = json.loads((output / "fixtures.json").read_text())
        validate(result)
        (output / "result.json").write_text(json.dumps(dict(status="passed", checks=result["checks"],
            cases=list(OUTCOMES), fingerprint=fingerprint, artifact_source_sha=source_sha,
            scope="controlled headless movement; no natural play or visual verification"), indent=2) + "\n")
        return result


if __name__ == "__main__":
    signal.signal(signal.SIGTERM, cancel)
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bundle", type=Path, required=True)
    parser.add_argument("--version", required=True)
    parser.add_argument("--source-sha", required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--godot", required=True)
    args = parser.parse_args()
    try:
        result = run(args.bundle, args.version, args.source_sha, args.output, args.godot)
        print(f"Movement QA: {result['checks']} checks, {result['failures']} failures; five cases verified")
    except KeyboardInterrupt:
        parser.exit(130, "Movement QA interrupted; logs preserved\n")
    except (OSError, ValueError, KeyError, TypeError, subprocess.SubprocessError, zipfile.BadZipFile) as error:
        parser.exit(1, f"Movement QA failed: {error}\n")
