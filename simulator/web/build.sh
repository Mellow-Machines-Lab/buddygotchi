#!/bin/sh
# Builds the simulator for a browser into simulator/web/dist/: the board's
# core as WebAssembly (boop-sim.js, boop-sim.wasm) from the same sources
# PlatformIO's native env builds (firmware/tools/wasm.sh), and the page's
# script beside it. Needs Emscripten (`brew install emscripten`) and the
# staged character pack (`python3 characters/charactergen.py --stage`,
# which make does).
#
#   simulator/web/build.sh          the staged pack: boop-sim.js
#   simulator/web/build.sh pixel    a pack by name, beside it: boop-sim-pixel.js,
#                                   for <boop-simulator pack="pixel">. What's
#                                   staged stays as it is.
set -eu
cd "$(dirname "$0")/../.."

PACK=${1:-}
OUT=simulator/web/dist
mkdir -p "$OUT"
firmware/tools/wasm.sh ${PACK:+--pack "$PACK"} "$OUT/boop-sim${PACK:+-$PACK}.js" \
    -Isimulator/core simulator/core/board.cpp simulator/core/web.cpp -sEXPORT_ES6
cp simulator/web/boop-simulator.js simulator/web/index.html "$OUT/"
ls -l "$OUT"
