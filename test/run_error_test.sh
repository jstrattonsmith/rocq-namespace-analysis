#!/usr/bin/env bash
# Error-path regression tests for NamespaceAnalysis's CLI.
#
# Usage: bash test/run_error_test.sh   (run from the repository root; also
# invoked automatically at the end of test/run_test.sh)
#
# Every case here expects the CLI to *fail* with a clean, one-line,
# Rocq-style error message and exit code 1 -- exactly what `rocq compile`
# itself gives on the same bad input -- rather than an uncaught
# "Fatal error: exception ..." dump with exit code 2. Before the try/with
# wrapper in cli/namespace_analysis_cli.ml (added alongside these tests),
# every single case below produced that raw dump; confirmed by reverting the
# wrapper and re-running this script.
#
# set -e would abort the whole script at the very first *expected* failure,
# so each check below toggles `set +e`/`set -e` around just the one command
# being tested, capturing its exit code and combined output explicitly --
# the same spirit as the `if`/`||` expected-failure assertions already used
# in test/run_test.sh, just applied to a command's exit code instead of its
# printed content.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

dune build
export OCAMLPATH="$ROOT/_build/install/default/lib:${OCAMLPATH:-}"
CLI="$ROOT/_build/default/cli/namespace_analysis_cli.exe"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

mkdir -p "$WORK/mydev"
cp test/fixtures/libs/PartA.v test/fixtures/libs/PartB.v "$WORK/mydev/"
rocq compile -R "$WORK/mydev" MyDev "$WORK/mydev/PartA.v" >/dev/null
rocq compile -R "$WORK/mydev" MyDev "$WORK/mydev/PartB.v" >/dev/null

# ---------------------------------------------------------------------------
echo "==> error path: no target file"
set +e
OUT=$("$CLI" 2>&1)
CODE=$?
set -e
[ "$CODE" -eq 1 ] || { echo "FAIL: expected exit 1 for no target file, got $CODE"; exit 1; }
echo "$OUT" | grep -q "namespace-analysis: need a target .v file"

# ---------------------------------------------------------------------------
echo "==> error path: -R pointing at a nonexistent directory"
set +e
OUT=$("$CLI" -R "$WORK/does-not-exist" SomeDirPath test/fixtures/MainCli.v 2>&1)
CODE=$?
set -e
[ "$CODE" -eq 1 ] || { echo "FAIL: expected exit 1 for bad -R dir, got $CODE"; exit 1; }
echo "$OUT" | grep -q "Cannot find a physical path bound to logical path"

# ---------------------------------------------------------------------------
echo "==> error path: target file fails to compile (type error)"
set +e
OUT=$("$CLI" test/fixtures/BadCompile.v 2>&1)
CODE=$?
set -e
[ "$CODE" -eq 1 ] || { echo "FAIL: expected exit 1 for a bad-compile target, got $CODE"; exit 1; }
echo "$OUT" | grep -q "has type \"bool\" while it is expected to have type \"nat\""
rm -f test/fixtures/BadCompile.vo test/fixtures/BadCompile.vok test/fixtures/BadCompile.vos \
  test/fixtures/BadCompile.glob test/fixtures/.BadCompile.aux

# ---------------------------------------------------------------------------
echo "==> error path: malformed --domain string"
set +e
OUT=$("$CLI" -R "$WORK/mydev" MyDev --domain "not a valid ident!!" test/fixtures/MainCli.v 2>&1)
CODE=$?
set -e
[ "$CODE" -eq 1 ] || { echo "FAIL: expected exit 1 for a malformed --domain, got $CODE"; exit 1; }
echo "$OUT" | grep -q "Invalid character"
rm -f test/fixtures/MainCli.vo test/fixtures/MainCli.vok test/fixtures/MainCli.vos \
  test/fixtures/MainCli.glob test/fixtures/.MainCli.aux

echo "ALL ERROR-PATH TESTS PASSED"
