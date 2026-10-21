#!/bin/sh
# mockup.html을 1280×720(배율 2)과 640×360(배율 1) PNG로 저장한다.
cd "$(dirname "$0")"
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
for v in a b c; do
  for s in 2 1; do
    "$CHROME" --headless --disable-gpu --hide-scrollbars --allow-file-access-from-files \
      --window-size=640,360 --force-device-scale-factor=$s \
      --screenshot="$PWD/option-$v-$((640 * s))x$((360 * s)).png" \
      "file://$PWD/mockup.html?v=$v" 2>/dev/null
  done
done
