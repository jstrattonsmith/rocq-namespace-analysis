(* Refers to its own definition through its own module name, which only
   resolves when the file is elaborated under its real logical name
   (SelfLib.SelfRef), as `rocq compile` does -- not under a fixed `Top`. *)
Definition a := 0.
Definition b := SelfRef.a.
