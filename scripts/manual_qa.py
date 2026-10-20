#!/usr/bin/env python3
"""Preflight and record bounded macOS Forward+ QA without activating the game."""

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


def preflight(binary, case, log):
    with log.open("x") as output:
        process = subprocess.Popen([str(binary), "--headless", "--path", str(ROOT),
                                    "--check-only", "--script", case["script"]],
                                   stdout=output, stderr=subprocess.STDOUT, start_new_session=True)
        try:
            result = process.wait(timeout=30)
        finally:
            if process.poll() is None:
                try:
                    os.killpg(process.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
                process.wait()
    if result or ERROR.search(log.read_text(errors="replace")):
        raise ValueError(f"Preflight failed; native launch blocked: {log}")


def launch(app, case, log, frames):
    return subprocess.Popen(["open", "-g", "-n", "-W", str(app), "--args", "--path", str(ROOT),
                             "--rendering-method", "forward_plus", "--accessibility", "always",
                             "--resolution", "x".join(map(str, case["resolution"])),
                             "--log-file", str(log), "--script", case["script"], "--", "--manual",
                             f"--capture-dir={frames}", *case.get("args", [])],
                            stdout=subprocess.DEVNULL, stderr=subprocess.STDOUT, start_new_session=True)


def run_case(app, case, directory, state):
    entry = state["cases"][case["id"]]
    attempt = directory / case["id"] / str(len(entry["attempts"]) + 1)
    attempt.mkdir(parents=True)
    log = attempt / "game.log"
    record = {"directory": str(attempt), "app": str(app), "started": time.time()}
    entry["attempts"].append(record)
    entry["status"] = "running"
    save(directory, state)
    launcher = None
    try:
        binary = app / "Contents/MacOS/Godot"
        version = subprocess.check_output([str(binary), "--version"], text=True, timeout=10).strip()
        expected = re.search(r"^GODOT_VERSION=(.+)$", (ROOT / "scripts/godot.env").read_text(), re.M)[1]
        if not version.startswith(expected + ".stable.official."):
            raise ValueError(f"Godot mismatch: {version}")
        preflight(binary, case, attempt / "preflight.log")
        launcher = launch(app, case, log, attempt / "frames")
        record["launcher_pid"] = launcher.pid
        save(directory, state)
        deadline = time.monotonic() + case["timeout"]
        while True:
            output = log.read_text(errors="replace") if log.exists() else ""
            if ERROR.search(output):
                raise ValueError(f"Godot error; discard this attempt's success events: {log}")
            if case["success_marker"] in output:
                if "Forward+" not in output:
                    raise ValueError("Forward+ startup evidence missing")
                entry["status"] = "awaiting_review"
                break
            if launcher.poll() is not None:
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
            if launcher is not None:
                try:
                    stop_native(app, log)
                finally:
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
            record["reason"] = "Interrupted during process cleanup"
            raise
        except Exception as error:
            entry["status"] = "failed"
            record["reason"] = str(error)
            raise
        finally:
            record["finished"] = time.time()
            record["status"] = entry["status"]
            save(directory, state)


def session(plan_path, directory):
    if directory.is_relative_to(ROOT):
        raise ValueError("Store session evidence outside the worktree")
    plan, fingerprint = load_plan(plan_path)
    path = directory / "state.json"
    if path.exists():
        state = json.loads(path.read_text())
        if state["fingerprint"] != fingerprint:
            raise ValueError("Plan/source inputs changed; preserve this session and use a new directory")
    else:
        state = {"source_sha": plan["source_sha"], "fingerprint": fingerprint,
                 "cases": {case["id"]: {"status": "not_run", "attempts": []} for case in plan["cases"]}}
        save(directory, state)
    return plan, state


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("run", "status", "accept", "reject"))
    parser.add_argument("plan", type=Path)
    parser.add_argument("directory", type=Path)
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
            plan, state = session(args.plan.resolve(), directory)
            for entry in state["cases"].values():
                for previous in entry["attempts"]:
                    if native_pids(Path(previous["app"]), Path(previous["directory"]) / "game.log"):
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
                    run_case(args.app.resolve(), case, directory, state)
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
