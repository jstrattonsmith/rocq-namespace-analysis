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
   clash), showing which one currently wins and what it shadows.
2. Every identifier the file actually uses, resolved to its fully-qualified
   defining location.

A related but distinct command, `ImportAnalysis`, is planned as a follow-up
(designed, not yet built) — see the Roadmap section.

## Why this exists

Several developments have broken because of exactly this kind of import
clash, and Rocq has no built-in aggregate report for it: `Locate` and `Print
Namespace` each show part of the picture, but only interactively, one
identifier or one namespace at a time. This tool is a thin synthesis of
machinery Rocq already ships — no new parser or elaborator required:

- **Clash detection** uses `Nametab.locate_all`, the exact function `Locate`
  itself calls to enumerate every visible candidate for a short name.
- **Domain enumeration** uses `Environ.fold_constants`/`fold_inductives`
  filtered by dirpath prefix — what `Print Namespace` uses internally.
- **Used-identifier resolution** hijacks `Dumpglob`'s `Feedback` output mode
  (normally used to generate `.glob` files for `coqdoc`) to capture, in
  memory, every identifier the elaborator resolves.

## Layout

```
src/
  domain_scan.ml         Enumerate constants/inductives under given dirpath prefixes.
  clash_detect.ml         For each name, find every candidate via Nametab.locate_all.
  glob_capture.ml           Capture resolved identifiers via Dumpglob.Feedback.
  report.ml                   Shared report type + renderer (used by both front ends).
  g_namespace_analysis.mlg      The `NamespaceAnalysis` vernacular command (native plugin).
theories/
  Loader.v                        `Declare ML Module` — Require Import this to load the plugin.
cli/
  namespace_analysis_cli.ml  Standalone driver: loads a Rocq document like `coqtop -l`,
                              runs the same analysis, prints to stdout.
test/
  fixtures/, expected/, run_test.sh   Two libraries with a clashing `K`; checks that
                                       the plugin and CLI reports match each other and
                                       a known-good expected report.
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
versions too, so this cap doesn't cost anything there).

## Running the tests

```sh
bash test/run_test.sh
```

Toolchain-agnostic: run it inside `nix develop`, or with Homebrew's
`rocq`/`dune` on `PATH` and `LIBRARY_PATH` exported as above.

This builds two fixture libraries that both define `Lemma K`, then checks
that the native plugin command and the external CLI report the identical
clash (`K -> MyDev.PartB.K (shadows MyDev.PartA.K)`) and identical resolved
used-identifiers, matching a checked-in expected report.

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
- **Clash scope is intentionally asymmetric**: domain arguments select which
  short names get *probed*, but once probed, every visible candidate is
  reported — even ones outside the named domains. This mirrors how `Locate`
  itself behaves and avoids hiding a real clash just because a third library
  wasn't named.
- The CLI always exits `0`; a `--strict` flag for CI gating (nonzero exit on
  any clash) isn't built yet.

## Roadmap

- File-path domain arguments (resolve a `.v` path to its module prefix).
- `--strict` CI exit-code mode.
- Additional regression fixtures: a domain argument matching nothing (should
  say so, not silently report a clean bill of health), a `Require`-without-
  `Import`ed library's definitions correctly absent from candidates, and a
  clash against the standard library.
- `ImportAnalysis` (designed, not yet built): a different question from
  `NamespaceAnalysis` — "of everything an imported domain exports, which
  pieces does this file actually depend on," so you can tell whether a
  symbol you're importing (and thus exposed to clashing on) is even needed.
  Built on `Assumptions.traverse` (the machinery behind `Print Assumptions`)
  rather than syntactic occurrence tracking, specifically so it doesn't miss
  dependencies injected by proof automation (`auto`, typeclass resolution,
  canonical structures) that never appear as literally-written identifiers.
- Notation clashes: feasible in principle (`Notation.locate_notation` is
  structurally close to `Nametab.locate_all`) but a genuinely separate
  follow-up — notations are keyed differently and have no `Print
  Namespace`-equivalent enumeration entry point.
