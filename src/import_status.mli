(** Whether the module a global belongs to is imported, judged against the
    current [Nametab] state -- the piece Rocq's public API doesn't expose.

    [Nametab.locate_all] lists every loaded global a name could refer to,
    but not which of them are import-visible under that name: the shadowed
    entries behind the winner live in [nametab.ml]'s private state. This
    module approximates it with an indirect test. Importing a module makes
    all of its definitions reachable by bare name, so take the module's
    other members whose names nothing else loaded shares ("testable
    siblings") and check whether each resolves, bare, right now.

    Prototyped as a throwaway probe on Iris 4.5.0 (Workstream 9, Pass 2):
    agreed with a hand check on 30 of 30 sampled use sites, at no measurable
    runtime cost. Its failure modes are real Rocq import semantics, which is
    why two of the verdicts below are reported rather than resolved:
    - a filtered import ([Export String (string(..))]) makes only some
      siblings resolve -- {!Partial};
    - a module can have no testable sibling at all (Stdlib's [Pos]/[N]/[Z]
      share nearly every name) -- {!Unknown};
    - a [Local] definition inside an imported module never resolves by bare
      name. [Local] siblings are skipped here; a [Local] {e candidate} is
      the caller's to label, since its module's status says nothing about it
      (see {!Glob_capture.candidate}). *)

type t =
  | Imported  (** every testable sibling resolves *)
  | Not_imported  (** none does *)
  | Partial of int * int  (** [(resolving, tested)]: a filtered import *)
  | Unknown  (** no testable sibling *)

(** [of_global gr]: the status of the innermost module containing [gr] (not
    of [gr] itself -- [gr]'s own bare name is usually the ambiguous one). *)
val of_global : Names.GlobRef.t -> t

(** The innermost module containing a global, as {!of_global} uses it;
    [None] if it has no [Nametab] path. *)
val module_of_global : Names.GlobRef.t -> Names.DirPath.t option

(** [of_module dp]: the same test for a module directly, with no member
    excluded. Equals [of_global gr] for any [gr] in [dp] whose own name is
    shared with some other loaded global (so it's never a testable sibling
    anyway) -- true of every clash candidate, which lets a caller judging
    many of them compute each module once. *)
val of_module : Names.DirPath.t -> t
