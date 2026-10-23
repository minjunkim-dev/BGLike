#!/usr/bin/env bash
set -euo pipefail
tests=(
  tests/combat_{hud,ai,turns,checks,actions,progression,loot,capture,feedback,save,preparation_save}_test.gd
  tests/{save,title,pause,continue}_test.gd
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
log=$(mktemp)
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
exec python3 - "$godot" "${tests[@]}" <<'PY'
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import time

tests = iter(sys.argv[2:])
active = []
status = 0
def cancel(_signal, _frame):
    raise KeyboardInterrupt
signal.signal(signal.SIGTERM, cancel)
with tempfile.TemporaryDirectory() as directory:
    try:
        pending = True
        while pending or active:
            while pending and len(active) < 2:
                test = next(tests, None)
                if test is None:
                    pending = False
                    break
                log = Path(directory) / Path(test).name
                with log.open("w") as output:
                    process = subprocess.Popen([sys.argv[1], "--headless", "--path", ".", "--script", test],
                                               stdout=output, stderr=subprocess.STDOUT, start_new_session=True)
                active.append((test, process, log))
            for item in active[:]:
                test, process, log = item
                result = process.poll()
                if result is None:
                    continue
                output = log.read_text()
                print(output, end="", flush=True)
                if "SCRIPT ERROR" in output or "Failed to load script" in output:
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
        for _, process, _ in active:
            if process.poll() is None:
                try:
                    os.killpg(process.pid, signal.SIGTERM)
                except ProcessLookupError:
                    pass
        for _, process, _ in active:
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                try:
                    os.killpg(process.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
                process.wait()
sys.exit(status)
PY
