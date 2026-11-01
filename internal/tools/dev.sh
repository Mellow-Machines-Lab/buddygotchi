#!/bin/sh
# `make dev`: the debug app on a folder of its own, with everything that
# watches it. Builds the app, puts the simulator window's page beside it
# (Boop's body when onboarding or Settings makes it so), starts the
# studio's server in the background and opens the studio, with what the
# brain reads in each eval written for its Brain view, and the live
# dashboard in a Terminal window of its own, then runs the app here,
# printing everything. Ctrl-C quits the app and stops the server and the
# dashboard with it.
#
# The app starts on its board, over Bluetooth, until the simulator is
# chosen, so the owner runs this from their own terminal, not an agent's.
# Its folder isn't the everyday Boop's:
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
SIM_URL="http://127.0.0.1:$PORT"

if [ -n "${FRESH:-}" ]; then
  echo "dev: starting $STATE afresh"
  rm -rf "$STATE"
  security delete-generic-password -s com.boopcomputer.boop -a "$KEY_ACCOUNT" >/dev/null 2>&1 || true
fi

if pgrep -x Boop >/dev/null; then
  echo "dev: another Boop is running. Only one can have the board over Bluetooth:"
  echo "     use the simulator window (Settings, Simulator), or quit the other one."
fi

make -s -C internal app
.build/debug/boopdev prompts >/dev/null || echo "dev: no prompts for the studio's Brain view"

# The simulator window's page, beside the app: built again only when
# something it's built from changed. And the studio's server, left alone
# when one is already running (make demo's, or another make dev's).
if command -v emcc >/dev/null; then
  if [ ! -f simulator/web/dist/boop-sim.wasm ] || [ -n "$(find firmware/src firmware/assets simulator/core \
      linkkit/device/src .character-build simulator/web/boop-simulator.js simulator/web/index.html simulator/web/app.html \
      simulator/web/build.sh firmware/tools/wasm.sh -newer simulator/web/dist/boop-sim.wasm -type f | head -1)" ]; then
    echo "dev: building the simulator"
    simulator/web/build.sh >/dev/null
  fi
  app/tools/simulator.sh .build/debug/simulator
else
  echo "dev: no simulator window: it needs Emscripten (brew install emscripten)"
  rm -rf .build/debug/simulator
fi
SIM_PID=
if curl -s -o /dev/null "$SIM_URL/characters/studio/"; then
  echo "dev: a studio server is already running at $SIM_URL; using it"
else
  python3 simulator/web/serve.py --port "$PORT" &
  SIM_PID=$!
  for _ in 1 2 3 4 5 6 7 8 9 10; do curl -s -o /dev/null "$SIM_URL/characters/studio/" && break; sleep 0.5; done
fi
curl -s -o /dev/null "$SIM_URL/characters/studio/" && open "$SIM_URL/characters/studio/#view=matrix"

DASH="internal/tools/boopctl dash --state-dir '$STATE'"
osascript -e "tell application \"Terminal\" to do script \"cd '$PWD' && $DASH\"" >/dev/null

cleanup() {
  [ -n "$SIM_PID" ] && kill "$SIM_PID" 2>/dev/null
  pkill -f "boopctl_lib dash --state-dir $STATE" 2>/dev/null
  true
}
trap cleanup EXIT INT TERM

.build/debug/Boop --debug --state-dir "$STATE"
