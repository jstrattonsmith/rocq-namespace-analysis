#!/usr/bin/env bash
# Performance regression test for Clash_detect.find_clashes.
#
# find_clashes used to group `members` by short name via a full linear scan
# (`List.filter` over every member) repeated once per unique name -- O(n)
# work per name, times n names, so O(n^2) overall. Confirmed by direct
# measurement before the fix: 10,000 scanned members took ~10.6s, while
# 1,000 took ~0.16s -- a 10x input growing to a ~65x-70x runtime increase,
# consistent with roughly quadratic scaling. Fixed by grouping members by
# basename once, up front, via an Id.Map (O(n log n) overall); confirmed
# after the fix, 10,000 members took ~0.15s and 100,000 took ~1.1s. See
# Examples.md for the full before/after numbers.
#
# This test pins the fix: asserts a moderately large (8,000-clash) scan
# completes comfortably within a generous time bound that the pre-fix
# O(n^2) behavior would have blown through (extrapolated pre-fix time at
# this size: several seconds; actual post-fix time: well under 1s).
#
# Usage: bash test/run_perf_test.sh   (run from the repository root; also
# invoked automatically at the end of test/run_test.sh)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

dune build
export OCAMLPATH="$ROOT/_build/install/default/lib:${OCAMLPATH:-}"
CLI="$ROOT/_build/default/cli/namespace_analysis_cli.exe"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

N=8000
mkdir -p "$WORK/perfa" "$WORK/perfb"
seq 0 $((N - 1)) | awk '{ print "Definition d" $1 " : nat -> nat := fun x => x." }' > "$WORK/perfa/PerfA.v"
cp "$WORK/perfa/PerfA.v" "$WORK/perfb/PerfB.v"
rocq compile -R "$WORK/perfa" PerfA "$WORK/perfa/PerfA.v" >/dev/null
rocq compile -R "$WORK/perfb" PerfB "$WORK/perfb/PerfB.v" >/dev/null

cat > "$WORK/PerfDriver.v" <<EOF
From PerfA Require Import PerfA.
From PerfB Require Import PerfB.
EOF

echo "==> performance: $N clashing symbols complete well within budget"
START=$(date +%s)
OUT=$("$CLI" -R "$WORK/perfa" PerfA -R "$WORK/perfb" PerfB --domain PerfA --domain PerfB \
  --format summary "$WORK/PerfDriver.v")
END=$(date +%s)
ELAPSED=$((END - START))
echo "  completed in ${ELAPSED}s"
echo "$OUT" | grep -q "$N clash(es) found"
[ "$ELAPSED" -le 5 ] || {
  echo "FAIL: expected completion within 5s, took ${ELAPSED}s (possible algorithmic regression in Clash_detect.find_clashes)"
  exit 1
}

echo "ALL PERFORMANCE TESTS PASSED"
