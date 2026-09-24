open Names

type clash = {
  name : Id.t;
  winner : GlobRef.t option;
      (** [Some w]: [w] is currently import-visible via [Nametab.locate] and
          not itself excluded. [None]: either nothing in [alternatives] is
          actually import-visible right now (a purely hypothetical clash
          among not-yet-imported domain members), or the real winner exists
          but falls under an excluded prefix -- the clash still gets
          reported (with its non-excluded alternatives), just with no
          winner singled out, rather than either hiding the whole clash or
          revealing an excluded winner anyway. *)
  alternatives : GlobRef.t list;
      (** Every other non-excluded candidate (i.e. all of them, if
          [winner = None]). *)
}

(** [find_clashes ~excluded members] probes the (deduplicated) short names
    of [members] and reports every name with 2+ non-excluded candidates.

    The candidate set for a probed name is the union of (a) whatever
    [Nametab.locate_all] finds actually visible right now, and (b) whichever
    of [members] share that basename -- (b) matters because [members] may
    include domains that were [Require]d but never [Import]ed (see
    [Ensure_loaded]), which [Nametab.locate_all] alone would never see,
    since [Require] doesn't bind short-name visibility. This also means a
    name can be reported as a clash even against something entirely outside
    [members] (mirrors how [Locate] itself behaves): [excluded] is the only
    thing that narrows the candidate set; probing itself is never
    restricted to [members] or to any particular domain. *)
val find_clashes : excluded:DirPath.t list -> GlobRef.t list -> clash list

(** One way a name, as written in the analyzed source, was ambiguous at the
    point it was used (see {!Glob_capture.type-use_site}). *)
type ambiguous_use = {
  written : string;
  lines : int list;  (** every line with this same situation, ascending *)
  use_winner : Glob_capture.candidate option;
      (** what it resolved to; [None] if that falls under an excluded
          prefix (same rule as {!clash.winner}) *)
  use_alternatives : Glob_capture.candidate list;
      (** every other non-excluded candidate, sorted by path *)
}

(** [ambiguous_uses ~excluded occurrences] keeps every use site with 2+
    non-excluded candidates at the moment of use, grouping uses that saw
    exactly the same winner and alternatives. Unlike {!find_clashes}, this
    never looks at the current [Nametab]: it only reads what
    {!Glob_capture} recorded at each use, so it describes the file as it
    was elaborated, not the namespace at the end of it. *)
val ambiguous_uses : excluded:DirPath.t list -> Glob_capture.occurrence list -> ambiguous_use list
