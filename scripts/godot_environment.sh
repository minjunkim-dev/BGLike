#!/usr/bin/env bash
# Source this file from the repository root.
source "${GODOT_CONFIG:-scripts/godot.env}"
case "$(uname -s)/$(uname -m)" in
  Linux/x86_64) GODOT_PLATFORM=linux.x86_64; GODOT_SHA256=$GODOT_LINUX_X86_64_SHA256 ;;
  Linux/aarch64|Linux/arm64) GODOT_PLATFORM=linux.arm64; GODOT_SHA256=$GODOT_LINUX_ARM64_SHA256 ;;
  Darwin/*) GODOT_PLATFORM=macos.universal; GODOT_SHA256=$GODOT_MACOS_SHA256 ;;
  *) echo 'Supported installation platforms: Linux x86_64/arm64 and macOS.' >&2; return 1 ;;
esac
GODOT_FILE="Godot_v${GODOT_VERSION}-stable_${GODOT_PLATFORM}"
GODOT_DIR="${GODOT_DIR:-${RUNNER_TEMP:-$PWD/.cache/godot/$GODOT_VERSION/$GODOT_PLATFORM}}"
GODOT_BINARY="$GODOT_DIR/$GODOT_FILE"
if [ "$GODOT_PLATFORM" = macos.universal ]; then
  GODOT_BINARY="$GODOT_DIR/Godot.app/Contents/MacOS/Godot"
fi
if [ -n "${GITHUB_OUTPUT:-}" ]; then
  printf 'version=%s\nsha256=%s\nbinary=%s\n' "$GODOT_VERSION" "$GODOT_SHA256" "$GODOT_BINARY" >> "$GITHUB_OUTPUT"
fi
