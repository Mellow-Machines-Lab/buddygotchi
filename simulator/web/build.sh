#!/bin/sh
# Builds the simulator for a browser into simulator/web/dist/: the board's
# core as WebAssembly (boop-sim.js, boop-sim.wasm) from the same sources
# PlatformIO's native env builds (firmware/tools/wasm.sh), and beside it
# the page's script, the local page and the page the internal build's
# board window shows (app.html). Needs Emscripten (`brew install
# emscripten`) and the staged character pack (`python3
# characters/charactergen.py --stage`, which make does).
set -eu
cd "$(dirname "$0")/../.."

OUT=simulator/web/dist
mkdir -p "$OUT"
firmware/tools/wasm.sh "$OUT/boop-sim.js" \
    -Isimulator/core simulator/core/board.cpp simulator/core/web.cpp -sEXPORT_ES6
cp simulator/web/boop-simulator.js simulator/web/index.html simulator/web/app.html "$OUT/"
ls -l "$OUT"
