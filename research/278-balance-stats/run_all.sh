#!/bin/sh
# Usage: run_all.sh <project> <out root> <runs per policy> <parallel>
# Runs autoplay278.gd headless (no window) for both policies.
set -e
P=$1; OUT=$2; N=$3; J=$4
G=${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}
HERE=$(cd "$(dirname "$0")" && pwd)
for policy in nearest mother; do
  i=1; while [ $i -le $N ]; do echo "$policy $i"; i=$((i+1)); done
done | xargs -P "$J" -n 2 sh -c '
  d="'"$OUT"'/$0/$1"; mkdir -p "$d"
  timeout 1800 "'"$G"'" --headless --fixed-fps 60 --disable-vsync --path "'"$P"'" -s "'"$HERE"'/autoplay278.gd" -- --out="$d" --policy=$0 --run=$1 > "$d/stdout.log" 2>&1
  echo "$0 $1 exit=$?"'
