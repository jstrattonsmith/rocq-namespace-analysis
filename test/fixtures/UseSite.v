From NamespaceAnalysis Require Import Loader.
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

NamespaceAnalysis UseLibA UseLibB.
