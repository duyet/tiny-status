#!/bin/sh
set -e
feat="${1:-window}"
stamp=$(date +%Y-%m-%d)
dir="$(dirname "$0")/../evidence/${stamp}-${feat}"
mkdir -p "$dir"
wid=$(osascript -e 'tell application "System Events" to tell process "TinyStatus" to get id of window 1' 2>/dev/null || true)
if [ -n "$wid" ]; then
  screencapture -l "$wid" "$dir/window.png"
else
  screencapture -w "$dir/window.png"
fi
echo "wrote $dir/window.png"
