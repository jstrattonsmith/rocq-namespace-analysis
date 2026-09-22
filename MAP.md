# MAP.md: feature → example → fixture/test → implementation

An index of every `NamespaceAnalysis` behavior, where it's demonstrated
with real captured output, where it's regression-tested, and where it's
implemented. Built in response to an explicit "do we have examples for
everything?" audit — five gaps (marked below) were found and backfilled
into `Examples.md` as part of building this file; the audit itself is the
reason this file exists at all, so it also records the two gaps that are
*documented but not backed by a fixture*, and the features that don't
exist yet (no example is possible for something that isn't built).

Only `NamespaceAnalysis` is covered below because that's the only command
that exists — `ImportAnalysis` (a related but distinct, designed-not-built
command) has zero examples anywhere; see the "Not built" section.

## Core analysis features

| Feature | Example | Fixture(s) | `run_test.sh` section | Implementation |
|---|---|---|---|---|
| Basic clash detection, winner marked | `Examples.md` §9 | `Main.v`/`MainCli.v` | "base fixture" | `src/clash_detect.ml`, `src/report.ml` |
| Multi-level domain probing (shallow prefix catches deep clash) | `Examples.md` §10 | `MultiLevel.v`/`Cli.v` | "multi-level domains" | `src/domain_scan.ml` (`in_domain` prefix match) |
| 0/1/2/3 domain arguments | `Examples.md` §11 | `ThreeDomains.v`/`Cli.v` | "0/1/2/3 domain arguments" | `cli/namespace_analysis_cli.ml`, `g_namespace_analysis.mlg` |
| Hypothetical (not-yet-imported) domain | `Examples.md` §12 | `Hypothetical.v`/`Cli.v` | "hypothetical domain" | `src/ensure_loaded.ml` |
| Exclude/include, Corelib excluded by default | `Examples.md` §13 | `ExcludeInclude.v`/`Cli.v` | "exclude/include" | `src/clash_detect.ml` (`in_excluded`) |
| Mutual-inductive scanning (every packet in a block, not just index 0) | `Examples.md` §1 | `MutualInductive.v`/`Cli.v` | "mutual-inductive clash" | `src/domain_scan.ml` |
| Constructor scanning | `Examples.md` §2 | `ConstructorClash.v`/`Cli.v` | "constructor clash" | `src/domain_scan.ml` |
| Excluded-winner edge case (real winner excluded → no winner shown, not hidden) | `Examples.md` §5 | `ExcludedWinner.v`/`Cli.v` | "excluded winner" | `src/clash_detect.ml` (`winner` computation) |
| Batch/`--dir` mode, multi-file aggregation | `Examples.md` §7 | `batch/{One,Two}.v` | "batch mode" | `cli/namespace_analysis_cli.ml` |
| `--format grid\|summary\|json` | `Examples.md` §7 | `batch/{One,Two}.v` | "`--format` summary/json agree..." | `src/report.ml` (`to_summary`, `to_json`) |
| Large-report note (grid past 100 clashes points at `--format`) | `Examples.md` §14 | generated at test-time, not checked in | "large-report note" / "...but not for a small report" | `src/report.ml` (`size_note`) |
| Transitive ("chained") imports found correctly, no special-case code | `Examples.md` §15 | `ChainedImport.v`/`Cli.v` | "transitive imports" | none needed — `Global.env ()`/`Nametab` are already fully-resolved |
| `Local`-definition false positive: labeled `(Local)`, not silently dropped | `Examples.md` §17 | `LocalFalsePositive.v`/`Cli.v` | "Local false positive" (both sections, incl. the `Hypothetical.v` non-regression check) | `src/report.ml` (`is_local_member`, via `Declare.is_local_constant`) |

## Robustness / error handling

| Feature | Example | Fixture(s) | Test | Implementation |
|---|---|---|---|---|
| Clean CLI error messages (no target file, bad `-R`, bad compile, bad `--domain`) | `Examples.md` §4 | `BadCompile.v` | `test/run_error_test.sh` (all 4 cases) | `cli/namespace_analysis_cli.ml` (top-level `try`/`with`) |
| `--format` rejects an unknown value cleanly | *(not in Examples.md — small enough to skip)* | n/a | `run_test.sh` "`--format` rejects an unknown value" | `cli/namespace_analysis_cli.ml` (`parse_format`) |

## Performance

| Feature | Example | Fixture(s) | Test | Implementation |
|---|---|---|---|---|
| O(n log n) clash detection at scale (was O(n²)) | `Examples.md` §8 (1k/10k/100k timings) | generated at test-time, not checked in | `test/run_perf_test.sh` | `src/clash_detect.ml` (`find_clashes`) |

## Infrastructure (not `NamespaceAnalysis` behavior itself)

| Item | Where documented | Where implemented |
|---|---|---|
| CI (GitHub Actions) | `Examples.md` §6 (two real run links) | `.github/workflows/test.yml` |
| OCaml API docs (odoc) | `Examples.md` §3 | `flake.nix`, `dune build @doc` |
| VS Code / VsRocq live editing | README "Editor setup", `Editor_planning.md` | `flake.nix` (`vsrocq-language-server`), `_CoqProject`, `test/build_fixtures.sh`, `.vscode/` |
| Emacs (Proof General), RocqIDE | `Editor_planning.md` only (planned, not wired up) | — |
| opam/Nix packaging (installable elsewhere) | `Editor_planning.md` only (planned) | — |

## Documented but not backed by a fixture (real gaps, not yet closed)

- **`--format` rejecting an unknown value.** Tested (`run_test.sh`), but
  small enough that it was never given a dedicated `Examples.md` write-up
  — noted here rather than silently treated as "covered."

## Not built (no example is possible)

- **Notation clashes.** README Roadmap: "feasible in principle... but a
  genuinely separate follow-up." Zero code, zero fixtures, zero examples.
- **`ImportAnalysis`.** A different, related command (README Roadmap:
  "designed, not yet built") — "of everything an imported domain exports,
  which pieces does this file actually depend on." Everything in this
  repo, including every example above, is `NamespaceAnalysis` only.
- **`--strict` CI exit-code mode.** Roadmap item; the CLI always exits 0
  today regardless of clashes found.
- **File-path domain arguments** (resolving a `.v` path to its module
  prefix, rather than requiring the logical dirpath). Roadmap item.
- **`_CoqProject`/`Makefile` auto-parsing for `--dir`.** Explicitly out of
  scope (Workstream 8) — batch mode requires manually-supplied `-R`/`-Q`.
