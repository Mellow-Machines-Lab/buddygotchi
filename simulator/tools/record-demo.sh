#!/bin/sh
# Records the staged character pack's demo for the simulator's page:
#
#     simulator/tools/record-demo.sh [pixel|gel] [OUT_DIR]
#
# It plays the pack's demo/demo.jsonl through the real headless app, with
# the simulator's board on the Mac as its device (the face named, pixel by
# default), and writes into OUT_DIR (simulator/web/dist/demo):
#   <face>.json       every line the board was sent, with when and what was
#                     happening (DemoRecording), which the page plays back
#   <face>-voice.bin  a voice pack with only the takes it says, when the
#                     pack has a voice
# It takes as long as the demo runs. Needs `make build` and the core
# (firmware/tools/pio.sh run -e native).
set -eu
cd "$(dirname "$0")/../.."
FACE="${1:-pixel}"
OUT="${2:-simulator/web/dist/demo}"
CORE=firmware/.pio/build/native/program
for built in "$CORE" .build/debug/Boop .build/debug/linkkit-bridge; do
    [ -x "$built" ] || { echo "record-demo: $built isn't built (make build; firmware/tools/pio.sh run -e native)" >&2; exit 1; }
done
# Short, for the sockets' sake: a Unix socket's path has room for 103 bytes.
DIR="$(mktemp -d /tmp/boop-demo.XXXXXX)"
trap 'kill $CORE_PID $BRIDGE_PID 2>/dev/null; rm -rf "$DIR"' EXIT
BOOP_SIM_FACE="$FACE" BOOP_SIM_PORT="$DIR/port" "$CORE" --live >/dev/null & CORE_PID=$!
BRIDGE_PID=
for _ in 1 2 3 4 5 6 7 8 9 10; do [ -e "$DIR/port" ] && break; sleep 0.2; done
.build/debug/linkkit-bridge --port "$DIR/port" --socket "$DIR/usb.sock" >/dev/null 2>&1 & BRIDGE_PID=$!
mkdir -p "$OUT"
.build/debug/Boop --headless --state-dir "$DIR/state" --link "usb:$DIR/usb.sock" --socket "$DIR/boop.sock" \
    --no-open --demo pack --record "$OUT/$FACE.json" 2>&1 | grep "demo:" || true
[ -s "$OUT/$FACE.json" ] || { echo "record-demo: nothing was recorded" >&2; exit 1; }
if [ -f .build/voice/voice.bin ]; then
    python3 simulator/tools/voice_subset.py "$OUT/$FACE.json" --out "$OUT/$FACE-voice.bin"
fi
echo "record-demo: $OUT/$FACE.json"
