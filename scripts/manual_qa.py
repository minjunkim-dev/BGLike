#!/usr/bin/env python3
"""Preflight and record bounded Forward+ QA offscreen, or on macOS with case-scoped focus consent."""

import argparse
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import signal
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[1]
ERROR = re.compile(r"SCRIPT ERROR|Failed to load script|^ERROR:|\b[1-9][0-9]* failures\b", re.M)
# Same import gate as scripts/check_godot.sh.
IMPORT_ERROR = re.compile(r"SCRIPT ERROR|Failed to load script")
IMAGE = "bglike-qa-offscreen"


def git(*args):
    return subprocess.check_output(["git", *args], cwd=ROOT)


def source_path(value):
    path = (ROOT / value.removeprefix("res://")).resolve()
    if not path.is_relative_to(ROOT) or not path.is_file():
        raise ValueError(f"Missing project input: {value}")
    return path


def load_plan(path):
    plan = json.loads(path.read_text())
    if plan["source_sha"] != git("rev-parse", "HEAD").decode().strip():
        raise ValueError("Plan source_sha differs from HEAD; create a new plan/session")
    ids = set()
    inputs = set(source_path(value) for value in plan.get("inputs", []))
    for case in plan["cases"]:
        name = case["id"]
        if not re.fullmatch(r"[a-z0-9][a-z0-9-]*", name) or name in ids:
            raise ValueError("Case IDs must be unique lowercase names")
        ids.add(name)
        inputs.add(source_path(case["script"]))
        if not case["script"].startswith("res://") or not case["script"].endswith(".gd"):
            raise ValueError("Case script must be a res:// GDScript")
        if not all(isinstance(case.get(key), str) and case[key].strip()
                   for key in ("acceptance", "success_marker")):
            raise ValueError("Each case needs acceptance and a success_marker")
        if not isinstance(case["timeout"], int) or not 0 < case["timeout"] <= 3600:
            raise ValueError("Case timeout must be 1..3600 seconds")
        size = case["resolution"]
        if not isinstance(size, list) or len(size) != 2 or not all(type(n) is int and n > 0 for n in size):
            raise ValueError("Case resolution must be [width, height]")
        if not isinstance(case.get("args", []), list) or not all(isinstance(arg, str) for arg in case.get("args", [])):
            raise ValueError("Case args must be strings")
        if "foreground_approval" in case and (not isinstance(case["foreground_approval"], str)
                                               or not case["foreground_approval"].strip()):
            raise ValueError("Foreground approval needs a nonempty record of the user's consent")
        if "preflight_args" in case or "preflight_success_marker" in case:
            args, marker = case.get("preflight_args"), case.get("preflight_success_marker")
            if (not isinstance(args, list) or not all(isinstance(arg, str) for arg in args)
                    or not isinstance(marker, str) or not marker.strip()):
                raise ValueError("Fixture preflight needs string args and a nonempty success marker")
    if not ids:
        raise ValueError("Plan must contain at least one case")
    # Include dirty and untracked source, plus explicitly listed ignored QA helpers.
    digest = hashlib.sha256(path.read_bytes() + git("diff", "HEAD", "--binary"))
    inputs.update(ROOT / os.fsdecode(name) for name in
                  git("ls-files", "--others", "--exclude-standard", "-z").split(b"\0") if name)
    for item in sorted(inputs):
        digest.update(str(item.relative_to(ROOT)).encode() + b"\0" + item.read_bytes())
    return plan, digest.hexdigest()


def save(directory, state):
    temporary = directory / "state.tmp"
    temporary.write_text(json.dumps(state, ensure_ascii=False, indent=2) + "\n")
    temporary.replace(directory / "state.json")


def native_pids(app, log):
    binary = str(app / "Contents/MacOS/Godot")
    rows = subprocess.check_output(["ps", "-axww", "-o", "pid=,command="], text=True).splitlines()
    found = []
    for row in rows:
        pid, command = row.strip().split(None, 1)
        if command.startswith(binary + " ") and ("--log-file " + str(log) + " ") in command + " ":
            found.append(int(pid))
    return found


def frontmost_pid():
    asn = subprocess.check_output(["lsappinfo", "front"], text=True).strip()
    match = re.search(r'"?pid"?\s*=\s*(\d+)', subprocess.check_output(["lsappinfo", "info", "-only", "pid", asn], text=True))
    return int(match[1]) if match else None


def container_alive(name):
    return bool(subprocess.check_output(["docker", "ps", "-q", "--filter", f"name=^{name}$"], text=True, timeout=5).strip())


def alive(record):
    if "container" in record:
        return container_alive(record["container"])
    return bool(native_pids(Path(record["app"]), Path(record["directory"]) / "game.log"))


def stop_container(name):
    subprocess.run(["docker", "rm", "-f", name], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=5)
    if container_alive(name):
        raise RuntimeError("Owned QA container did not stop")


def stop_native(app, log):
    # A unique log path and executable identify only this attempt, even after PID reuse.
    for signum in (signal.SIGTERM, signal.SIGKILL):
        for pid in native_pids(app, log):
            try:
                os.kill(pid, signum)
            except ProcessLookupError:
                pass
        deadline = time.monotonic() + 2
        while native_pids(app, log) and time.monotonic() < deadline:
            time.sleep(0.05)
    if native_pids(app, log):
        raise RuntimeError("Owned Godot instance did not stop")


def preflight(godot, project, case, log):
    base = [*godot, "--headless", "--path", str(project)]
    commands = [([*base, "--check-only", "--script", case["script"]], log, None)]
    if "preflight_args" in case:
        commands.append(([*base, "--script", case["script"], "--", *case["preflight_args"]],
                         log.with_name("fixture-preflight.log"), case["preflight_success_marker"]))
    for command, output_path, marker in commands:
        with output_path.open("x") as output:
            process = subprocess.Popen(command, stdout=output, stderr=subprocess.STDOUT, start_new_session=True)
            try:
                result = process.wait(timeout=30)
            finally:
                if process.poll() is None:
                    try:
                        os.killpg(process.pid, signal.SIGKILL)
                    except ProcessLookupError:
                        pass
                    process.wait()
        text = output_path.read_text(errors="replace")
        if result or ERROR.search(text) or (marker is not None and marker not in text):
            raise ValueError(f"Preflight failed; game launch blocked: {output_path}")


def docker_preflight():
    try:
        subprocess.run(["docker", "info", "--format", "{{.ServerVersion}}"], check=True, timeout=5,
                       stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    except (OSError, subprocess.SubprocessError) as error:
        raise ValueError(f"Docker connection unavailable (5s limit); inspect OrbStack: {error}") from None


def start_container(name, attempt):
    # The attempt directory is the container's /out, so logs and frames land beside native evidence.
    with (attempt / "container.log").open("x") as output:
        image = subprocess.check_output(["docker", "build", "-q", "-t", IMAGE, "-f", str(ROOT / "scripts/qa_offscreen.Dockerfile"),
                                         str(ROOT / "scripts")], text=True, stderr=output, timeout=1800).strip()
        # No network: the run needs nothing outside, and ignored local files are copied in with the project.
        subprocess.run(["docker", "run", "-d", "--rm", "--init", "--network", "none", "--name", name, "-v", f"{ROOT}:/src:ro",
                        "-v", f"{attempt}:/out", image, "sleep", "infinity"],
                       check=True, stdout=output, stderr=subprocess.STDOUT, timeout=60)
        subprocess.run(["docker", "exec", name, "sh", "-c", "mkdir /work && tar -C /src --exclude=./.godot --exclude=./.git "
                        "--exclude=./.cache --exclude='./.env*' --exclude=./export_credentials.cfg -cf - . | tar -C /work -xf -"],
                       check=True, stdout=output, stderr=subprocess.STDOUT, timeout=300)
    return image


def import_offscreen(name, attempt):
    with (attempt / "import.log").open("x") as output:
        result = subprocess.run(["docker", "exec", name, "godot", "--headless", "--path", "/work", "--import"],
                                stdout=output, stderr=subprocess.STDOUT, timeout=600)
    if result.returncode or IMPORT_ERROR.search((attempt / "import.log").read_text(errors="replace")):
        raise ValueError(f"Offscreen import failed; game launch blocked: {attempt / 'import.log'}")


def launch_offscreen(name, case):
    size = "x".join(map(str, case["resolution"]))
    # No --manual: nothing can send OS input to Xvfb, so the case script drives its own input.
    return subprocess.Popen(["docker", "exec", name, "xvfb-run", "-a", "-s", f"-screen 0 {size}x24",
                             "godot", "--path", "/work", "--rendering-method", "forward_plus",
                             "--rendering-driver", "vulkan", "--resolution", size, "--position", "0,0",
                             "--log-file", "/out/game.log", "--script", case["script"], "--",
                             "--capture-dir=/out/frames", *case.get("args", [])],
                            stdout=subprocess.DEVNULL, stderr=subprocess.STDOUT, start_new_session=True)


def launch(app, case, log, frames):
    return subprocess.Popen(["open", "-g", "-n", "-W", str(app), "--args", "--path", str(ROOT),
                             "--rendering-method", "forward_plus", "--accessibility", "always",
                             "--resolution", "x".join(map(str, case["resolution"])),
                             "--log-file", str(log), "--script", case["script"], "--", "--manual",
                             f"--capture-dir={frames}", *case.get("args", [])],
                            stdout=subprocess.DEVNULL, stderr=subprocess.STDOUT, start_new_session=True)


def run_case(app, case, directory, state, offscreen=False):
    entry = state["cases"][case["id"]]
    attempt = directory / case["id"] / str(len(entry["attempts"]) + 1)
    attempt.mkdir(parents=True)
    log = attempt / "game.log"
    record = {"directory": str(attempt), "started": time.time()}
    if offscreen:
        # The start time keeps a recreated session path from naming (and later removing) an older container.
        record["container"] = "bglike-qa-" + hashlib.sha256(f"{attempt}{record['started']}".encode()).hexdigest()[:16]
    else:
        record["app"] = str(app)
        if case.get("foreground_approval"):
            record["foreground_approval"] = case["foreground_approval"]
    entry["attempts"].append(record)
    entry["status"] = "running"
    save(directory, state)
    launcher = None
    container_attempted = False
    try:
        if offscreen:
            docker_preflight()
            container_attempted = True
            record["image"] = start_container(record["container"], attempt)
            import_offscreen(record["container"], attempt)
            godot, project = ["docker", "exec", record["container"], "godot"], "/work"
        else:
            godot, project = [str(app / "Contents/MacOS/Godot")], ROOT
        version = subprocess.check_output([*godot, "--version"], text=True, timeout=10).strip()
        expected = re.search(r"^GODOT_VERSION=(.+)$", (ROOT / "scripts/godot.env").read_text(), re.M)[1]
        if not version.startswith(expected + ".stable.official."):
            raise ValueError(f"Godot mismatch: {version}")
        preflight(godot, project, case, attempt / "preflight.log")
        if offscreen:
            launcher = launch_offscreen(record["container"], case)
        else:
            launcher = launch(app, case, log, attempt / "frames")
        record["launcher_pid"] = launcher.pid
        save(directory, state)
        deadline = time.monotonic() + case["timeout"]
        while True:
            # open -g may still activate Godot; only this case's recorded consent allows it.
            front = None if offscreen else frontmost_pid()
            if front is not None and front in native_pids(app, log):
                record["foreground_pid"] = front
                if not case.get("foreground_approval"):
                    record["foreground"] = "Godot became the frontmost app; stopping the owned instance"
                    raise ValueError(record["foreground"])
                record["foreground"] = "Owned Godot became frontmost under recorded user approval"
            # Poll before reading so a game that prints its marker and exits is not a false failure.
            exited = launcher.poll() is not None
            output = log.read_text(errors="replace") if log.exists() else ""
            if ERROR.search(output):
                raise ValueError(f"Godot error; discard this attempt's success events: {log}")
            if case["success_marker"] in output:
                if "Forward+" not in output:
                    raise ValueError("Forward+ startup evidence missing")
                entry["status"] = "awaiting_review"
                break
            if exited:
                raise ValueError(f"Game exited without success_marker: {log}")
            if time.monotonic() >= deadline:
                raise ValueError(f"Case timeout: {log}")
            time.sleep(0.1)
    except KeyboardInterrupt:
        entry["status"] = "interrupted"
        raise
    except Exception as error:
        entry["status"] = "failed"
        record["reason"] = str(error)
        raise
    finally:
        try:
            if launcher is not None or container_attempted:
                try:
                    if offscreen:
                        stop_container(record["container"])
                    else:
                        stop_native(app, log)
                finally:
                    if launcher is not None:
                        if launcher.poll() is None:
                            try:
                                os.killpg(launcher.pid, signal.SIGTERM)
                            except ProcessLookupError:
                                pass
                        try:
                            launcher.wait(timeout=5)
                        except subprocess.TimeoutExpired:
                            try:
                                os.killpg(launcher.pid, signal.SIGKILL)
                            except ProcessLookupError:
                                pass
                            launcher.wait()
                # Errors flushed during shutdown still invalidate a success marker.
                if entry["status"] == "awaiting_review" and ERROR.search(log.read_text(errors="replace")):
                    entry["status"] = "failed"
                    raise ValueError(f"Godot error at shutdown: {log}")
        except KeyboardInterrupt:
            entry["status"] = "interrupted"
            record["cleanup_error" if "reason" in record else "reason"] = "Interrupted during process cleanup"
            raise
        except Exception as error:
            entry["status"] = "failed"
            # Keep the original failure (e.g. a stopped Docker daemon) visible beside the cleanup error.
            record["cleanup_error" if "reason" in record else "reason"] = str(error)
            raise
        finally:
            record["finished"] = time.time()
            record["status"] = entry["status"]
            save(directory, state)


def session(plan_path, directory, mode="offscreen"):
    if directory.is_relative_to(ROOT):
        raise ValueError("Store session evidence outside the worktree")
    plan, fingerprint = load_plan(plan_path)
    if mode != "macos" and any("foreground_approval" in case for case in plan["cases"]):
        raise ValueError("Foreground approval is only valid in macos mode")
    path = directory / "state.json"
    if path.exists():
        state = json.loads(path.read_text())
        if state["fingerprint"] != fingerprint:
            raise ValueError("Plan/source inputs changed; preserve this session and use a new directory")
        # Sessions from before the offscreen mode recorded only macOS attempts.
        if state.get("mode", "macos") != mode:
            raise ValueError(f"Session uses {state.get('mode', 'macos')} mode; pass that --mode or use a new directory")
    else:
        state = {"source_sha": plan["source_sha"], "fingerprint": fingerprint, "mode": mode,
                 "cases": {case["id"]: {"status": "not_run", "attempts": []} for case in plan["cases"]}}
        save(directory, state)
    return plan, state


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("run", "status", "accept", "reject"))
    parser.add_argument("plan", type=Path)
    parser.add_argument("directory", type=Path)
    parser.add_argument("--mode", choices=("offscreen", "macos"), default="offscreen",
                        help="offscreen: Docker Xvfb + llvmpipe (default); macos: Godot.app, focus requires case approval")
    parser.add_argument("--app", type=Path, default=Path("/Applications/Godot.app"))
    parser.add_argument("--case")
    parser.add_argument("--evidence", type=Path)
    args = parser.parse_args()
    directory = args.directory.resolve()
    if directory.is_relative_to(ROOT):
        parser.error("Store session evidence outside the worktree")
    directory.mkdir(parents=True, exist_ok=True)
    try:
        with (directory / "session.lock").open("a") as lock:
            try:
                fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError:
                raise ValueError("QA controller is still running; inspect its existing game/state") from None
            plan, state = session(args.plan.resolve(), directory, args.mode)
            for entry in state["cases"].values():
                for previous in entry["attempts"]:
                    if alive(previous):
                        raise ValueError("Previous game is still alive; inspect it before restarting or reviewing")
                if entry["status"] == "running":
                    previous = entry["attempts"][-1]
                    entry["status"] = "interrupted"
                    previous["status"] = "interrupted"
                    previous["reason"] = "Controller stopped before a terminal state"
                    save(directory, state)
            if args.action in ("accept", "reject"):
                entry = state["cases"][args.case]
                if entry["status"] != "awaiting_review" or not args.evidence or not args.evidence.is_file() or not args.evidence.stat().st_size:
                    raise ValueError("Review requires awaiting_review and a nonempty --evidence file")
                entry["status"] = "passed" if args.action == "accept" else "failed"
                entry["attempts"][-1]["status"] = entry["status"]
                entry["attempts"][-1]["review"] = str(args.evidence.resolve())
                save(directory, state)
            elif args.action == "run":
                for case in plan["cases"]:
                    entry = state["cases"][case["id"]]
                    if entry["status"] == "passed":
                        continue
                    if entry["status"] == "awaiting_review":
                        raise ValueError(f"Review {case['id']} captures/input evidence before continuing")
                    run_case(args.app.resolve(), case, directory, state, args.mode == "offscreen")
                    break
            for name, entry in state["cases"].items():
                print(f"{name}: {entry['status']}")
        return 0
    except KeyboardInterrupt:
        print("QA interrupted; evidence preserved", file=sys.stderr)
        return 130
    except (OSError, ValueError, KeyError, TypeError, RuntimeError, subprocess.SubprocessError) as error:
        print(f"QA stopped: {error}", file=sys.stderr)
        return 1


def cancel(_signal, _frame):
    raise KeyboardInterrupt


if __name__ == "__main__":
    signal.signal(signal.SIGTERM, cancel)
    sys.exit(main())
