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

Both report, for the given domain(s) (library/module prefixes, in the same
style as `Print Namespace`):

1. Every short name with more than one visible candidate definition (a
   clash), as a grid — short name in column 1, every candidate alphabetically
   in column 2, with the winner marked.
2. Every identifier the file actually uses, resolved to its fully-qualified
   defining location.

A related but distinct command, `ImportAnalysis`, is planned as a follow-up
(designed, not yet built) — see the Roadmap section.

## Example output

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
| Target file(s) | positional (repeatable), must not start with `-` | *(implicit — the file you're compiling)* | The `.v` file(s) to analyze — all get loaded into one Rocq session, then analyzed together as a single report. CLI-only; the native command always analyzes the file it's running in. |
| Directory | `--dir <path>` (repeatable, CLI-only) | *(n/a)* | Recursively add every `*.v` under `path` (sorted per directory for determinism), appended after any explicit target files. See "Batch mode" below. |
| Output format | `--format <mode>` (CLI-only) | *(n/a)* | `grid` (default, the box-drawing table), `summary` (one line of counts, no per-name grid), or `json` (a fixed machine-readable shape — see "Batch mode" below). |

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
  -R test/fixtures/libs MyDev \
  --domain MyDev.PartA --domain MyDev.PartB \
  --include Corelib \
  test/fixtures/MainCli.v
# ^^^^^^^^^^^^^^^^^^^^^^^  standard Rocq flag: map physical dir to logical prefix MyDev
#                          ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^  our flags: which domains to probe, and un-hide Corelib
#                                                                                 ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ target file (positional)
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

## Batch mode

CLI-only. Point it at a whole project instead of one file:

```sh
namespace-analysis -R path/to/libs MyDev --dir path/to/project --format summary
```

Every target file (explicit positional files, then everything `--dir`
recursively finds, sorted per directory for determinism) loads into a single
Rocq session, in that order; the domain scan, clash detection, and report
then run exactly once at the end, over everything loaded — not once per
file. The engine itself needed no changes for this: `Glob_capture`'s
occurrence buffer already accumulates across however many files get loaded
before it's read, and `Report`/`Clash_detect` already operate on whatever's
currently loaded, not per-file. A single positional file is just the
one-element case of the same code path — output is byte-identical to
before batch mode existed.

**Precondition**: like any `Require`, every file's own dependencies need to
already be compiled to `.vo` on disk — `--dir` doesn't build anything itself,
it re-elaborates the files you point it at, relying on the target project's
own build having already run once (`make`/`dune build`/whatever it uses).
This is Rocq's own baseline requirement for `Require`, not something this
tool adds.

**No `_CoqProject`/`Makefile` parsing.** `--dir` collects `.v` files, not
`-R`/`-Q` mappings — you still supply those yourself, the same as
single-file usage (there's no reusable public parser for `_CoqProject`
exposed by the installed `rocq-runtime`; `coqdep`'s is internal, not a
library API). Fine for a handful of sub-projects with their own known
mappings; a genuine gap if you wanted to point this at an arbitrary
unfamiliar project with no manual setup.

**Output formats** (`--format`): `grid` (default) is the box-drawing table
from the example above. `summary` prints one line of counts instead — no
per-name grid — meant for a whole-corpus run where the full grid could run
to hundreds of rows:

```
NamespaceAnalysis: 1523 symbol(s) in scanned domain(s), 4 clash(es) found (1 with no winner marked), 812 identifier(s) used
```

"No winner marked" is one combined count — it doesn't distinguish a purely
hypothetical clash (nothing among the candidates is actually imported yet)
from the "excluded winner" case above (something *is* actually imported,
it's just excluded). `Clash_detect.clash.winner` collapses both to `None`
already (see its doc comment); splitting them in the summary would need a
`Clash_detect` signature change, not done here.

`json` emits a fixed, hand-serialized shape (no new dependency) for pulling
numbers out programmatically instead of grepping terminal output:

```json
{"member_count":3,"clashes":[{"name":"K","winner":"MyDev.PartB.K","alternatives":["MyDev.PartA.K"]}],"used":[{"identifier":"helper","defined_in":"MyDev.PartA"},{"identifier":"K","defined_in":"MyDev.PartB"}]}
```

Two caveats specific to a whole-corpus batch run, not single-file usage:
- **"Defined in" is always the *defining* library's logical path, not the
  analyzed source file.** `Dumpglob`'s own `filepath` field (which
  `Glob_capture`/`Report` read straight through) is
  `Names.DirPath.to_string lib_dp` — the dirpath of wherever the identifier
  is *defined*, regardless of which of the batch's files referenced it. Two
  files in the same batch that each use a different identifier will show up
  as two separate rows with their own (possibly identical) defining
  locations, not as two different file paths.
- **The single "winner" a batch run reports for a clashing name is an
  artifact of `--dir`'s file-processing order** (alphabetical, for
  determinism), not anything meaningful about the corpus's own real
  build/import order. Trust that a clash *exists*; don't read much into
  which candidate an aggregate run happened to mark as current winner.

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
  clash_detect.ml          Union Nametab.locate_all with probed members; filter by excluded prefixes.
  ensure_loaded.ml           Auto-Require a domain that isn't loaded yet, without Import-ing it.
  glob_capture.ml               Capture resolved identifiers via Dumpglob.Feedback.
  text_table.ml                    Shared box-drawing grid renderer (Pp.tag and ANSI backends).
  report.ml                           Shared report type + renderer (used by both front ends).
  g_namespace_analysis.mlg               The `NamespaceAnalysis` vernacular command (native plugin).
theories/
  Loader.v                                 `Declare ML Module` — Require Import this to load the plugin.
cli/
  namespace_analysis_cli.ml  Standalone driver: loads a Rocq document like `coqtop -l`,
                              runs the same analysis, prints to stdout.
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
marked, rather than either hidden entirely or shown anyway; batch mode
(`--dir`) correctly aggregating identifier occurrences from more than one
target file into a single report, with single-file invocations remaining
byte-identical to before batch mode existed; and `--format summary`/`json`
agreeing with the default grid's clash count on the same batch input.

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
`test/fixtures/MutualInductive.v`, `test/fixtures/ConstructorClash.v`,
`test/fixtures/ExcludedWinner.v` — the ones that call the native
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

One known cosmetic wrinkle from doing this: `-R test/fixtures/libs MyDev`
is recursive, and several unrelated fixture families
(`multilevel/`, `three/`, `mutual/`, `construct/`, `excldemo/`,
`exclwinner/`) happen to live as subdirectories of that same
`test/fixtures/libs/` — so opening `Main.v` prints a handful of harmless
`overriding-logical-loadpath` warnings as those subdirectories' own
`-R` entries (listed after `MyDev`'s in `_CoqProject`) correctly take
precedence. Doesn't affect correctness (confirmed: the clash-detection
output is exactly right regardless), just noise; the real fix would be
moving `PartA.v`/`PartB.v`/`PartC.v` into their own subdirectory to match
every other fixture family's layout, which hasn't been done since it'd
touch several already-tested paths in `test/run_test.sh` for a purely
cosmetic gain.

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
- **Domain arguments are library/module prefixes only** (e.g. `MyDev.PartA`),
  matching `Print Namespace`'s argument style. File-path domains are a
  planned extension, not yet built.
- **`Local` definitions can produce a false-positive clash, confirmed by
  direct testing.** `Local` (outside a section) only blocks a definition's
  *short-name* binding on `Import` — it's still fully-qualified-accessible
  from anywhere (`Check LocalTest.Priv.helper.` resolves fine from another
  file), and it still shows up as a domain "member" (`Environ.fold_constants`
  walks the kernel's constant table, which must retain it if any public
  lemma's proof term depends on it). `Clash_detect`'s candidate set unions
  "what's really visible" with "what the probed domain contains" — the
  second half doesn't know about `Local` — so probing a domain that has a
  `Local helper` alongside another library's real, non-`Local` `helper`
  reports a clash, even though Rocq itself would *never* actually resolve
  the short name `helper` to the `Local` one (confirmed: `Check helper.`
  unambiguously picked the real one). Sections themselves are fine — a
  `Variable` never becomes its own symbol, it's abstracted into an extra
  argument on whatever's defined inside the section, indistinguishable from
  an ordinary top-level definition once the section closes.
- **Open design question, not yet resolved**: when an excluded prefix (e.g.
  `Corelib`) happens to be the *actual current winner* of a clash, the clash
  is still reported (with only non-excluded alternatives shown) but with no
  winner singled out, rather than either hiding the whole clash or revealing
  an excluded winner anyway. Flagged for revisit. Pinned as a regression
  (not resolved) by `ExcludedWinner.v` in the test suite — see `Examples.md`.
- The CLI always exits `0`; a `--strict` flag for CI gating (nonzero exit on
  any clash) isn't built yet.

## Roadmap

- File-path domain arguments (resolve a `.v` path to its module prefix).
- `--strict` CI exit-code mode — `--format json` (see "Batch mode") gives
  this a firmer footing than parsing terminal output, but the exit-code flag
  itself still isn't built.
- A domain argument matching nothing should say so explicitly, distinct from
  a clean bill of health.
- `_CoqProject`/`Makefile` parsing for `--dir`, so batch mode could point at
  an arbitrary project without hand-supplied `-R`/`-Q` mappings — see "Batch
  mode" above for why this was deliberately left out for now.
- Filter (or at least visibly label) `Local` definitions in the clash
  candidate set — see "Known limitations" above. A `Local` member could
  still be worth surfacing (e.g. it becomes a real problem if someone later
  removes the `Local`), so labeling rather than silently dropping might be
  the better default; needs a decision, not just an implementation. Would
  also let `--summary`'s "no winner marked" count (see "Batch mode") split
  out a `Local`-caused false positive from a genuine clash — it can't today.
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
