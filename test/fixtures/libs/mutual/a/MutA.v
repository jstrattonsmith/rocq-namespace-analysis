Inductive FirstA : Set :=
  | FirstAMk : FirstA
with SharedName : Set :=
  | SharedAMk : FirstA -> SharedName.
