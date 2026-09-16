# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

Build (Nix is the primary/recommended path; a Homebrew alternative exists — see README "Building"):

```sh
nix develop
dune build
```

Run the full test suite. There is no per-test invocation: `test/run_test.sh` is one linear
hand-rolled bash script (not `dune runtest` — sandboxed dune rules proved fragile for a tool
that needs a real Rocq session with its own plugin loaded via `OCAMLPATH`) covering a growing list
of fixture sections in sequence under `set -euo pipefail`, aborting at the first failing section
(it also invokes `test/run_error_test.sh` automatically at the end):

```sh
nix develop -c bash test/run_test.sh
```

Build OCaml API docs (odoc; `src/*.mli` already carries the doc comments):

```sh
nix develop -c dune build @doc
# output: _build/default/_doc/_html/rocq-namespace-analysis/index.html
```

Run the CLI directly against a `.v` file, or a whole project via `--dir` (see README "Argument
reference" and "Batch mode" for full flag meanings):

```sh
export OCAMLPATH="$PWD/_build/install/default/lib:$OCAMLPATH"
_build/default/cli/namespace_analysis_cli.exe -R <dir> <DirPath> --domain <DirPath> <file.v>
_build/default/cli/namespace_analysis_cli.exe -R <dir> <DirPath> --dir <project> --format summary
```

`test/run_test.sh`'s target fixtures (`test/fixtures/*.v`) get compiled in place, leaving
`.vo`/`.glob`/`.aux` build artifacts alongside them (gitignored) — expected, not a sign anything's
broken.

Adding a new `.ml`/`.mli` module under `src/` requires listing it explicitly in `src/dune`'s
`(modules ...)` stanza — it's not picked up automatically.

Live/interactive editing in VS Code (VsRocq): `nix develop` already includes
`vsrocq-language-server` — launch `code .` *from inside* that shell (if VS Code is already
running, fully quit it first; otherwise `code .` just opens a new window in the existing process,
which never inherits the shell's `PATH`/`OCAMLPATH`). See README "Editor setup". `_CoqProject` at
the repo root is for this and other editor front-ends only — `dune build` doesn't read it, it's
separate from the real build.

## Architecture

One shared analysis engine (`src/`), consumed by two front ends that must stay behaviorally
identical — `test/run_test.sh` diffs their output against each other for every fixture:

- **Native plugin** (`src/g_namespace_analysis.mlg` + `theories/Loader.v`): a `NamespaceAnalysis`
  vernacular command usable inside a `.v` file mid-compilation. Only sees identifiers used *after*
  `Require Import Loader.` installs capture.
- **CLI** (`cli/namespace_analysis_cli.ml`): a standalone driver that loads a Rocq document like
  `coqtop -l`, installs capture *before* loading the target file (so it has none of the plugin's
  "must import Loader first" restriction), then runs the identical engine. Batch mode (`--dir`,
  repeatable positional files) folds `Vernac.load_vernac` over every target file into the same
  session before analyzing once at the end — the engine itself doesn't know or care whether it's
  looking at one file or a whole corpus.

Both front ends thread through the same pipeline, one module per stage:

1. **`Ensure_loaded`** — for every domain argument, auto-`Require`s it (never `Import`s it) if not
   already loaded, so "would this clash if I imported it" can be asked without editing the file
   first. Works around two real Rocq API quirks (`Library.library_is_loaded` always returning
   `true`; the `Require`-bypass's loaded-library bookkeeping not persisting across vernacular
   commands) — read the header comment in `src/ensure_loaded.ml` before touching this file.
2. **`Domain_scan`** — walks `Environ.fold_constants`/`fold_inductives` to enumerate every
   constant, inductive type, and constructor whose dirpath falls under a probed domain prefix.
   Must iterate every packet of a mutual inductive block and every constructor of each packet, not
   just index/constructor 0 — a real bug in both, fixed; see `PLANNING.md` Workstreams 1–2 and
   `Examples.md` for the fix and a worked example (fixing this also surfaces Rocq's
   auto-generated `_ind`/`_rec`/`_rect`/`_sind` induction-scheme constants as clash candidates).
3. **`Clash_detect`** — for each short name appearing among the scanned members, unions
   `Nametab.locate_all` (what's genuinely visible right now) with the scanned members themselves
   (covers `Require`d-but-not-`Import`ed hypothetical domains, which `Nametab.locate_all` alone
   never sees), filters both by excluded prefixes, and reports every name with 2+ non-excluded
   candidates. Load-bearing invariant: probing is never restricted to the named domains — a clash
   surfaces even against a library nobody named, mirroring how `Locate` itself behaves.
4. **`Glob_capture`** — hijacks `Dumpglob`'s `Feedback` output mode (normally how `.glob` files
   for `coqdoc` get generated) to record every identifier the elaborator resolves, in memory,
   instead of to disk. This shadows real `-dump-glob` output for the rest of the compilation unit.

`Report` renders the same result type four ways: `to_pp` (plugin message panel, `Pp.tag`-based
emphasis via `Text_table`), `to_string` (plain/ANSI grid, CLI stdout, TTY-detected — the clash
winner always gets a plain-text `<- used` suffix regardless of color support, never the only
signal), `to_summary` (one line of counts, no grid, for a whole-corpus `--dir` run), and `to_json`
(a fixed, hand-serialized shape, CLI-only, no JSON library dependency). The last two exist
specifically because the grid doesn't scale to a hundreds-of-files batch run.

Two Rocq versions are both actively supported (Nix: 9.1.1, Homebrew: 9.2.0); watch for API drift
between them (e.g. `Flags.in_synterp_phase`'s type differs — see `src/ensure_loaded.ml`) when
touching anything that isn't already isolated behind the existing modules.

`PLANNING.md` tracks the live workstream-by-workstream plan and status (there's a RocqPL 2027 talk
submission driving the current push) — check it for what's in progress before assuming a gap in
the README's "Known limitations"/"Roadmap" is unclaimed work. `Examples.md` is a holding file for
verified-output examples of recently-added features, meant to be folded into the README later.

## Working conventions

- Work through `PLANNING.md` workstreams one at a time — implement, verify, summarize, then wait
  for a go-ahead before starting the next one, even for workstreams that look small/independent.
- Every correctness fix or new capability gets a regression fixture wired into
  `test/run_test.sh`, confirmed load-bearing (e.g. by reverting the fix and re-running the suite
  to see it fail) — not case-by-case, this is a standing rule for this project.
- This repo (`rocq-namespace-analysis`) is private and single-maintainer with no PR/review gate —
  push to `origin/main` right after each commit rather than leaving commits local.
