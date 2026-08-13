#!/usr/bin/env bash
# Regression test for ImportAnalysis: builds two libraries that both define a
# lemma `K`, then checks that both the native plugin command and the
# external CLI report the same clash + used-identifier resolution.
#
# Usage: bash test/run_test.sh   (run from the repository root)
set -euo pipefail

# Toolchain-agnostic: run this either inside `nix develop` (recommended -- see
# flake.nix) or with a Homebrew-installed `rocq`/`dune` on PATH, in which case
# also export LIBRARY_PATH=/opt/homebrew/lib first (see README).

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

echo "==> dune build"
dune build

export OCAMLPATH="$ROOT/_build/install/default/lib:${OCAMLPATH:-}"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
cp test/fixtures/libs/PartA.v test/fixtures/libs/PartB.v "$WORK/"

echo "==> compiling fixture libraries (MyDev.PartA, MyDev.PartB)"
rocq compile -R "$WORK" MyDev "$WORK/PartA.v" >/dev/null
rocq compile -R "$WORK" MyDev "$WORK/PartB.v" >/dev/null

echo "==> native plugin command (Main.v)"
PLUGIN_OUT="$WORK/plugin_out.txt"
rocq compile -R _build/default/theories ImportAnalysis -R "$WORK" MyDev \
  test/fixtures/Main.v > "$PLUGIN_OUT" 2>&1
# The report starts at the "ImportAnalysis:" header; strip the preceding
# `Check` output, which is incidental to this test.
sed -n '/^ImportAnalysis:/,$p' "$PLUGIN_OUT" > "$WORK/plugin_report.txt"

echo "==> external CLI (MainCli.v)"
CLI_OUT="$WORK/cli_report.txt"
./_build/default/cli/import_analysis_cli.exe \
  -R "$WORK" MyDev --domain MyDev.PartA --domain MyDev.PartB \
  test/fixtures/MainCli.v > "$CLI_OUT"

echo "==> diffing plugin report against expected"
diff -u test/expected/report.txt "$WORK/plugin_report.txt"

echo "==> diffing CLI report against expected"
diff -u test/expected/report.txt "$CLI_OUT"

echo "==> diffing plugin report against CLI report (parity check)"
diff -u "$WORK/plugin_report.txt" "$CLI_OUT"

echo "ALL TESTS PASSED"
