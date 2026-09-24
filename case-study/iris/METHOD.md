# Case study: Iris 4.5.0 (Workstream 9, Pass 2)

How to reproduce this run from a clean checkout of this repo. See
`RESULTS.md` in this same directory for what it found.

## What's analyzed, and why this target

[Iris](https://iris-project.org/) 4.5.0 (tag `iris-4.5.0`, commit
`b909adcc698a6c38f4c3b2645936bdd0d870d412`), a widely used separation-logic
framework: 178 compiled `.v` files across `iris`, `iris.heap_lang`,
`iris.unstable` and `iris.deprecated`, on top of stdpp 1.13.0 and Rocq's
Stdlib.

Chosen over the originally planned `mech-eff-insep` corpus because nixpkgs
packages Iris and stdpp, prebuilt, for **the exact Rocq 9.1.1 build this repo
pins**, so the analysis runs with this repo's own unmodified toolchain.
`mech-eff-insep` is built with Rocq 9.0 and would need a throwaway rebuild of
the tool first.

**Scope = the Nix-installed tree, not the source checkout.** The installed
`user-contrib/iris` directory holds a `.v` next to every `.vo`, and exactly
the files Iris's own build compiles. The source tree has one extra file the
build skips (`iris/base_logic/lib/mono_Z.v`, on disk but not in
`config/source-list`), so `--dir` over the source tree would analyze one
file too many. Iris's `tests/` directory isn't built or installed either.

## Environment

- This repo with Workstream 11 (built-in import status) or later, Rocq
  9.1.1, via `nix develop`. The first version of this case study (commit
  `b1f4269`) needed a separate probe-patched run for the import-status
  split; that probe is now part of the tool.
- About 25 GB free disk is plenty; the Iris/stdpp/Stdlib store paths are a
  few hundred MB, fetched prebuilt from `cache.nixos.org`.
- `gitlab.mpi-sws.org` (Iris's home) wasn't reachable from the machine this
  was run on; nothing here needs it. For reading the original sources, the
  same tagged tree is `rocqPackages_9_1.iris.src` in nixpkgs, hash-checked by
  Nix.

## Commands

All from this repo's root, inside `nix develop`.

```sh
dune build
export OCAMLPATH="$PWD/_build/install/default/lib:${OCAMLPATH:-}"
CLI="$PWD/_build/default/cli/namespace_analysis_cli.exe"

# Iris, stdpp and Stdlib, built for the exact nixpkgs revision this repo pins.
nixpkg() {
  nix build --no-link --print-out-paths --impure --expr \
    "let f = builtins.getFlake (toString ./.);
         p = import f.inputs.nixpkgs { system = builtins.currentSystem; };
     in p.rocqPackages_9_1.$1"
}
UC=lib/coq/9.1/user-contrib
export ROCQPATH="$(nixpkg iris)/$UC:$(nixpkg stdpp)/$UC:$(nixpkg stdlib)/$UC"
IRIS="$(nixpkg iris)/$UC/iris"

# lia leaves a .lia.cache in the working directory; run from a scratch dir.
RUN=$(mktemp -d)
```

**The run.** `--domain iris` covers all four logical roots, since the
other three sit under `iris.`. Name the domain explicitly: with 0 domains,
the clash grid would instead scan every loaded library, Stdlib and stdpp
included. `-w -notation-overridden` only silences a warning Iris itself
turns off in its own build (`config/flags`).

```sh
(cd "$RUN" && /usr/bin/time -l "$CLI" -w -notation-overridden --domain iris \
  --dir "$IRIS" --format json > batch.json 2> run.err)
```

**Analysis**: every number in `RESULTS.md` comes from this script's output
(`triage_output.txt`). It also regenerates `sites.tsv` (one row per
ambiguous use site) and `output.json` (the run, trimmed to counts plus every
ambiguous use; the full file is ~21 MB).

```sh
python3 case-study/iris/triage.py "$RUN/batch.json" case-study/iris
```

The run takes about 3.5–4 minutes (178 files, one worker process each, run
one after another).

## How the split is made

The tool reports an **ambiguous use** wherever a name, as written, had more
than one candidate at the point it was used. That mixes two situations the
tool itself can't tell apart, because Rocq's public `Nametab` API doesn't
expose them (see the README's "Known limitations"):

- **shadowed**: the other candidate's module *was* imported, so the
  candidate was reachable by that name and lost to a later import — real
  "last import wins";
- **latent**: the other candidate's module is only loaded (`Require`d,
  often indirectly), never imported. Nothing is overridden now; importing it
  later would change what the name means.

The tool tells them apart **without** Rocq's private state
(`src/import_status.ml`), using an indirect test: importing a module makes
*all* of its definitions reachable by bare name. So for each alternative,
it takes every other definition in the same module whose name no other
loaded definition shares, and checks whether that name resolves, bare, at
the use site. The tool reports five labels; `triage.py` then resolves the
two undecided ones for Iris specifically:

| Siblings resolving | Tool's label | How `triage.py` treats it |
|---|---|---|
| all | `shadowed` | shadowed |
| none | `not imported` | latent |
| some | `partly imported k/n` (a filtered import, e.g. `Export M (x)`) | ≥ 90% resolving → shadowed; below → latent (see below) |
| no testable sibling | `import status unknown` | latent (see below) |
| *(any)*, but the alternative is itself `Local` | `Local` | its own category: a `Local` definition is never reachable by its bare name, imported or not, so it can't be shadowed and can't flip anything later |

A use site counts as **shadowed** if any of its alternatives is shadowed;
otherwise **latent** if any is latent; otherwise **local-only**.

Two judgment calls, each checked against the source rather than assumed:

- **Filtered.** Two kinds of ratio occur in Iris. Stdlib `String` is 5/28:
  stdpp's `strings.v` does `Export String (string(..))`, deliberately
  importing only the `string` type, so `String.length` is really latent.
  Everything else is 27/28 to 56/57 (`ectx_language`, `gen_inv_heap`): an
  imported module with a single sibling that isn't reachable (e.g. a
  `#[local]` field), so those count as shadowed.
- **Unknown.** All 30 modules that got this verdict (Stdlib's `Pos`, `N`,
  `Z` submodules, `Private_Tac`s, `Vector`, `Z2N`/`N2Nat`/..., and two small
  Iris-internal modules, `iprop.gFunctors` and `sel_patterns.sel_pat`) were checked by `grep` to be never `Import`ed or
  `Export`ed anywhere in Iris or stdpp. So they count as latent.
  (`triage.py` prints the list.)

**History.** The test began as a throwaway probe for this case study and
went through three versions, each fixing something the hand check or a
real run turned up: (1) one sibling per module, fooled by stdpp's filtered
`String` export; (2) all uniquely named siblings, with the "partly
imported" verdict; (3) plus each alternative's own `Local` flag, after
Iris's sealing pattern (`Local Definition ..._unseal`) showed up as
"shadowed". Version 3 became the tool's `Import_status` (Workstream 11),
which also tests constructors and every inductive of a mutual block as
siblings; rerunning Iris with it matched the probe on all 5,841 (use site,
alternative) pairs. The probe itself is in git history
(`case-study/iris/import_probe.patch` at commit `b1f4269`).

**Hand verification.** 30 sites drawn at random (seed 2027) from the first
version's verdicts, stratified 12 shadowed / 12 latent / 6 unknown, were
each checked against the Iris/stdpp sources: the file's own imports, and
the `Require Export` chains behind them. See `RESULTS.md` §4.
