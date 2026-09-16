#!/usr/bin/env bash
# Compiles the fixture *libraries* in place (persistent), unlike
# test/run_test.sh's own ephemeral mktemp workdir (deleted on exit) --
# so that the top-level fixture files (test/fixtures/Main.v,
# MutualInductive.v, ConstructorClash.v, ExcludedWinner.v, ...) can be
# opened directly in an editor with their `Require Import` lines resolving,
# via the matching -R mappings in _CoqProject.
#
# Usage: bash test/build_fixtures.sh   (run once after `dune build`, before
# opening a fixture .v file in an editor; safe to re-run any time, e.g.
# after editing a fixture library)
#
# Not run by test/run_test.sh itself -- that script deliberately keeps the
# repo clean during CI by compiling into a temp dir instead. This script is
# purely for interactive/editor use.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

compile() {
  local dir="$1" name="$2"
  shift 2
  for f in "$@"; do
    rocq compile -R "$dir" "$name" "$dir/$f" >/dev/null
  done
}

compile test/fixtures/libs MyDev PartA.v PartB.v PartC.v
compile test/fixtures/libs/multilevel/deep Demo.Sub.Deep DeepOne.v
compile test/fixtures/libs/multilevel/other Demo.Other Sibling.v
compile test/fixtures/libs/three/one LibOne Mod.v
compile test/fixtures/libs/three/two LibTwo Mod.v
compile test/fixtures/libs/three/three LibThree Mod.v
compile test/fixtures/libs/excldemo ExcludeDemo CorelibClash.v
compile test/fixtures/libs/mutual/a MutLibA MutA.v
compile test/fixtures/libs/mutual/b MutLibB MutB.v
compile test/fixtures/libs/construct/a ConstructLibA ConstructA.v
compile test/fixtures/libs/construct/b ConstructLibB ConstructB.v
compile test/fixtures/libs/exclwinner/a ExclWinLibA ExclWinA.v
compile test/fixtures/libs/exclwinner/b ExclWinLibB ExclWinB.v

echo "Fixture libraries compiled. Open e.g. test/fixtures/Main.v,"
echo "test/fixtures/MutualInductive.v, test/fixtures/ConstructorClash.v, or"
echo "test/fixtures/ExcludedWinner.v directly in your editor."
