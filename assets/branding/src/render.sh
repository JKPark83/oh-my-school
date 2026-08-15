#!/bin/bash
# usage: render.sh <html> <out.png> <w> <h>
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
"$CHROME" --headless=new --disable-gpu --hide-scrollbars --no-sandbox \
  --force-device-scale-factor=1 --default-background-color=00000000 \
  --virtual-time-budget=3000 \
  --window-size="$3,$4" --screenshot="$2" "file://$1" 2>/dev/null
ls -l "$2"
