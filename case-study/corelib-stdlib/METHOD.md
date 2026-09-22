# Case study: Corelib/Stdlib (Workstream 9, Pass 1)

How to reproduce this run from a clean checkout of this repo. See
`RESULTS.md` in this same directory for what it actually found.

## Environment

- This repo's own toolchain, unmodified — no external repo, no version
  mismatch to work around (that concern only applies to Pass 2, the
  `mech-eff-insep` corpus).
- Confirmed against: Rocq 9.1.1 (compiled with OCaml 4.14.4), repo commit
  `5b36809` (`git log -1`), via `nix develop` + `dune build` at this
  repo's root.

## Target file

Corelib/Stdlib's own prelude is auto-loaded into every Rocq session via
`Load.load_init_vernaculars` — the target file doesn't need to `Require`
anything for the "0 domains" case to already include it. A trivial
scratch file is enough; a couple of `Check`s just give the "Used
identifiers" section something real to show:

```coq
Check eq_refl.
Check plus.
Check 0.
```

## Commands

Build (if not already):
```sh
nix develop -c dune build
```

Set up the CLI:
```sh
export OCAMLPATH="$PWD/_build/install/default/lib:${OCAMLPATH:-}"
CLI="$PWD/_build/default/cli/namespace_analysis_cli.exe"
```

**The one easy-to-miss detail**: `Corelib` is excluded from candidate
lists by default (`default_excludes` in `cli/namespace_analysis_cli.ml`).
Since Corelib/Stdlib *is* the thing being probed here, every command below
needs `--include Corelib` explicitly — without it, every candidate for
every clashing name is itself under `Corelib`, gets filtered out by the
default exclusion, and the run trivially reports "no clashes found"
regardless of what's actually there. Confirmed directly (see `RESULTS.md`
§1) by running both ways.

```sh
# 1. Cheap first look
"$CLI" --include Corelib --format summary scratch.v

# 2. Full grid (clash count here is well under the 100-clash
#    large-report-note threshold, so the default grid format is readable)
"$CLI" --include Corelib scratch.v

# 3. JSON, for archival / programmatic inspection
"$CLI" --include Corelib --format json scratch.v
```

("0 domains" — no `--domain` flag — means "everything currently loaded,"
which for this trivial target is exactly Corelib/Stdlib itself; no
`-R`/`-Q` flags are needed since nothing project-specific is being
`Require`d.)
