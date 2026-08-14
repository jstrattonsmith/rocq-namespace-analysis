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
mkdir -p "$WORK/mydev" "$WORK/deep" "$WORK/other" "$WORK/one" "$WORK/two" "$WORK/three" "$WORK/excl"
cp test/fixtures/libs/PartA.v test/fixtures/libs/PartB.v test/fixtures/libs/PartC.v "$WORK/mydev/"
cp test/fixtures/libs/multilevel/deep/DeepOne.v "$WORK/deep/"
cp test/fixtures/libs/multilevel/other/Sibling.v "$WORK/other/"
cp test/fixtures/libs/three/one/Mod.v "$WORK/one/"
cp test/fixtures/libs/three/two/Mod.v "$WORK/two/"
cp test/fixtures/libs/three/three/Mod.v "$WORK/three/"
cp test/fixtures/libs/excldemo/CorelibClash.v "$WORK/excl/"
rocq compile -R "$WORK/mydev" MyDev "$WORK/mydev/PartA.v" >/dev/null
rocq compile -R "$WORK/mydev" MyDev "$WORK/mydev/PartB.v" >/dev/null
rocq compile -R "$WORK/mydev" MyDev "$WORK/mydev/PartC.v" >/dev/null
rocq compile -R "$WORK/deep" Demo.Sub.Deep "$WORK/deep/DeepOne.v" >/dev/null
rocq compile -R "$WORK/other" Demo.Other "$WORK/other/Sibling.v" >/dev/null
rocq compile -R "$WORK/one" LibOne "$WORK/one/Mod.v" >/dev/null
rocq compile -R "$WORK/two" LibTwo "$WORK/two/Mod.v" >/dev/null
rocq compile -R "$WORK/three" LibThree "$WORK/three/Mod.v" >/dev/null
rocq compile -R "$WORK/excl" ExcludeDemo "$WORK/excl/CorelibClash.v" >/dev/null

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

echo "ALL TESTS PASSED"
