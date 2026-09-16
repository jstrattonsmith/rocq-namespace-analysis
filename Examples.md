# Examples: features added this session

Holding file for concrete, runnable examples of the features added while
working through `PLANNING.md` (Workstreams 1, 2, and the odoc documentation
setup). Fold these into the README (or wherever they belong) later; for now
this is one spot to refer back to.

All commands assume `nix develop` and `dune build` have already been run
from the repo root, with:

```sh
export OCAMLPATH="$PWD/_build/install/default/lib:${OCAMLPATH:-}"
CLI="$PWD/_build/default/cli/namespace_analysis_cli.exe"
```

## 1. Mutual-inductive scanning (Workstream 1)

**Bug fixed**: `members_of_domains` used to hardcode inductive index `0`, so
for `Inductive A := ... with B := ...`, only `A` was ever scanned as a
domain member -- `B` was invisible to clash detection.

**Fixture libraries** (`test/fixtures/libs/mutual/{a,b}/`):

`MutA.v`:
```coq
Inductive FirstA : Set :=
  | FirstAMk : FirstA
with SharedName : Set :=
  | SharedAMk : FirstA -> SharedName.
```

`MutB.v`:
```coq
Inductive FirstB : Set :=
  | FirstBMk : FirstB
with SharedName : Set :=
  | SharedBMk : FirstB -> SharedName.
```

`SharedName` is the *second* type in each library's own two-type mutual
block -- exactly the case the bug missed.

**Command:**
```sh
rocq compile -R /tmp/ex_muta MutLibA /tmp/ex_muta/MutA.v
rocq compile -R /tmp/ex_mutb MutLibB /tmp/ex_mutb/MutB.v

"$CLI" -R /tmp/ex_muta MutLibA -R /tmp/ex_mutb MutLibB \
  --domain MutLibA --domain MutLibB \
  test/fixtures/MutualInductiveCli.v
```

**Actual output:**
```
NamespaceAnalysis: 24 symbol(s) in scanned domain(s)
Clashes:
┌─────────────────┬──────────────────────────────────────┐
│ Short name      │ Candidates (alphabetical)            │
├─────────────────┼──────────────────────────────────────┤
│ SharedName      │ MutLibA.MutA.SharedName              │
│                 │ MutLibB.MutB.SharedName <- used      │
├─────────────────┼──────────────────────────────────────┤
│ SharedName_ind  │ MutLibA.MutA.SharedName_ind          │
│                 │ MutLibB.MutB.SharedName_ind <- used  │
├─────────────────┼──────────────────────────────────────┤
│ SharedName_rec  │ MutLibA.MutA.SharedName_rec          │
│                 │ MutLibB.MutB.SharedName_rec <- used  │
├─────────────────┼──────────────────────────────────────┤
│ SharedName_rect │ MutLibA.MutA.SharedName_rect         │
│                 │ MutLibB.MutB.SharedName_rect <- used │
├─────────────────┼──────────────────────────────────────┤
│ SharedName_sind │ MutLibA.MutA.SharedName_sind         │
│                 │ MutLibB.MutB.SharedName_sind <- used │
└─────────────────┴──────────────────────────────────────┘
Used identifiers:
┌────────────┬──────────────┐
│ Identifier │ Defined in   │
├────────────┼──────────────┤
│ SharedName │ MutLibB.MutB │
└────────────┴──────────────┘
```

**Bonus finding, unplanned**: Rocq auto-generates induction-scheme constants
(`_ind`/`_rec`/`_rect`/`_sind`) per inductive type, and those are ordinary
`Constant`s that were *already* scanned correctly before this fix. Once
`SharedName` itself became visible as a member, its four auto-generated
schemes clashed too -- so this one fix surfaces 5 real clashes per
mutual-inductive short-name collision, not just 1. Worth a mention in the
talk: the "last import wins" hazard is wider than the syntactically-written
type/constructor name alone.

Before the fix, none of these five rows appeared at all -- the whole clash
was silently missed (confirmed: reverting the fix and re-running
`test/run_test.sh` fails at this section, see commit history).

## 2. Constructor scanning (Workstream 2)

**Gap fixed**: constructors (`GlobRef.ConstructRef`) were never enumerated
as domain members -- only constants and inductive *types* were. Two
libraries defining a constructor with the same short name (e.g. `Ok`,
`Node`, `Some`) never got flagged.

**Fixture libraries** (`test/fixtures/libs/construct/{a,b}/`):

`ConstructA.v`:
```coq
Inductive TreeA : Set := Node : TreeA.
```

`ConstructB.v`:
```coq
Inductive TreeB : Set := Node : TreeB.
```

Note the *type* names differ (`TreeA`/`TreeB`, no clash there) -- only the
*constructor* name `Node` collides, isolating this from the mutual-inductive
case above.

**Command:**
```sh
rocq compile -R /tmp/ex_consa ConstructLibA /tmp/ex_consa/ConstructA.v
rocq compile -R /tmp/ex_consb ConstructLibB /tmp/ex_consb/ConstructB.v

"$CLI" -R /tmp/ex_consa ConstructLibA -R /tmp/ex_consb ConstructLibB \
  --domain ConstructLibA --domain ConstructLibB \
  test/fixtures/ConstructorClashCli.v
```

**Actual output:**
```
NamespaceAnalysis: 12 symbol(s) in scanned domain(s)
Clashes:
┌────────────┬───────────────────────────────────────┐
│ Short name │ Candidates (alphabetical)             │
├────────────┼───────────────────────────────────────┤
│ Node       │ ConstructLibA.ConstructA.Node         │
│            │ ConstructLibB.ConstructB.Node <- used │
└────────────┴───────────────────────────────────────┘
Used identifiers:
┌────────────┬──────────────────────────┐
│ Identifier │ Defined in               │
├────────────┼──────────────────────────┤
│ Node       │ ConstructLibB.ConstructB │
└────────────┴──────────────────────────┘
```

Before the fix, `Node` never appeared as a member from either library, so it
never entered the candidate-name set at all -- this clash was invisible, not
just under-reported.

## 3. OCaml API docs via odoc

Not a clash-detection feature, but new project capability added this
session: `src/*.mli` files already carry ocamldoc-style `(** ... *)`
comments (odoc is the default OCaml documentation mechanism), and `odoc` is
now in the Nix dev shell (`flake.nix`).

**Command:**
```sh
dune build @doc
```

**Output**: HTML lands in
`_build/default/_doc/_html/rocq-namespace-analysis/`; open `index.html`
from there, e.g.:

```sh
open _build/default/_doc/_html/rocq-namespace-analysis/index.html
```

Per-module pages exist for every documented module, e.g.
`_build/default/_doc/_html/rocq-namespace-analysis/Domain_scan/index.html`
now documents the updated `members_of_domains` behavior (mutual-inductive +
constructor scanning) straight from the `.mli` comment.

## 4. Clean CLI error messages (Workstream 4)

**Bug fixed**: the CLI had no top-level exception handler, so anything past
argument parsing escaped as a raw, uncaught OCaml exception dump with exit
code 2, instead of a clean one-line message with exit code 1 the way
`rocq compile` itself handles the same bad input.

**Before** (confirmed by reverting the fix):
```
$ namespace-analysis -R /no/such/dir SomeDirPath MyFile.v
Fatal error: exception Synterp.UnmappedLibrary(_, _)
$ echo $?
2
```

**After:**
```
$ namespace-analysis -R /no/such/dir SomeDirPath MyFile.v
File "MyFile.v", line 1, characters 26-31:
Error: Cannot find a physical path bound to logical path
PartA with prefix MyDev.
$ echo $?
1
```

Same clean behavior now for a `.v` file that fails to compile:
```
$ namespace-analysis test/fixtures/BadCompile.v
File "test/fixtures/BadCompile.v", line 1, characters 24-28:
Error:
The term "true" has type "bool" while it is expected to have type "nat".
$ echo $?
1
```

...and for a malformed `--domain` string:
```
$ namespace-analysis -R /tmp/mydev MyDev --domain "not a valid ident!!" MyFile.v
Error: Invalid character ' ' in identifier "not a valid ident!!".
$ echo $?
1
```

See `test/run_error_test.sh` for all four error-path cases (including the
already-clean "no target file" case), run automatically at the end of
`test/run_test.sh`.

## 5. Pinning the "excluded winner" edge case (Workstream 5)

**What this pins**: README's "Known limitations" flags an open design
question -- if the symbol that's *actually* currently resolved for a short
name falls under an excluded prefix (`Corelib` by default), the clash is
still reported, but with no winner singled out (rather than either hiding
the clash entirely or revealing an excluded winner anyway). No fixture
exercised this before; this doesn't resolve the design question, just stops
it from being an untested code path.

**Fixture libraries** (`test/fixtures/libs/exclwinner/{a,b}/`), both defined
but deliberately never `Import`ed -- only ever named as probe-domain
arguments (`Require`-only, like the existing `Hypothetical.v` pattern):

`ExclWinA.v`: `Definition double (n : nat) := n + n.`
`ExclWinB.v`: `Definition double (n : nat) := n * 2.`

**Fixture file** (`test/fixtures/ExcludedWinner.v`) does `Import Nat.` --
making `Corelib.Init.Nat.double` the actual, currently-resolving `double`
right now -- then probes the two never-imported libraries above:

```coq
From NamespaceAnalysis Require Import Loader.
Import Nat.

Check double.

NamespaceAnalysis ExclWinLibA.ExclWinA ExclWinLibB.ExclWinB.
```

**Actual output:**
```
NamespaceAnalysis: 2 symbol(s) in scanned domain(s)
Clashes:
┌────────────┬─────────────────────────────┐
│ Short name │ Candidates (alphabetical)   │
├────────────┼─────────────────────────────┤
│ double     │ ExclWinLibA.ExclWinA.double │
│            │ ExclWinLibB.ExclWinB.double │
└────────────┴─────────────────────────────┘
Used identifiers:
┌────────────┬──────────────────┐
│ Identifier │ Defined in       │
├────────────┼──────────────────┤
│ double     │ Corelib.Init.Nat │
└────────────┴──────────────────┘
```

The clash is reported (2 non-excluded alternatives, neither ever `Import`ed
in this file) with **no** `<- used` marker on either row -- even though
"Used identifiers" independently proves `double` really does resolve, right
now, to `Corelib.Init.Nat.double`. That gap between "what's really visible"
and "what the report can call a winner" is exactly the pinned behavior.

Confirmed load-bearing: temporarily removing the excluded-prefix check on
`winner` in `src/clash_detect.ml` (so an excluded symbol could be reported
as the winner) makes this test section fail with `FAIL: excluded-winner
clash unexpectedly marked a winner`; reverted immediately after confirming.

## 6. CI (Workstream 7)

**What's new**: `.github/workflows/test.yml` runs `nix develop -c bash
test/run_test.sh` (which already invokes `test/run_error_test.sh` at the
end) on every push/PR to `main`, using `cachix/install-nix-action` to get
Nix working on `ubuntu-latest`. Nix path only — see README "Building" for
why the Homebrew path isn't also CI'd.

**Confirmed actually green**, not just "should work": watched two real runs
with `gh run watch --exit-status`.
- [`35004564508`](https://github.com/jstrattonsmith/rocq-namespace-analysis/actions/runs/35004564508):
  initial run, ~45s, one harmless Node.js-20-deprecation annotation from
  `actions/checkout@v4` (GitHub forcing it onto Node 24).
- [`35004704388`](https://github.com/jstrattonsmith/rocq-namespace-analysis/actions/runs/35004704388):
  after bumping to `actions/checkout@v7`, ~41s, no annotations.

Both runs finished in well under a minute with no packages built from
source — nixpkgs' binary cache already had every dependency (`rocq-core`,
`dune`, `ocaml`, `odoc`, etc.) for the pinned `flake.lock` revision.

## 7. Batch mode and output formats (Workstream 8)

**Fixture files** (`test/fixtures/batch/`) -- two independent target files,
each `Require`ing a different half of `MyDev` and `Check`-ing a different
identifier, so that only a correctly-aggregating batch run surfaces both:

`One.v`:
```coq
From MyDev Require Import PartA.

Check helper 3.
```

`Two.v`:
```coq
From MyDev Require Import PartB.

Check K.
```

**Command:**
```sh
namespace-analysis -R path/to/libs MyDev --domain MyDev.PartA --domain MyDev.PartB \
  --dir test/fixtures/batch
```

**Actual output** -- both `helper` (from `One.v`) and `K` (from `Two.v`)
appear in one aggregated report, proving `Glob_capture` accumulated
occurrences across both files rather than just the last one loaded:
```
NamespaceAnalysis: 3 symbol(s) in scanned domain(s)
Clashes:
┌────────────┬───────────────────────────┐
│ Short name │ Candidates (alphabetical) │
├────────────┼───────────────────────────┤
│ K          │ MyDev.PartA.K             │
│            │ MyDev.PartB.K <- used     │
└────────────┴───────────────────────────┘
Used identifiers:
┌────────────┬─────────────┐
│ Identifier │ Defined in  │
├────────────┼─────────────┤
│ helper     │ MyDev.PartA │
├────────────┼─────────────┤
│ K          │ MyDev.PartB │
└────────────┴─────────────┘
```

Note "Defined in" shows the *defining* library for both rows, not `One.v`
or `Two.v` -- that column was always the identifier's definition location,
not the analyzed source file (`Dumpglob`'s own `filepath` field is
`Names.DirPath.to_string lib_dp`, confirmed by reading
`rocq-runtime`'s `interp/dumpglob.ml` directly). What proves multi-file
aggregation here is that *both rows appear at all*, not what's in that
column.

**`--format summary`** on the same input:
```
NamespaceAnalysis: 3 symbol(s) in scanned domain(s), 1 clash(es) found (0 with no winner marked), 2 identifier(s) used
```

**`--format json`** on the same input:
```json
{"member_count":3,"clashes":[{"name":"K","winner":"MyDev.PartB.K","alternatives":["MyDev.PartA.K"]}],"used":[{"identifier":"helper","defined_in":"MyDev.PartA"},{"identifier":"K","defined_in":"MyDev.PartB"}]}
```

**Backward compatibility confirmed, not just claimed**: the same single-file
invocation that predates batch mode (`MainCli.v` against `test/expected/report.txt`)
still diffs byte-identical after this change.

**Confirmed load-bearing**: reverting `cli/namespace_analysis_cli.ml` back
to its pre-batch-mode version makes `test/run_test.sh` fail immediately at
the new batch-mode section with a clean `Don't know what to do with --dir`
from Rocq's own argument parser (the flag falls through to it once our own
parser no longer claims it) -- confirmed directly, then reverted.
