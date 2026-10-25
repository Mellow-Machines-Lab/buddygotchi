#!/bin/sh
# Runs PlatformIO with its core and packages in the main checkout's
# firmware/.platformio-core (tools/pio-core.sh), shared by every worktree,
# and its builds in this checkout's .pio. All paths are git-ignored.
#   firmware/tools/pio.sh run -e cyd24
# Uses the `pio` on PATH if there is one. Without one, the first run
# installs PlatformIO with pip into the core's venv, with the first
# Python 3.10 or later it finds: the ESP32 platform refuses the Mac's
# own 3.9.
set -eu
firmware_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
PLATFORMIO_CORE_DIR=$("$firmware_dir/tools/pio-core.sh")
export PLATFORMIO_CORE_DIR
# The unit tests keep their objects and libraries apart, in each project's
# .pio/test: `pio test` links every suite as its env's `program`, and
# installs Unity, which `pio run` then removes as unused. Sharing .pio, the
# tests left a test runner where the native simulator was, and with a
# `pio run -e native` alongside, each linked or lost the other's files.
if [ "${1:-}" = test ] && [ -z "${PLATFORMIO_WORKSPACE_DIR:-}" ]; then
  # shellcheck disable=SC2016 # PlatformIO expands it, for each project
  export PLATFORMIO_WORKSPACE_DIR='${PROJECT_DIR}/.pio/test'
fi
cd "$firmware_dir"
# The chosen character pack's firmware, staged into ../.character-build/
# (characters/CHARACTER.md §2), which platformio.ini builds from.
python3 "$firmware_dir/../characters/charactergen.py" --stage

pio=$(command -v pio || true)
if [ -z "$pio" ]; then
  venv="$PLATFORMIO_CORE_DIR/venv"
  pio="$venv/bin/pio"
  if [ ! -x "$pio" ]; then
    if ! python=$("$firmware_dir/tools/find-python.sh"); then
      echo "pio.sh: no pio on PATH, and installing PlatformIO needs Python 3.10 or later (brew install python)" >&2
      exit 1
    fi
    echo "pio.sh: no pio on PATH; installing PlatformIO into $venv with $python (once, about a minute)" >&2
    rm -rf "$venv"
    "$python" -m venv "$venv"
    "$venv/bin/python" -m pip install --quiet --disable-pip-version-check platformio
  fi
fi
# An upload builds first, then waits for the board's lock, which every
# tool that talks to the board over USB takes, so no session flashes over
# another's test; and it's logged. `internal/tools/boopctl board` says who
# has the board and what was flashed on it.
board_py="$firmware_dir/../internal/tools/boopctl_lib/board.py"
for arg in "$@"; do
  case "$arg" in
    upload* | -tupload* | --target=upload*)
      [ -f "$board_py" ] && exec python3 "$board_py" upload -- "$pio" "$@"
      ;;
  esac
done
exec "$pio" "$@"
