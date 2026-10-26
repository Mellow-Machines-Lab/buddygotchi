#!/bin/sh
# Prints PlatformIO's core directory, its toolchains and packages, a few
# GB: $PLATFORMIO_CORE_DIR if set, else firmware/.platformio-core in the
# repository's main checkout, so every worktree shares the one copy
# instead of downloading its own. PlatformIO locks its installs, so
# worktrees building at once don't clash. Outside git, or in a submodule
# (a character repository's engine/), this checkout's.
set -eu
firmware_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
if [ -n "${PLATFORMIO_CORE_DIR:-}" ]; then
  echo "$PLATFORMIO_CORE_DIR"
elif [ -n "$(git -C "$firmware_dir" rev-parse --show-superproject-working-tree 2>/dev/null)" ]; then
  echo "$firmware_dir/.platformio-core"
elif common=$(git -C "$firmware_dir" rev-parse --path-format=absolute --git-common-dir 2>/dev/null); then
  echo "$(dirname -- "$common")/firmware/.platformio-core"
else
  echo "$firmware_dir/.platformio-core"
fi
