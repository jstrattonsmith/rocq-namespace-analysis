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
separate from the real build. To open a demo fixture (`test/fixtures/Main.v` etc.) directly, run
`bash test/build_fixtures.sh` after `dune build` first — it compiles the fixture libraries
*in place* (persistent, unlike `test/run_test.sh`'s own ephemeral temp-dir compilation), matching
`_CoqProject`'s `-R` entries for them.

## Architecture

One shared analysis engine (`src/`), consumed by two front ends that must stay behaviorally
identical — `test/run_test.sh` diffs their output against each other for every fixture:

- **Native plugin** (`src/g_namespace_analysis.mlg` + `theories/Loader.v`): a `NamespaceAnalysis`
  vernacular command usable inside a `.v` file mid-compilation. Only sees identifiers used *after*
  `Require Import Loader.` installs capture.
- **CLI** (`cli/namespace_analysis_cli.ml`): a standalone driver that loads a Rocq document like
  `coqtop -l` — under the file's real logical name (`Coqargs.TopPhysical`, the same derivation
  `rocq compile` uses), not `Top` — installs capture *before* loading the target file (so it has
  none of the plugin's "must import Loader first" restriction), then runs the identical engine.
  Batch mode (`--dir`, repeatable positional files) re-executes the CLI once per file with a hidden
  `--batch-worker` flag, each file in its own process, and the parent only collects pre-rendered
  per-file results. Never load several files into one session: that duplicates each file against
  the compiled copy its neighbours `Require` (see `Examples.md` §18).

Because use sites are reported by line and the test suite diffs plugin output against CLI output,
every `test/fixtures/*Cli.v` twin must stay line-for-line aligned with its plugin fixture (the
`Loader` line becomes a comment, in-file `NamespaceAnalysis` commands become blank lines).

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
   The feedback arrives synchronously, mid-elaboration, so the handler also judges each use site
   right then: it reads the name as written from the source and records `Nametab.locate`/
   `locate_all` for it (minus libraries `Ensure_loaded` loaded itself), plus each alternative's
   `Import_status` at that moment. `Clash_detect.ambiguous_uses` later filters and groups these; it
   never consults the current `Nametab`.
5. **`Import_status`** — whether a candidate's module is imported, which Rocq's public API doesn't
   expose: a module counts as imported when its uniquely named members (from
   `Domain_scan.fold_globals`) resolve by bare name right now. Reports `Partial`/`Unknown` rather
   than guessing when the test can't decide (filtered imports; no testable member).

`Report` has three sections — ambiguous uses (per use site), clashes (the namespace at the
analysis point: the command's position for the plugin, end of file for the CLI), used
identifiers — and renders them four ways: `to_pp` (plugin message panel, `Pp.tag`-based
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
