#!/bin/sh
# Builds the gel's frame-time bench (gel_bench.cpp) and runs it: the
# simulator's board, the staged pack and the firmware's portable code, as
# firmware/tools/wasm.sh gathers them, built natively at -O2 as the board
# builds its drawing (OPT= for another), into $TMPDIR/boop-bench/.
#
#   internal/firmware/bench/bench.sh [SECONDS [FRAME_MS [SCENE...]]]
#
# Prints each scene's microseconds a frame, the Mac's, on one core: for
# comparing builds and stages, never for the board's budgets
# (internal/VERIFICATION.md L2, perf).
set -eu
cd "$(dirname "$0")/../../.."
ROOT=$(pwd)
python3 characters/charactergen.py --stage >/dev/null
FW=.character-build/firmware
JSON=firmware/.pio/libdeps/native/ArduinoJson/src
[ -d "$JSON" ] || firmware/tools/pio.sh pkg install -e native >/dev/null
HOSTED=$(python3 - firmware/platformio.ini <<'EOF'
import configparser, re, sys
ini = configparser.ConfigParser(interpolation=None, inline_comment_prefixes=(";",))
ini.read(sys.argv[1])
print(" ".join("firmware/src/" + d for d in re.findall(r"\+<([^>]*)>", ini["hosted"]["src_filter"])))
EOF
)
OUT=${TMPDIR:-/tmp}/boop-bench/$(basename "$ROOT")
mkdir -p "$OUT/obj"
FLAGS="-std=c++17 ${OPT:--O2} -DNDEBUG -Ifirmware/src -Ifirmware/assets -I$FW/include -I$FW/src -Ilinkkit/device/src -I$JSON -Isimulator/core"
# shellcheck disable=SC2086
SOURCES=$( (find $HOSTED linkkit/device/src "$FW/src" -name '*.cpp'; echo simulator/core/board.cpp; echo internal/firmware/bench/gel_bench.cpp) | LC_ALL=C sort)
echo "$SOURCES" | xargs -P "$(sysctl -n hw.ncpu)" -I{} sh -c 'o="$1/obj/o$(echo "$2" | tr / _).o"; c++ $3 -w -c "$2" -o "$o"' _ "$OUT" {} "$FLAGS"
c++ "$OUT"/obj/*.o -o "$OUT/gel_bench"
"$OUT/gel_bench" "$@"
