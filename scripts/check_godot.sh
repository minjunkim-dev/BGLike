#!/usr/bin/env bash
set -euo pipefail
# The save test is the longest by far, so it starts first and the rest take whichever slot frees up.
tests=(
  tests/combat_save_test.gd
  tests/combat_{hud,ai,turns,checks,actions,progression,loot,capture,feedback,preparation_save,staging,dice_roll,warrior,archer}_test.gd
  tests/{save,title,pause,continue,ui_theme}_test.gd
)
if [ "$#" -gt 0 ]; then
  registered=false
  for test_script in "${tests[@]}"; do
    if [ "$#" -eq 1 ] && [ "$1" = "$test_script" ]; then
      registered=true
      break
    fi
  done
  if [ "$registered" != true ]; then
    printf 'Expected one registered Godot test path; omit the argument to run all tests.\n' >&2
    exit 2
  fi
  tests=("$1")
fi
source scripts/godot_environment.sh
godot="${GODOT:-$GODOT_BINARY}"
if [ ! -x "$godot" ]; then
  printf 'Godot is missing: run make godot-install or set GODOT to the pinned editor executable.\n' >&2
  exit 1
fi
actual=$("$godot" --version)
case "$actual" in
  "$GODOT_VERSION.stable.official."*) ;;
  *) printf 'Godot mismatch: expected %s stable official, got %s\n' "$GODOT_VERSION" "$actual" >&2; exit 1 ;;
esac
printf 'Godot: %s\nCommit: %s\n' "$actual" "$(git rev-parse HEAD)"
# Godot exits 0 even when a script fails to parse, so the output decides.
log=$(mktemp "${TMPDIR:-/tmp}/godot.XXXXXX")
trap 'rm -f "$log"' EXIT
run_godot() {
  "$godot" --headless --path . "$@" 2>&1 | tee "$log"
  if grep -qE 'SCRIPT ERROR|Failed to load script' "$log"; then
    printf 'Godot script error during: %s\n' "$*" >&2
    exit 1
  fi
}
run_godot --import
run_godot --quit-after 2
rm -f "$log"
trap - EXIT
# Separate process groups let cancellation stop each owned test and its children.
# Each line is relayed as it arrives with the test name and elapsed time, so a cancelled job still shows where time went.
exec python3 - "$godot" "${tests[@]}" <<'PY'
import os
from pathlib import Path
import signal
import subprocess
import sys
import threading
import time

tests = iter(sys.argv[2:])
active = []
status = 0
lock = threading.Lock()
ERRORS = ("SCRIPT ERROR", "Failed to load script")
def say(name, started, text):
    with lock:
        print(f"[{name} {time.monotonic() - started:.0f}s] {text}", end="", flush=True)
def relay(name, started, process, lines, errored):
    for line in process.stdout:
        lines.append(line)
        if any(error in line for error in ERRORS):
            errored.set()
        # A broken stdout must not stop draining, or Godot blocks on a full pipe.
        try:
            say(name, started, line if line.endswith("\n") else line + "\n")
        except (OSError, UnicodeError):
            pass
spawning = False
deferred = False
def cancel(_signal, _frame):
    global deferred
    # A signal between starting a test and registering it would leave that test unstopped.
    if spawning:
        deferred = True
        return
    raise KeyboardInterrupt
signal.signal(signal.SIGTERM, cancel)
signal.signal(signal.SIGINT, cancel)
try:
    pending = True
    while pending or active:
        while pending and len(active) < 2:
            test = next(tests, None)
            if test is None:
                pending = False
                break
            name = Path(test).stem
            started = time.monotonic()
            lines = []
            errored = threading.Event()
            spawning = True
            process = subprocess.Popen([sys.argv[1], "--headless", "--path", ".", "--script", test],
                                       stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
                                       errors="replace", start_new_session=True)
            reader = threading.Thread(target=relay, args=(name, started, process, lines, errored), daemon=True)
            active.append((test, process, reader, lines, started, errored))
            spawning = False
            if deferred:
                raise KeyboardInterrupt
            say(name, started, "started\n")
            reader.start()
        for item in active[:]:
            test, process, reader, lines, started, errored = item
            result = process.poll()
            stopped = result is None
            if stopped:
                # The error already fails the test, and a scene that failed to compile can await forever.
                if not errored.is_set():
                    continue
                result = 1
            # Leftover children would hold the pipe open and outlive the check.
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            reader.join(timeout=5)
            output = "".join(lines)
            say(Path(test).stem, started, "stopped after a script error\n" if stopped
                else f"finished with exit code {result}\n")
            if reader.is_alive():
                # Unread output could still hold a script error, so it cannot pass.
                print(f"Godot output did not end during: --script {test}", file=sys.stderr)
                result = 1
            elif any(error in output for error in ERRORS):
                print(f"Godot script error during: --script {test}", file=sys.stderr)
                result = 1
            if result:
                status = result if result > 0 else 128 - result
            active.remove(item)
        if active:
            time.sleep(0.02)
except KeyboardInterrupt:
    status = 130
finally:
    # Cancellation often sends a second signal (SIGINT, then SIGTERM); it must not cut cleanup short.
    signal.signal(signal.SIGINT, signal.SIG_IGN)
    signal.signal(signal.SIGTERM, signal.SIG_IGN)
    # The group may outlive an exited test process or ignore SIGTERM, so stop it either way.
    for _, process, _, _, _, _ in active:
        try:
            os.killpg(process.pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    for _, process, _, _, _, _ in active:
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            pass
        try:
            os.killpg(process.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        process.wait()
    for _, _, reader, _, _, _ in active:
        if reader.is_alive():
            reader.join(timeout=1)
sys.exit(status)
PY
