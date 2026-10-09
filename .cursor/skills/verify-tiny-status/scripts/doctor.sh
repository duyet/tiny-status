#!/bin/sh
set -e
cd "$(dirname "$0")/../../../.."
test -x TinyStatus.app/Contents/MacOS/TinyStatus
echo "binary ok $(ls -l TinyStatus.app/Contents/MacOS/TinyStatus | awk '{print $5,$6,$7,$8}')"
if pgrep -x TinyStatus >/dev/null; then
  echo "process running pid=$(pgrep -x TinyStatus | tr '\n' ' ')"
else
  echo "process not running"
  exit 1
fi
defaults read net.duyet.tiny-status TinyStatus.density 2>/dev/null || echo "density unset (expect regular default)"
