#!/bin/sh
# Builds a board with no hardware (src/board/hosted/) to WebAssembly with
# Emscripten: the hosted board and the firmware's portable code it runs,
# as platformio.ini's [hosted] lists them for the native env too,
# LinkKit's device library, ArduinoJson and a character pack's firmware,
# with an entry's own sources and flags beside them. The Mac's mirror of
# the board (tools/mirror.sh) and the simulator's page
# (simulator/web/build.sh) build with it. Needs Emscripten
# (`brew install emscripten`).
#
#   firmware/tools/wasm.sh [--pack PACK] [--board BOARD] OUT.js EM++ARG...
#
#   --pack PACK    that pack, staged beside what's staged, which stays as
#                  it is; without it, the staged pack
#   --board BOARD  only the face the pack gives that board (character.json's
#                  `faces`), as the board's own build takes it; without it,
#                  every face, as the native env's
#   EM++ARG        the entry's sources and flags: its exports, the module's shape
set -eu
cd "$(dirname "$0")/../.."

PACK= BOARD=
while :; do
  case ${1:-} in
    --pack) PACK=$2; shift 2 ;;
    --board) BOARD=$2; shift 2 ;;
    *) break ;;
  esac
done
OUT=$1
shift
command -v em++ >/dev/null || { echo "wasm: no em++ here. Install Emscripten: brew install emscripten" >&2; exit 1; }

# The pack's firmware as staging makes it (moods.h, rig_tables.h, its faces).
if [ -n "$PACK" ]; then
  FW=.character-build/wasm/$PACK
  python3 characters/charactergen.py --firmware-to="$FW" "characters/$PACK" >/dev/null
  FW=$FW/firmware
  PACKDIR=characters/$PACK
else
  FW=.character-build/firmware
  PACKDIR=$(cat .character-build/pack)
fi
# Its sources: every face's, or the board's face's and none of the others'.
PACKSRC=$(find "$FW/src" -name '*.cpp')
DEFINE=
if [ -n "$BOARD" ]; then
  FACE=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("faces", {}).get(sys.argv[2], ""))' \
    "$PACKDIR/character.json" "$BOARD")
  [ -n "$FACE" ] && [ -d "$FW/src/render/$FACE" ] || { echo "wasm: the $(basename "$PACKDIR") pack gives the $BOARD no face" >&2; exit 1; }
  PACKSRC="$(echo "$PACKSRC" | grep -v "^$FW/src/render/[^/]*/")
$(find "$FW/src/render/$FACE" -name '*.cpp')"
  DEFINE=-DBOOP_FACE_$(echo "$FACE" | tr '[:lower:]' '[:upper:]')
fi
# The hosted board and the portable code it runs, as the native env builds them.
HOSTED=$(python3 - firmware/platformio.ini <<'EOF'
import configparser, re, sys
ini = configparser.ConfigParser(interpolation=None, inline_comment_prefixes=(";",))
ini.read(sys.argv[1])
print(" ".join("firmware/src/" + d for d in re.findall(r"\+<([^>]*)>", ini["hosted"]["src_filter"])))
EOF
)
# ArduinoJson, which the firmware and LinkKit's device library use, as
# PlatformIO fetched it for the native env.
JSON=firmware/.pio/libdeps/native/ArduinoJson/src
[ -d "$JSON" ] || firmware/tools/pio.sh pkg install -e native >/dev/null

# In one order, so a build from the same sources is the same, byte for byte.
# shellcheck disable=SC2086
SOURCES=$( (find $HOSTED linkkit/device/src -name '*.cpp'; echo "$PACKSRC") | LC_ALL=C sort)
# shellcheck disable=SC2086
em++ -std=c++17 -O2 $DEFINE \
    -Ifirmware/src -Ifirmware/assets -I"$FW/include" -I"$FW/src" -Ilinkkit/device/src -I"$JSON" \
    $SOURCES "$@" \
    -sMODULARIZE -sENVIRONMENT=web,node -sALLOW_MEMORY_GROWTH \
    -sEXPORTED_RUNTIME_METHODS=cwrap,HEAPU8,UTF8ToString --no-entry \
    -o "$OUT"
