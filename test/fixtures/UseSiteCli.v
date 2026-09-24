(* CLI twin of UseSite.v, kept line-for-line aligned with it (use sites are reported by line); the CLI needs no Loader import. *)
From UseLibA Require Import UseA.
From UseLibB Require UseB.

Check x.
Section S.
  Import UseLibB.UseB.
  Check x.
End S.
Check x.
Check UseLibB.UseB.x.
Import UseLibB.UseB.
Check x.
