#!/bin/sh
# Puts the simulator window's page in DEST: the page (app.html), the
# simulator's core and script from simulator/web/dist/, the chosen pack's
# voice, and the face the pack gives the AMOLED board, which the window
# draws (app/Boop/BoardWindow.swift). The internal build carries it in its
# Resources (bundle.sh); make dev's debug build finds it beside its binary.
# The page must be built first (simulator/web/build.sh).
#   app/tools/simulator.sh DEST
set -eu
cd "$(dirname "$0")/../.."
dest=$1
mkdir -p "$dest"
cp simulator/web/dist/app.html simulator/web/dist/boop-simulator.js simulator/web/dist/boop-sim.js \
  simulator/web/dist/boop-sim.wasm "$dest/"
pack=$(python3 characters/charactergen.py --which)
rm -f "$dest/voice.bin"
[ -f "$pack/voice/voice.bin" ] && cp "$pack/voice/voice.bin" "$dest/voice.bin"
python3 -c 'import json,sys; faces = json.load(open(sys.argv[1])).get("faces", {}); print(faces.get("amoled206") or "pixel")' \
  "$pack/character.json" > "$dest/face"
