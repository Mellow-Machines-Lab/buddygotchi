#!/bin/sh
# Plays a character pack's demo by name in the simulator's page:
#
#     simulator/tools/demo.sh [NAME] [FACE]      (make demo NAME=landing)
#
# NAME is a pack's demo/NAME.jsonl (landing by default): the chosen pack's
# if it has one, else the one pack in characters/ that does
# (internal/tools/session/script.py, which `make demo IN=…` uses too). FACE
# is the board's face, pixel by default or gel. The first time, and
# whenever the script is newer than its recording or FRESH=1, it records
# the demo (record-demo.sh, as long as the demo runs); then it serves the
# page (make simulator) and opens the demo in a browser. Ctrl-C stops it.
# NAME=? lists the demos there are. BOARD=usb:SOCKET plays it live on a
# board on a USB bridge instead (internal/tools/boopctl bridge), and stops
# when it's over.
set -eu
cd "$(dirname "$0")/../.."
NAME="${1:-landing}"
FACE="${2:-pixel}"
OUT=simulator/web/dist/demo

if [ "$NAME" = "?" ]; then
    echo "demos, by pack (make demo NAME=<name>, and CHARACTER=<pack> where two packs share a name):" >&2
    for f in characters/*/demo/*.jsonl; do
        printf '  %-8s %s\n' "$(basename "$(dirname "$(dirname "$f")")")" "$(basename "$f" .jsonl)" >&2
    done
    exit 0
fi
SCRIPT="$(python3 internal/tools/session/script.py which "$NAME")"
# The demo's pack for everything below: the builds, the board and the app.
BOOP_CHARACTER="$(cd "$(dirname "$SCRIPT")/.." && pwd)"
export BOOP_CHARACTER

if [ -n "${BOARD:-}" ] && [ "$BOARD" != sim ]; then
    case "$BOARD" in usb:*) ;; *) echo "demo: BOARD is sim or usb:SOCKET" >&2; exit 1 ;; esac
    DIR="$(mktemp -d /tmp/boop-demo.XXXXXX)"
    make build >"$DIR/build.log" 2>&1 || { tail -20 "$DIR/build.log" >&2; exit 1; }
    CREATURE="$(python3 -c 'import json, sys; print(json.load(open(sys.argv[1]))["name"])' "$BOOP_CHARACTER/character.json")"
    echo "demo: playing $NAME on the board at $BOARD; its log is $DIR/boop.log"
    # Only the demo's lines, and anything Boop stops on; Boop's own exit status.
    { .build/debug/Boop --headless --state-dir "$DIR" --link "$BOARD" --no-open --name "$CREATURE" --demo "$SCRIPT" 2>&1
      echo $? >"$DIR/status"; } | grep --line-buffered -E "demo:|^[^0-9]"
    exit "$(cat "$DIR/status")"
fi

REC="$FACE-$NAME"
ID="$(python3 -c 'import json, sys; print(json.load(open(sys.argv[1]))["id"])' "$BOOP_CHARACTER/character.json")"

# A recording is stale when the script is newer, or it's another pack's.
stale() {
    [ "${FRESH:-}" = 1 ] || [ ! -s "$OUT/$REC.json" ] || [ "$SCRIPT" -nt "$OUT/$REC.json" ] ||
        ! python3 -c 'import json, sys; sys.exit(json.load(open(sys.argv[1]))["character"] != sys.argv[2])' "$OUT/$REC.json" "$ID"
}
if stale; then
    echo "demo: recording $ID's $NAME on the $FACE face, as long as it runs (once, until the script changes)"
    make build >/dev/null
    firmware/tools/pio.sh run -e native >/dev/null
    simulator/tools/record-demo.sh "$FACE" "$OUT" "$NAME"
fi

URL="http://127.0.0.1:8206/?demo=$REC"
echo "demo: $URL"
# Opened only for someone at a terminal, not for a script or an agent.
if [ -t 1 ] && command -v open >/dev/null; then (sleep 3 && open "$URL") & fi
exec make -s simulator
