# Case study: Iris 4.5.0 — results

See `METHOD.md` in this same directory for how to reproduce every number
here. All figures come from `triage_output.txt` (the output of `triage.py`),
captured on Rocq 9.1.1. First produced with a separate probe (commit
`b1f4269`, whose `METHOD.md` was dry-run end to end in a fresh worktree and
reproduced it exactly); regenerated from the tool's own built-in
import-status labels (Workstream 11), which agree with the probe on all
5,841 (use site, alternative) pairs and give the same split below.

## 1. Headline

| | |
|---|---|
| Files analyzed | 178 (0 failed), one worker process each |
| Wall-clock, whole corpus | 214–223 s before Workstream 11; about 3–4% more with the built-in labels (§5) |
| Peak memory (largest single worker) | 1.1 GB |
| Identifier uses captured | 232,093 |
| **Ambiguous use sites** | **2,251** (in 127 files; 291 distinct names as written; 775 grouped rows) |
| — real shadowing | **873** (39%) |
| — latent | **1,308** (58%) |
| — local-only | **70** (3%) |

- **Ambiguous use site**: a (file, line, name as written) where the name had
  more than one candidate at that point, not counting `Corelib` candidates
  (excluded by default).
- **Real shadowing**: another candidate's module *was* imported there, and
  it lost to the winner — "last import wins" in action.
- **Latent**: every other candidate's module is only loaded (usually
  indirectly), never imported. Nothing is overridden; importing that module
  later would change what the name means.
- **Local-only**: every other candidate is declared `Local`, so it can never
  be reached by that bare name.

Rocq's public API can't distinguish these (README "Known limitations"), so
the tool labels each alternative by an indirect test instead (§4,
`METHOD.md`). Its own split, as it reports it:

| Shadowing | Partly imported | Unknown | Latent | Local-only |
|---|---|---|---|---|
| 855 | 63 | 351 | 912 | 70 |

The 873 / 1,308 / 70 above resolve the two undecided labels by two
Iris-specific judgment calls, each checked against the source (`METHOD.md`):
the partly-imported ones are either a lone `#[local]` sibling (counted as
shadowed) or stdpp's filtered `String` export (latent), and every
"unknown" module was checked never to be imported anywhere in Iris or
stdpp (latent). **Say "2,251 uses of
a name that's also defined somewhere else that's loaded", never "2,251
shadowing bugs"**: even among the 873 real-shadowing sites, almost all are
deliberate design (§2).

For context, the end-of-file Clashes grid (`--domain iris`, per file) finds a
median of 126 clashing short names per file (max 291; 9 files have none),
among a median of 4,456 scanned `iris` members per file. That grid answers
"what's ambiguous in the namespace here", not "what did this file actually
run into"; the per-use numbers above are the second question.

## 2. What the real shadowing is

The 873 real-shadowing sites fall into recognizable patterns (`triage.py`
buckets them by the winner's and the shadowed candidates' namespaces):

| Sites | Pattern | Example |
|---|---|---|
| 601 | **Language interface shadowed by an instance or refinement.** `heap_lang` defines concrete `val`, `expr`, `state`, `to_val`, `fill`, … and also imports the generic projections from `program_logic.language`/`ectx_language`/`ectxi_language`, which it `Require Export`s (in that order, so `ectxi_language.fill` beats `ectx_language.fill`). | `heap_lang/proofmode.v:288`: `val` → `heap_lang.val`, over three interface `val`s |
| 95 | **heap_lang library: implementation over its interface.** A lock/atomic-heap implementation defines `is_lock`, `writer_locked`, `pointsto`, … while exporting the interface that declares the same names. | `heap_lang/lib/rw_spin_lock.v:79`: `writer_locked` |
| 87 | **Logic layering.** Model-level lemmas (`uPred_primitive`, `siProp_primitive`) over the generic BI ones, BI lemmas over stdpp's (`True_impl`, `exist_proper`), "restate" modules. | `bi/big_op.v:301`: `True_impl` → `bi.derived_laws.bi`, over `stdpp.base` |
| 36 | **stdpp replacing Stdlib.** stdpp's `base.v` does `From Stdlib Require Export … List …` and then defines its own `filter`, `NoDup`, `Forall_app`, …, which win. | `algebra/gmap.v:179`: `filter` |
| 24 | **Step-index specialization.** `stepindex_finite`'s `dist_le`, `dist_S`, … over the generic OFE/CMRA lemmas. | `algebra/cofe_solver.v:109`: `dist_le` |
| 30 | **Other** — listed below. | |

All but the last row are the same finding as Pass 1's Corelib case study
(`Decimal`/`Hexadecimal`/`Number`): a large development deliberately
reusing names across parallel layers and relying on import order to pick
the right one. It works — but the only thing recording *which* one a
given line gets is the order of `Require Export`s, sometimes several files
away.

The "other" 30 are the most interesting for the talk, because in these
the same name is reused for **different concepts**, not layers of the same
one:

| Sites | Name | Winner | Shadowed | What's going on |
|---|---|---|---|---|
| 6 + 3 | `Free`, `state` | `heap_lang.lib.logatom_lock` | heap_lang's `Free` (the deallocation *expression*) and `state` (the heap) | `logatom_lock.v` defines `Inductive state := Free \| Locked` — a lock state — while importing heap_lang, whose `Free` and `state` mean something else entirely |
| 5 + 2 | `nsteps` | `program_logic.language.nsteps` | `stdpp.relations.nsteps` | n-step execution of language configurations vs. n-step closure of an arbitrary relation |
| 2 | `set_bind_singleton` | `stdpp.sets` | `stdpp.fin_sets` | **stdpp has two different lemmas with this name** (`{[x]} ≫= f ≡ f x` for monadic set bind, vs. `set_bind f {[x]} ≡ f x`), both imported; import order decides |
| 3 | `fresh` | `heap_lang.locations.Loc.fresh` | `stdpp.base.fresh` | fresh location vs. the generic `Fresh` class method |
| 2 | `join` | `heap_lang.lib.spawn.join` | `stdpp.base.join` | a heap_lang program that waits for a spawned thread vs. the lattice-join class method (`Join A := A → A → A`) |
| 3 | `lt_wf` | `stepindex.SIdx.sidx.lt_wf` | `Stdlib.Arith.Wf_nat.lt_wf` | well-foundedness of an abstract step-index order vs. of `nat` |
| 2 | `lookup_ne` | `algebra.gmap.ofe.lookup_ne` | `stdpp.fin_maps.lookup_ne` | "lookup is non-expansive" (an instance) vs. "if two lookups differ, so do the keys" (a lemma) |
| 2 | `faa_atomic` | `heap_lang.lib.atomic_heap` | `heap_lang.class_instances` | interface vs. instance again, across two library files |

None of these is a bug in Iris — each file means the winner, and it
compiles. But each is a place where adding or reordering one import
silently changes what a line refers to, and where the error you'd get (if
any) wouldn't mention the import.

## 3. The per-line judgment matters, in real code

`iris/program_logic/ownp.v` `Require`s `ectx_language` at the top but only
`Import`s it inside one section:

```coq
(* line 5 *)   From iris.program_logic Require ectx_language.
...
(* line 212 *) Section ectx_lifting.
(* line 213 *)   Import ectx_language.
```

So the same written name means different things in different parts of the
file:

| Line | Written | Resolves to | Other candidate |
|---|---|---|---|
| 110, 145, 204 | `prim_step` | `language.prim_step` | `ectx_language.prim_step` — latent |
| 202 | `state` | `language.state` | `ectx_language.state` — latent |
| 214 | `state` | `ectx_language.state` | `language.state` — **shadowed** |
| 216, 217 | `val`, `expr` | `ectx_language.*` | `language.*` — shadowed |

An end-of-file snapshot sees none of this: by the end of the file the
section is closed. This is the pattern the use-site analysis
(Workstream 10) was built for, occurring naturally in Iris.

## 4. Hand verification of the import-status test

30 sites, drawn at random (seed 2027) from the probe's first version,
stratified 12 shadowed / 12 latent / 6 unknown. Each was checked against
the Iris/stdpp sources: the file's imports, and the `Require Export`
chains behind them.

| # | Use site | Written | Resolved to | Other candidate(s) | Probe v1 | By hand | Why |
|---|---|---|---|---|---|---|---|
| 1 | `bi/big_op.v:1970` | `filter` | `stdpp.base.filter` | `Stdlib.Lists.List.filter` | shadowed | shadowed | stdpp's `base.v` does `From Stdlib Require Export ... List ...` |
| 2 | `unstable/algebra/list.v:32` | `Forall_app` | `stdpp…list.Forall_app` | `Stdlib.Lists.List.Forall_app` | shadowed | shadowed | same `List` export |
| 3 | `heap_lang/lib/rw_spin_lock.v:79` | `writer_locked` | `…rw_spin_lock.proof.writer_locked` | `…rw_lock.writer_locked` | shadowed | shadowed | file `Require Export`s the `rw_lock` interface, defines its own |
| 4 | `base_logic/lib/fancy_updates_from_vs.v:37` | `fupd` | `…fancy_updates_from_vs.fupd.fupd` | `iris.bi.updates.fupd` | shadowed | shadowed | `Export base_logic` reaches `bi.updates`; file defines its own `fupd` |
| 5 | `algebra/gmap.v:179` | `filter` | `stdpp.base.filter` | `Stdlib.Lists.List.filter` | shadowed | shadowed | as #1 |
| 6 | `heap_lang/proofmode.v:490` | `fill` | `…ectxi_language.fill` | `…ectx_language.fill` | shadowed | shadowed | `lang.v` exports `language ectx_language ectxi_language`, in that order |
| 7 | `heap_lang/lib/array.v:100` | `length` | `Corelib…Datatypes.length` | `Stdlib.Strings.String.length` | **shadowed** | **latent** | stdpp exports only `String (string(..))`; `length` isn't imported |
| 8 | `program_logic/ectx_language.v:111` | `state` | `…ectx_language.state` | `…language.state` | shadowed | shadowed | `Require Import language`; file defines its own `state` |
| 9 | `heap_lang/lib/logatom_lock.v:22` | `state` | `…logatom_lock.state` | heap_lang/language `state`s; `proofmode.tokens.state` | shadowed | shadowed (tokens: latent) | heap_lang proofmode exports down to `lang`; file defines `Inductive state := Free \| Locked` |
| 10 | `heap_lang/proofmode.v:288` | `val` | `…heap_lang.val` | three language-interface `val`s | shadowed | shadowed | as #6 |
| 11 | `proofmode/class_instances.v:640` | `length` | `Corelib…Datatypes.length` | `Stdlib.Strings.String.length` | **shadowed** | **latent** | as #7 |
| 12 | `program_logic/ectx_language.v:126` | `state` | `…ectx_language.state` | `…language.state` | shadowed | shadowed | as #8 |
| 13 | `base_logic/bi.v:58` | `wand_ne` | `…uPred_primitive.wand_ne` | `iris.bi.interface.bi.wand_ne` | latent | latent | file does `Import uPred_primitive`, never `Import bi` |
| 14 | `bi/plainly.v:158` | `and_elim_l` | `iris.bi.interface.bi.and_elim_l` | `…siProp_primitive.and_elim_l` | latent | latent | `siProp_primitive` is imported only in `si_logic/bi.v`, never exported |
| 15 | `base_logic/bi.v:54` | `impl_ne` | `…uPred_primitive.impl_ne` | `bi.interface.bi`, `siProp_primitive` | latent | latent | as #13, #14 |
| 16 | `bi/big_op.v:783` | `length` | `Corelib…Datatypes.length` | `String.length`, `stdpp.numbers.Pos.length` | latent | latent | as #7 |
| 17 | `program_logic/adequacy.v:290` | `state` | `…language.state` | `iris.proofmode.tokens.state` | latent | latent | `tokens` is only ever `Import`ed (3 proofmode files), never exported |
| 18 | `base_logic/bi.v:53` | `or_ne` | `…uPred_primitive.or_ne` | `bi.interface.bi`, `siProp_primitive` | latent | latent | as #15 |
| 19 | `base_logic/lib/own.v:288` | `wand_intro_r` | `iris.bi.interface.bi.wand_intro_r` | `…uPred_primitive.wand_intro_r` | latent | latent | `uPred_primitive` is only imported in `base_logic/bi.v`, never exported |
| 20 | `base_logic/lib/token.v:42` | `token` | `…lib.token.token` | `iris.proofmode.tokens.token` | latent | latent | as #17 |
| 21 | `proofmode/coq_tactics.v:1279` | `env` | `…environments.env` | `Stdlib.micromega.ZMicromega.env` | latent | latent | loaded by `lia`, never imported |
| 22 | `program_logic/ownp.v:110` | `prim_step` | `…language.prim_step` | `…ectx_language.prim_step` | latent | latent | `ectx_language` is only `Require`d at line 5, and `Import`ed later, at line 213 |
| 23 | `algebra/gset.v:15` | `union` | `stdpp.base.union` | `Stdlib…Relation_Operators.union` | latent | latent | never imported |
| 24 | `program_logic/total_weakestpre.v:198` | `and_elim_r` | `iris.bi.interface.bi.and_elim_r` | `uPred_primitive`, `siProp_primitive` | latent | latent | as #14, #19 |
| 25 | `unstable/algebra/list.v:28` | `Forall_cons` | `stdpp…list.Forall_cons` | `Stdlib.Vectors.Vector(Def).Forall_cons` | unknown | latent | `Vector` is never imported in Iris or stdpp |
| 26 | `base_logic/lib/invariants.v:162` | `inv` | `…invariants.inv` | `Stdlib…SuccNat2Pos.inv`, `stdpp.numbers.Qp.inv` | unknown | latent | neither module is ever imported |
| 27 | `algebra/view.v:503` | `inj` | `stdpp.base.inj` | 12 Stdlib `…2…` conversion-module `inj`s | unknown | latent | none of those modules is ever imported |
| 28 | `algebra/cofe_solver.v:43` | `eq_refl` | `Corelib.Init.Logic.eq_refl` | 16 Stdlib `Nat`/`N`/`Pos`/`Z` (`Private_Tac`…) `eq_refl`s | unknown | latent | none ever imported |
| 29 | `algebra/stepindex.v:289` | `lt_succ_diag_r` | `…stepindex.SIdx.sidx.lt_succ_diag_r` | `Nat`/`N`/`Pos`/`Z` versions | unknown | latent | none ever imported |
| 30 | `unstable/algebra/list.v:157` | `nil` | `Corelib…Datatypes.nil` | `Stdlib.Vectors.Vector(Def).nil` | unknown | latent | as #25 |

Result: the first version agreed on 28 of 30. Both misses were the same
cause: stdpp's `strings.v` deliberately imports only part of Stdlib's
`String`:

```coq
(** To avoid poluting the global namespace, we export only the [string] data
type (with its constructors and eliminators) and notations. *)
Export String (string(..)).
```

The first version tested one sibling (`string`, which the filter lets
through) and concluded the whole module was imported. The final version
tests every uniquely named sibling and flags a mix (5 of 28 here) as a
filtered import; it agrees with the hand check on all 30. Two things came
out of this beyond the fix:

- **stdpp is guarding against exactly this hazard, on purpose.**
  `Require Import String` is the classic way to accidentally make `length`
  mean string length. The data confirms the guard works: `String.length`
  is an alternative at 141 sites and latent at every one.
- **A third version was needed** when the `(Local)` check below turned up
  Iris's sealing pattern (`Local Definition …_unseal`), which the second
  version counted as shadowed. A `Local` alternative is never reachable by
  its bare name, so those 70 sites (mostly `pointsto_unseal`, 23) are
  "local-only" now.

## 5. Bonus checks

- **`(Local)` labels on a real corpus.** Rendering the grids for the 20
  files with the most ambiguous uses produced 596 `(Local)` labels — all
  from Iris's own sealing idiom (`Local Definition siProp_unseal`,
  `uPred_*_unseal`, `monPred_*_unseal`, …). So the label added in
  Workstream 9 Pass 1 (`Examples.md` §17) fires on real code, not just its
  fixture.
- **Scale.** 178 files in about 3.5 minutes sequentially, peak 1.1 GB for
  the largest single file. Judging use sites is a negligible part of that
  (Workstream 10 measured 0.08 s for all of Iris's lookups). The built-in
  import-status labels (Workstream 11) add about 3–4% over the whole
  corpus, measured back to back against the previous build (`summary`
  222 s → 229 s, `json` 217–219 s → 226–228 s).
- **Notations**, which Iris overrides deliberately and often (its
  `config/flags` turns off `notation-overridden`), are out of scope: the
  tool doesn't analyze notations yet (README Roadmap).

## 6. Caveats

- The shadowed/latent split relies on the tool's indirect test (a module
  counts as imported when all its uniquely named siblings resolve by bare
  name) plus two hand-checked judgment calls (METHOD.md). It is verified on
  a 30-site sample, not proven in general.
- "Latent" includes candidates that are practically unreachable, e.g.
  Stdlib's `Private_Tac` modules (3,341 latent alternatives are Stdlib's).
  Latent is a statement about what *could* happen after an import, not a
  claim that anyone would write that import.
- Excluding `Corelib` (the default) hides Corelib-vs-Corelib ambiguity
  and Corelib winners; Pass 1 covered Corelib itself.
- One file per process means each file is judged in its own context — the
  right question for "last import wins", but it means totals across files
  are sums of independent per-file results, not properties of one merged
  namespace.
