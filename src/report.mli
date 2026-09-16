(** A plugin/CLI-agnostic report: built once from live environment state,
    then rendered either for the proof/message panel ([to_pp], via
    [Feedback.msg_notice]) or for a terminal ([to_string]). Both front ends
    must render identical content. *)

type t = {
  member_count : int;
  clashes : Clash_detect.clash list;
  used : Glob_capture.occurrence list;
}

val make :
  member_count:int ->
  clashes:Clash_detect.clash list ->
  used:Glob_capture.occurrence list ->
  t

val to_pp : t -> Pp.t

(** [color] (default [false]) additionally wraps the winning candidate in
    bold+ANSI color codes; pass [~color:(Unix.isatty Unix.stdout)] from a
    terminal front end. The plain-text winner marker is always present
    regardless. *)
val to_string : ?color:bool -> t -> string

(** Counts only, one line, no per-name grid -- for a whole-corpus batch run
    where the full grid could run to hundreds of rows. "No winner marked"
    covers both a purely hypothetical clash (nothing visible yet) and an
    excluded actual winner ({!Clash_detect.clash.winner}'s [None] case
    doesn't currently distinguish the two -- see its doc comment); this is
    reported as one combined count rather than overclaiming a split we can't
    actually make from the data we have. *)
val to_summary : t -> string

(** A fixed JSON shape (hand-serialized, no external JSON dependency,
    intentionally not a general-purpose encoder): [{"member_count": int,
    "clashes": [{"name", "winner" (string or null), "alternatives": [string]},
    ...], "used": [{"identifier", "defined_in"}, ...]}]. Alternatives are
    sorted alphabetically, same as the grid. *)
val to_json : t -> string
