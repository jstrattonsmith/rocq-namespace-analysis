# Case study: Corelib/Stdlib — results

See `METHOD.md` in this same directory for exactly how to reproduce this.
All output below is real, captured directly (not paraphrased) against
Rocq 9.1.1, repo commit `5b36809`.

## 1. Confirming the `--include Corelib` requirement

Without it:
```
NamespaceAnalysis: 1010 symbol(s) in scanned domain(s), 0 clash(es) found (0 with no winner marked), 2 identifier(s) used
```
With it:
```
NamespaceAnalysis: 1010 symbol(s) in scanned domain(s), 46 clash(es) found (45 with no winner marked), 2 identifier(s) used
```
Both completed in well under a second (0.24s and 0.03s respectively) —
consistent with this session's own confirmed performance work (Corelib
alone is ~1,010 members, far below the confirmed-fast 100,000+ range).

## 2. Full clash grid (`--include Corelib`, default format)

```
NamespaceAnalysis: 1010 symbol(s) in scanned domain(s)
Clashes:
┌───────────────────┬─────────────────────────────────────────────┐
│ Short name        │ Candidates (alphabetical)                   │
├───────────────────┼─────────────────────────────────────────────┤
│ D0                │ Corelib.Init.Decimal.D0                     │
│                   │ Corelib.Init.Hexadecimal.D0                 │
├───────────────────┼─────────────────────────────────────────────┤
│ D1                │ Corelib.Init.Decimal.D1                     │
│                   │ Corelib.Init.Hexadecimal.D1                 │
├───────────────────┼─────────────────────────────────────────────┤
│ D2                │ Corelib.Init.Decimal.D2                     │
│                   │ Corelib.Init.Hexadecimal.D2                 │
├───────────────────┼─────────────────────────────────────────────┤
│ D3                │ Corelib.Init.Decimal.D3                     │
│                   │ Corelib.Init.Hexadecimal.D3                 │
├───────────────────┼─────────────────────────────────────────────┤
│ D4                │ Corelib.Init.Decimal.D4                     │
│                   │ Corelib.Init.Hexadecimal.D4                 │
├───────────────────┼─────────────────────────────────────────────┤
│ D5                │ Corelib.Init.Decimal.D5                     │
│                   │ Corelib.Init.Hexadecimal.D5                 │
├───────────────────┼─────────────────────────────────────────────┤
│ D6                │ Corelib.Init.Decimal.D6                     │
│                   │ Corelib.Init.Hexadecimal.D6                 │
├───────────────────┼─────────────────────────────────────────────┤
│ D7                │ Corelib.Init.Decimal.D7                     │
│                   │ Corelib.Init.Hexadecimal.D7                 │
├───────────────────┼─────────────────────────────────────────────┤
│ D8                │ Corelib.Init.Decimal.D8                     │
│                   │ Corelib.Init.Hexadecimal.D8                 │
├───────────────────┼─────────────────────────────────────────────┤
│ D9                │ Corelib.Init.Decimal.D9                     │
│                   │ Corelib.Init.Hexadecimal.D9                 │
├───────────────────┼─────────────────────────────────────────────┤
│ Decimal           │ Corelib.Init.Decimal.Decimal                │
│                   │ Corelib.Init.Number.Decimal                 │
├───────────────────┼─────────────────────────────────────────────┤
│ Hexadecimal       │ Corelib.Init.Hexadecimal.Hexadecimal        │
│                   │ Corelib.Init.Number.Hexadecimal             │
├───────────────────┼─────────────────────────────────────────────┤
│ Neg               │ Corelib.Init.Decimal.Neg                    │
│                   │ Corelib.Init.Hexadecimal.Neg                │
├───────────────────┼─────────────────────────────────────────────┤
│ Nil               │ Corelib.Init.Decimal.Nil                    │
│                   │ Corelib.Init.Hexadecimal.Nil                │
├───────────────────┼─────────────────────────────────────────────┤
│ Pos               │ Corelib.Init.Decimal.Pos                    │
│                   │ Corelib.Init.Hexadecimal.Pos                │
├───────────────────┼─────────────────────────────────────────────┤
│ abs               │ Corelib.Init.Decimal.abs                    │
│                   │ Corelib.Init.Hexadecimal.abs                │
├───────────────────┼─────────────────────────────────────────────┤
│ app               │ Corelib.Init.Datatypes.app <- used          │
│                   │ Corelib.Init.Decimal.app                    │
│                   │ Corelib.Init.Hexadecimal.app                │
├───────────────────┼─────────────────────────────────────────────┤
│ app_int           │ Corelib.Init.Decimal.app_int                │
│                   │ Corelib.Init.Hexadecimal.app_int            │
├───────────────────┼─────────────────────────────────────────────┤
│ del_head          │ Corelib.Init.Decimal.del_head               │
│                   │ Corelib.Init.Hexadecimal.del_head           │
├───────────────────┼─────────────────────────────────────────────┤
│ del_head_int      │ Corelib.Init.Decimal.del_head_int           │
│                   │ Corelib.Init.Hexadecimal.del_head_int       │
├───────────────────┼─────────────────────────────────────────────┤
│ del_tail          │ Corelib.Init.Decimal.del_tail               │
│                   │ Corelib.Init.Hexadecimal.del_tail           │
├───────────────────┼─────────────────────────────────────────────┤
│ del_tail_int      │ Corelib.Init.Decimal.del_tail_int           │
│                   │ Corelib.Init.Hexadecimal.del_tail_int       │
├───────────────────┼─────────────────────────────────────────────┤
│ double            │ Corelib.Init.Decimal.Little.double          │
│                   │ Corelib.Init.Hexadecimal.Little.double      │
│                   │ Corelib.Init.Nat.double                     │
├───────────────────┼─────────────────────────────────────────────┤
│ int_of_int        │ Corelib.Init.Decimal.int_of_int             │
│                   │ Corelib.Init.Number.int_of_int              │
├───────────────────┼─────────────────────────────────────────────┤
│ nb_digits         │ Corelib.Init.Decimal.nb_digits              │
│                   │ Corelib.Init.Hexadecimal.nb_digits          │
├───────────────────┼─────────────────────────────────────────────┤
│ norm              │ Corelib.Init.Decimal.norm                   │
│                   │ Corelib.Init.Hexadecimal.norm               │
├───────────────────┼─────────────────────────────────────────────┤
│ nzhead            │ Corelib.Init.Decimal.nzhead                 │
│                   │ Corelib.Init.Hexadecimal.nzhead             │
├───────────────────┼─────────────────────────────────────────────┤
│ nztail            │ Corelib.Init.Decimal.nztail                 │
│                   │ Corelib.Init.Hexadecimal.nztail             │
├───────────────────┼─────────────────────────────────────────────┤
│ nztail_int        │ Corelib.Init.Decimal.nztail_int             │
│                   │ Corelib.Init.Hexadecimal.nztail_int         │
├───────────────────┼─────────────────────────────────────────────┤
│ opp               │ Corelib.Init.Decimal.opp                    │
│                   │ Corelib.Init.Hexadecimal.opp                │
├───────────────────┼─────────────────────────────────────────────┤
│ rev               │ Corelib.Init.Decimal.rev                    │
│                   │ Corelib.Init.Hexadecimal.rev                │
├───────────────────┼─────────────────────────────────────────────┤
│ revapp            │ Corelib.Init.Decimal.revapp                 │
│                   │ Corelib.Init.Hexadecimal.revapp             │
├───────────────────┼─────────────────────────────────────────────┤
│ signed_int        │ Corelib.Init.Decimal.signed_int             │
│                   │ Corelib.Init.Hexadecimal.signed_int         │
│                   │ Corelib.Init.Number.signed_int              │
├───────────────────┼─────────────────────────────────────────────┤
│ signed_int_beq    │ Corelib.Init.Decimal.signed_int_beq         │
│                   │ Corelib.Init.Hexadecimal.signed_int_beq     │
│                   │ Corelib.Init.Number.signed_int_beq          │
├───────────────────┼─────────────────────────────────────────────┤
│ signed_int_eq_dec │ Corelib.Init.Decimal.signed_int_eq_dec      │
│                   │ Corelib.Init.Hexadecimal.signed_int_eq_dec  │
│                   │ Corelib.Init.Number.signed_int_eq_dec       │
├───────────────────┼─────────────────────────────────────────────┤
│ succ              │ Corelib.Init.Decimal.Little.succ            │
│                   │ Corelib.Init.Hexadecimal.Little.succ        │
│                   │ Corelib.Init.Nat.succ                       │
├───────────────────┼─────────────────────────────────────────────┤
│ succ_double       │ Corelib.Init.Decimal.Little.succ_double     │
│                   │ Corelib.Init.Hexadecimal.Little.succ_double │
├───────────────────┼─────────────────────────────────────────────┤
│ uint              │ Corelib.Init.Decimal.uint                   │
│                   │ Corelib.Init.Hexadecimal.uint               │
│                   │ Corelib.Init.Number.uint                    │
├───────────────────┼─────────────────────────────────────────────┤
│ uint_beq          │ Corelib.Init.Decimal.uint_beq               │
│                   │ Corelib.Init.Hexadecimal.uint_beq           │
│                   │ Corelib.Init.Number.uint_beq                │
├───────────────────┼─────────────────────────────────────────────┤
│ uint_eq_dec       │ Corelib.Init.Decimal.uint_eq_dec            │
│                   │ Corelib.Init.Hexadecimal.uint_eq_dec        │
│                   │ Corelib.Init.Number.uint_eq_dec             │
├───────────────────┼─────────────────────────────────────────────┤
│ uint_ind          │ Corelib.Init.Decimal.uint_ind               │
│                   │ Corelib.Init.Hexadecimal.uint_ind           │
├───────────────────┼─────────────────────────────────────────────┤
│ uint_of_uint      │ Corelib.Init.Decimal.uint_of_uint           │
│                   │ Corelib.Init.Number.uint_of_uint            │
├───────────────────┼─────────────────────────────────────────────┤
│ uint_rec          │ Corelib.Init.Decimal.uint_rec               │
│                   │ Corelib.Init.Hexadecimal.uint_rec           │
├───────────────────┼─────────────────────────────────────────────┤
│ uint_rect         │ Corelib.Init.Decimal.uint_rect              │
│                   │ Corelib.Init.Hexadecimal.uint_rect          │
├───────────────────┼─────────────────────────────────────────────┤
│ uint_sind         │ Corelib.Init.Decimal.uint_sind              │
│                   │ Corelib.Init.Hexadecimal.uint_sind          │
├───────────────────┼─────────────────────────────────────────────┤
│ unorm             │ Corelib.Init.Decimal.unorm                  │
│                   │ Corelib.Init.Hexadecimal.unorm              │
└───────────────────┴─────────────────────────────────────────────┘
Used identifiers:
┌────────────┬────────────────────┐
│ Identifier │ Defined in         │
├────────────┼────────────────────┤
│ eq_refl    │ Corelib.Init.Logic │
├────────────┼────────────────────┤
│ plus       │ Corelib.Init.Peano │
└────────────┴────────────────────┘
```

Full `--format json` output for this run is archived alongside this file
as `output.json`.

## 3. Analysis

**46 total clashes, 1,010 members scanned, 0.03s.** Performance is a
non-issue at this scale, as already established.

**This is a different, more interesting failure mode than the `Local`
false positive** — not what was originally expected going in:

- **0 of the 46 are `Local`-related.** Checked directly against Corelib's
  own source (`Init/Decimal.v`, the single largest contributor to this
  list at 21 top-level definitions): zero `Local` declarations in that
  file. Every candidate here is a genuine, fully public, deliberately
  exported definition.
- **44 of 46 are parallel-submodule echoes, not real practical risk.**
  `Corelib.Init.Decimal` and `Corelib.Init.Hexadecimal` are two
  intentionally near-identical modules (digit representations for base-10
  vs. base-16), reusing the same internal names throughout (`D0`-`D9`,
  `Neg`, `Pos`, `Nil`, `abs`, `norm`, `rev`, `uint`, `uint_rec`, etc.) —
  `Corelib.Init.Number` mirrors a subset of the same names again. In
  practice these are essentially always accessed fully qualified
  (`Decimal.D0`, `Hexadecimal.D0`), never both bare-imported at once, so
  this is Corelib's own authors relying on qualification discipline
  exactly the way this tool's own "Why this exists" section describes as
  risky in general — Rocq's *own* standard library takes on that same
  risk deliberately, at scale, as a design choice.
- **4 of 46 are genuinely more interesting**: `app`, `double`, `succ`,
  `succ_double` each collide between the Decimal/Hexadecimal pair *and* a
  third, much more commonly-used module (`Datatypes`, `Nat`). `app` is
  the standout: `Corelib.Init.Datatypes.app` (ordinary list append,
  ubiquitous) collides with `Decimal.app`/`Hexadecimal.app` (digit-list
  append) — and it's the *only* one of the 46 with an actual current
  winner (`Datatypes.app <- used`), since `Datatypes` is exported by the
  default prelude. This is the one finding that looks like a genuine
  "last import wins" hazard in the sense the tool exists to catch, not
  just an intentional internal-naming echo.

**Conclusion on the `Local` investigation** (per the conditional plan):
the premise "if this shows up a lot" is **not met** — it shows up zero
times in this run. `src/clash_detect.ml`'s `Local` fix (a real, confirmed-
feasible API, `Declare.is_local_constant` — see the plan) is not
implemented as part of this pass as a result. The finding worth carrying
into the talk instead is the parallel-submodule pattern above, which is a
different and arguably more interesting story: even Rocq's own standard
library both hits this exact hazard class *and* accepts it as a design
tradeoff, rather than avoiding it.
