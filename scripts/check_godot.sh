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
"$godot" --headless --path . --import
"$godot" --headless --path . --quit-after 2
for test in tests/combat_turns_test.gd tests/combat_checks_test.gd \
  tests/combat_actions_test.gd tests/combat_hud_test.gd tests/combat_ai_test.gd; do
  "$godot" --headless --path . --script "$test"
done
