#!/bin/sh
# Prints the first Python 3.10 or later on PATH, or fails with nothing.
# The Mac's own python3 is 3.9, and Homebrew's Python may be there only
# as python3.14 or the like, with no python3 of its own, so each version
# is tried by name.
for candidate in python3 python3.14 python3.13 python3.12 python3.11 python3.10; do
  if "$candidate" -c 'import sys; sys.exit(sys.version_info < (3, 10))' 2>/dev/null; then
    echo "$candidate"
    exit 0
  fi
done
exit 1
