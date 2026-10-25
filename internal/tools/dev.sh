#!/bin/sh
# `make dev`: the debug app on a folder of its own, with everything that
# watches it. Builds the app, starts the simulator in the background (the
# board in a browser, Settings' Simulator row), opens its page and the
# studio's matrix, with what the brain reads in each eval written for the
# studio's Brain view, and the live dashboard in a Terminal window of its own,
# then runs the app here, printing everything. Ctrl-C quits the app and
# stops the simulator and the dashboard with it.
#
# The app starts on its board, over Bluetooth, so the owner runs this from
# their own terminal, not an agent's. Its folder isn't the everyday Boop's:
# it registers a hook socket of its own, so it hears the real agents too,
# keeps a Jev key of its own in the Keychain, and never changes the hooks
# or the login item.
#
#   FRESH=1   start the folder afresh, its Jev key with it: onboarding again
set -eu
cd "$(dirname "$0")/../.."

STATE="$HOME/Library/Application Support/Boop-dev"
# The Keychain entry of a Boop on that folder (Keychain.account(for:)).
KEY_ACCOUNT=dev-Boop-dev
PORT=8206
SIM="http://127.0.0.1:$PORT"

if [ -n "${FRESH:-}" ]; then
  echo "dev: starting $STATE afresh"
  rm -rf "$STATE"
  security delete-generic-password -s com.boopcomputer.boop -a "$KEY_ACCOUNT" >/dev/null 2>&1 || true
fi

if pgrep -x Boop >/dev/null; then
  echo "dev: another Boop is running. Only one can have the board over Bluetooth:"
  echo "     use the simulator (Settings, Simulator, Use it), or quit the other one."
fi

make -s -C internal app
.build/debug/boopdev prompts >/dev/null || echo "dev: no prompts for the studio's Brain view"

# The simulator: built again only when something it's built from changed,
# and left alone when one is already running (make demo's, or another
# make dev's).
SIM_PID=
if curl -s -o /dev/null "$SIM/"; then
  echo "dev: a simulator is already running at $SIM; using it"
elif command -v emcc >/dev/null; then
  if [ ! -f simulator/web/dist/boop-sim.wasm ] || [ -n "$(find firmware/src firmware/assets simulator/core \
      linkkit/device/src .character-build simulator/web/boop-simulator.js simulator/web/index.html \
      simulator/web/build.sh firmware/tools/wasm.sh -newer simulator/web/dist/boop-sim.wasm -type f | head -1)" ]; then
    echo "dev: building the simulator"
    simulator/web/build.sh >/dev/null
  fi
  python3 simulator/web/serve.py --port "$PORT" &
  SIM_PID=$!
  for _ in 1 2 3 4 5 6 7 8 9 10; do curl -s -o /dev/null "$SIM/" && break; sleep 0.5; done
else
  echo "dev: no simulator: it needs Emscripten (brew install emscripten)"
fi

# The page is the board, so it opens only for a simulator started here: a
# running one has its page open already. The pack's own face: the gel for
# Boop's, else pixel.
FACE=pixel
[ "$(basename "$(cat .character-build/pack)")" = boop ] && FACE=gel
[ -n "$SIM_PID" ] && open "$SIM/?face=$FACE"
curl -s -o /dev/null "$SIM/" && open "$SIM/characters/studio/#view=matrix&board=/board"

DASH="internal/tools/boopctl dash --state-dir '$STATE'"
osascript -e "tell application \"Terminal\" to do script \"cd '$PWD' && $DASH\"" >/dev/null

cleanup() {
  [ -n "$SIM_PID" ] && kill "$SIM_PID" 2>/dev/null
  pkill -f "boopctl_lib dash --state-dir $STATE" 2>/dev/null
  true
}
trap cleanup EXIT INT TERM

.build/debug/Boop --debug --state-dir "$STATE"
