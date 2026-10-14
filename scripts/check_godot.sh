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
for test in tests/combat_turns_test.gd tests/combat_checks_test.gd \
  tests/combat_actions_test.gd tests/combat_hud_test.gd tests/combat_ai_test.gd \
  tests/combat_progression_test.gd tests/combat_loot_test.gd; do
  run_godot --script "$test"
done
