#!/bin/sh
# Builds and uploads the firmware for the board plugged in: the AMOLED,
# on the S3's own USB (/dev/cu.usbmodem*, env amoled206). BOOP_PORT
# picks the port. With more than one board plugged in it stops and asks
# for one of them.
#   firmware/tools/flash.sh            (or `make flash` from the repo root)
set -eu
tools_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

board=amoled206
port=${BOOP_PORT:-}

if [ -z "$port" ]; then
  found=$(ls /dev/cu.usbmodem* 2>/dev/null || true)
  count=$(printf '%s' "$found" | grep -c . || true)
  if [ "$count" -eq 0 ]; then
    echo "flash: no Boop board on USB (looked for /dev/cu.usbmodem*)" >&2
    exit 2
  fi
  if [ "$count" -gt 1 ]; then
    echo "flash: more than one board on USB; pick one with BOOP_PORT=…:" >&2
    printf '%s\n' "$found" | sed 's/^/  /' >&2
    exit 2
  fi
  port=$found
fi

echo "flash: $board on $port"
exec "$tools_dir/pio.sh" run -e "$board" -t upload --upload-port "$port"
