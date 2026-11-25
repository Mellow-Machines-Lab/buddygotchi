#!/bin/sh
# Builds the Mac's mirror of the board (characters/CHARACTER.md §9): the
# firmware for a board with no hardware (src/board/mirror/), with the face
# Boop's pack gives the AMOLED, as WebAssembly (tools/wasm.sh), into the
# pack's mac/mirror/board.js, which its page there loads. Only code that
# ships: the firmware's portable code, LinkKit's device library,
# ArduinoJson and the pack's firmware, which it stages first. Needs
# Emscripten (`brew install emscripten`).
#
#   firmware/tools/mirror.sh            characters/boop/mac/mirror/board.js
#   firmware/tools/mirror.sh --check    builds it again and checks it's the
#                                       one checked in, byte for byte
set -eu
cd "$(dirname "$0")/../.."

CHECK=
if [ "${1:-}" = --check ]; then CHECK=1; fi

MIRROR=characters/boop/mac/mirror/board.js
OUT=characters/boop/mac/mirror
[ -n "$CHECK" ] && OUT=$(mktemp -d)
python3 characters/charactergen.py --stage characters/boop >/dev/null
# One file, the WebAssembly inside it, since the page can't fetch.
firmware/tools/wasm.sh --board amoled206 "$OUT/board.js" firmware/src/board/mirror/mirror.cpp \
    -sEXPORT_NAME=BoopMirrorBoard -sSINGLE_FILE -sFILESYSTEM=0

if [ -n "$CHECK" ]; then
  if cmp -s "$OUT/board.js" "$MIRROR"; then
    echo "MIRROR PASS: $MIRROR is the build of its sources"
    rm -rf "$OUT"
  else
    echo "MIRROR FAIL: $MIRROR isn't the build of its sources: run firmware/tools/mirror.sh (emcc $(em++ -dumpversion))" >&2
    rm -rf "$OUT"
    exit 1
  fi
else
  ls -l "$OUT/board.js"
fi
