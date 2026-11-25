#!/bin/sh
# Builds the Mac's mirror of the board (characters/CHARACTER.md §9): the
# firmware for a board with no hardware (src/board/mirror/), with the face
# Boop's pack gives the AMOLED, as WebAssembly (tools/wasm.sh), into the
# pack's mac/mirror/board.js, which its page there loads. Only code that
# ships: the firmware's portable code, LinkKit's device library,
# ArduinoJson and the pack's firmware, which it stages first. Needs
# Emscripten (`brew install emscripten`).
#
#   firmware/tools/mirror.sh             builds characters/boop/mac/mirror/board.js
#   firmware/tools/mirror.sh --if-stale  builds it only when it's missing or older
#                                        than its sources; with no Emscripten
#                                        here it warns and goes on, so a build
#                                        that doesn't show the face still works
#   firmware/tools/mirror.sh --need      as --if-stale, but no Emscripten fails
#
# board.js is a build's output, not checked in (the pack's .gitignore).
set -eu
cd "$(dirname "$0")/../.."

MODE=${1:-}
MIRROR=characters/boop/mac/mirror/board.js
OUT=characters/boop/mac/mirror

if [ "$MODE" = --if-stale ] || [ "$MODE" = --need ]; then
  if [ -f "$MIRROR" ] && [ -z "$(find firmware/src firmware/assets firmware/tools/wasm.sh firmware/tools/mirror.sh \
      firmware/platformio.ini linkkit/device/src characters/boop/firmware characters/boop/character.json \
      characters/boop/rig characters/charactergen.py -newer "$MIRROR" -type f 2>/dev/null | head -1)" ]; then
    exit 0
  fi
  if ! command -v em++ >/dev/null; then
    if [ "$MODE" = --need ]; then
      echo "mirror: $MIRROR needs building and there's no em++ here: brew install emscripten" >&2; exit 1
    fi
    echo "mirror: no em++ here, so $MIRROR isn't built and the Mac shows no face: brew install emscripten" >&2
    exit 0
  fi
fi

python3 characters/charactergen.py --stage characters/boop >/dev/null
# One file, the WebAssembly inside it, since the page can't fetch.
firmware/tools/wasm.sh --board amoled206 "$OUT/board.js" firmware/src/board/mirror/mirror.cpp \
    -sEXPORT_NAME=BoopMirrorBoard -sSINGLE_FILE -sFILESYSTEM=0
ls -l "$OUT/board.js"
