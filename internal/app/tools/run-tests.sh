#!/bin/sh
# Runs Boop's Swift tests (.build/debug/BoopTests) as several runners side
# by side, each taking every Nth test (BOOP_TEST_SHARD, in the generated
# runner): the tests wait on real clocks more than they compute, so six
# runners finish in about a third of the time of one.
#
#   internal/app/tools/run-tests.sh          half the cores' runners, six at most (BOOP_TEST_SHARDS=N for another count)
#   BOOP_TEST_FILTER=Golden ...run-tests.sh  one runner, only the tests whose name contains it
#
# A failing runner's whole output is printed, and the exit status is 1.
set -u
cd "$(dirname "$0")/../../.."
RUNNER=.build/debug/BoopTests
# Half the cores, six at most: some tests time real deadlines, and on a
# machine with few cores (CI's has three) six runners starve them.
CORES=$(sysctl -n hw.ncpu 2>/dev/null || echo 2)
HALF=$((CORES / 2)); [ "$HALF" -lt 1 ] && HALF=1; [ "$HALF" -gt 6 ] && HALF=6
N=${BOOP_TEST_SHARDS:-$HALF}
if [ -n "${BOOP_TEST_FILTER:-}" ] || [ "$N" -le 1 ]; then
  exec "$RUNNER"
fi
LOGS=.build/test-shards
rm -rf "$LOGS" && mkdir -p "$LOGS"
i=0
pids=
while [ "$i" -lt "$N" ]; do
  BOOP_TEST_SHARD="$i/$N" "$RUNNER" > "$LOGS/$i.log" 2>&1 &
  pids="$pids $!"
  i=$((i + 1))
done
status=0
i=0
for pid in $pids; do
  if wait "$pid"; then
    tail -n 1 "$LOGS/$i.log"
  else
    status=1
    echo "---- runner $i of $N failed; its output:"
    cat "$LOGS/$i.log"
  fi
  i=$((i + 1))
done
[ "$status" -eq 0 ] && echo "✓ every runner passed ($N side by side; their output is in $LOGS/)"
exit "$status"
