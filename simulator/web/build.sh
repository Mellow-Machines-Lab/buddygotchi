#!/bin/sh
# Builds the simulator for a browser into simulator/web/dist/: the board's
# core as WebAssembly (boop-sim.js, boop-sim.wasm) from the same sources
# PlatformIO's native env builds, and the page's script beside it.
# Needs Emscripten (`brew install emscripten`) and the staged character
# pack (`python3 characters/charactergen.py --stage`, which make does).
#
#   simulator/web/build.sh          the staged pack: boop-sim.js
#   simulator/web/build.sh pixel    a pack by name, beside it: boop-sim-pixel.js,
#                                   for <boop-simulator pack="pixel">. What's
#                                   staged stays as it is.
set -eu
cd "$(dirname "$0")/../.."

PACK=${1:-}
if [ -n "$PACK" ]; then
    FW=.character-build/sim/$PACK
    python3 characters/charactergen.py --firmware-to="$FW" "characters/$PACK"
    FW=$FW/firmware
    CORE=boop-sim-$PACK
else
    FW=.character-build/firmware
    CORE=boop-sim
fi

command -v emcc >/dev/null || { echo "simulator: no emcc here. Install Emscripten: brew install emscripten" >&2; exit 1; }
# ArduinoJson, which the firmware and LinkKit's device library use, as
# PlatformIO fetched it for the native env.
JSON=firmware/.pio/libdeps/native/ArduinoJson/src
[ -d "$JSON" ] || firmware/tools/pio.sh pkg install -e native >/dev/null

OUT=simulator/web/dist
mkdir -p "$OUT"
SOURCES="$(find firmware/src/render firmware/src/app firmware/src/voice firmware/src/board/hosted $FW/src linkkit/device/src -name '*.cpp')
simulator/core/board.cpp
simulator/core/web.cpp"
# shellcheck disable=SC2086
em++ -std=c++17 -O2 \
    -Ifirmware/src -Ifirmware/assets -I$FW/include -I$FW/src \
    -Ilinkkit/device/src -I"$JSON" -Isimulator/core \
    $SOURCES \
    -sMODULARIZE -sEXPORT_ES6 -sENVIRONMENT=web,node -sALLOW_MEMORY_GROWTH \
    -sEXPORTED_RUNTIME_METHODS=ccall,cwrap,HEAPU8,UTF8ToString \
    -o "$OUT/$CORE.js"
cp simulator/web/boop-simulator.js simulator/web/index.html "$OUT/"
ls -l "$OUT"
