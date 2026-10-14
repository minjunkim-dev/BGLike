#!/usr/bin/env bash
set -euo pipefail
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
logs=$(mktemp -d)
pids=()
trap 'for pid in ${pids[@]+"${pids[@]}"}; do kill "$pid" 2>/dev/null || true; wait "$pid" 2>/dev/null || true; done; rm -rf "$logs"' EXIT
run_godot() {
  local log status=0
  log=$(mktemp "$logs/check.XXXXXX")
  "$godot" --headless --path . "$@" 2>&1 | tee "$log" || status=$?
  if grep -qE 'SCRIPT ERROR|Failed to load script' "$log"; then
    printf 'Godot script error during: %s\n' "$*" >&2
    return 1
  fi
  return "$status"
}
run_godot --import
run_godot --quit-after 2
run_tests() {
  local test
  for test in "$@"; do
    run_godot --script "$test" || return $?
  done
}
# Import owns the shared resource cache; independent tests use two bounded lanes.
run_tests tests/combat_hud_test.gd tests/combat_turns_test.gd tests/combat_actions_test.gd &
pids+=("$!")
run_tests tests/combat_ai_test.gd tests/combat_checks_test.gd \
  tests/combat_progression_test.gd tests/combat_loot_test.gd &
pids+=("$!")
status=0
for pid in "${pids[@]}"; do
  wait "$pid" || status=$?
done
pids=()
exit "$status"
