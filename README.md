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
| Target file | positional, must not start with `-` | *(implicit — the file you're compiling)* | The `.v` file to analyze. CLI-only argument; the native command always analyzes the file it's running in. |

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

Covers: the original two-library `K` clash (plugin/CLI parity against a
checked-in golden report); a 4-level-deep domain caught by probing a
2-level-shallow prefix; 0/1/2/3 `--domain` arguments against three
same-named libraries; a domain named only as an argument, never actually
`Require`d, correctly surfacing as a would-be clash while proving no
short-name pollution occurred; the default `Corelib` exclusion
disappearing/reappearing correctly with `--include`; a clash buried in the
*second* type of a two-type mutual inductive block; a clash between two
libraries' same-named constructors on otherwise differently-named types; and
the "excluded winner" edge case below, pinning that a clash whose actual
current winner falls under an excluded prefix is still reported, with no
winner marked, rather than either hidden entirely or shown anyway.

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
- `--strict` CI exit-code mode.
- A domain argument matching nothing should say so explicitly, distinct from
  a clean bill of health.
- Filter (or at least visibly label) `Local` definitions in the clash
  candidate set — see "Known limitations" above. A `Local` member could
  still be worth surfacing (e.g. it becomes a real problem if someone later
  removes the `Local`), so labeling rather than silently dropping might be
  the better default; needs a decision, not just an implementation.
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
