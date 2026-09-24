# NamespaceAnalysis

A tool for Rocq (formerly Coq) proof developments that reports where every
identifier used in a file is actually defined, and proactively flags name
clashes among imported symbols — e.g. two different imported libraries each
defining a lemma/function called `K`, where Rocq's "last import wins"
shadowing rule silently picks one of them.

Usable two ways from a single shared analysis engine:

- **Inside a `.v` file**, as a native vernacular command that prints into the
  proof/message panel:

  ```coq
  From NamespaceAnalysis Require Import Loader.
  From MyDev Require Import PartA.
  From MyDev Require Import PartB.

  NamespaceAnalysis MyDev.PartA MyDev.PartB.
  ```

- **From the command line**, for CI, editors, or LLM-agent tooling:

  ```sh
  namespace-analysis -R path/to/libs MyDev \
    --domain MyDev.PartA --domain MyDev.PartB \
    MyFile.v
  ```

Both report three things:

1. **Ambiguous uses** — every name the file actually used whose written form
   had more than one candidate *at the point it was used*, with what it
   resolved to there and what else it could have meant. This is the
   file-level lint: each use is judged against the namespace as it stood on
   that line, so a `Section`/`Module`-scoped `Import`, or a later `Import`
   that changes what the same name means further down, is accounted for.
2. **Clashes** — for the given domain(s) (library/module prefixes, in the
   same style as `Print Namespace`), every short name with more than one
   candidate definition in the namespace *at the analysis point* (where the
   `NamespaceAnalysis` command sits; the end of the file for the CLI), as a
   grid, with the current winner marked. This is where "what if I also
   imported library X?" questions get answered.
3. Every identifier the file actually uses, resolved to its fully-qualified
   defining location.

A related but distinct command, `ImportAnalysis`, is planned as a follow-up
(designed, not yet built) — see the Roadmap section.

## Example output

For `test/fixtures/UseSite.v`, where `UseLibA.UseA` and `UseLibB.UseB` both
define `x`:

```coq
(* 1 *) From NamespaceAnalysis Require Import Loader.
(* 2 *) From UseLibA Require Import UseA.
(* 3 *) From UseLibB Require UseB.
(* 4 *)
(* 5 *) Check x.
(* 6 *) Section S.
(* 7 *)   Import UseLibB.UseB.
(* 8 *)   Check x.
(* 9 *) End S.
(*10 *) Check x.
(*11 *) Check UseLibB.UseB.x.
(*12 *) Import UseLibB.UseB.
(*13 *) Check x.
(*14 *)
(*15 *) NamespaceAnalysis UseLibA UseLibB.
```

```
NamespaceAnalysis: 2 symbol(s) in scanned domain(s)
Ambiguous uses (judged where each name was used):
┌─────────────────┬─────────────────────────────────────────┐
│ Name as written │ Candidates at that point (alphabetical) │
├─────────────────┼─────────────────────────────────────────┤
│ x (lines 5, 10) │ UseLibA.UseA.x <- used                  │
│                 │ UseLibB.UseB.x                          │
├─────────────────┼─────────────────────────────────────────┤
│ x (lines 8, 13) │ UseLibA.UseA.x                          │
│                 │ UseLibB.UseB.x <- used                  │
└─────────────────┴─────────────────────────────────────────┘
Clashes (namespace state at the analysis point):
┌────────────┬───────────────────────────┐
│ Short name │ Candidates (alphabetical) │
├────────────┼───────────────────────────┤
│ x          │ UseLibA.UseA.x            │
│            │ UseLibB.UseB.x <- used    │
└────────────┴───────────────────────────┘
Used identifiers:
┌────────────┬──────────────┐
│ Identifier │ Defined in   │
├────────────┼──────────────┤
│ x          │ UseLibA.UseA │
├────────────┼──────────────┤
│ x          │ UseLibB.UseB │
├────────────┼──────────────┤
│ x          │ UseLibA.UseA │
├────────────┼──────────────┤
│ x          │ UseLibB.UseB │
├────────────┼──────────────┤
│ x          │ UseLibB.UseB │
└────────────┴──────────────┘
```

The two grids answer different questions, from different moments. The
Clashes grid is a snapshot at line 15, where `x` means `UseLibB.UseB.x`, so
on its own it would be wrong about lines 5 and 10. The Ambiguous uses grid
shows what actually happened on each line: `UseLibA.UseA.x` on line 5;
`UseLibB.UseB.x` on line 8, inside the section that imports it; `UseLibA.UseA.x`
again on line 10, because the section's `Import` ended with `End S`; and
`UseLibB.UseB.x` on line 13, after the file-level `Import`. Line 11 writes the
fully qualified name, which has only one candidate, so it's not reported.
Uses that saw the same winner and the same alternatives are grouped into
one row.

The winner (`<- used`) is always marked with that plain-text arrow regardless
of terminal support, and *additionally* bold+colored when the CLI's stdout is
a TTY (auto-detected, never forced) or in a `Pp`-tag-aware front end — the
arrow is the one signal you can always rely on; color is a bonus on top of
it, never the only indicator.

## Argument reference

Every argument, explained by position — this is the part that wasn't
self-explanatory before, so it gets its own section.

### Standard Rocq flags (we only pass these through, untouched)

These aren't ours — they're standard `rocq compile`/`rocq repl` flags,
documented in full at
[the Rocq manual](https://rocq-prover.org/doc/V9.2.0/refman/practical-tools/coq-commands.html).
The CLI's argument parser (`parse_extra` in `cli/namespace_analysis_cli.ml`)
only consumes its own flags (below) and the target file; everything else is
handed off to Rocq's own standard parser untouched.

| Flag | Meaning |
|---|---|
| `-R dir dirpath` | Map physical directory `dir` to logical prefix `dirpath`, recursively, and allow `Require`ing its contents with a *partially*-qualified name (no `From` clause needed). This is what you want for your own project's own source. |
| `-Q dir dirpath` | Same mapping, but requires a *fully*-qualified name or an explicit `From dirpath Require ...` clause. |
| `-I dir` | Adds `dir` to the OCaml/plugin load path — unrelated to `-R`/`-Q`, rarely needed for a pure `.v` project. |

Worked example: `-R path/to/libs MyDev` means "the physical directory
`path/to/libs` is the root of logical prefix `MyDev`" — so
`path/to/libs/PartA.v` becomes requireable as `MyDev.PartA`
(`Require Import PartA.` after `From MyDev`, or, because it's `-R` not `-Q`,
even a bare unqualified `Require Import PartA.` once nothing else shadows the
name).

### NamespaceAnalysis's own arguments

| Argument | CLI flag | Native command | Meaning |
|---|---|---|---|
| Domains | `--domain <dirpath>` (repeatable) | bare space-separated list, e.g. `NamespaceAnalysis MyDev.PartA MyDev.PartB.` | Which library/module prefixes to scan. **0** domains = everything currently imported (`Library.loaded_libraries`, including the auto-loaded `Corelib` prelude). **1** domain = just that prefix (and anything nested under it). **N** domains = the union — and this list only controls what gets *probed*; a clash is still reported even against a candidate from an unnamed library (see "Clash scope" below). A domain that isn't `Require`d yet is auto-loaded on the spot (see "Checking a domain you haven't imported yet"). |
| Exclude | `--exclude <dirpath>` (repeatable) | `: Excluding <dirpath>...` clause | Hide candidates under this prefix from the report. `Corelib` is excluded by default. |
| Include | `--include <dirpath>` (repeatable) | `: Including <dirpath>...` clause | Un-hide a prefix — overrides both the `Corelib` default and any `--exclude`. |
| Target file(s) | positional (repeatable), must not start with `-` | *(implicit — the file you're compiling)* | The `.v` file(s) to analyze. Each is elaborated under its real logical name, derived from the `-R`/`-Q` mappings exactly as `rocq compile` does it (an explicit `-top` still wins). With 2+ files, each is analyzed on its own, in its own process — see "Batch mode" below. CLI-only; the native command always analyzes the file it's running in. |
| Directory | `--dir <path>` (repeatable, CLI-only) | *(n/a)* | Shorthand for a file list: recursively adds every `*.v` under `path` (sorted per directory for determinism) as a target file, after any explicit ones. See "Batch mode" below. |
| Output format | `--format <mode>` (CLI-only) | *(n/a)* | `grid` (default, the box-drawing tables), `summary` (one line of counts, no per-name grid), or `json` (a fixed machine-readable shape — see "Output formats" below). |

Native-command syntax note: `Excluding`/`Including` clauses need a literal
`:` before them (`NamespaceAnalysis MyDev.PartA : Excluding Corelib.`, not a
bare `NamespaceAnalysis MyDev.PartA Excluding Corelib.`). This isn't
arbitrary — `Excluding`/`Including` are ordinary identifiers to Rocq's
grammar (nothing reserves them as keywords), so without a punctuation
boundary a `MyDev.PartA` domain list would greedily swallow `Excluding` as if
it were one more domain name. `:` can never be parsed as part of a domain
reference, so the list cleanly stops there — the same idiom Rocq's own
`Hint ... : db` syntax uses for this exact ambiguity.

Fully-annotated example:

```sh
namespace-analysis \
  -R test/fixtures/libs/mydev MyDev \
  --domain MyDev.PartA --domain MyDev.PartB \
  --include Corelib \
  test/fixtures/MainCli.v
#  ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^  standard Rocq flag: map physical dir to logical prefix MyDev
#                                 ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^  our flags: which domains to probe, and un-hide Corelib
#                                                                                        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ target file (positional)
```

### Checking a domain you haven't imported yet

Any domain argument — to either front end — gets auto-`Require`d if it isn't
loaded yet, so you can ask "if I imported this, would anything clash?"
without editing your file first. This is safe because `Require` alone (never
`Import`) never binds short names into your ambient namespace — only
`Import`/`Export` does that — so nothing about your file's actual name
resolution changes; the domain's own definitions just become visible to
*this report*, and are compared against what's genuinely visible right now.
A clash reported this way names the domain's candidate as non-winning
(nothing not-yet-imported can be the actual current winner); if two purely
hypothetical domains would clash *with each other*, the report says so with
no winner at all, since nothing among the candidates is actually imported.
A hypothetical domain only ever shows up in the Clashes grid: libraries the
tool loaded itself are never counted as candidates in Ambiguous uses, since
the file never loaded them (without this, an earlier in-file
`NamespaceAnalysis` command would change what later uses in the same file
report).

Caveat: a domain argument has always been allowed to be a *namespace prefix*
with no exact compiled library of its own (e.g. plain `MyDev` matching both
`MyDev.PartA` and `MyDev.PartB`) — that's what makes probing a shallow prefix
to catch a deeper clash useful. Only an *exact* library path can actually be
`Require`d, so a prefix that doesn't correspond to one real compiled unit is
silently left alone (Domain_scan's own prefix matching still finds whatever's
already loaded under it). The tradeoff: a genuine typo of an
otherwise-exact hypothetical domain name degrades to the same "0 members, no
clashes" result an unmatched domain always gave — not a regression, just not
distinguishable in general from "this was always meant as a prefix".

### Clash scope

Domain arguments (and the exclude/include filters) control what gets
*probed* and what counts as a *candidate* — never what counts as a *clash in
the first place*. Once a name is probed, every visible candidate is reported,
even one from a library you never named — this mirrors how `Locate` itself
behaves, and exists specifically so a real clash can't hide just because you
forgot to name a third library.

### Transitive imports and circular imports

**Transitive (chained) `Require`/`Import` is handled correctly, by
construction, with no special-case code for it anywhere in this tool.**
Confirmed directly: if `C` `Require Import`s only `B`, and `B` itself
`Require Export`s (or even just plain `Require`s) `A`, a clash between
`A`'s and some other library's identically-named definition is still found
and correctly reported — even though `C` never mentions `A` at all. This
isn't a special feature; it falls out of the tool's whole design: `Domain_scan`
and `Clash_detect` inspect the live, fully-resolved kernel environment and
`Nametab` state (`Global.env ()`, `Nametab.locate_all`) *after* Rocq's own
elaborator has already processed the entire transitive closure of
`Require`s — the tool never walks an import graph itself, so it can't miss
a link in a chain regardless of how many hops deep it is. See `Examples.md`
section 15 for a worked example.

**Circular `Require`s can't happen, and aren't something this tool needs to
defend against.** Confirmed directly: two files that `Require` each other
both fail to compile outright ("Unable to locate library ... (while
searching for a .vos file)"), for either one, regardless of which you try
to compile first — a `.vo` can only reference dependencies that are
*already* compiled, so Rocq's library system is structurally a DAG, not
just conventionally one. By the time this tool ever sees a compiled
library, its dependency graph is guaranteed acyclic.

## Batch mode

CLI-only. Give it several files, or a whole directory:

```sh
namespace-analysis -R path/to/project MyDev --domain MyDev --dir path/to/project --format summary
```

**Each target file is analyzed on its own**, in a fresh process, exactly as
if you'd run the CLI on that one file — the files are never loaded into a
shared session. The parent process just collects the per-file reports and
prints them one after another (`==> <file>` headers in the grid format),
followed by a total:

```
test/fixtures/batch/One.v: NamespaceAnalysis: 0 ambiguous use site(s), 3 symbol(s) in scanned domain(s), 1 clash(es) found (0 with no winner marked), 1 identifier(s) used
test/fixtures/batch/Two.v: NamespaceAnalysis: 0 ambiguous use site(s), 3 symbol(s) in scanned domain(s), 1 clash(es) found (0 with no winner marked), 1 identifier(s) used
Total: 2 file(s) analyzed, 0 failed, 0 ambiguous use site(s)
```

Only the ambiguous-use-site count is added up across files; the other
counts describe each file's own (overlapping) environment, so a sum of them
wouldn't mean anything. A file that fails to elaborate is reported as
`FAILED` (its error goes to stderr), the remaining files still run, and the
CLI exits `1` at the end.

Why not one shared session: an earlier version did exactly that, and it was
wrong for any real project. Loading a file's source puts its definitions in
the session a second time, next to the compiled copy that its neighbours
`Require` — so every definition "clashed" with itself (522 of 584 symbols,
on just Iris's `ofe.v` and `cmra.v`). Two files defining the same short name
aborted the run ("already exists"), and one file's `Import`s leaked into the
next file's elaboration. More fundamentally, "last import wins" is a
per-file (really, per-line) question; a merged environment answers a
question nobody asks. See `Examples.md` §18.

**Cost**: a batch run elaborates every file, so it costs roughly what
compiling those files costs, plus about 0.25s of process start-up and
dependency loading per file. Measured: all 178 files of Iris 4.5.0 in 215s,
sequentially. Judging each use site adds almost nothing (157,446 lookups
across all of Iris took 0.08s in total).

**Precondition**: like any `Require`, every file's dependencies need to
already be compiled to `.vo` on disk — batch mode doesn't build anything
itself, it re-elaborates the files you point it at, relying on the target
project's own build having already run once (`make`/`dune build`/whatever it
uses). This is Rocq's own baseline requirement for `Require`, not something
this tool adds.

**No `_CoqProject`/`Makefile` parsing.** `--dir` collects `.v` files, not
`-R`/`-Q` mappings — you still supply those yourself, the same as
single-file usage (there's no reusable public parser for `_CoqProject`
exposed by the installed `rocq-runtime`; `coqdep`'s is internal, not a
library API). It also collects every `.v` file under the directory, which
can be more than the project actually builds (Iris's source tree has one
unlisted `mono_Z.v`); pass the real file list positionally when that
matters.

## Output formats

`--format` (CLI-only): `grid` (default) is the box-drawing tables from the
example above. `summary` prints one line of counts instead — no per-name
grid:

```
NamespaceAnalysis: 1 ambiguous use site(s), 3 symbol(s) in scanned domain(s), 1 clash(es) found (0 with no winner marked), 2 identifier(s) used
```

"Ambiguous use sites" counts distinct (name, line) pairs, not grouped rows.
"No winner marked" is one combined count — it doesn't distinguish a purely
hypothetical clash (nothing among the candidates is actually imported yet)
from the "excluded winner" case above (something *is* actually imported,
it's just excluded). `Clash_detect.clash.winner` collapses both to `None`
already (see its doc comment); splitting them in the summary would need a
`Clash_detect` signature change, not done here.

Past 100 distinct clashing names or ambiguous-use rows, the `grid` format
itself (both front ends) prepends a one-line note pointing at `--format
summary`/`json` — confirmed 1,000 clashes alone render as a 3,007-line
table, so the note exists to surface the compact alternative before you're
scrolling through one, not after.

`json` emits a fixed, hand-serialized shape (no new dependency) for pulling
numbers out programmatically instead of grepping terminal output:

```json
{"member_count":3,"ambiguous_uses":[{"name":"K","lines":[6],"winner":"MyDev.PartB.K","alternatives":["MyDev.PartA.K"]}],"clashes":[{"name":"K","winner":"MyDev.PartB.K","alternatives":["MyDev.PartA.K"]}],"used":[{"identifier":"helper","defined_in":"MyDev.PartA"},{"identifier":"K","defined_in":"MyDev.PartB"}]}
```

In batch mode, that per-file object is wrapped:
`{"files":[{"file":"<path>","report":{...}} or {"file":"<path>","error":true}, ...],"failed":<n>,"ambiguous_sites":<n>}`.

**"Defined in" is always the *defining* library's logical path**, not the
analyzed source file: `Dumpglob`'s own `filepath` field (which
`Glob_capture`/`Report` read straight through) is
`Names.DirPath.to_string lib_dp`, the dirpath of wherever the identifier is
*defined*.

## Why this exists

Several developments have broken because of exactly this kind of import
clash, and Rocq has no built-in aggregate report for it: `Locate` and `Print
Namespace` each show part of the picture, but only interactively, one
identifier or one namespace at a time. This tool is a thin synthesis of
machinery Rocq already ships — no new parser or elaborator required:

- **Clash detection** uses `Nametab.locate_all`, the exact function `Locate`
  itself calls to enumerate every visible candidate for a short name, unioned
  with the probed domains' own members (so a `Require`d-but-not-`Import`ed
  hypothetical domain is still seen as a candidate, even though
  `Nametab.locate_all` alone wouldn't find it).
- **Domain enumeration** uses `Environ.fold_constants`/`fold_inductives`
  filtered by dirpath prefix — what `Print Namespace` uses internally.
- **Used-identifier resolution** hijacks `Dumpglob`'s `Feedback` output mode
  (normally used to generate `.glob` files for `coqdoc`) to capture, in
  memory, every identifier the elaborator resolves.
- **Use-site judgment** relies on that capture being synchronous: each
  record arrives while the command using the name is still being
  elaborated, so looking the name up (`Nametab.locate`/`locate_all`, as
  written in the source) right then sees exactly the namespace Rocq just
  resolved it against — no separate pass over the file, and no extra
  elaboration.
- **Auto-loading a not-yet-imported domain** uses the same
  `Loadpath.locate_absolute_library` → `Library.intern_from_file` →
  `Library.require_library_from_dirpath` pipeline the real `Require`
  vernacular uses internally, minus the qualid-resolution machinery we don't
  need (see `src/ensure_loaded.ml` for two real Rocq quirks worked around
  here, confirmed by direct experimentation, not assumed).

## Layout

```
src/
  domain_scan.ml          Enumerate constants/inductives under given dirpath prefixes.
  clash_detect.ml          Union Nametab.locate_all with probed members; filter by excluded prefixes;
                           group ambiguous use sites.
  ensure_loaded.ml           Auto-Require a domain that isn't loaded yet, without Import-ing it.
  glob_capture.ml               Capture resolved identifiers via Dumpglob.Feedback, judging each
                                use site against the namespace at that moment.
  text_table.ml                    Shared box-drawing grid renderer (Pp.tag and ANSI backends).
  report.ml                           Shared report type + renderer (used by both front ends).
  g_namespace_analysis.mlg               The `NamespaceAnalysis` vernacular command (native plugin).
theories/
  Loader.v                                 `Declare ML Module` — Require Import this to load the plugin.
cli/
  namespace_analysis_cli.ml  Standalone driver: loads a Rocq document like `coqtop -l`
                              (under its real logical name), runs the same analysis,
                              prints to stdout; batch mode runs one worker process per file.
test/
  fixtures/, expected/, run_test.sh   Fixture libraries (clashing names, multi-level domains,
                                       three-way domain counts, a hypothetical-only domain, a
                                       Corelib-clashing domain) exercised by both front ends.
```

## Building

### With Nix (recommended)

```sh
nix develop
dune build
```

`flake.nix` provides `rocq-core` (currently pinned via `rocqPackages_9_1` —
9.2 isn't on the `nixpkgs-unstable` channel yet, only on `nixpkgs` master,
which would force a from-source build instead of fetching a cached binary),
its version-matched `ocamlPackages` (OCaml 4.14 for the 9.1 line), `dune`,
`findlib`, and `zarith` — nothing else needs to be installed on the host.
`ocamlfind list` finds every `rocq-runtime.*` package automatically inside
the shell (Nix wires this up via its own findlib setup-hook, not manual
`OCAMLPATH`/`LIBRARY_PATH` exports); the `shellHook` additionally puts this
project's own `_build/install/default/lib` on `OCAMLPATH` once you've run
`dune build`, so `Declare ML Module` and the CLI work immediately with no
manual export at all. `flake.lock` pins the exact nixpkgs revision for
reproducibility — update it deliberately with `nix flake lock`, not as a
side effect of other changes.

### With Homebrew (alternative)

```sh
brew install ocaml dune rocq
```

Then, from the repository root:

```sh
export LIBRARY_PATH="/opt/homebrew/lib:$LIBRARY_PATH"   # needed for gmp at link time
dune build
export OCAMLPATH="$(pwd)/_build/install/default/lib:$OCAMLPATH"
```

Both paths build the identical `dune-project` (currently capped at
`(lang dune 3.23)` / `(using rocq 0.13)` to match what Nix's `dune_3`
currently supports — Homebrew's newer dune accepts these older language
versions too, so this cap doesn't cost anything there). Note the two paths
currently resolve to different exact Rocq versions (Nix: 9.1.1, Homebrew:
9.2.0) — both tested and passing, but see `src/ensure_loaded.ml` for a
version-drift pitfall hit during development (`Flags.in_synterp_phase`'s
type isn't even stable between them).

## Running the tests

```sh
bash test/run_test.sh
```

Toolchain-agnostic: run it inside `nix develop`, or with Homebrew's
`rocq`/`dune` on `PATH` and `LIBRARY_PATH` exported as above. Deliberately
hand-rolled shell + `rocq compile`/CLI invocations, not `dune runtest` —
sandboxed dune rules proved fragile for a project that needs a real Rocq
session and its own plugin loaded via `OCAMLPATH`.

CI (`.github/workflows/test.yml`) runs the same script — `nix develop -c
bash test/run_test.sh` — on push/PR to `main`, Nix path only (see "Building"
above for why the Homebrew path isn't also CI'd).

Covers: the original two-library `K` clash (plugin/CLI parity against a
checked-in golden report); a 4-level-deep domain caught by probing a
2-level-shallow prefix; 0/1/2/3 `--domain` arguments against three
same-named libraries; a domain named only as an argument, never actually
`Require`d, correctly surfacing as a would-be clash while proving no
short-name pollution occurred; the default `Corelib` exclusion
disappearing/reappearing correctly with `--include`; a clash buried in the
*second* type of a two-type mutual inductive block; a clash between two
libraries' same-named constructors on otherwise differently-named types; the
"excluded winner" edge case below, pinning that a clash whose actual current
winner falls under an excluded prefix is still reported, with no winner
marked, rather than either hidden entirely or shown anyway; use sites
judged where they happen (`UseSite.v`: a mid-file `Import` flipping a
name's meaning, a `Section`-scoped `Import` ending with its section, and a
fully qualified use not being reported); a file that names its own module
(`SelfRef.v`) elaborating under its real logical name; batch mode giving
each file its own report, never duplicating a file against its own compiled
copy or aborting on two files that define the same name, and reporting a
failing file while still running the rest; and `--format summary`/`json`
agreeing with the grid on the same input. Every plugin fixture's CLI twin
(`*Cli.v`) is kept line-for-line aligned with it, since use sites are
reported by line and the two front ends' output is diffed.

`test/run_error_test.sh`, invoked automatically at the end of the above,
covers the CLI's error paths: no target file, an `-R` pointing at a
nonexistent directory, a target file that fails to compile, and a malformed
`--domain` string — each expected to fail with a clean, one-line message and
exit code 1, the same as `rocq compile` gives on identical input.

## Documentation

OCaml source (`src/*.mli`) is documented with ordinary
[odoc](https://ocaml.github.io/odoc/)/ocamldoc-style `(** ... *)` comments
ahead of each `val`, which is the default documentation mechanism for OCaml
libraries. Build the HTML docs with:

```sh
dune build @doc
```

Output lands in `_build/default/_doc/_html/rocq-namespace-analysis/`; open
`index.html` from there. `odoc` is included in the Nix dev shell
(`flake.nix`); with Homebrew, `opam install odoc` instead.

The `.v` theory files (currently just `theories/Loader.v`, which has no
public API worth documenting yet) would use Rocq's equivalent, `rocq doc`
(the modern name for `coqdoc`), the same tool that backs the
cross-referencing `Glob_capture` itself hijacks -- see "Shadows real `.glob`
output" below.

## Editor setup (live/interactive testing)

`NamespaceAnalysis` is an ordinary vernacular command that prints via
`Feedback.msg_notice` -- exactly like `Locate`/`Search` -- so any Rocq
front-end that can drive a Rocq process and render its `Feedback` output
gets it for free, with no NamespaceAnalysis-specific editor integration.
What it does need, like any Rocq plugin, is to actually be *findable*:
`OCAMLPATH` reaching this project's own `_build/install/default/lib` (for
`Declare ML Module`), and an `-R`/`_CoqProject` mapping so
`From NamespaceAnalysis Require Import Loader.` resolves. This project
isn't published via opam/Nix yet (see `Editor_planning.md`), so both are
wired up locally:

- **`_CoqProject`** at the repo root maps `-R _build/default/theories
  NamespaceAnalysis` -- dune's *build output* directory, not `theories/`
  itself, since that's where `dune build` actually puts `Loader.vo`. Run
  `dune build` at least once before opening an editor.
- **`nix develop`** already includes `vsrocq-language-server` (folded into
  the one shared devShell rather than split into a separate `.#editor`
  output -- this is a private, single-maintainer project, so the closure
  size this adds to every CLI/test session isn't worth the extra "which
  shell do I use" friction; confirmed it only adds fetch time, not build
  time, since nixpkgs' binary cache already has it and its GTK3/Cairo/Pango
  dependencies prebuilt).

**VS Code**: install the recommended extension (`.vscode/extensions.json`
points at `rocq-prover.vsrocq`), then launch VS Code *from inside* the dev
shell so it inherits `PATH`/`OCAMLPATH`:
```sh
nix develop
code .
```
**If VS Code was already running, fully quit it first (Cmd+Q, not just
closing the window/tab) before running `code .`** — otherwise that command
just tells the already-running instance to open a new window, which never
inherits the shell's environment at all. This is the most common cause of
VsRocq reporting no Rocq/`vsrocqtop` available even after doing everything
else right.

`.vscode/settings.json` sets `"vsrocq.path": "vsrocqtop"` (a bare command,
resolved via `PATH` — not a hardcoded `/nix/store/...` path, which would go
stale on the next `nix flake update`). Confirmed the underlying mechanism
works end-to-end by driving `rocq repl` the same way `vsrocqtop` would
(`rocq repl -R _build/default/theories NamespaceAnalysis`, loading the
plugin and running `NamespaceAnalysis Hello.` successfully) — the actual
VS Code extension itself wasn't separately verified in a GUI session, so if
`vsrocqtop` still isn't found after a full VS Code restart, VsRocq's own
FAQ notes this is "usually a PATH issue" and suggests a hardcoded full path
in `vsrocq.path` as the fallback.

### Trying it on the checked-in fixtures

`theories/Loader.v` alone has nothing to actually analyze. To open one of
the demo fixtures directly (`test/fixtures/Main.v`,
`test/fixtures/UseSite.v`, `test/fixtures/MutualInductive.v`,
`test/fixtures/ConstructorClash.v`, `test/fixtures/ExcludedWinner.v` — the ones that call the native
`NamespaceAnalysis` command, as opposed to the `*Cli.v` files, which are
CLI-only and have no live-editable payload), its own dependency libraries
need to be compiled first, and `_CoqProject` needs to know where they
ended up:

```sh
dune build
bash test/build_fixtures.sh
```

`test/build_fixtures.sh` compiles each `test/fixtures/libs/**` library *in
place* (unlike `test/run_test.sh`, which deliberately compiles into an
ephemeral temp dir so the repo stays clean during CI) — safe to re-run any
time, e.g. after editing a fixture library. `_CoqProject` has matching `-R`
entries for all of them. Confirmed end-to-end by driving `rocq repl` with
every `-R` flag from `_CoqProject`, piping in `test/fixtures/Main.v`, and
getting the real clash-detection grid back.

`PartA.v`/`PartB.v`/`PartC.v` live in their own `test/fixtures/libs/mydev/`
subdirectory, matching every other fixture family's layout — this used to
not be the case (they sat directly in `test/fixtures/libs/`), which meant
`-R test/fixtures/libs MyDev`'s recursion overlapped with every other
fixture family's own subdirectory underneath it. That was initially
dismissed as cosmetic (`rocq repl` correctly applies the more specific,
later `-R` override, just with a harmless warning) — but it turned out to
be a *real* problem for VsRocq specifically: opening `ExcludeInclude.v`
failed with "Cannot find a physical path bound to logical path
CorelibClash with prefix ExcludeDemo" even with everything else set up
correctly (confirmed via `rocq repl` reproducing the identical config
successfully, isolating the discrepancy to VsRocq's own handling of
overlapping `_CoqProject` entries). Restructuring away the overlap
entirely fixed it outright rather than relying on override semantics
matching between two different tools.

**Emacs (Proof General) and RocqIDE**: not wired up yet — see
`Editor_planning.md` for what's already confirmed (Proof General reads
`_CoqProject` automatically; RocqIDE's Nix packaging status is still an
open question) and what's left to do.

## Known limitations

- **Capture starts at plugin load time.** The native command only sees
  identifiers used *after* `Require Import Loader.`, so that must be the
  first line of anything you want analyzed. The CLI doesn't have this
  restriction — it installs capture itself before loading the target file.
- **Shadows real `.glob` output.** Enabling capture overrides Rocq's normal
  `-dump-glob` file output for the rest of that compilation unit. Irrelevant
  unless you're simultaneously generating `coqdoc` documentation from the
  same run.
- **An ambiguous use doesn't say whether the other candidates were imported.**
  Its alternatives are every loaded global whose name ends in what was
  written — the same set `Locate` shows — so they mix two situations: a
  candidate that *was* imported and then shadowed by a later `Import` (real
  "last import wins"), and one whose module was only `Require`d (latent:
  importing it later would flip the result). Rocq's public `Nametab` API
  doesn't expose the difference: `locate_all` returns only the head entry
  of each name-tree node, and the shadowed entries behind it live in
  `nametab.ml`'s internal state, with no import-status query in
  `Declaremods` either. Libraries the tool itself loaded (hypothetical
  domains, via `Ensure_loaded`) are left out of use sites entirely, since
  the file never loaded them.
- **Use sites are judged from the source text on disk.** The written form
  of a reference is only available as a byte range, so it's read from the
  file. If the file on disk doesn't match what was elaborated (e.g. an
  editor buffer with unsaved changes), the slice won't end in the resolved
  identifier and that use is skipped rather than misjudged.
- **Domain arguments are library/module prefixes only** (e.g. `MyDev.PartA`),
  matching `Print Namespace`'s argument style. File-path domains are a
  planned extension, not yet built.
- **`Local` candidates are labeled, not filtered out.** `Local` (outside a
  section) only blocks a definition's *short-name* binding on `Import` —
  it's still fully-qualified-accessible from anywhere, and still shows up
  as a domain "member" (`Environ.fold_constants` walks the kernel's
  constant table, which must retain it if any public lemma's proof term
  depends on it) — so it used to be reported as an indistinguishable
  clash candidate even though Rocq itself would *never* actually resolve
  a bare short name to it. Fixed via `Declare.is_local_constant` (see
  `Examples.md` §17): such a candidate now gets a plain-text `(Local)`
  suffix in the grids (both front ends, both Clashes and Ambiguous uses),
  rather than being silently
  dropped — a `Local` member could still be worth surfacing (e.g. it
  becomes a real problem if someone later removes the `Local`). Not shown
  in `--format summary`/`json`. Scoped to constants only — `Local` outside
  a section isn't a distinct state Rocq's inductive/constructor machinery
  tracks at all. Sections themselves were never affected — a `Variable`
  never becomes its own symbol, it's abstracted into an extra argument on
  whatever's defined inside the section, indistinguishable from an
  ordinary top-level definition once the section closes.
- **Open design question, not yet resolved**: when an excluded prefix (e.g.
  `Corelib`) happens to be the *actual current winner* of a clash, the clash
  is still reported (with only non-excluded alternatives shown) but with no
  winner singled out, rather than either hiding the whole clash or revealing
  an excluded winner anyway. Flagged for revisit. Pinned as a regression
  (not resolved) by `ExcludedWinner.v` in the test suite — see `Examples.md`.
- The CLI exits `0` whatever it finds (`1` only when a file fails to
  elaborate, including one file of a batch); a `--strict` flag for CI
  gating (nonzero exit on any ambiguous use or clash) isn't built yet.

## Roadmap

- File-path domain arguments (resolve a `.v` path to its module prefix).
- Parallel batch mode (`-j N`): the per-file workers are independent
  processes, so running several at once is straightforward; they run one
  at a time for now.
- Split ambiguous uses into "imported, then shadowed" and "loaded but not
  imported" — needs a way to see `Nametab`'s shadowed entries that the
  public API doesn't offer (see "Known limitations"). Reading Rocq's private
  name-table state would work but could break silently between Rocq
  versions; the cleaner route is an upstream request for a public function
  returning the shadowed entries under a name as written — which
  candidates are import-visible as that name, not just which ones exist
  (the latter is already public via `Nametab.locate_all`). `Locate` could
  use it too, to say what shadows what.
- `--strict` CI exit-code mode — `--format json` (see "Output formats") gives
  this a firmer footing than parsing terminal output, but the exit-code flag
  itself still isn't built.
- A domain argument matching nothing should say so explicitly, distinct from
  a clean bill of health.
- `_CoqProject`/`Makefile` parsing for `--dir`, so batch mode could point at
  an arbitrary project without hand-supplied `-R`/`-Q` mappings, and
  analyze exactly the files the project builds — see "Batch mode" above for
  why this was deliberately left out for now.
- `--format summary`/`json` don't carry the `(Local)` label the grid now
  does (see "Known limitations" above) — `--summary`'s "no winner marked"
  count (see "Output formats") still can't split out a `Local`-caused false
  positive from a genuine one. Would need either a `Clash_detect`
  signature change or a JSON schema change (adding a `local` field to
  each candidate) — not done, since no real consumer of that distinction
  in machine-readable form exists yet.
- `ImportAnalysis` (designed, not yet built): a different question from
  `NamespaceAnalysis` — "of everything an imported domain exports, which
  pieces does this file actually depend on," so you can tell whether a
  symbol you're importing (and thus exposed to clashing on) is even needed.
  Built on `Assumptions.traverse` (the machinery behind `Print Assumptions`)
  rather than syntactic occurrence tracking, specifically so it doesn't miss
  dependencies injected by proof automation (`auto`, typeclass resolution,
  canonical structures) that never appear as literally-written identifiers —
  and therefore only sees *completed* (`Qed`/`Defined`) definitions.
- Notation clashes: feasible in principle (`Notation.locate_notation` is
  structurally close to `Nametab.locate_all`) but a genuinely separate
  follow-up — notations are keyed differently and have no `Print
  Namespace`-equivalent enumeration entry point.
- Revisit the two Rocq quirks worked around in `src/ensure_loaded.ml`
  (`Library.library_is_loaded` always returning `true`; our own
  `Require`-bypass not durably persisting loaded-library bookkeeping across
  vernacular commands) — either report upstream or find the real fix rather
  than routing around them.

## License

MIT — see [LICENSE](LICENSE).
