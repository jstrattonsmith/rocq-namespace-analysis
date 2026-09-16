#!/usr/bin/env bash
# Regression test for NamespaceAnalysis.
#
# Usage: bash test/run_test.sh   (run from the repository root)
#
# Toolchain-agnostic: run this either inside `nix develop` (recommended -- see
# flake.nix) or with a Homebrew-installed `rocq`/`dune` on PATH, in which case
# also export LIBRARY_PATH=/opt/homebrew/lib first (see README).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

echo "==> dune build"
dune build

export OCAMLPATH="$ROOT/_build/install/default/lib:${OCAMLPATH:-}"
CLI="$ROOT/_build/default/cli/namespace_analysis_cli.exe"
THEORIES="-R _build/default/theories NamespaceAnalysis"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# Splits a file containing N stacked "NamespaceAnalysis: ..." report blocks
# into $1_1, $1_2, ... (1-indexed), stripping any incidental `Check` output
# before the first block.
split_blocks() {
  local src="$1" prefix="$2"
  awk -v prefix="$prefix" '
    /^NamespaceAnalysis:/ { n++; file = prefix "_" n }
    n > 0 { print > file }
  ' "$src"
}

echo "==> compiling fixture libraries"
mkdir -p "$WORK/mydev" "$WORK/deep" "$WORK/other" "$WORK/one" "$WORK/two" "$WORK/three" "$WORK/excl" \
  "$WORK/muta" "$WORK/mutb" "$WORK/consa" "$WORK/consb" "$WORK/exclwina" "$WORK/exclwinb"
cp test/fixtures/libs/PartA.v test/fixtures/libs/PartB.v test/fixtures/libs/PartC.v "$WORK/mydev/"
cp test/fixtures/libs/multilevel/deep/DeepOne.v "$WORK/deep/"
cp test/fixtures/libs/multilevel/other/Sibling.v "$WORK/other/"
cp test/fixtures/libs/three/one/Mod.v "$WORK/one/"
cp test/fixtures/libs/three/two/Mod.v "$WORK/two/"
cp test/fixtures/libs/three/three/Mod.v "$WORK/three/"
cp test/fixtures/libs/excldemo/CorelibClash.v "$WORK/excl/"
cp test/fixtures/libs/mutual/a/MutA.v "$WORK/muta/"
cp test/fixtures/libs/mutual/b/MutB.v "$WORK/mutb/"
cp test/fixtures/libs/construct/a/ConstructA.v "$WORK/consa/"
cp test/fixtures/libs/construct/b/ConstructB.v "$WORK/consb/"
cp test/fixtures/libs/exclwinner/a/ExclWinA.v "$WORK/exclwina/"
cp test/fixtures/libs/exclwinner/b/ExclWinB.v "$WORK/exclwinb/"
rocq compile -R "$WORK/mydev" MyDev "$WORK/mydev/PartA.v" >/dev/null
rocq compile -R "$WORK/mydev" MyDev "$WORK/mydev/PartB.v" >/dev/null
rocq compile -R "$WORK/mydev" MyDev "$WORK/mydev/PartC.v" >/dev/null
rocq compile -R "$WORK/deep" Demo.Sub.Deep "$WORK/deep/DeepOne.v" >/dev/null
rocq compile -R "$WORK/other" Demo.Other "$WORK/other/Sibling.v" >/dev/null
rocq compile -R "$WORK/one" LibOne "$WORK/one/Mod.v" >/dev/null
rocq compile -R "$WORK/two" LibTwo "$WORK/two/Mod.v" >/dev/null
rocq compile -R "$WORK/three" LibThree "$WORK/three/Mod.v" >/dev/null
rocq compile -R "$WORK/excl" ExcludeDemo "$WORK/excl/CorelibClash.v" >/dev/null
rocq compile -R "$WORK/muta" MutLibA "$WORK/muta/MutA.v" >/dev/null
rocq compile -R "$WORK/mutb" MutLibB "$WORK/mutb/MutB.v" >/dev/null
rocq compile -R "$WORK/consa" ConstructLibA "$WORK/consa/ConstructA.v" >/dev/null
rocq compile -R "$WORK/consb" ConstructLibB "$WORK/consb/ConstructB.v" >/dev/null
rocq compile -R "$WORK/exclwina" ExclWinLibA "$WORK/exclwina/ExclWinA.v" >/dev/null
rocq compile -R "$WORK/exclwinb" ExclWinLibB "$WORK/exclwinb/ExclWinB.v" >/dev/null

# ---------------------------------------------------------------------------
echo "==> base fixture: native plugin command (Main.v)"
rocq compile $THEORIES -R "$WORK/mydev" MyDev test/fixtures/Main.v > "$WORK/main_out.txt" 2>&1
sed -n '/^NamespaceAnalysis:/,$p' "$WORK/main_out.txt" > "$WORK/main_plugin.txt"

echo "==> base fixture: external CLI (MainCli.v)"
"$CLI" -R "$WORK/mydev" MyDev --domain MyDev.PartA --domain MyDev.PartB \
  test/fixtures/MainCli.v > "$WORK/main_cli.txt"

diff -u test/expected/report.txt "$WORK/main_plugin.txt"
diff -u test/expected/report.txt "$WORK/main_cli.txt"
diff -u "$WORK/main_plugin.txt" "$WORK/main_cli.txt"

# ---------------------------------------------------------------------------
echo "==> multi-level domains (MultiLevel.v): shallower prefix still catches a deeper clash"
rocq compile $THEORIES -R "$WORK/deep" Demo.Sub.Deep -R "$WORK/other" Demo.Other \
  test/fixtures/MultiLevel.v > "$WORK/ml_out.txt" 2>&1
sed -n '/^NamespaceAnalysis:/,$p' "$WORK/ml_out.txt" > "$WORK/ml_plugin.txt"
"$CLI" -R "$WORK/deep" Demo.Sub.Deep -R "$WORK/other" Demo.Other --domain Demo.Sub \
  test/fixtures/MultiLevelCli.v > "$WORK/ml_cli.txt"
diff -u "$WORK/ml_plugin.txt" "$WORK/ml_cli.txt"
grep -q "NamespaceAnalysis: 1 symbol(s) in scanned domain(s)" "$WORK/ml_plugin.txt"
grep -q "Demo.Sub.Deep.DeepOne.Gadget" "$WORK/ml_plugin.txt"
grep -q "Demo.Other.Sibling.Gadget <- used" "$WORK/ml_plugin.txt"

# ---------------------------------------------------------------------------
echo "==> 0/1/2/3 domain arguments (ThreeDomains.v)"
rocq compile $THEORIES -R "$WORK/one" LibOne -R "$WORK/two" LibTwo -R "$WORK/three" LibThree \
  test/fixtures/ThreeDomains.v > "$WORK/td_out.txt" 2>&1
split_blocks "$WORK/td_out.txt" "$WORK/td"
# Block 1 = 0 domains ("everything imported"): don't exact-diff (includes the
# whole Corelib prelude, which is large and not the point of this test) --
# just check it's clearly broader in scope and still finds the real clash.
grep -q "^NamespaceAnalysis: [0-9]* symbol(s)" "$WORK/td_1"
MEMBER_COUNT_0=$(grep -o '[0-9]*' "$WORK/td_1" | head -1)
[ "$MEMBER_COUNT_0" -gt 3 ] || { echo "expected 0-domain member count > 3, got $MEMBER_COUNT_0"; exit 1; }
grep -q "LibThree.Mod.Shared <- used" "$WORK/td_1"
grep -q "LibOne.Mod.Shared" "$WORK/td_1"
grep -q "LibTwo.Mod.Shared" "$WORK/td_1"
# Blocks 2/3/4 = 1/2/3 named domains: identical clash content each time --
# naming fewer than all three still surfaces clashes against the others.
for n in 2 3 4; do
  grep -q "LibThree.Mod.Shared <- used" "$WORK/td_$n"
  grep -q "LibOne.Mod.Shared" "$WORK/td_$n"
  grep -q "LibTwo.Mod.Shared" "$WORK/td_$n"
done
diff -u <(grep -v '^NamespaceAnalysis:' "$WORK/td_2") <(grep -v '^NamespaceAnalysis:' "$WORK/td_3")
diff -u <(grep -v '^NamespaceAnalysis:' "$WORK/td_3") <(grep -v '^NamespaceAnalysis:' "$WORK/td_4")

echo "==> 0/1/2/3 domain arguments, CLI parity"
"$CLI" -R "$WORK/one" LibOne -R "$WORK/two" LibTwo -R "$WORK/three" LibThree \
  test/fixtures/ThreeDomainsCli.v > "$WORK/td_cli_1"
"$CLI" -R "$WORK/one" LibOne -R "$WORK/two" LibTwo -R "$WORK/three" LibThree --domain LibOne.Mod \
  test/fixtures/ThreeDomainsCli.v > "$WORK/td_cli_2"
"$CLI" -R "$WORK/one" LibOne -R "$WORK/two" LibTwo -R "$WORK/three" LibThree --domain LibOne.Mod --domain LibTwo.Mod \
  test/fixtures/ThreeDomainsCli.v > "$WORK/td_cli_3"
"$CLI" -R "$WORK/one" LibOne -R "$WORK/two" LibTwo -R "$WORK/three" LibThree --domain LibOne.Mod --domain LibTwo.Mod --domain LibThree.Mod \
  test/fixtures/ThreeDomainsCli.v > "$WORK/td_cli_4"
for n in 2 3 4; do
  diff -u <(grep -v '^NamespaceAnalysis:' "$WORK/td_$n") <(grep -v '^NamespaceAnalysis:' "$WORK/td_cli_$n")
done

# ---------------------------------------------------------------------------
echo "==> hypothetical (not-yet-imported) domain (Hypothetical.v)"
rocq compile $THEORIES -R "$WORK/mydev" MyDev test/fixtures/Hypothetical.v > "$WORK/hyp_out.txt" 2>&1
split_blocks "$WORK/hyp_out.txt" "$WORK/hyp"
# First block: PartC was never Required in this file, only named as an
# argument -- the report should still surface it as a would-be clash against
# what's actually imported (PartA), with PartA correctly shown as the winner.
grep -q "MyDev.PartA.K <- used" "$WORK/hyp_1"
grep -q "MyDev.PartC.K" "$WORK/hyp_1"
# Second block (after `Check K.`): proves no short-name pollution occurred --
# K must still resolve to PartA, never PartC, since PartC was only Required,
# never Imported.
HYP_USED_SECTION="$(sed -n '/^Used identifiers:/,$p' "$WORK/hyp_2")"
echo "$HYP_USED_SECTION" | grep -q "MyDev.PartA"
if echo "$HYP_USED_SECTION" | grep -q "MyDev.PartC"; then
  echo "FAIL: K resolved to MyDev.PartC -- hypothetical domain polluted short-name visibility"
  exit 1
fi

echo "==> hypothetical domain, CLI parity"
# Compared against block 2 (post-`Check K.`), not block 1: the CLI always
# processes the whole file before analyzing, so its single report lines up
# with the plugin's state *after* Check K has already run, same as block 2.
"$CLI" -R "$WORK/mydev" MyDev --domain MyDev.PartC test/fixtures/HypotheticalCli.v > "$WORK/hyp_cli"
diff -u <(grep -v '^NamespaceAnalysis:' "$WORK/hyp_2") <(grep -v '^NamespaceAnalysis:' "$WORK/hyp_cli")

# ---------------------------------------------------------------------------
echo "==> exclude/include (ExcludeInclude.v): Corelib hidden by default, shown with --include"
rocq compile $THEORIES -R "$WORK/excl" ExcludeDemo test/fixtures/ExcludeInclude.v > "$WORK/ei_out.txt" 2>&1
split_blocks "$WORK/ei_out.txt" "$WORK/ei"
grep -q "No clashes found." "$WORK/ei_1"
grep -q "ExcludeDemo.CorelibClash.double <- used" "$WORK/ei_2"
grep -q "Corelib.Init.Nat.double" "$WORK/ei_2"

echo "==> exclude/include, CLI parity"
"$CLI" -R "$WORK/excl" ExcludeDemo --domain ExcludeDemo.CorelibClash \
  test/fixtures/ExcludeIncludeCli.v > "$WORK/ei_cli_default"
"$CLI" -R "$WORK/excl" ExcludeDemo --domain ExcludeDemo.CorelibClash --include Corelib \
  test/fixtures/ExcludeIncludeCli.v > "$WORK/ei_cli_included"
grep -q "No clashes found." "$WORK/ei_cli_default"
grep -q "ExcludeDemo.CorelibClash.double <- used" "$WORK/ei_cli_included"

# ---------------------------------------------------------------------------
echo "==> mutual-inductive clash (MutualInductive.v): second type in a mutual block is scanned"
rocq compile $THEORIES -R "$WORK/muta" MutLibA -R "$WORK/mutb" MutLibB \
  test/fixtures/MutualInductive.v > "$WORK/mut_out.txt" 2>&1
sed -n '/^NamespaceAnalysis:/,$p' "$WORK/mut_out.txt" > "$WORK/mut_plugin.txt"
# SharedName is the *second* inductive in each library's two-type mutual
# block (`FirstA`/`FirstB` come first) -- before the fix, `members_of_domains`
# hardcoded index 0 and never saw it from either library, so this clash was
# silently missed entirely (the name never even entered the candidate set).
grep -q "MutLibA.MutA.SharedName" "$WORK/mut_plugin.txt"
grep -q "MutLibB.MutB.SharedName <- used" "$WORK/mut_plugin.txt"

echo "==> mutual-inductive clash, CLI parity"
"$CLI" -R "$WORK/muta" MutLibA -R "$WORK/mutb" MutLibB --domain MutLibA --domain MutLibB \
  test/fixtures/MutualInductiveCli.v > "$WORK/mut_cli.txt"
diff -u "$WORK/mut_plugin.txt" "$WORK/mut_cli.txt"

# ---------------------------------------------------------------------------
echo "==> constructor clash (ConstructorClash.v): same-named constructors across libraries are scanned"
rocq compile $THEORIES -R "$WORK/consa" ConstructLibA -R "$WORK/consb" ConstructLibB \
  test/fixtures/ConstructorClash.v > "$WORK/cons_out.txt" 2>&1
sed -n '/^NamespaceAnalysis:/,$p' "$WORK/cons_out.txt" > "$WORK/cons_plugin.txt"
# `Node` is a constructor of each library's differently-named inductive type
# (`TreeA`/`TreeB`), so this only clashes at the constructor level -- before
# the fix, constructors were never enumerated as domain members at all, so
# this "last import wins" hazard was invisible.
grep -q "ConstructLibA.ConstructA.Node" "$WORK/cons_plugin.txt"
grep -q "ConstructLibB.ConstructB.Node <- used" "$WORK/cons_plugin.txt"

echo "==> constructor clash, CLI parity"
"$CLI" -R "$WORK/consa" ConstructLibA -R "$WORK/consb" ConstructLibB --domain ConstructLibA --domain ConstructLibB \
  test/fixtures/ConstructorClashCli.v > "$WORK/cons_cli.txt"
diff -u "$WORK/cons_plugin.txt" "$WORK/cons_cli.txt"

# ---------------------------------------------------------------------------
echo "==> excluded winner (ExcludedWinner.v): actual winner under an excluded prefix reports no winner"
rocq compile $THEORIES -R "$WORK/exclwina" ExclWinLibA -R "$WORK/exclwinb" ExclWinLibB \
  test/fixtures/ExcludedWinner.v > "$WORK/ew_out.txt" 2>&1
sed -n '/^NamespaceAnalysis:/,$p' "$WORK/ew_out.txt" > "$WORK/ew_plugin.txt"
# `Import Nat.` makes `double` actually resolve, right now, to the excluded
# Corelib.Init.Nat.double -- neither ExclWinLibA nor ExclWinLibB is ever
# Import-ed (both are Require-only "hypothetical" probe domains, like
# Hypothetical.v), so nothing about the file's real name resolution changes.
# The clash must still be reported (2 non-excluded alternatives), but with
# no winner marked, since the actual winner (Corelib) is excluded --
# "Used identifiers" independently proves the real resolution to pin the gap
# between "what's really visible" and "what the report can call a winner".
grep -q "ExclWinLibA.ExclWinA.double" "$WORK/ew_plugin.txt"
grep -q "ExclWinLibB.ExclWinB.double" "$WORK/ew_plugin.txt"
if grep -q -- "<- used" "$WORK/ew_plugin.txt"; then
  echo "FAIL: excluded-winner clash unexpectedly marked a winner"
  exit 1
fi
grep -q "double.*Corelib.Init.Nat" "$WORK/ew_plugin.txt"

echo "==> excluded winner, CLI parity"
"$CLI" -R "$WORK/exclwina" ExclWinLibA -R "$WORK/exclwinb" ExclWinLibB \
  --domain ExclWinLibA.ExclWinA --domain ExclWinLibB.ExclWinB \
  test/fixtures/ExcludedWinnerCli.v > "$WORK/ew_cli.txt"
diff -u "$WORK/ew_plugin.txt" "$WORK/ew_cli.txt"

# ---------------------------------------------------------------------------
echo "==> batch mode (--dir): aggregates occurrences across multiple target files into one report"
# Two independent target files (test/fixtures/batch/{One,Two}.v), each
# Requiring a different half of MyDev and Check-ing a different identifier.
# Neither file alone would surface both -- this is specifically checking
# that Glob_capture's occurrence buffer accumulates across every file in the
# batch, not just the last one loaded. (Note: "Defined in" is always the
# *defining* library's logical dirpath -- Dumpglob's own filepath field is
# `Names.DirPath.to_string lib_dp`, not the analyzed source file -- so both
# rows below correctly still say "MyDev.PartA"/"MyDev.PartB", not the path
# to One.v/Two.v; what's being checked is that both rows appear at all.)
"$CLI" -R "$WORK/mydev" MyDev --domain MyDev.PartA --domain MyDev.PartB \
  --dir test/fixtures/batch > "$WORK/batch_grid.txt"
grep -q "helper.*MyDev.PartA" "$WORK/batch_grid.txt"
grep -q "K.*MyDev.PartB" "$WORK/batch_grid.txt"
grep -q "MyDev.PartB.K <- used" "$WORK/batch_grid.txt"

echo "==> batch mode, backward compatibility: single-file invocation is still byte-identical"
"$CLI" -R "$WORK/mydev" MyDev --domain MyDev.PartA --domain MyDev.PartB \
  test/fixtures/MainCli.v > "$WORK/batch_compat.txt"
diff -u test/expected/report.txt "$WORK/batch_compat.txt"

echo "==> --format summary / --format json agree with the grid on the same batch input"
"$CLI" -R "$WORK/mydev" MyDev --domain MyDev.PartA --domain MyDev.PartB \
  --dir test/fixtures/batch --format summary > "$WORK/batch_summary.txt"
grep -q "1 clash(es) found (0 with no winner marked), 2 identifier(s) used" "$WORK/batch_summary.txt"
"$CLI" -R "$WORK/mydev" MyDev --domain MyDev.PartA --domain MyDev.PartB \
  --dir test/fixtures/batch --format json > "$WORK/batch_json.txt"
grep -q '"name":"K","winner":"MyDev.PartB.K","alternatives":\["MyDev.PartA.K"\]' "$WORK/batch_json.txt"
grep -q '"identifier":"helper","defined_in":"MyDev.PartA"' "$WORK/batch_json.txt"
grep -q '"identifier":"K","defined_in":"MyDev.PartB"' "$WORK/batch_json.txt"

echo "==> --format rejects an unknown value cleanly"
set +e
OUT=$("$CLI" -R "$WORK/mydev" MyDev --format bogus test/fixtures/MainCli.v 2>&1)
CODE=$?
set -e
[ "$CODE" -eq 1 ] || { echo "FAIL: expected exit 1 for unknown --format, got $CODE"; exit 1; }
echo "$OUT" | grep -q "unknown --format value"

# ---------------------------------------------------------------------------
echo "==> error-path tests"
bash "$ROOT/test/run_error_test.sh"

echo "ALL TESTS PASSED"
