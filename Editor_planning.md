# Getting `rocq-namespace-analysis` installable (opam + Nix), so any editor gets it for free

## Status update: local VS Code demo/testing is DONE, ahead of opam/Nix packaging

Jeremy wanted to demo/test live from within VS Code *now*, against this
repo directly, before P1/P2 (real opam/Nix packaging) exist. That's a
different, smaller need than everything below: it doesn't need this project
to be *installed* anywhere, it needs `dune build`'s local output to be
*findable* by an editor, which is exactly the same problem the CLI already
solved for a terminal shell.

Done:
- `_CoqProject` at repo root: `-R _build/default/theories NamespaceAnalysis`.
- `flake.nix`: `rocqPackages_9_1.vsrocq-language-server` is in the one
  shared `devShells.default` — **revised from an earlier separate
  `devShells.editor` output**: Jeremy explicitly decided the closure-size
  argument for splitting doesn't outweigh the "which shell do I use"
  friction for a private, single-maintainer project, especially once actual
  troubleshooting was in progress. `vsrocq-language-server` does pull in a
  real GTK3/Cairo/Pango dependency chain (~40 extra store paths, confirmed
  via the build log) but it's cache-fetched, not built from source, so the
  real cost is fetch time only.
- `.vscode/extensions.json` (recommends `rocq-prover.vsrocq`) and
  `.vscode/settings.json` (`"vsrocq.path": "vsrocqtop"`, a bare PATH-resolved
  command, not a hardcoded store path).
- Verified the underlying mechanism end-to-end (not just "should work"): ran
  `rocq repl -R _build/default/theories NamespaceAnalysis` (the same
  process model `vsrocqtop` uses) piping in `From NamespaceAnalysis Require
  Import Loader.` + `NamespaceAnalysis Hello.`, and got the plugin-loaded
  message back.
- **Real troubleshooting, now resolved**: Jeremy hit "no Rocq available"
  after following the (then two-shell) instructions. The fix was the
  full-quit-before-`code .` issue documented in the README (an already-
  running VS Code instance doesn't inherit a newly-launched shell's
  environment) — **confirmed working** after that. This was the one thing
  that couldn't be verified from here (no GUI available in this
  environment); it's now actually confirmed end-to-end, not just
  should-work.
- **Fixture libraries for the checked-in demo files**: `_CoqProject` alone
  only covered `NamespaceAnalysis` itself — the top-level demo fixtures
  (`test/fixtures/Main.v`, `MutualInductive.v`, `ConstructorClash.v`,
  `ExcludedWinner.v`) also `Require` their own dependency libraries
  (`MyDev`, `MutLibA`/`B`, etc.), which only ever existed compiled into
  `test/run_test.sh`'s ephemeral temp dir. New `test/build_fixtures.sh`
  compiles them *in place* instead (persistent), with matching `-R` entries
  added to `_CoqProject`. Verified end-to-end by driving `rocq repl` with
  every `_CoqProject` `-R` flag against `test/fixtures/Main.v` directly and
  getting the real clash grid back. One cosmetic wrinkle found and
  documented (not fixed): `-R test/fixtures/libs MyDev` is recursive and
  overlaps with several other fixture families' own subdirectories,
  producing harmless `overriding-logical-loadpath` warnings — see README
  "Trying it on the checked-in fixtures" for why this wasn't restructured
  away (would touch several already-tested `run_test.sh` paths for a purely
  cosmetic gain).

See the README's new "Editor setup" section for the actual how-to. Emacs
and RocqIDE are still just planned (below), not wired up.

Everything below this point is the original opam/Nix *packaging* plan —
still relevant for making `NamespaceAnalysis` installable by other people
into their own ambient Rocq installation (so it works in *their* editor
with zero setup, the way `Locate` does), which is a separate, larger goal
from "Jeremy can demo it live today."

## Reframe (superseded an earlier draft of this plan)

The first pass at this plan treated VS Code, Emacs, and RocqIDE as three
separate integration workstreams. That was wrong, and Jeremy caught it:
`NamespaceAnalysis` is an ordinary `VERNAC COMMAND EXTEND` that calls
`Feedback.msg_notice`, exactly like `Locate`/`Search`/`Print Namespace` do
internally. Every front-end works by driving a Rocq process and rendering
whatever `Feedback` comes back — none of them have special-cased knowledge
of *which* commands exist. So the only reason `NamespaceAnalysis` currently
needs any custom setup at all is that it isn't installed the way `Locate`
is (baked into every Rocq install) or the way a normal third-party plugin
is (Equations, QuickChick, Coq-Elpi — installed via opam/Nix into the
*ambient* Rocq installation any front-end already uses). Once it's
installed that way, it becomes exactly as front-end-agnostic as any of
those, with zero editor-specific code — not "less work per editor," *no*
work per editor.

That collapses the three editor-specific workstreams into two packaging
workstreams: **opam** and **Nix**. This file is now about those.

## Already fixed during this planning pass (confirmed, kept)

Checked whether this project is even structurally ready to be installed as
a package at all, using dune's own `@install` target as the source of
truth (`dune build @install` generates `_build/default/rocq-namespace-analysis.install`,
the literal manifest `dune install`/opam would use) — found and fixed one
real gap:

**`theories/dune`'s `(rocq.theory ...)` stanza had no `(package ...)`
field.** Confirmed via the generated `.install` file: before the fix, it
listed the OCaml library, plugin, and CLI binary (all three already had
`public_name`, so they were correctly attached to the package) but *nothing
under `theories/`* — the compiled `Loader.vo` would never have been
installed anywhere. Added `(package rocq-namespace-analysis)` next to the
existing `(name NamespaceAnalysis)`/`(plugins ...)` fields; confirmed by
re-running `dune build @install` that this now produces:
```
lib_root: [
  "_build/install/default/lib/coq/user-contrib/NamespaceAnalysis/Loader.glob"
  "_build/install/default/lib/coq/user-contrib/NamespaceAnalysis/Loader.v"
  "_build/install/default/lib/coq/user-contrib/NamespaceAnalysis/Loader.vo"
]
```
Full test suite still passes after this change (no behavior change for the
existing dev workflow, purely additive install metadata).

**This is the load-bearing fact for the whole plan**: `coq/user-contrib/` is
on Rocq's *default* load path — nothing needs an `-R`/`-Q` flag or a
`_CoqProject` entry to find something installed there. So once this package
is actually opam- or Nix-installed into an ambient Rocq installation,
`From NamespaceAnalysis Require Import Loader.` resolves automatically, in
any front-end, the same way `From Corelib Require Import ...` already does
today with zero configuration. The entire earlier draft's `_CoqProject`
workstream (for *our own* theory) is now moot — it was only ever needed
because the plugin lived nowhere but this repo's own `_build/`.

(A project *consuming* `NamespaceAnalysis` — i.e. whatever `.v` files a user
actually wants analyzed — still needs its own normal `-R`/`-Q` mapping or
`_CoqProject` for *its own* sources, same as it always would; that's not
something this plan changes or needs to.)

## A consequential decision this creates: going public

Both the official opam-repository and nixpkgs require a publicly fetchable
source (a tagged release / tarball URL, typically from GitHub).
`PLANNING.md`'s own Context section already notes this repo is private,
deliberately, until Jeremy decides to flip it (e.g. to link it from the
RocqPL abstract). **Submitting to either package index effectively *is*
that decision** — not a separate, later one. Flagging this explicitly
rather than letting it happen as a side effect of "getting packaging done."

Two lighter-weight paths exist that don't force that decision yet:

- **Nix**: doesn't need nixpkgs at all for this to work. `flake.nix` already
  being a flake means anyone with access to this (private) repo can already
  do `nix profile install git+ssh://git@github.com/jstrattonsmith/rocq-namespace-analysis`,
  or add it as a flake input to another project, *today* — provided
  `flake.nix` actually exposes a `packages.default` output. It currently
  only exposes `devShells.default`. **That's the real Nix gap** — not "get
  into nixpkgs," which is a separate, optional, later step only worth doing
  once the repo is public anyway.
- **opam**: a custom opam repository (just a git repo in the right
  directory shape) that Jeremy hosts and users add manually
  (`opam repo add namespace-analysis <url>`) works without going through
  opam-repository's review process, and without needing the *package
  index* to be public — though the repo it points at (this one, or a
  dedicated host for the custom opam repo) still needs to be fetchable by
  whoever adds it, which for a private GitHub repo means they need access
  credentials same as with the Nix flake-input path above.

## Workstream P1 — Nix: a real `packages.default` output

**File**: `flake.nix`.

Right now the flake produces only `devShells.default`. Add
`packages.default` (or `packages.rocq-namespace-analysis`) building this
project as an actual installable derivation, not just a shell to develop
in. nixpkgs already has the building block to model this on: confirmed
`rocqPackages_9_1.mkCoqDerivation` exists (a function, used to build real
Rocq packages like `rocqPackages_9_1.coq-lsp`) — worth using as the
reference shape rather than hand-rolling a `stdenv.mkDerivation` that
re-invents dune-with-Rocq build conventions nixpkgs has already solved.

Open questions to resolve during implementation, not now:
- Does `mkCoqDerivation` handle a project that also builds a plain OCaml
  CLI binary + library (not just theory files), or is that additional
  `buildDunePackage`-style wiring on top? This project has three moving
  parts (OCaml lib, OCaml plugin, Rocq theory) under one opam package —
  worth checking how a similarly-shaped existing nixpkgs derivation (if one
  exists) handles this before assuming `mkCoqDerivation` alone suffices.
- Should `packages.default` build from the local working tree (`src = ./.`,
  simplest, always matches what's checked out) or from a tagged git
  revision (more "real package" semantics, matches how `coq-lsp`'s
  derivation pins a specific archive URL)? Local tree is almost certainly
  right for now given the repo isn't tagged/released yet.

## Workstream P2 — opam packaging

**Files**: `dune-project` (metadata), a generated `rocq-namespace-analysis.opam`.

`dune-project` today has `name`/`synopsis`/`license`/`depends` but is
missing the fields a real opam package wants: `authors`, `maintainers`,
`homepage`, `bug_reports`, `source` (a `(github user/repo)` stanza dune
uses to fill in `dev-repo`/`bug-reports`/`homepage` automatically). No
`.opam` file exists in the repo yet — add `(generate_opam_files true)` to
`dune-project` and run `dune build` to generate
`rocq-namespace-analysis.opam` from the package stanza, rather than
hand-writing one that can drift from `dune-project`'s own dependency list.

Also needs, before this is truly installable via opam:
- A version — either a git tag opam pins to, or (for the custom-repo path)
  whatever versioning scheme Jeremy wants for pre-1.0 iteration.
- A decision on **which path** (see "going public" above): full
  opam-repository submission (public, goes through community review, most
  discoverable) vs. a custom opam repo (no public index requirement, no
  review, less discoverable — fine if the audience is "people Jeremy tells
  directly," e.g. RocqPL talk attendees with the repo link).

## Workstream P3 — editor documentation (small, once P1/P2 exist)

Once either P1 or P2 lands, using `NamespaceAnalysis` from any front-end is
just "you already have it installed like any other Rocq library, use your
editor's normal Rocq support" — genuinely no more than a short README
paragraph per front-end, not a workstream with its own design questions:

- **VS Code**: install the VsRocq extension (`rocq-prover.vsrocq` on the
  Marketplace) the way you would for any Rocq project. No settings beyond
  what VsRocq already needs for the project you're analyzing.
- **Emacs**: install Proof General (MELPA, or `emacsPackages.proof-general`
  in Nix — confirmed present, version `20260622.1503`) the way you already
  do for any Rocq project.
- **RocqIDE**: same idea, once a working binary is sorted out for whichever
  install path is in use — genuinely unresolved right now (see below), but
  that's an install-path problem, not an integration problem.

The one caveat worth a documented note either way: `Declare ML Module`
still needs the *plugin's* OCaml side (`namespace_analysis_plugin.cmxs`) to
be findable via `OCAMLPATH`/findlib from whatever process each front-end
spawns — a properly opam- or Nix-installed package puts that in the
ambient installation's own standard location automatically, the same way
it does for any other opam-installed Rocq plugin, so this resolves itself
once P1/P2 exist. No separate fix needed.

### RocqIDE's install path is still an open question, independent of this plan

Checked directly: `rocqPackages_9_1` has no `rocqide`/`coqide` attribute
(only `coq-lsp`, `vsrocq-language-server`, `overrideScope`), and the
already-built `rocq-core` package's own `bin/` doesn't bundle one either
(`csdpcert`, `ocamllibdep`, `rocq`, `rocq.byte`, `rocqchk`, `votour` —
no IDE binary). Not confirmed *why* (RocqIDE needs
`lablgtk3-sourceview3`/GTK3, plausibly just not built by this particular
derivation), only *that* it's absent. A Homebrew fallback exists and is
confirmed real (`brew install --cask coqide`, or the bundled
`coq-platform` cask) — consistent with how this project already treats
Homebrew as documented-but-not-CI'd (Workstream 7). This doesn't block P1/P2
at all; it only affects whether RocqIDE specifically has a clean Nix path
to recommend once packaging is done.

## Local-dev note (unaffected by any of this)

None of the above changes how *this project's own* development works.
`nix develop` + `dune build` + the `OCAMLPATH` shellHook remain exactly
right for hacking on `NamespaceAnalysis` itself, editing test fixtures,
etc. — P1/P2 are about how *other people* (or Jeremy, in a different
project) consume the finished plugin, not a replacement for the existing
dev loop.

## Decisions needed from Jeremy

- **Public now, or one of the lighter-weight private paths (Nix flake
  input / custom opam repo) for now?** This is the load-bearing decision —
  everything else in P1/P2 is sequenced after it.
- **If going public: opam-repository + nixpkgs submission, or just "push a
  tag and point people at `nix profile install`/a custom opam repo" for
  now, with real package-index submission later** (e.g. once the RocqPL
  talk actually needs the discoverability)?
- Does RocqIDE matter enough to chase down its Nix packaging gap now, or
  is "works via Homebrew, Nix TBD" an acceptable answer for the near term?

## Suggested execution order

Decide the public/private question first (it gates everything else) → P1
(Nix `packages.default` — works today even while private, via a flake
input) → P2 (opam metadata + `.opam` generation; submission timing depends
on the public/private decision) → P3 (the short per-editor documentation,
plus folding this into the README once at least one install path is
actually confirmed working end-to-end — per this project's standing rule of
confirming before documenting as done).
