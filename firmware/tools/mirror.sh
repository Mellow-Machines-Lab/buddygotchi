#!/bin/sh
# Builds the Mac's mirror of the board (characters/CHARACTER.md §9): the
# firmware for a board with no hardware (src/board/mirror/), with the face
# a character pack gives the AMOLED, as WebAssembly, into the pack's
# mac/mirror/board.js, which its page there loads. Only code that ships:
# the firmware's portable code, LinkKit's device library, ArduinoJson and
# the pack's firmware. Needs Emscripten (`brew install emscripten`).
#
#   firmware/tools/mirror.sh            Boop's pack: characters/boop/mac/mirror/board.js
#   firmware/tools/mirror.sh PACK       another pack's
#   firmware/tools/mirror.sh --check    builds it again and checks it's the
#                                       one checked in, byte for byte
set -eu
cd "$(dirname "$0")/../.."

CHECK=
if [ "${1:-}" = --check ]; then CHECK=1; shift; fi
PACK=${1:-boop}
command -v em++ >/dev/null || { echo "mirror: no em++ here. Install Emscripten: brew install emscripten" >&2; exit 1; }

# The pack's firmware as staging makes it (moods.h, rig_tables.h), beside
# what's staged, which stays as it is; and the face it gives the AMOLED.
STAGE=.character-build/mirror/$PACK
python3 characters/charactergen.py --firmware-to="$STAGE" "characters/$PACK" >/dev/null
FW=$STAGE/firmware
FACE=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("faces", {}).get("amoled206", ""))' "characters/$PACK/character.json")
[ -n "$FACE" ] && [ -d "$FW/src/render/$FACE" ] || { echo "mirror: the $PACK pack gives the AMOLED no face" >&2; exit 1; }
# ArduinoJson, as PlatformIO fetched it for the native env.
JSON=firmware/.pio/libdeps/native/ArduinoJson/src
[ -d "$JSON" ] || firmware/tools/pio.sh pkg install -e native >/dev/null

OUT=characters/$PACK/mac/mirror
[ -n "$CHECK" ] && OUT=$(mktemp -d)
SOURCES="$(find firmware/src/render firmware/src/app firmware/src/voice firmware/src/board/hosted firmware/src/board/mirror \
  "$FW/src/render/$FACE" linkkit/device/src -name '*.cpp' | LC_ALL=C sort)
$FW/src/render/make_face.cpp"
# shellcheck disable=SC2086
em++ -std=c++17 -O2 -DBOOP_FACE_$(echo "$FACE" | tr '[:lower:]' '[:upper:]') \
    -Ifirmware/src -Ifirmware/assets -I"$FW/include" -I"$FW/src" -Ilinkkit/device/src -I"$JSON" \
    $SOURCES \
    -sMODULARIZE -sEXPORT_NAME=BoopMirrorBoard -sENVIRONMENT=web,node -sSINGLE_FILE -sFILESYSTEM=0 \
    -sALLOW_MEMORY_GROWTH -sEXPORTED_RUNTIME_METHODS=cwrap,HEAPU8,UTF8ToString --no-entry \
    -o "$OUT/board.js"

if [ -n "$CHECK" ]; then
  if cmp -s "$OUT/board.js" "characters/$PACK/mac/mirror/board.js"; then
    echo "MIRROR PASS: characters/$PACK/mac/mirror/board.js is the build of its sources"
    rm -rf "$OUT"
  else
    echo "MIRROR FAIL: characters/$PACK/mac/mirror/board.js isn't the build of its sources: run firmware/tools/mirror.sh $PACK (emcc $(em++ -dumpversion))" >&2
    rm -rf "$OUT"
    exit 1
  fi
else
  ls -l "$OUT/board.js"
fi
