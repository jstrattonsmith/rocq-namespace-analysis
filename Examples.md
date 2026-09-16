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

## 8. Fixing an O(n^2) bottleneck in Clash_detect (performance)

**What prompted this**: a direct question about whether many conflicts
and/or many scanned symbols could cause slowdown or a hang ahead of the
Workstream 9 case study. Rather than guess, built a synthetic stress test
(two libraries with N identically-named `Definition`s each, all clashing)
and measured directly.

**Before the fix** -- `Clash_detect.find_clashes` grouped `members` by
short name via a full `List.filter` scan over *every* member, repeated
once per unique name: O(n) work per name, times n names, so O(n^2)
overall:

| Clashing symbols | Time |
|---|---|
| 1,000 | 0.16s |
| 10,000 | 10.65s |

A 10x growth in input produced a ~65-70x growth in runtime -- consistent
with roughly quadratic scaling, not a fluke.

**The fix**: group `members` by basename once, up front, via an `Id.Map`
(`src/clash_detect.ml`), turning the per-name lookup into an O(log n) map
access instead of an O(n) linear scan -- O(n log n) overall.

**After the fix**, same measurements plus a much larger one:

| Clashing symbols | Time |
|---|---|
| 1,000 | 0.037s |
| 10,000 | 0.146s (**~73x faster**) |
| 100,000 | 1.145s |

**Confirmed load-bearing**: `test/run_perf_test.sh` (auto-invoked from
`test/run_test.sh`) asserts an 8,000-clash scan completes within 5
seconds. Reverting the fix and re-running it: 7s, failing the assertion
(matching the extrapolated pre-fix estimate); with the fix: 0s.

**Answering the original question directly**: no, this doesn't hang --
even 100,000 simultaneous clashes (a scale a real corpus is very unlikely
to actually hit) complete in close to a second. The genuine risk at scale
isn't the algorithm anymore; it's the **grid output becoming unreadable**
long before it becomes slow -- 1,000 clashes alone render as a 3,007-line
box-drawing table. That's exactly what `--format summary`/`--format json`
(Workstream 8, section 7 above) are for: the same 1,000-clash run reduces
to one line via `--format summary`, or a JSON blob under 100KB via
`--format json`.

**Follow-up investigation: is there more headroom past the O(n log n)
fix?** Checked directly rather than guessing: ran 200,000 scanned members
with *zero* clashes (all unique names) and got ~1.24s -- essentially
identical to the 100,000-clash run above (1.145s). That means
`Clash_detect`'s per-name work is no longer the cost driver at all; the
remaining time is dominated by `Domain_scan.members_of_domains`'s
`Environ.fold_constants`/`fold_inductives`, which walks *every* object in
the entire kernel environment (Corelib included) regardless of how narrow
the probed domain is, filtering as it goes. Checked whether Rocq itself
has a faster path for this: read `vernacentries.ml`'s own `print_namespace`
(the implementation behind `Print Namespace`, which `Domain_scan`'s own
doc comment already says it mirrors) -- it does the exact same full
`Environ.fold_constants` walk, filtered by module-path match. There's no
faster official API; this is the real floor of "enumerate everything under
a dirpath prefix" as Rocq exposes it, not something specific to this
tool's own logic. A genuinely faster path would mean walking a named
domain's own compiled module structure directly instead of the whole
environment -- a real, understood, but substantially bigger re-architecture
of `Domain_scan`, not attempted here given 200,000 members already
completes in close to a second, an order of magnitude beyond anything a
real corpus is likely to contain.

---

The sections below backfill examples for the original v1/v2 feature set
(everything that predates `Examples.md` itself, from before Workstream 1)
-- prompted by an explicit "do we have examples for everything?" check
that found this gap. All output captured directly, same as above.

## 9. Basic two-library clash with a winner marked

Two libraries define the same short name (`K`); the one `Import`ed last
wins, and the report says so with a plain-text `<- used` marker.

`test/fixtures/libs/mydev/PartA.v`: `Lemma K : True. ... Definition helper (n : nat) := n + 1.`
`test/fixtures/libs/mydev/PartB.v`: `Lemma K : 1 = 1. ...`

```coq
From NamespaceAnalysis Require Import Loader.
From MyDev Require Import PartA.
From MyDev Require Import PartB.

Check helper 3.
Check K.

NamespaceAnalysis MyDev.PartA MyDev.PartB.
```

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

This is the tool's own checked-in golden report (`test/expected/report.txt`)
-- plugin and CLI must both produce this exact text, byte-for-byte.

## 10. Multi-level domains: a shallow prefix catches a deeper clash

Probing `Demo.Sub` (2 levels deep) still catches a clash 4 levels down, at
`Demo.Sub.Deep.DeepOne`, against a completely different branch
(`Demo.Other.Sibling`) -- domain arguments are prefixes, not exact paths.

```coq
From NamespaceAnalysis Require Import Loader.
From Demo.Sub.Deep Require Import DeepOne.
From Demo.Other Require Import Sibling.

Check Gadget.

NamespaceAnalysis Demo.Sub.
```

```
NamespaceAnalysis: 1 symbol(s) in scanned domain(s)
Clashes:
┌────────────┬───────────────────────────────────┐
│ Short name │ Candidates (alphabetical)         │
├────────────┼───────────────────────────────────┤
│ Gadget     │ Demo.Other.Sibling.Gadget <- used │
│            │ Demo.Sub.Deep.DeepOne.Gadget      │
└────────────┴───────────────────────────────────┘
Used identifiers:
┌────────────┬────────────────────┐
│ Identifier │ Defined in         │
├────────────┼────────────────────┤
│ Gadget     │ Demo.Other.Sibling │
└────────────┴────────────────────┘
```

Note the winning candidate (`Demo.Other.Sibling.Gadget`) is found even
though only its *shallower* ancestor `Demo.Sub` was ever named as a
domain -- the other candidate, `Demo.Sub.Deep.DeepOne.Gadget`, is 4 levels
under the probed prefix.

## 11. 0/1/2/3 domain arguments against three same-named libraries

Three libraries (`LibOne`/`LibTwo`/`LibThree`) each define `Shared`.
Naming 0 domains means "everything currently imported" (so the count
includes the whole Corelib prelude -- 1013 symbols here, vs. 1-3 when
domains are named explicitly) but the *clash itself* is identical either
way -- domain arguments control what's probed, never what counts as a
clash in the first place.

```coq
From NamespaceAnalysis Require Import Loader.
From LibOne Require Import Mod.
From LibThree Require Import Mod.
From LibTwo Require Import Mod.

Check Shared.

NamespaceAnalysis.
NamespaceAnalysis LibOne.Mod.
NamespaceAnalysis LibOne.Mod LibTwo.Mod.
NamespaceAnalysis LibOne.Mod LibTwo.Mod LibThree.Mod.
```

First block (0 domains):
```
NamespaceAnalysis: 1013 symbol(s) in scanned domain(s)
Clashes:
┌────────────┬─────────────────────────────┐
│ Short name │ Candidates (alphabetical)   │
├────────────┼─────────────────────────────┤
│ Shared     │ LibOne.Mod.Shared           │
│            │ LibThree.Mod.Shared <- used │
│            │ LibTwo.Mod.Shared           │
└────────────┴─────────────────────────────┘
```
Blocks 2-4 (1, 2, then 3 named domains) are identical in content to each
other -- only the member count changes (1, 2, 3) -- confirming that naming
fewer than all three libraries still surfaces the clash against the ones
you didn't name.

## 12. A hypothetical (not-yet-imported) domain

`MyDev.PartC` is named as a probe argument but never actually `Require`d
or `Import`ed in the file -- the report still surfaces it as a would-be
clash against what's genuinely imported (`PartA`), and proves no
short-name pollution occurred: `Check K.` still resolves to `PartA`, never
`PartC`.

```coq
From NamespaceAnalysis Require Import Loader.
From MyDev Require Import PartA.

NamespaceAnalysis MyDev.PartC.

Check K.

NamespaceAnalysis MyDev.PartC.
```

First block (before `Check K.`):
```
NamespaceAnalysis: 1 symbol(s) in scanned domain(s)
Clashes:
┌────────────┬───────────────────────────┐
│ Short name │ Candidates (alphabetical) │
├────────────┼───────────────────────────┤
│ K          │ MyDev.PartA.K <- used     │
│            │ MyDev.PartC.K             │
└────────────┴───────────────────────────┘
Used identifiers: (none captured)
```
`PartA.K` is already marked as winner even though `Check K.` hasn't run
yet in this block -- it's the real ambient resolution, `PartC.K` is purely
hypothetical (`Require`d on the spot to be probed, never `Import`ed).
Second block, after `Check K.`, confirms it directly: "Used identifiers"
shows `K` resolved to `MyDev.PartA`, never `MyDev.PartC`.

## 13. Exclude/include: Corelib hidden by default

A library's `double` collides with `Corelib.Init.Nat.double`. Hidden by
default (no clash reported at all -- only 1 non-excluded candidate
remains); revealed with `--include`/`: Including`.

```coq
From NamespaceAnalysis Require Import Loader.
From ExcludeDemo Require Import CorelibClash.

Check double 3.

NamespaceAnalysis ExcludeDemo.CorelibClash.
NamespaceAnalysis ExcludeDemo.CorelibClash : Including Corelib.
```

Default (Corelib excluded):
```
NamespaceAnalysis: 1 symbol(s) in scanned domain(s)
Clashes:
No clashes found.
```
With `: Including Corelib`:
```
NamespaceAnalysis: 1 symbol(s) in scanned domain(s)
Clashes:
┌────────────┬─────────────────────────────────────────┐
│ Short name │ Candidates (alphabetical)               │
├────────────┼─────────────────────────────────────────┤
│ double     │ Corelib.Init.Decimal.Little.double      │
│            │ Corelib.Init.Hexadecimal.Little.double  │
│            │ Corelib.Init.Nat.double                 │
│            │ ExcludeDemo.CorelibClash.double <- used │
└────────────┴─────────────────────────────────────────┘
```
Un-hiding Corelib reveals it was actually a 4-way collision the whole
time (two more `double`s live under `Corelib.Init.{Decimal,Hexadecimal}`),
not just the one against `Corelib.Init.Nat` the "excluded winner" example
(section 5 above) uses.

## 14. Large-report note (grid readability)

Directly prompted by a question about the grid becoming hard to read at
scale. Past 100 distinct clashing names, both `to_pp` (plugin) and
`to_string` (CLI grid) prepend a one-line note:

```
NamespaceAnalysis: 202 symbol(s) in scanned domain(s)
Note: 101 clashes found -- for a more compact view of a report this size, use the CLI with --format summary or --format json.
Clashes:
...
```

`--format summary`/`--format json` never show this note -- they're already
the compact form the note points at. Confirmed no false positive on an
ordinary small report (`test/run_test.sh` asserts the note is *absent* for
`MainCli.v`'s single clash), and confirmed load-bearing by reverting
`src/report.ml`/`.mli` and watching the new `run_test.sh` section fail.

## 15. Transitive ("chained") imports -- no special-case code needed

Directly prompted by a question about whether multi-hop import chains
(file C requires B, B requires A) are handled correctly. They are, and
the tool needed zero changes to prove it -- built a 3-library chain to
confirm rather than just reasoning about it.

`ChainA.v`: `Definition ChainedName := 1.`
`ChainB.v`: `Require Export ChainA.` (also tested with a plain `Require
ChainA.`, no `Export` -- same result either way, since domain membership
comes from the kernel environment, not import visibility)
`ChainD.v`: `Definition ChainedName := 99.` (unrelated to A/B, just
happens to clash)

```coq
From NamespaceAnalysis Require Import Loader.
From ChainB Require Import ChainB.
From ChainD Require Import ChainD.

Check ChainedName.

NamespaceAnalysis ChainA ChainD.
```

The target file never mentions `ChainA` at all -- only `ChainB`, which
transitively pulls it in:

```
NamespaceAnalysis: 2 symbol(s) in scanned domain(s)
Clashes:
┌─────────────┬───────────────────────────────────┐
│ Short name  │ Candidates (alphabetical)         │
├─────────────┼───────────────────────────────────┤
│ ChainedName │ ChainA.ChainA.ChainedName         │
│             │ ChainD.ChainD.ChainedName <- used │
└─────────────┴───────────────────────────────────┘
```

`ChainA.ChainA.ChainedName` is found and correctly flagged as clashing
with `ChainD.ChainD.ChainedName`, despite being two hops away from the
analyzed file. This works because `Domain_scan`/`Clash_detect` query the
live kernel environment and `Nametab` *after* Rocq's elaborator has
already resolved the entire transitive closure -- there's no import graph
for this tool to walk (or fail to walk correctly) in the first place. See
README "Transitive imports and circular imports" for why circular imports
are a non-issue for the same underlying reason (they can't compile at
all, confirmed directly: two mutually-`Require`ing files both fail with
"Unable to locate library ... (while searching for a .vos file)").
