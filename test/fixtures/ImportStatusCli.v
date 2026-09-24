(* CLI twin of ImportStatus.v, kept line-for-line aligned with it (use sites are reported by line); the CLI needs no Loader import. *)
From ISLibA Require Import ISA.
From ISLibB Require ISB.
From ISLibC Require ISC.
Import ISC (isc_one).
From ISLibD Require Import ISD.
From ISLibE Require ISE.
Check x.
Check y.
Check z.
Check w.
Import ISB.
Check x.
Check w.
Import ISA.
Check w.
Module Late.
  Definition x := 7.
  Definition late_only := 7.
End Late.
Check x.
