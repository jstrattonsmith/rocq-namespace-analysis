Inductive FirstB : Set :=
  | FirstBMk : FirstB
with SharedName : Set :=
  | SharedBMk : FirstB -> SharedName.
