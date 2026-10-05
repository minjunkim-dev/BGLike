#!/usr/bin/env bash
set -euo pipefail
source scripts/godot_environment.sh
mkdir -p "$GODOT_DIR"
godot_archive="$GODOT_DIR/godot.zip"
godot_archive_source=restored
verify_godot_archive() {
  if command -v sha256sum >/dev/null 2>&1; then
    printf '%s  %s\n' "$GODOT_SHA256" "$godot_archive" | sha256sum -c -
  else
    printf '%s  %s\n' "$GODOT_SHA256" "$godot_archive" | shasum -a 256 -c -
  fi
}
if [ ! -f "$godot_archive" ]; then
  godot_archive_source=downloaded
elif ! verify_godot_archive; then
  godot_archive_source=recovered
  printf 'Cached archive failed verification; downloading the official archive again.\n'
  rm -f "$godot_archive"
fi
if [ -n "${GITHUB_OUTPUT:-}" ]; then
  printf 'archive-source=%s\n' "$godot_archive_source" >> "$GITHUB_OUTPUT"
fi
if [ ! -f "$godot_archive" ]; then
  curl -fL --retry 3 --connect-timeout 15 --max-time 120 -o "$godot_archive" \
    "https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-stable/$GODOT_FILE.zip"
fi
verify_godot_archive
unzip -oq "$godot_archive" -d "$GODOT_DIR"
chmod +x "$GODOT_BINARY"
"$GODOT_BINARY" --version
